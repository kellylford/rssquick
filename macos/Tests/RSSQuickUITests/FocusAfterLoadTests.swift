import AppKit
import Testing
import RSSQuickCore
@testable import RSSQuickUI

@Suite("Focus and the status line around a load", .serialized)
@MainActor
struct FocusAfterLoadTests {
    @Test("Selecting a feed does not load it - only Return does")
    func selectionDoesNotLoad() async throws {
        let harness = try await FocusHarness.make()

        let row = harness.outline.row(forItem: harness.goodFeed)
        harness.outline.selectRowIndexes([row], byExtendingSelection: false)
        await harness.settle()

        #expect(harness.controller.headlines.isEmpty)
        #expect(harness.server.requestCount == 0)
    }

    @Test("Return on a feed loads it and hands focus to the first headline")
    func focusLandsOnFirstHeadline() async throws {
        let harness = try await FocusHarness.make()
        await harness.pressReturnOnFeed(harness.goodFeed)

        #expect(harness.controller.headlines.count == 2)
        #expect(harness.window.firstResponder === harness.table)
        #expect(harness.table.selectedRow == 0)
    }

    /// The load summary used to be overwritten within microseconds by the position announcement
    /// that focusing the first headline caused - so "3 of 20 feeds failed", the message with no
    /// other route to the reader, was never seen.
    @Test("The load summary survives the selection the load itself makes")
    func loadSummarySurvives() async throws {
        let harness = try await FocusHarness.make()
        await harness.pressReturnOnFeed(harness.goodFeed)

        #expect(harness.controller.status == "Loaded 2 headlines from Example News")
    }

    @Test("Position takes over from the first arrow key")
    func positionTakesOverAfterwards() async throws {
        let harness = try await FocusHarness.make()
        await harness.pressReturnOnFeed(harness.goodFeed)

        harness.moveDownInHeadlines()

        #expect(harness.controller.status == "Example News - 2 of 2")
    }

    @Test("Coming back to the headlines returns to the row you were on")
    func returnsToTheSameRow() async throws {
        let harness = try await FocusHarness.make()
        await harness.pressReturnOnFeed(harness.goodFeed)

        harness.moveDownInHeadlines()
        harness.controller.focusFeedTree()
        #expect(harness.window.firstResponder === harness.outline)

        harness.controller.focusHeadlines()

        #expect(harness.window.firstResponder === harness.table)
        #expect(harness.table.selectedRow == 1)
    }

    @Test("A second feed starts from the top rather than from the old row")
    func secondLoadStartsAtTheTop() async throws {
        let harness = try await FocusHarness.make()
        await harness.pressReturnOnFeed(harness.goodFeed)
        harness.moveDownInHeadlines()

        await harness.pressReturnOnFeed(harness.otherFeed)

        #expect(harness.table.selectedRow == 0)
        #expect(harness.controller.status == "Loaded 1 headlines from Atom Example")
    }

    /// Windows needed containment rather than an is-focused check here, because focus sits on a
    /// row rather than on the container and both branches read false - so the key only ever
    /// moved one way.
    @Test("F6 moves both ways, not just into the feed tree")
    func cyclingGoesBothWays() async throws {
        let harness = try await FocusHarness.make()
        await harness.pressReturnOnFeed(harness.goodFeed)
        #expect(harness.window.firstResponder === harness.table)

        harness.controller.cycleSections()
        #expect(harness.window.firstResponder === harness.outline)

        harness.controller.cycleSections()
        #expect(harness.window.firstResponder === harness.table)
    }

    @Test("Open in Browser is enabled only when the selected headline has a link")
    func openButtonFollowsTheSelection() async throws {
        let harness = try await FocusHarness.make()
        #expect(harness.controller.openButton.isEnabled == false)

        await harness.pressReturnOnFeed(harness.goodFeed)

        #expect(harness.controller.openButton.isEnabled)
    }

    @Test("Refreshing reloads what is on screen, not what the tree happens to be on")
    func refreshFollowsTheLoadedFeed() async throws {
        let harness = try await FocusHarness.make()
        await harness.pressReturnOnFeed(harness.goodFeed)

        // Arrow on past it, the way a reader looking for the next feed would.
        let row = harness.outline.row(forItem: harness.otherFeed)
        harness.outline.selectRowIndexes([row], byExtendingSelection: false)

        harness.controller.refreshCurrentFeed()
        await harness.finishLoading()

        #expect(harness.controller.status == "Loaded 2 headlines from Example News")
    }

