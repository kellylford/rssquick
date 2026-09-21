import Testing
@testable import RSSQuickCore

@Suite("Headline text cleaning")
struct FeedTextTests {
    @Test("Zero-width characters are removed outright")
    func zeroWidthRemoved() {
        #expect(FeedText.cleanTitle("Break\u{200B}ing") == "Breaking")
        #expect(FeedText.cleanTitle("Break\u{200C}ing") == "Breaking")
        #expect(FeedText.cleanTitle("Break\u{200D}ing") == "Breaking")
        #expect(FeedText.cleanTitle("Break\u{2060}ing") == "Breaking")
        #expect(FeedText.cleanTitle("\u{FEFF}Breaking") == "Breaking")
    }

    @Test("Exotic spaces become ordinary ones")
    func exoticSpacesNormalised() {
        #expect(FeedText.cleanTitle("Five\u{00A0}pounds") == "Five pounds")
        #expect(FeedText.cleanTitle("Five\u{2009}pounds") == "Five pounds")
        #expect(FeedText.cleanTitle("Five\u{202F}pounds") == "Five pounds")
    }

    /// The original bug: deleting control characters ran the words either side together.
    @Test("Tabs separate words rather than disappearing")
    func tabsBecomeSpaces() {
        #expect(FeedText.cleanTitle("Lions GM\t\tBrad Holmes") == "Lions GM Brad Holmes")
        #expect(FeedText.cleanTitle("First line\nSecond line") == "First line Second line")
    }

    @Test("Runs of whitespace collapse, and the edges are trimmed")
    func whitespaceCollapsed() {
        #expect(FeedText.cleanTitle("  Too    much   room  ") == "Too much room")
        #expect(FeedText.cleanTitle("\u{00A0}\u{00A0}Leading") == "Leading")
    }

    @Test("Nothing usable reads as No Title rather than as a blank row")
    func emptyBecomesNoTitle() {
        #expect(FeedText.cleanTitle(nil) == "No Title")
        #expect(FeedText.cleanTitle("") == "No Title")
        #expect(FeedText.cleanTitle("   ") == "No Title")
        #expect(FeedText.cleanTitle("\u{200B}\u{200B}") == "No Title")
    }

    @Test("Ordinary text is left alone")
    func ordinaryTextUntouched() {
        #expect(FeedText.cleanTitle("Budget 2026: what it means") == "Budget 2026: what it means")
        #expect(FeedText.cleanTitle("Café life — a report") == "Café life — a report")
    }
}
