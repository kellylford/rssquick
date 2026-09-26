import AppKit
import Foundation
import Testing
import RSSQuickCore
@testable import RSSQuickUI

/// Make This My Default Feed List and Use Starter Feed List, in the real window: when each is
/// dimmed, and what each writes. The Windows version is tests/RSSQuick.Tests/DefaultFeedListTests.cs.
@Suite("The default feed list commands", .serialized)
@MainActor
struct DefaultFeedListTests {
    private static let mine = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline text="Mine">
              <outline text="My feed" xmlUrl="https://example.com/mine.xml"/>
            </outline>
          </body>
        </opml>
        """.utf8)

    /// A window whose saved list is `saved`, set before construction because startup reads it.
    private func makeWindow(saving data: Data? = nil) throws -> MainWindowController {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let saved = FocusHarness.emptySavedFeedList()
        if let data { try saved.save(data) }
        MainWindowController.savedFeedList = saved
        return MainWindowController()
    }

    private func isEnabled(_ action: Selector, in controller: MainWindowController) -> Bool {
        controller.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
    }

    private let makeDefault = #selector(MainWindowController.makeDefaultFeedList(_:))
    private let useStarter = #selector(MainWindowController.useStarterFeedList(_:))

    @Test("With nothing saved, Use Starter Feed List is dimmed")
    func nothingSaved() throws {
        let controller = try makeWindow()

        #expect(!isEnabled(useStarter, in: controller))
    }

    @Test("A saved list opens at startup, and cannot be made the default again")
    func savedOpensAtStartup() throws {
        let controller = try makeWindow(saving: Self.mine)

        #expect(controller.roots.map(\.title) == ["Mine"])
        #expect(controller.currentFeedList?.isSaved == true)
        #expect(!isEnabled(makeDefault, in: controller))
        #expect(isEnabled(useStarter, in: controller))
    }

    @Test("An imported list can be made the default, which saves its exact bytes")
    func makeImportedListDefault() throws {
        let controller = try makeWindow()
        let imported = try OpenedFeedList(data: Self.mine, isSaved: false)

        controller.show(imported, isDefault: false)
        #expect(isEnabled(makeDefault, in: controller))

        controller.makeDefaultFeedList(nil)

        #expect(try Data(contentsOf: MainWindowController.savedFeedList.url) == Self.mine)
        #expect(!isEnabled(makeDefault, in: controller))
        #expect(isEnabled(useStarter, in: controller))
        #expect(controller.status.hasPrefix("Saved as your default feed list"))
    }

    @Test("Use Starter Feed List forgets the saved list")
    func useStarterForgets() throws {
        let controller = try makeWindow(saving: Self.mine)

        controller.useStarterFeedList(nil)

        #expect(!MainWindowController.savedFeedList.exists)
        #expect(!isEnabled(useStarter, in: controller))
    }
}
