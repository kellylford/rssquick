import AppKit

/// The one channel by which anything is spoken without the user asking for it.
///
/// On Windows this is the status bar `TextBlock`, the single element carrying
/// `AutomationProperties.LiveSetting="Polite"`. AppKit has no live-region attribute, so the
/// equivalent is an announcement notification; the rule it exists to enforce is the same one.
/// Everything that wants to tell the reader something goes through `MainWindowController.status`
/// rather than adding a second channel, because two things talking at once is worse than either.
@MainActor
enum Announcer {
    /// Speaks a message, politely - VoiceOver finishes what it is saying first.
    ///
    /// Not everything written to the status bar comes through here. Moving between rows updates
    /// the status text but does not announce it: VoiceOver already says "3 of 45" on its own for
    /// a table row, and repeating it turns every arrow key into two announcements. What is
    /// announced is what VoiceOver has no other way to know - load results, failures, and where
    /// focus has just been sent.
    static func announce(_ message: String, in window: NSWindow?) {
        guard let window, !message.isEmpty else { return }

        NSAccessibility.post(
            element: window,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }
}
