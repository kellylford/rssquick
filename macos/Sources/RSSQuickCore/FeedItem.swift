import Foundation

/// A node in the feed tree: either a feed, or a folder holding more of them.
///
/// A reference type because `NSOutlineView` identifies its rows by object identity - it asks for
/// `child(_:ofItem:)` and then hands the same item back in every later call. It is immutable, so
/// it is safely `Sendable` and can be handed to a background load without copying.
public final class FeedItem: Sendable {
    public let title: String

    /// The feed URL. Empty for a folder.
    public let url: String

    public let category: String

    /// True for a folder, which loads every feed beneath it rather than one.
    public let isCategory: Bool

    public let children: [FeedItem]

    public init(
        title: String,
        url: String = "",
        category: String = "",
        isCategory: Bool = false,
        children: [FeedItem] = []
    ) {
        self.title = title
        self.url = url
        self.category = category
        self.isCategory = isCategory
        self.children = children
    }

    /// Every feed under this folder, at any depth. A feed answers with itself.
    public var allFeeds: [FeedItem] {
        guard isCategory else { return [self] }
        return children.flatMap(\.allFeeds)
    }
}
