import Foundation
import Testing
import RSSQuickTestSupport
@testable import RSSQuickCore

@Suite("Fetching feeds", .serialized)
struct FeedLoaderTests {
    private func feed(_ title: String, _ url: String) -> FeedItem {
        FeedItem(title: title, url: url)
    }

    @Test("A feed served over HTTP comes back parsed and sorted")
    func loadsOneFeed() async throws {
        let server = try LocalFeedServer(routes: ["/news.xml": .init(body: SampleFeeds.rss2)])
        defer { server.stop() }

        let articles = try await FeedLoader.loadFeed(feed("Example", server.url(for: "/news.xml")))

        #expect(articles.map(\.title) == ["Newer story", "Older story"])
        #expect(articles.allSatisfy { $0.feedTitle == "Example" })
    }

    /// The fault this class exists to fix: one publisher being down must not cost the reader
    /// the nineteen feeds that worked.
    @Test("A folder keeps going when one of its feeds fails")
    func folderSurvivesAFailure() async throws {
        let server = try LocalFeedServer(routes: [
            "/good.xml": .init(body: SampleFeeds.rss2),
            "/broken.xml": .init(status: 500, body: "server on fire"),
            "/atom.xml": .init(body: SampleFeeds.atom),
        ])
        defer { server.stop() }

        let result = try await FeedLoader.loadFolder([
            feed("Good", server.url(for: "/good.xml")),
            feed("Broken", server.url(for: "/broken.xml")),
            feed("Atom", server.url(for: "/atom.xml")),
        ])

        #expect(result.feedsAttempted == 3)
        #expect(result.feedsSucceeded == 2)
        #expect(result.articles.count == 3)
        #expect(result.failures.map(\.feedTitle) == ["Broken"])
    }

    @Test("A failure is described in words a reader can act on")
    func failureReasons() async throws {
        let server = try LocalFeedServer(routes: [
            "/missing.xml": .init(status: 404, body: "nope"),
            "/nonsense.xml": .init(body: SampleFeeds.notAFeed),
            "/garbled.xml": .init(body: SampleFeeds.malformedXML),
        ])
        defer { server.stop() }

        let result = try await FeedLoader.loadFolder([
            feed("Missing", server.url(for: "/missing.xml")),
            feed("Nonsense", server.url(for: "/nonsense.xml")),
            feed("Garbled", server.url(for: "/garbled.xml")),
        ])

        let reasons = Dictionary(uniqueKeysWithValues: result.failures.map { ($0.feedTitle, $0.reason) })

        #expect(reasons["Missing"]?.hasPrefix("server said 404") == true)
        #expect(reasons["Nonsense"] == "is not a feed RSS Quick understands")
        #expect(reasons["Garbled"] == "is not valid XML")
    }

    @Test("A feed with an unusable address fails on its own rather than throwing")
    func malformedURL() async throws {
        let result = try await FeedLoader.loadFolder([feed("Nonsense", "not a url at all")])

        #expect(result.failures.count == 1)
        #expect(result.failures.first?.reason == "has an address RSS Quick cannot read")
    }

    /// Bounded rather than unbounded: a folder can hold dozens of feeds, and opening that many
    /// connections at once gets a client rate-limited by some publishers.
    @Test("A folder is fetched concurrently, and no more than six at a time")
    func concurrencyIsCapped() async throws {
        let paths = (0..<14).map { "/feed\($0).xml" }
        let routes = Dictionary(uniqueKeysWithValues: paths.map {
            ($0, LocalFeedServer.Route(body: SampleFeeds.rss2, delay: 0.25))
        })

        let server = try LocalFeedServer(routes: routes)
        defer { server.stop() }

        let feeds = paths.enumerated().map { feed("Feed \($0.offset)", server.url(for: $0.element)) }
        let result = try await FeedLoader.loadFolder(feeds)

        #expect(result.feedsSucceeded == 14)
        #expect(server.peakInFlight > 1, "the feeds were fetched one after another")
        #expect(server.peakInFlight <= FeedLoader.maxConcurrentFeeds)
    }

    @Test("Progress is reported once per feed")
    func progressReported() async throws {
        let server = try LocalFeedServer(routes: [
            "/a.xml": .init(body: SampleFeeds.rss2),
            "/b.xml": .init(body: SampleFeeds.atom),
        ])
        defer { server.stop() }

        let reported = Mutex<[Int]>([])
        _ = try await FeedLoader.loadFolder(
            [feed("A", server.url(for: "/a.xml")), feed("B", server.url(for: "/b.xml"))],
            progress: { done in reported.withLock { $0.append(done) } }
        )

        #expect(reported.withLock { $0 } == [1, 2])
    }

    @Test("Cancelling a folder load stops it")
    func cancellationStopsTheLoad() async throws {
        let paths = (0..<8).map { "/slow\($0).xml" }
        let routes = Dictionary(uniqueKeysWithValues: paths.map {
            ($0, LocalFeedServer.Route(body: SampleFeeds.rss2, delay: 3))
        })

        let server = try LocalFeedServer(routes: routes)
        defer { server.stop() }

        let feeds = paths.enumerated().map { feed("Slow \($0.offset)", server.url(for: $0.element)) }

        let task = Task { try await FeedLoader.loadFolder(feeds) }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()

        await #expect(throws: (any Error).self) { try await task.value }
        #expect(server.requestCount < feeds.count, "every feed was fetched despite the cancellation")
    }

    @Test("A folder's headlines are merged newest first across its feeds")
    func mergedNewestFirst() async throws {
        let older = """
        <rss version="2.0"><channel><title>Older</title>
          <item><title>From A</title><link>https://example.com/a</link><pubDate>Mon, 02 Mar 2026 09:00:00 GMT</pubDate></item>
        </channel></rss>
        """
        let newer = """
        <rss version="2.0"><channel><title>Newer</title>
          <item><title>From B</title><link>https://example.com/b</link><pubDate>Wed, 04 Mar 2026 09:00:00 GMT</pubDate></item>
        </channel></rss>
        """

        let server = try LocalFeedServer(routes: ["/a.xml": .init(body: older), "/b.xml": .init(body: newer)])
        defer { server.stop() }

        let result = try await FeedLoader.loadFolder([
            feed("A", server.url(for: "/a.xml")),
            feed("B", server.url(for: "/b.xml")),
        ])

        #expect(result.articles.map(\.title) == ["From B", "From A"])
        #expect(result.articles.map(\.feedTitle) == ["B", "A"])
    }

    @Test("An empty folder is not an error")
    func emptyFolder() async throws {
        let result = try await FeedLoader.loadFolder([])
        #expect(result.feedsAttempted == 0)
        #expect(result.articles.isEmpty)
    }
}

/// A small box so a `@Sendable` progress callback can collect what it was told.
private final class Mutex<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
