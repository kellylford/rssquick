import Foundation
import Testing
import RSSQuickTestSupport
@testable import RSSQuickCore

@Suite("Reading a feed")
struct FeedParserTests {
    private func parse(_ text: String, title: String = "Preferred") throws -> [ArticleItem] {
        try FeedParser.parse(Data(text.utf8), preferredTitle: title)
    }

    @Test("RSS 2.0 items come back newest first")
    func rssNewestFirst() throws {
        let articles = try parse(SampleFeeds.rss2)

        #expect(articles.map(\.title) == ["Newer story", "Older story"])
        #expect(articles.first?.link == "https://example.com/newer")
        #expect(articles.first?.summary == "Something else happened.")
    }

    /// On Windows a malformed date throws from a property getter, and one bad entry used to
    /// lose the whole feed. Dates are the field publishers get wrong most often.
    @Test("One unreadable date costs that article its timestamp and nothing else")
    func badDateDoesNotLoseTheFeed() throws {
        let articles = try parse(SampleFeeds.rss2WithBadDate)

        #expect(articles.count == 3)
        let bad = try #require(articles.first { $0.title == "Bad date" })
        #expect(bad.publishedOn == nil)
        #expect(bad.published.isEmpty)
    }

    @Test("Undated articles sort below dated ones, keeping the feed's own order")
    func undatedSortLast() throws {
        let articles = try parse("""
        <rss version="2.0"><channel><title>Mixed</title>
          <item><title>No date one</title><link>https://example.com/1</link></item>
          <item><title>Dated</title><link>https://example.com/2</link><pubDate>Mon, 02 Mar 2026 09:00:00 GMT</pubDate></item>
          <item><title>No date two</title><link>https://example.com/3</link></item>
        </channel></rss>
        """)

        #expect(articles.map(\.title) == ["Dated", "No date one", "No date two"])
    }

    /// Feeds commonly carry an enclosure ahead of the article link, and taking the first one
    /// meant Return opened an MP3 instead of the story.
    @Test("The article link wins over an enclosure")
    func alternateLinkPreferred() throws {
        let articles = try parse(SampleFeeds.podcast)
        #expect(articles.first?.link == "https://example.com/episode-4")
    }

    @Test("Atom: rel=alternate wins over the other relationships")
    func atomAlternateLink() throws {
        let articles = try parse(SampleFeeds.atom)
        #expect(articles.first?.link == "https://example.com/entry-1")
    }

    @Test("Atom: the publication date beats the later update time")
    func atomPublishedBeatsUpdated() throws {
        let published = try #require(try parse(SampleFeeds.atom).first?.publishedOn)
        #expect(published == ISO8601DateFormatter().date(from: "2026-03-02T09:00:00Z"))
    }

    @Test("Atom: updated is used when there is no published")
    func atomUpdatedFallback() throws {
        let articles = try parse("""
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>T</title>
          <entry><title>E</title><link rel="alternate" href="https://example.com/e"/><updated>2026-03-05T11:30:00Z</updated></entry>
        </feed>
        """)

        #expect(articles.first?.publishedOn == ISO8601DateFormatter().date(from: "2026-03-05T11:30:00Z"))
    }

    @Test("Atom: the author's name is read out of the nested element")
    func atomAuthor() throws {
        #expect(try parse(SampleFeeds.atom).first?.author == "A Writer")
    }

    @Test("RSS 1.0 over RDF is read, including its Dublin Core date and author")
    func rdfRead() throws {
        let articles = try parse(SampleFeeds.rdf)

        #expect(articles.map(\.title) == ["An RDF item"])
        #expect(articles.first?.author == "Someone")
        #expect(articles.first?.publishedOn != nil)
    }

    @Test("Every article records the feed it came from")
    func feedTitleRecorded() throws {
        #expect(try parse(SampleFeeds.rss2).allSatisfy { $0.feedTitle == "Preferred" })
    }

    @Test("The feed's own title is used only when the OPML entry gave none")
    func fallbackTitle() throws {
        #expect(try parse(SampleFeeds.rss2, title: "").first?.feedTitle == "Example News")
    }

    /// Titles reaching a headline go through the cleaner. There is one factory for this so the
    /// two loading paths cannot drift apart again.
    @Test("Headline text is cleaned on the way in")
    func titlesCleaned() throws {
        #expect(try parse(SampleFeeds.braille).first?.title == "Lions GM Brad Holmes")
    }

    @Test("An item with no title reads as No Title rather than as a blank row")
    func missingTitle() throws {
        let articles = try parse("<rss version=\"2.0\"><channel><title>T</title><item><link>https://example.com/a</link></item></channel></rss>")
        #expect(articles.first?.title == "No Title")
    }

    @Test("A permalink guid is used when the item gave no link")
    func guidAsLink() throws {
        let articles = try parse("""
        <rss version="2.0"><channel><title>T</title>
          <item><title>A</title><guid isPermaLink="true">https://example.com/a</guid></item>
        </channel></rss>
        """)

        #expect(articles.first?.link == "https://example.com/a")
    }

