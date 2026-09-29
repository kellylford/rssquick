import Foundation
import Testing
@testable import RSSQuickCore

/// Which headlines a search finds, and what it says about them. The Windows version answers the
/// same questions in tests/RSSQuick.Tests/HeadlineSearchTests.cs.
@Suite("Searching headlines")
struct HeadlineSearchTests {
    private static func headline(_ title: String, _ feed: String = "BBC News") -> ArticleItem {
        ArticleItem(title: title, link: "", feedTitle: feed)
    }

    private static let headlines = [
        headline("Storm closes schools"),
        headline("Café opens in the high street", "Local"),
        headline("Election results", "The Guardian"),
        headline("Storm warning for the coast", "The Guardian"),
    ]

    private func find(_ query: String) -> [String] {
        HeadlineSearch.filter(Self.headlines, query: query).map(\.title)
    }

    @Test("A word matches any headline containing it, whatever its case")
    func caseInsensitive() {
        #expect(find("STORM") == ["Storm closes schools", "Storm warning for the coast"])
    }

    @Test("Every word has to match, but not next to each other")
    func everyWord() {
        #expect(find("coast storm") == ["Storm warning for the coast"])
    }

    @Test("A feed's name counts, so a search can narrow to one publisher")
    func feedName() {
        #expect(find("bbc storm") == ["Storm closes schools"])
    }

    @Test("Accents are ignored")
    func accents() {
        #expect(find("cafe") == ["Café opens in the high street"])
    }

    @Test("Nothing to search for finds nothing")
    func empty() {
        #expect(find("").isEmpty)
        #expect(find("   ").isEmpty)
    }

    @Test("A feed in two folders is searched once")
    func duplicates() {
        let a = FeedItem(title: "A", isCategory: true, children: [FeedItem(title: "One", url: "https://example.com/one.xml")])
        let b = FeedItem(title: "B", isCategory: true, children: [
            FeedItem(title: "One again", url: "https://EXAMPLE.com/one.xml"),
            FeedItem(title: "Two", url: "https://example.com/two.xml"),
        ])

        #expect(HeadlineSearch.feedsToSearch([a, b]).map(\.title) == ["One", "Two"])
    }

    @Test("What it says covers found, nothing found, and failures")
    func descriptions() {
        let clean = FolderLoadResult(articles: Self.headlines, failures: [], feedsAttempted: 12)
        let partial = FolderLoadResult(articles: Self.headlines, failures: [FeedFailure(feedTitle: "Gone", reason: "timed out")], feedsAttempted: 12)
        let none = FolderLoadResult(articles: [], failures: [FeedFailure(feedTitle: "A", reason: "x"), FeedFailure(feedTitle: "B", reason: "y")], feedsAttempted: 2)

        #expect(HeadlineSearch.describeStart("storm", feedCount: 12) == "Searching 12 feeds for storm…")
        #expect(HeadlineSearch.describe("storm", matches: 2, result: clean) == "Found 2 headlines matching storm in 12 feeds")
        #expect(HeadlineSearch.describe("storm", matches: 1, result: clean) == "Found 1 headline matching storm in 12 feeds")
        #expect(HeadlineSearch.describe("storm", matches: 0, result: clean) == "No headlines match storm in 12 feeds")
        #expect(HeadlineSearch.describe("storm", matches: 2, result: partial) == "Found 2 headlines matching storm in 11 of 12 feeds; 1 could not be loaded")
        #expect(HeadlineSearch.describe("storm", matches: 0, result: none) == "None of the 2 feeds could be loaded, so nothing was searched")
    }
}
