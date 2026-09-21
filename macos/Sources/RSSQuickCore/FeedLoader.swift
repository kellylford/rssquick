import Foundation

/// One feed that could not be read, and why, in words a reader can act on.
public struct FeedFailure: Sendable, Equatable {
    public let feedTitle: String
    public let reason: String

    public init(feedTitle: String, reason: String) {
        self.feedTitle = feedTitle
        self.reason = reason
    }
}

/// The outcome of loading a folder: what arrived, and what did not.
public struct FolderLoadResult: Sendable {
    public let articles: [ArticleItem]
    public let failures: [FeedFailure]
    public let feedsAttempted: Int

    public var feedsSucceeded: Int { feedsAttempted - failures.count }

    public init(articles: [ArticleItem], failures: [FeedFailure], feedsAttempted: Int) {
        self.articles = articles
        self.failures = failures
        self.feedsAttempted = feedsAttempted
    }
}

/// Fetches and parses feeds.
public enum FeedLoader {
    /// How many of a folder's feeds are fetched at once.
    ///
    /// Bounded rather than unbounded: a folder can hold dozens of feeds, and opening that many
    /// connections at once is unkind to a shared connection and gets a client rate-limited by
    /// some publishers. Six is enough that one slow server no longer holds up the rest.
    public static let maxConcurrentFeeds = 6

    /// Long enough for a slow-but-working server, short enough that a dead one does not read as
    /// the application having hung.
    public static let requestTimeout: TimeInterval = 15

    /// A hostile or misconfigured server cannot make us buffer an unbounded response.
    static let maxResponseBytes = 16 * 1024 * 1024

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout * 2
        // No cache at all, matching the Windows build: a reader who presses F5 is asking for
        // what the publisher has now, not for what was in a store from an hour ago.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = [
            // Some publishers reject requests with no User-Agent, or serve them a challenge page.
            "User-Agent": "RSSQuick/1.1 (macOS; +https://github.com/kellylford/rssquick)",
            "Accept": "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.9, */*;q=0.5",
            // Most feeds are served compressed and are several times smaller for it.
            "Accept-Encoding": "gzip, deflate",
        ]
        return URLSession(configuration: configuration)
    }()

    /// A response that did not arrive with a success status.
    public struct HTTPFailure: Error {
        public let status: Int
    }

    public struct MalformedURL: Error {}

    public struct ResponseTooLarge: Error {}

    /// Loads one feed's articles, newest first.
    public static func loadFeed(_ feed: FeedItem) async throws -> [ArticleItem] {
        try await fetch(feed)
    }

    /// Loads every feed in a folder concurrently and merges the results, newest first.
    ///
    /// A feed that fails does not fail the folder. Its reason is collected into `failures` so the
    /// caller can say so - on Windows those failures used to go to a `Console.WriteLine` that a
    /// windowed process discards, leaving a short list and no explanation.
    ///
    /// - Parameter progress: Reports the number of feeds finished, for the status bar.
    public static func loadFolder(
        _ feeds: [FeedItem],
        progress: (@Sendable (Int) -> Void)? = nil
    ) async throws -> FolderLoadResult {
        guard !feeds.isEmpty else {
            return FolderLoadResult(articles: [], failures: [], feedsAttempted: 0)
        }

        // Indexed rather than appended, so a folder's headlines come out in the same order every
        // time. Undated articles from different feeds would otherwise interleave by whichever
        // server answered first.
        var perFeed = [[ArticleItem]](repeating: [], count: feeds.count)
        var failures: [FeedFailure] = []
        var completed = 0

        try await withThrowingTaskGroup(of: (Int, Result<[ArticleItem], Error>).self) { group in
            var next = 0

            func addTask() {
                let index = next
                let feed = feeds[index]
                next += 1

                group.addTask {
                    do {
                        return (index, .success(try await fetch(feed)))
                    } catch {
                        // Only a cancellation the caller actually asked for stops the folder.
                        // A timeout is an ordinary per-feed failure - that distinction is the
                        // whole reason this function exists, and conflating the two is what made
                        // one slow server take down twenty working ones.
                        if Task.isCancelled { throw CancellationError() }
                        return (index, .failure(error))
                    }
                }
            }

            for _ in 0..<Swift.min(maxConcurrentFeeds, feeds.count) { addTask() }

            while let (index, result) = try await group.next() {
                completed += 1
                progress?(completed)

                switch result {
                case .success(let articles):
                    perFeed[index] = articles
                case .failure(let error):
                    failures.append(FeedFailure(feedTitle: feeds[index].title, reason: ErrorText.describe(error)))
                }

                if next < feeds.count { addTask() }
            }
        }

        return FolderLoadResult(
            articles: perFeed.flatMap { $0 }.sortedNewestFirst(),
            failures: failures,
            feedsAttempted: feeds.count
        )
    }

    private static func fetch(_ feed: FeedItem) async throws -> [ArticleItem] {
        guard let url = URL(string: feed.url), url.scheme != nil else { throw MalformedURL() }

        let (data, response) = try await session.data(from: url)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw HTTPFailure(status: http.statusCode)
        }

        guard data.count <= maxResponseBytes else { throw ResponseTooLarge() }

        return try FeedParser.parse(data, preferredTitle: feed.title)
    }

}
