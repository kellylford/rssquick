import SwiftUI

extension FeedItem: Identifiable {
    /// Rows are identified by object, as the macOS outline view identifies them.
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

/// What the navigation stack pushes: the headlines of one feed, or of every feed in a folder.
struct HeadlinesRoute: Hashable {
    let source: FeedItem

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.source === rhs.source }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(source)) }
}

enum Announcer {
    /// Speaks a sentence with VoiceOver.
    ///
    /// The one announcement channel, as the status bar is on Windows and the notification is on
    /// macOS. Delayed slightly because an announcement made in the same moment as a screen
    /// change is dropped when VoiceOver moves focus to the new screen.
    @MainActor
    static func announce(_ message: String, after delay: Duration = .milliseconds(600)) {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            AccessibilityNotification.Announcement(message).post()
        }
    }
}
