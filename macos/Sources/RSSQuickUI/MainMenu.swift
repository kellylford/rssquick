import AppKit

/// The menu bar.
///
/// Not decoration. On macOS the menu bar is the discoverable index of everything an application
/// can do: VoiceOver reads it, Help's search field finds items in it by name, and every command
/// in it is reachable from the keyboard whether or not the reader knows its shortcut. A Mac
/// application that hides its commands in the window is much harder to drive without sight than
/// the equivalent Windows one, because Windows has no equivalent of that search.
@MainActor
public enum MainMenu {
    public static func build(applicationName: String = "RSS Quick") -> NSMenu {
        let root = NSMenu()

        root.addItem(applicationMenu(applicationName))
        root.addItem(fileMenu())
        root.addItem(editMenu())
        root.addItem(articleMenu())
        root.addItem(viewMenu())
        root.addItem(windowMenu())
        root.addItem(helpMenu(applicationName))

        return root
    }

    private static func applicationMenu(_ name: String) -> NSMenuItem {
        let menu = NSMenu(title: name)
        menu.addItem(withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        let services = NSMenu(title: "Services")
        let servicesItem = menu.addItem(withTitle: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        NSApp.servicesMenu = services

        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")

        let hideOthers = menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]

        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        return wrap(menu)
    }

    private static func fileMenu() -> NSMenuItem {
        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "Import OPML File…", action: #selector(MainWindowController.importOpml(_:)), keyEquivalent: "o")

        // Dimmed rather than hidden when there is nothing for them to do, so VoiceOver reads
        // them as unavailable and the reader learns they exist. See validateMenuItem.
        menu.addItem(withTitle: "Make This My Default Feed List", action: #selector(MainWindowController.makeDefaultFeedList(_:)), keyEquivalent: "d")
        menu.addItem(withTitle: "Use Starter Feed List", action: #selector(MainWindowController.useStarterFeedList(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh", action: #selector(MainWindowController.refresh(_:)), keyEquivalent: "r")

        // Command-period is the Mac's stop-what-you-are-doing key. Escape does the same thing
        // and is what the Windows build uses, but it cannot be shown as a menu equivalent.
        menu.addItem(withTitle: "Stop Loading", action: #selector(MainWindowController.stopLoading(_:)), keyEquivalent: ".")

        return wrap(menu)
    }

    /// Standard editing commands, which the Import panel's own text fields need.
    private static func editMenu() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return wrap(menu)
    }

    private static func articleMenu() -> NSMenuItem {
        let menu = NSMenu(title: "Article")
        menu.addItem(withTitle: "Open in Browser", action: #selector(MainWindowController.openInBrowser(_:)), keyEquivalent: "b")
        return wrap(menu)
    }

    private static func viewMenu() -> NSMenuItem {
        let menu = NSMenu(title: "View")

        menu.addItem(withTitle: "Feed Tree", action: #selector(MainWindowController.focusFeedTreeCommand(_:)), keyEquivalent: "1")
        menu.addItem(withTitle: "Headlines", action: #selector(MainWindowController.focusHeadlinesCommand(_:)), keyEquivalent: "2")

        // F6 and Control-Tab do this too; they are handled in the window rather than here
        // because Tab cannot be a menu key equivalent.
        let cycle = menu.addItem(withTitle: "Next Pane", action: #selector(MainWindowController.cyclePanes(_:)), keyEquivalent: String(NSEvent.SpecialKey.f6.unicodeScalar))
        cycle.keyEquivalentModifierMask = []

        menu.addItem(.separator())
        menu.addItem(withTitle: "Larger Text", action: #selector(MainWindowController.increaseTextSize(_:)), keyEquivalent: "+")
        menu.addItem(withTitle: "Smaller Text", action: #selector(MainWindowController.decreaseTextSize(_:)), keyEquivalent: "-")
        menu.addItem(withTitle: "Actual Size", action: #selector(MainWindowController.resetTextSize(_:)), keyEquivalent: "0")

        return wrap(menu)
    }

    private static func windowMenu() -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = menu
        return wrap(menu)
    }

    private static func helpMenu(_ name: String) -> NSMenuItem {
        let menu = NSMenu(title: "Help")
        menu.addItem(withTitle: "\(name) Keyboard Shortcuts", action: #selector(AppDelegate.showKeyboardShortcuts(_:)), keyEquivalent: "/")
        NSApp.helpMenu = menu
        return wrap(menu)
    }

    private static func wrap(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
