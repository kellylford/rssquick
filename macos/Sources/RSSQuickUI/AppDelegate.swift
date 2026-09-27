import AppKit
import RSSQuickCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var mainWindow: MainWindowController?

    /// A newer version than this one, once a check has found it.
    private(set) var availableUpdate: AvailableRelease?

    /// How long after launch to look for a newer version: long enough that startup has finished
    /// announcing the feed list and placing focus, so the check competes with neither.
    private static let updateCheckDelay: Duration = .seconds(5)

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()

        let controller = MainWindowController()
        mainWindow = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        // Here rather than in the window controller, so that the tests - which build windows
        // without an application delegate - never reach GitHub.
        if let version = Self.runningVersion {
            Task { [weak self] in
                try? await Task.sleep(for: Self.updateCheckDelay)
                // Failures are ignored at launch. No network is not worth interrupting anyone
                // for, and the next launch asks again.
                guard let release = try? await ReleaseCheck.check(current: version) else { return }
                self?.offer(release)
            }
        }
    }

    /// The version in the bundle's Info.plist, which make-app.sh copies from VERSION.
    ///
    /// Nil under `swift run`, which has no bundle, so a development build never asks.
    static var runningVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private func offer(_ release: AvailableRelease) {
        availableUpdate = release
        mainWindow?.showUpdate(release)
    }

    /// RSS Quick menu: Check for Updates…, or Download RSS Quick <version>… once one is known.
    @objc public func checkForUpdates(_ sender: Any?) {
        if let release = availableUpdate {
            NSWorkspace.shared.open(release.page)
            mainWindow?.setStatus("Opened the RSS Quick \(release.version) page in your browser")
            return
        }

        guard let version = Self.runningVersion else {
            mainWindow?.setStatus("This copy of RSS Quick is a development build, so it has no version to compare")
            return
        }

        mainWindow?.setStatus("Checking for a newer version…")
        Task { [weak self] in
            do {
                if let release = try await ReleaseCheck.check(current: version) {
                    self?.offer(release)
                } else {
                    self?.mainWindow?.setStatus("RSS Quick \(version) is the newest version")
                }
            } catch {
                self?.mainWindow?.setStatus("Could not check for a newer version - GitHub \(ErrorText.describe(error))")
            }
        }
    }

    /// Names the version in the menu once there is one, so the menu itself says there is an
    /// update - to a reader browsing it, and to Help's search.
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) {
            menuItem.title = availableUpdate.map { "Download RSS Quick \($0.version)…" } ?? "Check for Updates…"
        }
        return true
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
