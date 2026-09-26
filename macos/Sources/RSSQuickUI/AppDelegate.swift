import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()

        let controller = MainWindowController()
        mainWindow = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The list of keys, in a window rather than in a README nobody has open.
    ///
    /// A reader who has just been handed this application needs to find out how to drive it
    /// without leaving it, and Help is where macOS teaches people to look.
    @objc public func showKeyboardShortcuts(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "RSS Quick Keyboard Shortcuts"
        alert.informativeText = """
        Moving around
          Tab / Shift-Tab      Import button, feed tree, headlines, Open in Browser
          F6 or Control-Tab    Switch between the feed tree and the headlines
          Command-1 / 2        Go straight to the feed tree or the headlines
          Arrow keys           Move within a list; Left and Right collapse and expand folders
          Type a few letters   Jump to a feed or headline by name

        Reading
          Return               On a feed, load its headlines. On a folder, load all of them.
                               On a headline, open it in your browser.
          Command-B            Open the selected headline in your browser
          Command-R or F5      Reload what is on screen
          Escape or Command-.  Stop a load that is taking too long

        Text and files
          Command-Plus/Minus   Larger or smaller text, remembered between launches
          Command-0            Back to the standard size
          Command-O            Import a different OPML feed list
          Command-D            Make the feed list on screen your default

        Selecting a feed never fetches anything. Only Return does.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