    @Test("A guid marked as not a permalink is an identifier, not an address")
    func guidNotPermalink() throws {
        let articles = try parse("""
        <rss version="2.0"><channel><title>T</title>
          <item><title>A</title><guid isPermaLink="false">https://example.com/a</guid></item>
        </channel></rss>
        """)

        #expect(articles.first?.link.isEmpty == true)
    }

    @Test("CDATA titles and descriptions are read")
    func cdata() throws {
        let articles = try parse("""
        <rss version="2.0"><channel><title>T</title>
          <item><title><![CDATA[Bread & butter]]></title><description><![CDATA[<p>Body</p>]]></description><link>https://example.com/a</link></item>
        </channel></rss>
        """)

        #expect(articles.first?.title == "Bread & butter")
        #expect(articles.first?.summary == "<p>Body</p>")
    }

    @Test("content:encoded is used when the item offered no description")
    func contentEncodedFallback() throws {
        let articles = try parse("""
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
          <channel><title>T</title>
            <item><title>A</title><link>https://example.com/a</link><content:encoded>The whole body</content:encoded></item>
          </channel>
        </rss>
        """)

        #expect(articles.first?.summary == "The whole body")
    }

    @Test("A channel logo's title is not mistaken for the feed's own")
    func imageTitleIgnored() throws {
        let articles = try parse("""
        <rss version="2.0"><channel>
          <image><title>Logo</title><url>https://example.com/l.png</url></image>
          <title>The Real Title</title>
          <item><title>A</title><link>https://example.com/a</link></item>
        </channel></rss>
        """, title: "")

        #expect(articles.first?.feedTitle == "The Real Title")
    }

    @Test("A well-formed document that is not a feed says so in words")
    func notAFeed() {
        #expect(throws: FeedParser.Failure.self) { _ = try parse(SampleFeeds.notAFeed) }
        #expect(ErrorText.describe(FeedParser.Failure.notAFeed) == "is not a feed RSS Quick understands")
    }

    @Test("Content that is not XML says so in words")
    func malformed() {
        #expect(throws: FeedParser.Failure.self) { _ = try parse(SampleFeeds.malformedXML) }
        #expect(ErrorText.describe(FeedParser.Failure.notWellFormed("x")) == "is not valid XML")
    }

    @Test("A DOCTYPE declaration is refused before parsing begins")
    func doctypeRefused() {
        #expect(throws: XMLSafety.DoctypeRejected.self) {
            _ = try parse("""
            <?xml version="1.0"?>
            <!DOCTYPE rss [<!ENTITY a "aaaa">]>
            <rss version="2.0"><channel><title>&a;</title></channel></rss>
            """)
        }
    }

    @Test("A feed whose article text mentions a DOCTYPE still parses")
    func doctypeInContentAllowed() throws {
        let articles = try parse("""
        <rss version="2.0"><channel><title>T</title>
          <item><title>On writing &lt;!DOCTYPE html&gt;</title><link>https://example.com/a</link></item>
        </channel></rss>
        """)

        #expect(articles.count == 1)
    }
}

@Suite("Feed dates")
struct FeedDateTests {
    @Test("RFC 822, as RSS 2.0 requires it")
    func rfc822() {
        #expect(FeedDate.parse("Mon, 02 Mar 2026 09:00:00 GMT") != nil)
        #expect(FeedDate.parse("Mon, 02 Mar 2026 09:00:00 +0000") != nil)
        #expect(FeedDate.parse("02 Mar 2026 09:00:00 GMT") != nil)
        #expect(FeedDate.parse("Mon, 02 Mar 2026 09:00 GMT") != nil)
    }

    @Test("ISO 8601, as Atom requires it")
    func iso8601() {
        #expect(FeedDate.parse("2026-03-02T09:00:00Z") != nil)
        #expect(FeedDate.parse("2026-03-02T09:00:00+01:00") != nil)
        #expect(FeedDate.parse("2026-03-02T09:00:00.123Z") != nil)
    }

    @Test("The looser forms publishers use anyway")
    func looseForms() {
        #expect(FeedDate.parse("2026-03-02") != nil)
        #expect(FeedDate.parse("2026-03-02 09:00:00") != nil)
    }

    @Test("Nonsense is nil rather than an error")
    func nonsense() {
        #expect(FeedDate.parse("last Tuesday-ish") == nil)
        #expect(FeedDate.parse("") == nil)
        #expect(FeedDate.parse(nil) == nil)
        #expect(FeedDate.parse("   ") == nil)
    }

    /// A French locale must not stop an English feed's dates parsing.
    @Test("An English feed parses whatever the reader's locale is")
    func localeIndependent() {
        #expect(FeedDate.parse("Wed, 04 Mar 2026 09:00:00 GMT") != nil)
    }
}
