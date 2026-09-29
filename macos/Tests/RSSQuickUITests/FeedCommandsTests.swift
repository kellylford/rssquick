import AppKit
import Foundation
import Testing
import RSSQuickCore
import RSSQuickTestSupport
@testable import RSSQuickUI

/// Search, subscribe, remove and export, in the real window against feeds served on loopback.
/// Each command's sheet cannot be driven here, so these call what the sheet hands its answer to.
/// The Windows version is tests/RSSQuick.Tests/MenuAndFeedCommandsTests.cs.
@Suite("Searching and changing the feed list", .serialized)
@MainActor
struct FeedCommandsTests {
    private static func feedList(_ feeds: [(folder: String, title: String, url: String)]) -> Data {
        var body = ""
        var folders: [String] = []
        for feed in feeds where !folders.contains(feed.folder) { folders.append(feed.folder) }
        for folder in folders {
            body += "<outline text=\"\(folder)\">"
            for feed in feeds where feed.folder == folder {
                body += "<outline text=\"\(feed.title)\" xmlUrl=\"\(feed.url)\"/>"
            }
            body += "</outline>"
        }
        return Data("<?xml version=\"1.0\"?><opml version=\"2.0\"><head><title>Test</title></head><body>\(body)</body></opml>".utf8)
    }

