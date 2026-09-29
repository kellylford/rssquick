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

    // MARK: Subscribing, removing and exporting

    /// Every folder a new feed can go into, and the top level.
    var folderChoices: [FolderChoice] { OpmlEditor.folders(current?.document.roots ?? []) }

    /// The top level, which is where a subscription goes unless the reader picks a folder.
    var topLevel: FolderChoice {
        OpmlEditor.suggest(folderChoices, roots: roots, selected: nil)
    }

    /// The list on screen, exactly as read or last changed, for Export Feed List.
    var exportData: Data? { current?.data }

    /// Finds the feed at an address, adds it to the list, and saves the list as the default.
    ///
    /// Saving is not optional, as on the desktop: a subscription that vanished the next time the
    /// app opened would be worse than none. Nothing changes until the feed has been found and the
    /// list saved.
    ///
    /// - Returns: A sentence for the reader to hear, and whether it worked, so the sheet knows
    ///   whether to close.
    func subscribe(to address: String, into folder: FolderChoice) async -> (message: String, succeeded: Bool) {
        if let typed = FeedDiscovery.normalize(address),
           let known = OpmlEditor.findFeed(roots, url: typed.absoluteString) {
            return ("You already subscribe to \(known.title), in \(known.category).", false)
        }

        let feed: DiscoveredFeed
        do {
            feed = try await FeedDiscovery.find(address)
        } catch {
            return ("Could not subscribe. \(address) \(ErrorText.describe(error)).", false)
        }

        if let existing = OpmlEditor.findFeed(roots, url: feed.url) {
            return ("You already subscribe to \(existing.title), in \(existing.category).", false)
        }

        switch change({ try OpmlEditor.addFeed(to: $0, folder: folder.path, title: feed.title, url: feed.url) }) {
        case .failure(let reason):
            return ("Could not add \(feed.title) to your feed list. \(reason)", false)
        case .success(let note):
            return ("Subscribed to \(feed.title) in \(folder.name).\(note)", true)
        }
    }

    /// Takes a feed out of the list and saves the list as the default.
    func remove(_ feed: FeedItem) -> String {
        guard !feed.isCategory, let path = feed.outlinePath else { return "Only a feed can be removed." }

        switch change({ try OpmlEditor.remove(from: $0, at: path) }) {
        case .failure(let reason):
            return "Could not remove \(feed.title). \(reason)"
        case .success(let note):
            return "Removed \(feed.title).\(note)"
        }
    }

    private enum Change {
        /// What to add when this made the list the default, which the reader did not ask for in
        /// so many words.
        case success(note: String)
        case failure(String)
    }

    private func change(_ edit: (Data) throws -> Data) -> Change {
        let list: OpenedFeedList
        do {
            let data = try edit(current?.data ?? OpmlEditor.empty)
            list = try OpenedFeedList(data: data, isSaved: true)
            try saved.save(data)
        } catch {
            return .failure(Self.describe(error))
        }

        let note = isShowingDefault ? "" : " This feed list is now your default, so it opens every time RSS Quick starts."
        show(list, isDefault: true)
        hasSavedList = true
        return .success(note: note)
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
        case let failure as OpmlEditor.Failure: failure.description
        case is XMLSafety.DoctypeRejected: "The file declares a DOCTYPE, which RSS Quick does not accept."
        default: error.localizedDescription
        }
    }

    static func feeds(_ count: Int) -> String {
        count == 1 ? "1 feed" : "\(count) feeds"
    }
}
