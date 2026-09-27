import AppKit
import Foundation
import Testing
import RSSQuickCore
@testable import RSSQuickUI

/// What the window does when a newer version is found: one announcement, and nothing that moves
/// the reader. The Windows version is tests/RSSQuick.Tests/UpdateOfferTests.cs, which also covers
/// the button the Mac does without - here the offer is a menu item.
@Suite("Saying a newer version is available", .serialized)
@MainActor
struct UpdateNoticeTests {
    private static let release = AvailableRelease(
        version: "1.3.0",
        page: URL(string: "https://github.com/kellylford/rssquick/releases/tag/v1.3.0")!)

    private static let notice =
        "RSS Quick 1.3.0 is available. Download RSS Quick 1.3.0 in the RSS Quick menu opens its page"

    @Test("A newer version is announced")
    func announced() async throws {
        let harness = try await FocusHarness.make()

        harness.controller.showUpdate(Self.release)

        #expect(harness.controller.status == Self.notice)
    }

    @Test("A newer version does not move focus")
    func focusStays() async throws {
        let harness = try await FocusHarness.make()
        await harness.pressReturnOnFeed(harness.goodFeed)
        let before = harness.window.firstResponder

        harness.controller.showUpdate(Self.release)
        await harness.settle()

        #expect(harness.window.firstResponder === before)
    }

    /// The check finishes a few seconds after launch, which is when a reader is most likely to be
    /// waiting on their first feed. Announced then, it would be overwritten by the load summary
    /// before it was heard.
    @Test("A newer version found during a load is announced after the load")
    func deferredDuringLoad() async throws {
        let harness = try await FocusHarness.make()

        // pressReturnOnFeed waits for the load; this has to act while it is still running.
        let row = harness.outline.row(forItem: harness.goodFeed)
        harness.outline.selectRowIndexes([row], byExtendingSelection: false)
        harness.window.makeFirstResponder(harness.outline)
        harness.outline.keyDown(with: FocusHarness.returnKey)

        harness.controller.showUpdate(Self.release)
        #expect(harness.controller.status == "Loading Example News…")

        await harness.finishLoading()

        #expect(harness.controller.status == "Loaded 2 headlines from Example News. \(Self.notice)")
    }

    @Test("A newer version is announced once")
    func announcedOnce() async throws {
        let harness = try await FocusHarness.make()

        let row = harness.outline.row(forItem: harness.goodFeed)
        harness.outline.selectRowIndexes([row], byExtendingSelection: false)
        harness.window.makeFirstResponder(harness.outline)
        harness.outline.keyDown(with: FocusHarness.returnKey)
        harness.controller.showUpdate(Self.release)
        await harness.finishLoading()

        await harness.pressReturnOnFeed(harness.goodFeed)

        #expect(harness.controller.status == "Loaded 2 headlines from Example News")
    }
}
