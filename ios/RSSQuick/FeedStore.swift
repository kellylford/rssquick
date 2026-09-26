import Foundation
import Observation

/// The feed list, and where it came from.
///
/// The only thing kept between runs is the reader's saved default, as on Windows and macOS: a
/// copy of the OPML they chose with Make This My Default Feed List. It is a copy rather than a
/// reference because a file picked from Files is only lent to the app for the moment it was
/// picked. Never feed content, which is always fetched fresh, as on the other platforms.
///
/// Importing a list shows it without saving it, so looking at someone else's list does not lose
/// your own. The first TestFlight build saved on every import; that file is where the saved
/// default still lives, so a list saved by that build keeps opening.
@MainActor
@Observable
final class FeedStore {
    private(set) var roots: [FeedItem] = []
    private(set) var feedCount = 0

    /// Set when the list could not be read, for the feed list to show in place of the tree.
    private(set) var loadError: String?

    /// True while the list on screen is the one RSS Quick opens at startup, which is what dims
    /// Make This My Default Feed List.
    private(set) var isShowingDefault = false

    /// True when Make This My Default Feed List has something to do.
    var canMakeDefault: Bool { current != nil && !isShowingDefault }

    /// True when there is a saved default for Use Starter Feed List to forget.
    private(set) var hasSavedList = false

    /// The list on screen, kept so it can be saved as the default exactly as it was read.
    private var current: OpenedFeedList?

    /// Set at startup when a saved list existed but could not be read, for the view to announce
    /// once the screen is up. Handed out once, by `takeStartupProblem`.
    private var startupProblem: String?

    /// The startup problem, if there was one, and never again: the view that asks re-appears
    /// every time the reader comes back from a feed.
    func takeStartupProblem() -> String? {
        defer { startupProblem = nil }
        return startupProblem
    }

    private let saved = SavedFeedList(url: URL.applicationSupportDirectory.appending(path: "Imported.opml"))

    init() {
        loadStartupList()
    }

    private func loadStartupList() {
        let starter = Bundle.main.url(forResource: "RSS", withExtension: "opml")
        do {
            let startup = try StartupFeedList.choose(saved: saved, starter: starter)
            startupProblem = startup.savedListProblem.map { "\($0). Showing the starter feed list instead." }
            if let list = startup.list {
                show(list, isDefault: startup.savedListProblem == nil)
            } else {
                loadError = "The starter feed list is missing from this copy of RSS Quick. Import an OPML file to begin."
            }
        } catch {
            loadError = "The feed list could not be read. Import an OPML file to replace it."
        }
        hasSavedList = saved.exists
    }

    /// Shows an OPML file the reader picked. It does not become the default until they say so.
    ///
    /// The file is parsed before anything is replaced, so choosing the wrong file leaves the
    /// current list exactly where it was.
    ///
    /// - Returns: A sentence describing what happened, for the reader to hear.
    func importList(from url: URL) -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let list: OpenedFeedList
        do {
            list = try OpenedFeedList(data: Data(contentsOf: url), isSaved: false)
        } catch {
            return "Could not import \(url.lastPathComponent). \(Self.describe(error))"
        }

        guard list.document.feedCount > 0 else {
            return "\(url.lastPathComponent) has no feeds in it. Your feed list has not changed."
        }

        show(list, isDefault: false)
        return "Imported \(Self.feeds(list.document.feedCount)). To open it every time, choose Make This My Default Feed List."
    }

    /// Opens the list on screen every time RSS Quick starts.
    func makeCurrentListDefault() -> String {
        guard let current else { return "There is no feed list to make your default. Import one first." }
        guard !isShowingDefault else { return "This feed list is already your default." }

        do {
            try saved.save(current.data)
        } catch {
            return "Could not save your default feed list. \(error.localizedDescription)"
        }

        self.current?.isSaved = true
        isShowingDefault = true
        hasSavedList = true
        return "Saved as your default feed list, \(Self.feeds(current.document.feedCount)). It will open every time RSS Quick starts."
    }

    /// Forgets the saved default and goes back to the list RSS Quick ships with.
    func restoreStarterList() -> String {
        do {
            try saved.forget()
        } catch {
            return "Could not remove your default feed list. \(error.localizedDescription)"
        }
        hasSavedList = false

        // The list on screen stays if the starter cannot be shown, but it no longer opens at
        // startup, so it can be saved again.
        guard let starter = Bundle.main.url(forResource: "RSS", withExtension: "opml") else {
            isShowingDefault = false
            return "Removed your default feed list. The starter feed list is missing from this copy of RSS Quick."
        }
        do {
            let list = try OpenedFeedList(data: Data(contentsOf: starter), isSaved: false)
            show(list, isDefault: true)
            return "Removed your default feed list. Showing the starter feed list, \(Self.feeds(feedCount))."
        } catch {
            isShowingDefault = false
            return "Removed your default feed list, but the starter feed list could not be read. \(Self.describe(error))"
        }
    }

    private func show(_ list: OpenedFeedList, isDefault: Bool) {
        current = list
        isShowingDefault = isDefault
        roots = list.document.roots
        feedCount = list.document.feedCount
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
