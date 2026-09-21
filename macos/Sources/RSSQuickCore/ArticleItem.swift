import Foundation

/// One headline, as shown in the list.
public struct ArticleItem: Sendable, Identifiable {
    public let id = UUID()

    public let title: String
    public let link: String
    public let summary: String

    /// When the article was published, or nil when the feed did not say.
    ///
    /// Kept as a real instant rather than as text. The Windows version sorted by running a parse
    /// over a string it had just formatted, so an article whose formatted date failed to parse
    /// back sorted to the bottom whatever its real date - and which articles those were depended
    /// on the reader's regional settings, because the format was locale-sensitive.
    public let publishedOn: Date?

    public let author: String

    /// The feed this article came from. Always set, including for a single-feed load, because the
    /// status bar names it and a merged folder view has no other way to say where a headline
    /// came from.
    public let feedTitle: String

    public init(
        title: String,
        link: String,
        summary: String = "",
        publishedOn: Date? = nil,
        author: String = "",
        feedTitle: String
    ) {
        self.title = title
        self.link = link
        self.summary = summary
        self.publishedOn = publishedOn
        self.author = author
        self.feedTitle = feedTitle
    }

    /// The one place a parsed feed entry becomes an `ArticleItem`.
    ///
    /// Both of the Windows loading paths used to build these by hand, and they drifted every time
    /// either was touched: title cleaning was applied on one path only, which is the original
    /// braille whitespace bug, and the two later disagreed on date format and on whether the
    /// summary and author were populated at all. Routing everything through here is what stops
    /// that recurring, and it is worth keeping to on this side too.
    public static func from(_ entry: FeedEntry, feedTitle: String) -> ArticleItem {
        ArticleItem(
            title: FeedText.cleanTitle(entry.title),
            link: entry.link,
            summary: entry.summary,
            publishedOn: entry.publishedOn,
            author: entry.author,
            feedTitle: feedTitle
        )
    }

    /// `publishedOn` for display, in the reader's own locale.
    ///
    /// Empty when the feed gave no date. Silence is better than noise here: a date is part of
    /// every headline a screen reader speaks, and a feed with no dates used to announce
    /// "1/1/0001, 12:00 AM" on every single one.
    public var published: String {
        guard let publishedOn else { return "" }
        return ArticleItem.displayFormatter.string(from: publishedOn)
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

public extension Array where Element == ArticleItem {
    /// Dated articles first, newest to oldest, then undated ones in the order the feed gave them -
    /// which for a feed with no dates is its own idea of newest first.
    ///
    /// Stable by construction. Swift's `sorted(by:)` gives no stability guarantee, so undated
    /// articles would otherwise come back in an order that could change between runs over
    /// identical input.
    func sortedNewestFirst() -> [ArticleItem] {
        enumerated()
            .sorted { left, right in
                switch (left.element.publishedOn, right.element.publishedOn) {
                case let (lhs?, rhs?):
                    return lhs == rhs ? left.offset < right.offset : lhs > rhs
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case (nil, nil):
                    return left.offset < right.offset
                }
            }
            .map(\.element)
    }
}
