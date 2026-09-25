import Foundation
import Observation

/// The feed list, and where it came from.
///
/// This is the one place the iOS version keeps anything between runs, and it is a deliberate
/// difference from Windows. There a file on disk is simply there next time; on iOS a file picked
/// from Files is only lent to the app for the moment it was picked, so without a copy the reader
/// would have to import their list again every launch. Only the OPML is kept - never feed
/// content, which is always fetched fresh, as on the other platforms.
@MainActor
@Observable
final class FeedStore {
    private(set) var roots: [FeedItem] = []
    private(set) var feedCount = 0

    /// Set when the list could not be read, for the feed list to show in place of the tree.
    private(set) var loadError: String?

    /// True once the reader has imported a list of their own.
    private(set) var isUsingImportedList = false

    init() {
        loadSavedOrBundledList()
    }

    private static var importedListURL: URL {
        URL.applicationSupportDirectory.appending(path: "Imported.opml")
    }

    private func loadSavedOrBundledList() {
        let imported = Self.importedListURL
        if FileManager.default.fileExists(atPath: imported.path()), apply(try? Data(contentsOf: imported)) {
            isUsingImportedList = true
            return
        }

        guard let bundled = Bundle.main.url(forResource: "RSS", withExtension: "opml") else {
            loadError = "The starter feed list is missing from this copy of RSS Quick. Import an OPML file to begin."
            return
        }
        _ = apply(try? Data(contentsOf: bundled))
        isUsingImportedList = false
    }

    /// Replaces the feed list with an OPML file the reader picked, and keeps a copy for next time.
    ///
    /// The file is parsed before anything is replaced, so choosing the wrong file leaves the
    /// current list exactly where it was.
    ///
    /// - Returns: A sentence describing what happened, for the reader to hear.
    func importList(from url: URL) -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        let document: OpmlDocument
        do {
            data = try Data(contentsOf: url)
            document = try OpmlParser.parse(data)
        } catch {
            return "Could not import \(url.lastPathComponent). \(Self.describe(error))"
        }

        guard document.feedCount > 0 else {
            return "\(url.lastPathComponent) has no feeds in it. Your feed list has not changed."
        }

        show(document)
        isUsingImportedList = true

        do {
            try FileManager.default.createDirectory(
                at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try data.write(to: Self.importedListURL, options: .atomic)
        } catch {
            return "Imported \(Self.feeds(document.feedCount)), but could not save the list for next time."
        }

        return "Imported \(Self.feeds(document.feedCount))."
    }

    /// Goes back to the list RSS Quick ships with.
    func restoreStarterList() -> String {
        try? FileManager.default.removeItem(at: Self.importedListURL)
        loadSavedOrBundledList()
        return "Restored the starter feed list, \(Self.feeds(feedCount))."
    }

    private func apply(_ data: Data?) -> Bool {
        guard let data, let document = try? OpmlParser.parse(data) else {
            loadError = "The feed list could not be read. Import an OPML file to replace it."
            return false
        }
        show(document)
        return true
    }

    private func show(_ document: OpmlDocument) {
        roots = document.roots
        feedCount = document.feedCount
        loadError = nil
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case let failure as OpmlParser.Failure: failure.description
        case is XMLSafety.DoctypeRejected: "The file declares a DOCTYPE, which RSS Quick does not accept."
        default: error.localizedDescription
        }
    }

    static func feeds(_ count: Int) -> String {
        count == 1 ? "1 feed" : "\(count) feeds"
    }
}
