import Foundation
import Testing
import RSSQuickTestSupport
@testable import RSSQuickCore

/// Turning what a reader typed into a feed. The Windows version answers the same questions in
/// tests/RSSQuick.Tests/FeedDiscoveryTests.cs.
@Suite("Finding a feed to subscribe to", .serialized)
struct FeedDiscoveryTests {
    @Test("An address is made into a web address", arguments: [
        ("example.com/feed.xml", "https://example.com/feed.xml"),
        ("  http://example.com/rss  ", "http://example.com/rss"),
        ("feed://example.com/rss", "http://example.com/rss"),
        ("feed:https://example.com/rss", "https://example.com/rss"),
    ])
    func normalize(typed: String, expected: String) {
        #expect(FeedDiscovery.normalize(typed)?.absoluteString == expected)
    }

    @Test("Something that cannot be a web address is refused", arguments: ["", "ftp://example.com/feed.xml", "file:///Users/me/feeds.xml"])
    func refuse(typed: String) {
        #expect(FeedDiscovery.normalize(typed) == nil)
    }

    @Test("A page's feed links are found in order, and made absolute")
    func links() throws {
        let page = """
            <html><head>
              <link rel="stylesheet" href="/style.css">
              <link rel="alternate" type="application/rss+xml" title="Posts" href="/feed.xml">
              <LINK REL='alternate' TYPE='application/atom+xml' HREF='https://other.example.com/atom?a=1&amp;b=2'>
              <link rel="alternate" type="text/html" href="/fr/">
              <link rel="alternate" type="application/rss+xml" href="/feed.xml">
            </head></html>
            """

        let links = FeedDiscovery.feedLinks(in: page, page: try #require(URL(string: "https://example.com/blog/")))

        #expect(links.map(\.absoluteString) == ["https://example.com/feed.xml", "https://other.example.com/atom?a=1&b=2"])
    }

    @Test("A feed address is used as it is, and named by the feed")
    func feedAddress() async throws {
        let server = try LocalFeedServer(routes: ["/news.xml": .init(body: SampleFeeds.rss2)])
        defer { server.stop() }

        let found = try await FeedDiscovery.find(server.url(for: "/news.xml"))

        #expect(found == DiscoveredFeed(title: "Example News", url: server.url(for: "/news.xml")))
    }

    @Test("A website address leads to the feed it links to")
    func websiteAddress() async throws {
        let server = try LocalFeedServer(routes: [
            "/feed.xml": .init(body: SampleFeeds.rss2),
            "/index.html": .init(body: """
                <!DOCTYPE html>
                <html><head><link rel="alternate" type="application/rss+xml" href="feed.xml"></head><body>Hi</body></html>
                """, contentType: "text/html"),
        ])
        defer { server.stop() }

        let found = try await FeedDiscovery.find(server.url(for: "/index.html"))

        #expect(found == DiscoveredFeed(title: "Example News", url: server.url(for: "/feed.xml")))
    }

    @Test("A page with no feed says so")
    func noFeed() async throws {
        let server = try LocalFeedServer(routes: [
            "/plain.html": .init(body: "<!DOCTYPE html><html><body>Nothing here</body></html>", contentType: "text/html"),
        ])
        defer { server.stop() }

        await #expect(throws: FeedDiscovery.NoFeedFound.self) {
            try await FeedDiscovery.find(server.url(for: "/plain.html"))
        }
        #expect(ErrorText.describe(FeedDiscovery.NoFeedFound()) == "has no feed RSS Quick can find")
    }

    @Test("A missing page reports what the server said")
    func missing() async throws {
        let server = try LocalFeedServer(routes: [:])
        defer { server.stop() }

        do {
            _ = try await FeedDiscovery.find(server.url(for: "/gone"))
            Issue.record("A missing page was taken for a feed")
        } catch {
            #expect(ErrorText.describe(error).hasPrefix("server said 404"))
        }
    }
}
