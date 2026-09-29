import Foundation

/// Search across every feed in the list: which feeds to fetch, which headlines match, and what to
/// say about it.
///
/// There is no cache, so searching all feeds means fetching them all, the way a folder load does,
/// and keeping the headlines that match. A headline matches when every word of the search appears
/// in its title or in its feed's name, ignoring case and accents - so "bbc storm" finds the BBC's
/// storm stories, and "cafe" finds "Café".
///
/// The Windows version is `src/RSSQuick/Services/HeadlineSearch.cs`, and the two say the same
/// things in the same words - apart from the ellipsis, which is the character on the Mac and three
/// dots on Windows, as in each platform's other loading messages.
public enum HeadlineSearch {
    /// The words of a search, cleaned the way a headline is.
    public static func words(_ query: String) -> [String] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return FeedText.cleanTitle(query).split(separator: " ").map(String.init)
    }

    /// True when every word appears in the headline's title or its feed's name.
    public static func matches(_ article: ArticleItem, words: [String]) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return !words.isEmpty && words.allSatisfy { word in
            article.title.range(of: word, options: options) != nil
                || article.feedTitle.range(of: word, options: options) != nil
        }
    }

    /// The matching headlines, in the order given.
    public static func filter(_ articles: [ArticleItem], query: String) -> [ArticleItem] {
        let words = words(query)
        return articles.filter { matches($0, words: words) }
    }

    /// Every feed in the tree once, in reading order.
    ///
    /// The same feed can sit in two folders - the starter list has several - and fetching it twice
    /// would list each of its matches twice.
    public static func feedsToSearch(_ roots: [FeedItem]) -> [FeedItem] {
        var seen = Set<String>()
        return roots.flatMap(\.allFeeds).filter { feed in
            seen.insert(feed.url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted
        }
    }

    /// What the search is doing, for the status line while it runs.
    public static func describeStart(_ query: String, feedCount: Int) -> String {
        "Searching \(StartupFeedList.feeds(feedCount)) for \(query)…"
    }

    /// One line covering what was found, and how much of the list could be searched.
    public static func describe(_ query: String, matches: Int, result: FolderLoadResult) -> String {
        if result.feedsAttempted > 0, result.feedsSucceeded == 0 {
            return "None of the \(StartupFeedList.feeds(result.feedsAttempted)) could be loaded, so nothing was searched"
        }

        let found = switch matches {
        case 0: "No headlines match \(query)"
        case 1: "Found 1 headline matching \(query)"
        default: "Found \(matches) headlines matching \(query)"
        }

        let searched = result.failures.isEmpty
            ? " in \(StartupFeedList.feeds(result.feedsAttempted))"
            : " in \(result.feedsSucceeded) of \(StartupFeedList.feeds(result.feedsAttempted)); \(result.failures.count) could not be loaded"

        return found + searched
    }
}
