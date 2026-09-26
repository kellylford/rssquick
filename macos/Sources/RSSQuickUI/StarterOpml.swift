import Foundation
import RSSQuickCore

/// Locates the feed list RSS Quick ships with.
public enum StarterOpml {
    /// Matched case-insensitively by the file system, so this covers RSS.opml and rss.opml.
    private static let fileName = "RSS.opml"

    /// The first feed list found, or nil when there is none.
    ///
    /// The working directory comes first, so "drop an rss.opml beside the program and launch it
    /// there" keeps working, and so a copy run from a folder of its own uses the list beside it.
    /// The application bundle's own resources are the fallback: a program launched from the Dock
    /// or from Spotlight is given the user's home directory as its working directory, and
    /// without this the installed build would open with an empty feed tree even though RSS.opml
    /// sits right inside it. Both come after the reader's saved default; see
    /// `StartupFeedList.choose`.
    public static func find() -> URL? {
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(fileName),
            Bundle.main.resourceURL?.appendingPathComponent(fileName),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(fileName),
        ]

        return candidates
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// ~/Library/Application Support/RSSQuick/Default.opml
    public static let savedListURL = URL.applicationSupportDirectory
        .appendingPathComponent("RSSQuick", isDirectory: true)
        .appendingPathComponent("Default.opml")
}
