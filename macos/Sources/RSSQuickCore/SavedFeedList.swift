import Foundation

/// The feed list the reader chose to open every time RSS Quick starts.
///
/// The one thing RSS Quick keeps between runs, on every platform. It is a copy of the file, not a
/// note of where the file was: on iOS there is no choice, because a file picked from Files is
/// only lent to the app for the moment it was picked, and on the Mac a copy means moving or
/// deleting the original does not break startup.
///
/// The copy is the file's exact bytes, never a list rebuilt from the tree, so nothing the parser
/// does not understand is lost by saving it.
///
/// The Windows version is `src/RSSQuick/Services/SavedFeedList.cs`. The two answer the same
/// questions, and their tests should change together.
public struct SavedFeedList: Sendable {
    /// Where the copy lives.
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// The saved bytes, or nil when nothing has been saved.
    public func load() throws -> Data? {
        guard exists else { return nil }
        return try Data(contentsOf: url)
    }

    /// Replaces the saved list.
    ///
    /// Atomic, so a failure part way through leaves the previous default intact rather than half
    /// a file.
    public func save(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Removes the saved list, so the starter list opens next time.
    public func forget() throws {
        guard exists else { return }
        try FileManager.default.removeItem(at: url)
    }
}

/// A feed list as it was opened: the tree, and the bytes it came from.
public struct OpenedFeedList: Sendable {
    public let document: OpmlDocument

    /// Kept so the list on screen can be saved exactly as it was read.
    public let data: Data

    /// True when this is the reader's saved default.
    public var isSaved: Bool

    public init(data: Data, isSaved: Bool) throws {
        self.document = try OpmlParser.parse(data)
        self.data = data
        self.isSaved = isSaved
    }
}

/// What to show at startup.
public struct StartupFeedList: Sendable {
    /// Nil when there is nothing to show.
    public let list: OpenedFeedList?

    /// Set when a saved list exists but could not be used, so the reader can be told why they
    /// are looking at the starter list instead of their own.
    public let savedListProblem: String?

    /// The saved list if there is a usable one, otherwise the starter list.
    ///
    /// The saved list has to come first: the app always carries the shipped RSS.opml, so anything
    /// that looked there first would never reach the reader's own. A saved list that cannot be
    /// read is left where it is rather than deleted. It is the reader's, and Use Starter Feed List
    /// is there for them to clear it deliberately.
    ///
    /// - Parameter starter: The shipped RSS.opml, or nil when there is none.
    /// - Throws: Only for a starter list that will not parse, which the caller reports exactly as
    ///   it did before there was such a thing as a saved list.
    public static func choose(saved: SavedFeedList, starter: URL?) throws -> StartupFeedList {
        var problem: String?
        do {
            if let data = try saved.load() {
                return StartupFeedList(list: try OpenedFeedList(data: data, isSaved: true), savedListProblem: nil)
            }
        } catch {
            problem = "Your default feed list could not be read (\(ErrorText.describe(error)))"
        }

        guard let starter else {
            return StartupFeedList(list: nil, savedListProblem: problem)
        }
        let list = try OpenedFeedList(data: Data(contentsOf: starter), isSaved: false)
        return StartupFeedList(list: list, savedListProblem: problem)
    }

    /// "1 feed" or "12 feeds".
    public static func feeds(_ count: Int) -> String {
        count == 1 ? "1 feed" : "\(count) feeds"
    }
}