    @Test("Refreshing before anything is loaded says so rather than doing nothing")
    func refreshWithNothingLoaded() async throws {
        let harness = try await FocusHarness.make()
        harness.controller.refreshCurrentFeed()

        #expect(harness.controller.status == "Nothing to refresh yet - press Return on a feed first")
    }

    @Test("Escape abandons a load that is taking too long")
    func escapeCancels() async throws {
        let harness = try await FocusHarness.make()

        harness.controller.loadFeed(harness.slowFeed)
        try await Task.sleep(for: .milliseconds(50))

        harness.controller.cancelOperation(nil)

        #expect(harness.controller.status == "Loading cancelled")
        await harness.settle()
        #expect(harness.controller.headlines.isEmpty)
    }
}

@Suite("Loading a folder", .serialized)
@MainActor
struct FolderLoadTests {
    /// Tested through a folder rather than through a single feed, which puts up a dialog.
    @Test("A feed that fails is named, and the rest still arrive")
    func partialFailureIsReported() async throws {
        let harness = try await FocusHarness.make()
        await harness.pressReturnOnFeed(harness.folder)

        #expect(harness.controller.headlines.count == 3)
        #expect(harness.controller.status.contains("Loaded 3 headlines from 2 of 3 feeds in Everything"))
        #expect(harness.controller.status.contains("Broken server said 500"))
    }

    @Test("A folder's headlines are merged newest first")
    func mergedNewestFirst() async throws {
        let harness = try await FocusHarness.make()
        await harness.pressReturnOnFeed(harness.folder)

        let dates = harness.controller.headlines.compactMap(\.publishedOn)
        #expect(dates == dates.sorted(by: >))
    }

    /// In a merged folder the title alone does not say whose headline it is, and a reader
    /// listening to twenty publishers at once needs to know.
    @Test("After a folder load a row names the feed it came from")
    func rowNamesItsFeed() async throws {
        let harness = try await FocusHarness.make()
        await harness.pressReturnOnFeed(harness.folder)

        let cell = try #require(harness.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? HeadlineCellView)
        let label = try #require(cell.accessibilityLabel())

        #expect(label.hasPrefix(harness.controller.headlines[0].title))
        #expect(label.contains(harness.controller.headlines[0].feedTitle))
    }

    /// The same words on every row would be noise, and a braille line is short.
    @Test("After a single feed a row is just the headline")
    func singleFeedRowIsJustTheHeadline() async throws {
        let harness = try await FocusHarness.make()
        await harness.pressReturnOnFeed(harness.goodFeed)

        let cell = try #require(harness.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? HeadlineCellView)

        #expect(cell.accessibilityLabel() == harness.controller.headlines[0].title)
    }

    @Test("A folder with nothing in it says so")
    func emptyFolder() async throws {
        let harness = try await FocusHarness.make()
        let empty = FeedItem(title: "Nothing", isCategory: true)

        harness.controller.loadFolder(empty)
        await harness.finishLoading()

        #expect(harness.controller.status == "Nothing has no feeds in it")
    }

    @Test("Every failure is summarised rather than listed when there are many")
    func manyFailuresSummarised() {
        let result = FolderLoadResult(
            articles: [],
            failures: (1...5).map { FeedFailure(feedTitle: "Feed \($0)", reason: "timed out") },
            feedsAttempted: 20
        )

        let summary = MainWindowController.describeFolderLoad("Morning", result)

        #expect(summary == "Loaded 0 headlines from 15 of 20 feeds in Morning; 5 failed")
    }

    @Test("A folder where nothing worked says so plainly")
    func everythingFailed() {
        let result = FolderLoadResult(
            articles: [],
            failures: (1...3).map { FeedFailure(feedTitle: "Feed \($0)", reason: "timed out") },
            feedsAttempted: 3
        )

        #expect(MainWindowController.describeFolderLoad("Morning", result)
            == "None of the 3 feeds in Morning could be loaded")
    }
}
