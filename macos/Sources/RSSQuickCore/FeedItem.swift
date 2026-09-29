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

    /// Where this node's `<outline>` sits in the OPML file: its index among its parent's outlines,
    /// at each level down from `<body>`.
    ///
    /// Nil for the "Uncategorized" folder the parser makes up for loose feeds, which has no
    /// element of its own - adding to it adds at the top level. This is what lets `OpmlEditor`
    /// change the file the tree came from rather than rebuilding one from the tree and losing
    /// whatever the parser does not read.
    public let outlinePath: [Int]?

    public init(
        title: String,
        url: String = "",
        category: String = "",
        isCategory: Bool = false,
        children: [FeedItem] = [],
        outlinePath: [Int]? = nil
    ) {
        self.title = title
        self.url = url
        self.category = category
        self.isCategory = isCategory
        self.children = children
        self.outlinePath = outlinePath
    }

    /// Every feed under this folder, at any depth. A feed answers with itself.
    public var allFeeds: [FeedItem] {
        guard isCategory else { return [self] }
        return children.flatMap(\.allFeeds)
    }
}
