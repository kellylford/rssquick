import AppKit
import RSSQuickCore
import RSSQuickTestSupport
@testable import RSSQuickUI

/// Builds a real window, backed by a real loopback server, and drives it the way a reader does.
///
/// Nothing here is a stand-in: the window is the window the application shows, Return is the
/// real handler, and a load is a real fetch over HTTP with a real parse at the end of it. Focus
/// behaviour is the part of this program most worth testing and the part hardest to check by
/// hand, so it is worth the loopback server to be able to.
@MainActor
final class FocusHarness {
    let server: LocalFeedServer
    let controller: MainWindowController

    var window: NSWindow { controller.window! }
    var outline: FeedOutlineView { controller.outline }
    var table: HeadlinesTableView { controller.table }

    let goodFeed: FeedItem
    let otherFeed: FeedItem
    let brokenFeed: FeedItem
    let brokenFeed2: FeedItem
    let slowFeed: FeedItem
    let folder: FeedItem

    /// Builds a harness and lets the window finish starting up.
    ///
    /// The window defers its startup focus to the next turn of the run loop, because its views
    /// are not laid out while it is being constructed. A test that acts before that has happened
    /// races it, and the deferred block lands in the middle of whatever the test is asserting.
    static func make() async throws -> FocusHarness {
        let harness = try FocusHarness()
        await harness.settle()
        return harness
    }

    private init() throws {
        // A window cannot be made before the application object exists. Accessory rather than
        // regular: the test runner should not take over the screen or steal the Dock.
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        server = try LocalFeedServer(routes: [
            "/news.xml": .init(body: SampleFeeds.rss2),
            "/atom.xml": .init(body: SampleFeeds.atom),
            "/broken.xml": .init(status: 500, body: "server on fire"),
            "/slow.xml": .init(body: SampleFeeds.rss2, delay: 3),
        ])

        goodFeed = FeedItem(title: "Example News", url: server.url(for: "/news.xml"))
        otherFeed = FeedItem(title: "Atom Example", url: server.url(for: "/atom.xml"))
        brokenFeed = FeedItem(title: "Broken", url: server.url(for: "/broken.xml"))
        brokenFeed2 = FeedItem(title: "Also Broken", url: server.url(for: "/missing.xml"))
        slowFeed = FeedItem(title: "Slow", url: server.url(for: "/slow.xml"))
        folder = FeedItem(
            title: "Everything",
            category: "Everything",
            isCategory: true,
            children: [goodFeed, otherFeed, brokenFeed]
        )

        controller = MainWindowController()
        controller.roots = [folder]
        controller.outline.reloadData()
        controller.outline.expandItem(folder)

        // Off-screen, so a test run does not put a window in front of whatever the developer is
        // doing. Focus is still real: first responder does not require a window to be on screen,
        // which is also why this reads focus that way rather than through the key window.
        window.orderBack(nil)
    }

    deinit { server.stop() }

    /// Lets anything the window deferred to the next turn of the run loop actually happen.
    func settle() async {
        // Awaiting is what drains the main queue here: the main actor's executor is the main
        // queue, so anything the window deferred with DispatchQueue.main.async runs while this
        // sleeps. Three short turns rather than one long one, because a deferred block can
        // itself defer.
        for _ in 0..<3 { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// Selects a row in the feed tree and presses Return on it, as a reader would.
    func pressReturnOnFeed(_ item: FeedItem) async {
        let row = outline.row(forItem: item)
        precondition(row >= 0, "\(item.title) is not visible in the tree")

        outline.selectRowIndexes([row], byExtendingSelection: false)
        window.makeFirstResponder(outline)
        outline.keyDown(with: FocusHarness.returnKey)

        await finishLoading()
    }

    /// A load is started and never awaited by the window, so a test cannot simply await it.
    func finishLoading() async {
        await controller.loadTask?.value
        await settle()
    }

    func moveDownInHeadlines() {
        let row = min(table.selectedRow + 1, table.numberOfRows - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
    }

    static let returnKey = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\r",
        charactersIgnoringModifiers: "\r",
        isARepeat: false,
        keyCode: 36
    )!
}
