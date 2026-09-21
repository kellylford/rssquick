import AppKit
import RSSQuickUI

// Top-level code runs on the main thread, but in this language mode the compiler does not know
// that, so it is stated rather than assumed.
MainActor.assumeIsolated {
    // A regular application with a Dock icon and a menu bar, rather than the background process
    // a bare executable would otherwise be.
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)

    let delegate = AppDelegate()
    application.delegate = delegate

    application.run()
}