    private static let other = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel><title>Brand New</title>
          <item><title>Storm hits the coast</title><link>https://example.com/storm</link></item>
          <item><title>Nothing to see</title><link>https://example.com/nothing</link></item>
        </channel></rss>
        """

    private func show(_ harness: FocusHarness, _ data: Data, isDefault: Bool = false) throws {
        harness.controller.show(try OpenedFeedList(data: data, isSaved: isDefault), isDefault: isDefault)
    }

    private func selected(_ harness: FocusHarness) -> FeedItem? {
        harness.outline.item(atRow: harness.outline.selectedRow) as? FeedItem
    }

    private func savedTitles(_ harness: FocusHarness) throws -> [String] {
        let data = try #require(try harness.controller.savedList.load())
        return try OpenedFeedList(data: data, isSaved: true).document.roots.flatMap(\.allFeeds).map(\.title)
    }

    // MARK: Search

    @Test("Search fetches every feed and shows only what matches")
    func searchFindsMatches() async throws {
        let harness = try await FocusHarness.make()
        let server = try await LocalFeedServer.start(routes: ["/other.xml": .init(body: Self.other)])
        defer { server.stop() }
        try show(harness, Self.feedList([
            ("News", "Example News", harness.server.url(for: "/news.xml")),
            ("More", "Brand New", server.url(for: "/other.xml")),
        ]))

        harness.controller.search(for: "story")
        await harness.finishLoading()

        #expect(Set(harness.controller.headlines.map(\.title)) == ["Newer story", "Older story"])
        #expect(harness.controller.status == "Found 2 headlines matching story in 2 feeds")
        #expect(harness.window.firstResponder === harness.table)
        #expect(harness.controller.headlinesAreMerged)
    }

    @Test("A search with no results says so, and names what failed")
    func searchFindsNothing() async throws {
        let harness = try await FocusHarness.make()
        try show(harness, Self.feedList([
            ("News", "Example News", harness.server.url(for: "/news.xml")),
            ("News", "Broken", harness.server.url(for: "/broken.xml")),
        ]))

        harness.controller.search(for: "zebra")
        await harness.finishLoading()

        #expect(harness.controller.headlines.isEmpty)
        #expect(harness.controller.status == "No headlines match zebra in 1 of 2 feeds; 1 could not be loaded")
    }

    @Test("Refresh runs the search again")
    func refreshRepeatsSearch() async throws {
        let harness = try await FocusHarness.make()
        try show(harness, Self.feedList([("News", "Example News", harness.server.url(for: "/news.xml"))]))

        harness.controller.search(for: "newer")
        await harness.finishLoading()
        let before = harness.server.requestCount

        harness.controller.refresh(nil)
        await harness.finishLoading()

        #expect(harness.server.requestCount == before + 1)
        #expect(harness.controller.status == "Found 1 headline matching newer in 1 feed")
    }

    // MARK: Subscribing

    @Test("Subscribing adds the feed, saves the list, and selects the new feed")
    func subscribe() async throws {
        let harness = try await FocusHarness.make()
        let server = try await LocalFeedServer.start(routes: ["/other.xml": .init(body: Self.other)])
        defer { server.stop() }
        try show(harness, Self.feedList([("News", "Example News", harness.server.url(for: "/news.xml"))]))
        let news = try #require(OpmlEditor.folders(harness.controller.roots).first { $0.name == "News" })

        harness.controller.subscribe(to: server.url(for: "/other.xml"), into: news)
        await harness.controller.subscribeTask?.value
        await harness.settle()

        #expect(harness.controller.status == "Subscribed to Brand New in News. This feed list is now your default, so it opens every time RSS Quick starts.")
        #expect(selected(harness)?.title == "Brand New")
        #expect(harness.window.firstResponder === harness.outline)
        #expect(try savedTitles(harness) == ["Example News", "Brand New"])
    }

    @Test("Subscribing to a feed already there selects it and changes nothing")
    func subscribeTwice() async throws {
        let harness = try await FocusHarness.make()
        try show(harness, Self.feedList([("News", "Example News", harness.server.url(for: "/news.xml"))]))

        harness.controller.subscribe(to: harness.server.url(for: "/news.xml"), into: nil)
        await harness.settle()

        #expect(harness.controller.status == "You already subscribe to Example News, in News")
        #expect(selected(harness)?.title == "Example News")
        #expect(!harness.controller.savedList.exists)
        #expect(harness.server.requestCount == 0)
    }

    @Test("An address with no feed says why, and changes nothing")
    func subscribeToNothing() async throws {
        let harness = try await FocusHarness.make()
        let server = try await LocalFeedServer.start(routes: [
            "/page.html": .init(body: "<!DOCTYPE html><html><body>No feeds</body></html>", contentType: "text/html"),
        ])
        defer { server.stop() }
        try show(harness, Self.feedList([("News", "Example News", harness.server.url(for: "/news.xml"))]))

        harness.controller.subscribe(to: server.url(for: "/page.html"), into: nil)
        await harness.controller.subscribeTask?.value

        #expect(harness.controller.status == "Could not subscribe: \(server.url(for: "/page.html")) has no feed RSS Quick can find")
        #expect(!harness.controller.savedList.exists)
    }

    /// The folder is a position in the list. A feed removed while the new one is being looked for
    /// moves every folder after it, so the subscription stops rather than guessing.
    @Test("A list that changes while a feed is found is not changed again")
    func listChangesDuringSubscribe() async throws {
        let harness = try await FocusHarness.make()
        let server = try await LocalFeedServer.start(routes: ["/slow.xml": .init(body: Self.other, delay: 1)])
        defer { server.stop() }
        try show(harness, Self.feedList([
            ("News", "One", "https://example.com/one.xml"),
            ("Sport", "Two", "https://example.com/two.xml"),
        ]), isDefault: true)
        let sport = try #require(OpmlEditor.folders(harness.controller.roots).first { $0.name == "Sport" })

        harness.controller.subscribe(to: server.url(for: "/slow.xml"), into: sport)
        harness.controller.remove(harness.controller.roots[0].children[0])
        await harness.controller.subscribeTask?.value

        #expect(harness.controller.status.hasPrefix("Your feed list changed"))
        #expect(try savedTitles(harness) == ["Two"])
    }

    // MARK: Removing

    @Test("Open folders stay open after a removal")
    func foldersStayOpen() async throws {
        let harness = try await FocusHarness.make()
        try show(harness, Self.feedList([
            ("News", "One", "https://example.com/one.xml"),
            ("Sport", "Two", "https://example.com/two.xml"),
            ("Sport", "Three", "https://example.com/three.xml"),
        ]), isDefault: true)
        harness.outline.expandItem(harness.controller.roots[0])

        harness.controller.remove(harness.controller.roots[1].children[0])

        #expect(harness.outline.isItemExpanded(harness.controller.roots[0]))
        #expect(selected(harness)?.title == "Three")
    }

    @Test("Removing a feed saves the list and moves to the next feed")
    func removeMovesToNext() async throws {
        let harness = try await FocusHarness.make()
        try show(harness, Self.feedList([
            ("News", "One", "https://example.com/one.xml"),
            ("News", "Two", "https://example.com/two.xml"),
            ("News", "Three", "https://example.com/three.xml"),
        ]), isDefault: true)
        let two = harness.controller.roots[0].children[1]

        harness.controller.remove(two)

        #expect(harness.controller.status == "Removed Two.")
        #expect(selected(harness)?.title == "Three")
        #expect(try savedTitles(harness) == ["One", "Three"])
    }

    @Test("Removing the only feed in a folder moves to the folder")
    func removeLastInFolder() async throws {
        let harness = try await FocusHarness.make()
        try show(harness, Self.feedList([
            ("News", "One", "https://example.com/one.xml"),
            ("Sport", "Two", "https://example.com/two.xml"),
        ]), isDefault: true)

        harness.controller.remove(harness.controller.roots[1].children[0])

        #expect(selected(harness)?.title == "Sport")
    }

    @Test("Remove Feed is dimmed on a folder")
    func removeDimmedOnFolder() async throws {
        let harness = try await FocusHarness.make()
        harness.outline.selectRowIndexes([harness.outline.row(forItem: harness.folder)], byExtendingSelection: false)

        let item = NSMenuItem(title: "", action: #selector(MainWindowController.removeFeed(_:)), keyEquivalent: "")
        #expect(!harness.controller.validateMenuItem(item))
    }

    // MARK: Exporting

    @Test("Export writes the list on screen, including a new subscription")
    func export() async throws {
        let harness = try await FocusHarness.make()
        let server = try await LocalFeedServer.start(routes: ["/other.xml": .init(body: Self.other)])
        defer { server.stop() }
        try show(harness, Self.feedList([("News", "Example News", harness.server.url(for: "/news.xml"))]))
        harness.controller.subscribe(to: server.url(for: "/other.xml"), into: nil)
        await harness.controller.subscribeTask?.value

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rssquick-export-\(UUID().uuidString).opml")
        defer { try? FileManager.default.removeItem(at: url) }
        harness.controller.exportFeedList(to: url)

        #expect(harness.controller.status == "Exported 2 feeds to \(url.lastPathComponent)")
        #expect(try Data(contentsOf: url) == harness.controller.savedList.load())
    }
}
