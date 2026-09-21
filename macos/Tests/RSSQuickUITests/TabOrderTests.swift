import AppKit
import Testing
@testable import RSSQuickUI

@Suite("Tab order", .serialized)
@MainActor
struct TabOrderTests {
    /// Import, feed tree, headlines, Open in Browser, and back to the start.
    ///
    /// Asserted on the chain rather than by calling `selectNextKeyView`, deliberately: whether
    /// Tab reaches a button at all depends on the machine's Keyboard Navigation setting, and a
    /// test that changes its answer with the developer's System Settings is worth nothing. What
    /// this fixes is the order, which is ours.
    @Test("The tab ring runs Import, feeds, headlines, Open in Browser")
    func ringOrder() async throws {
        let harness = try await FocusHarness.make()

        #expect(harness.controller.importButton.nextKeyView === harness.outline)
        #expect(harness.outline.nextKeyView === harness.table)
        #expect(harness.table.nextKeyView === harness.controller.openButton)
        #expect(harness.controller.openButton.nextKeyView === harness.controller.importButton)
    }

    /// AppKit's own loop orders controls geometrically, which put Open in Browser ahead of the
    /// headlines it acts on. The ring above is only kept if the automatic one is turned off.
    @Test("The ring is ours, not the one AppKit recalculates")
    func automaticLoopDisabled() async throws {
        let harness = try await FocusHarness.make()
        #expect(harness.window.autorecalculatesKeyViewLoop == false)
    }

    @Test("Tab lands on a panel that can hold focus")
    func panelsAcceptFocus() async throws {
        let harness = try await FocusHarness.make()

        #expect(harness.outline.acceptsFirstResponder)
        #expect(harness.table.acceptsFirstResponder)
        #expect(harness.outline.refusesFirstResponder == false)
        #expect(harness.table.refusesFirstResponder == false)
    }

    @Test("The window opens with focus in the feed tree")
    func initialFocus() async throws {
        let harness = try await FocusHarness.make()
        #expect(harness.window.initialFirstResponder === harness.outline)
    }

    /// Both panels report a name, so focus arriving anywhere in the window says where it is.
    @Test("Both panels name themselves to a screen reader")
    func panelsAreNamed() async throws {
        let harness = try await FocusHarness.make()

        #expect(harness.outline.accessibilityLabel()?.isEmpty == false)
        #expect(harness.table.accessibilityLabel()?.isEmpty == false)
        #expect(harness.outline.accessibilityHelp()?.isEmpty == false)
        #expect(harness.table.accessibilityHelp()?.isEmpty == false)
        #expect(harness.controller.statusField.accessibilityLabel() == "Status")
    }
}
