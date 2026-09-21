import Foundation
import Testing
import RSSQuickTestSupport
@testable import RSSQuickCore

@Suite("Reading an OPML feed list")
struct OpmlParserTests {
    private func parse(_ text: String) throws -> OpmlDocument {
        try OpmlParser.parse(Data(text.utf8))
    }

    @Test("Folders nest to whatever depth the file uses")
    func nesting() throws {
        let document = try parse(SampleFeeds.opml)

        let news = try #require(document.roots.first { $0.title == "News" })
        #expect(news.isCategory)
        #expect(news.children.map(\.title) == ["Wires", "Papers"])

        let wires = try #require(news.children.first)
        #expect(wires.children.map(\.title) == ["Reuters", "AP"])
        #expect(wires.children.allSatisfy { !$0.isCategory })
    }

    @Test("Feeds are counted at any depth; folders are not")
    func feedCount() throws {
        #expect(try parse(SampleFeeds.opml).feedCount == 4)
    }

    /// Every feed sits inside a folder so the tree has one shape rather than two.
    @Test("A feed listed loose at the top level lands in Uncategorized")
    func looseFeedsGathered() throws {
        let document = try parse(SampleFeeds.opml)

        let uncategorized = try #require(document.roots.first { $0.title == "Uncategorized" })
        #expect(uncategorized.isCategory)
        #expect(uncategorized.children.map(\.title) == ["A loose feed"])
    }

    @Test("An outline with an xmlUrl is a feed whatever its type attribute says")
    func typeAttributeIgnored() throws {
        let document = try parse("""
        <opml><body>
          <outline text="Folder">
            <outline text="No type given" xmlUrl="https://example.com/a.xml"/>
          </outline>
        </body></opml>
        """)

        let feed = try #require(document.roots.first?.children.first)
        #expect(!feed.isCategory)
        #expect(feed.url == "https://example.com/a.xml")
    }

    @Test("text is preferred over title, as the OPML spec says")
    func textPreferredOverTitle() throws {
        let document = try parse("""
        <opml><body><outline text="From text" title="From title"/></body></opml>
        """)

        #expect(document.roots.first?.title == "From text")
    }

    @Test("An outline with no usable label is named rather than left blank")
    func unnamedOutline() throws {
        let document = try parse("<opml><body><outline text=\"   \"/></body></opml>")
        #expect(document.roots.first?.title == "Unknown")
    }

    /// Feed names come from the same exporters as headlines and carry the same invisible
    /// characters, and they are read out just as often.
    @Test("Outline names are cleaned the way headlines are")
    func outlineNamesCleaned() throws {
        let document = try parse("""
        <opml><body><outline text="The\u{00A0}Guardian\u{200B}" xmlUrl="https://example.com/g.xml"/></body></opml>
        """)

        let feed = try #require(document.roots.first?.children.first)
        #expect(feed.title == "The Guardian")
    }

    @Test("A feed records the folder it came from")
    func categoryRecorded() throws {
        let document = try parse(SampleFeeds.opml)
        let reuters = try #require(document.roots.first?.children.first?.children.first)
        #expect(reuters.category == "Wires")
    }

    @Test("A file with no body is rejected with something a reader can act on")
    func noBody() {
        #expect(throws: OpmlParser.Failure.self) {
            _ = try parse("<opml><head><title>Nothing here</title></head></opml>")
        }
    }

    @Test("Content that is not XML is rejected")
    func notXML() {
        #expect(throws: (any Error).self) { _ = try parse("this is not xml at all") }
    }

    /// Entity expansion is the standard way to turn parsing a small file into a denial of
    /// service, and an OPML file is whatever the reader exported from wherever.
    @Test("A DOCTYPE declaration is refused before parsing begins")
    func doctypeRefused() {
        #expect(throws: XMLSafety.DoctypeRejected.self) {
            _ = try parse("""
            <?xml version="1.0"?>
            <!DOCTYPE opml [<!ENTITY a "aaaaaaaaaa">]>
            <opml><body><outline text="&a;"/></body></opml>
            """)
        }
    }

    @Test("A DOCTYPE inside article text is not mistaken for a declaration")
    func doctypeInContentAllowed() throws {
        let document = try parse("""
        <opml><body><outline text="Writing &lt;!DOCTYPE html&gt; by hand" xmlUrl="https://example.com/a.xml"/></body></opml>
        """)

        #expect(document.feedCount == 1)
    }

    @Test("Every feed under a folder is found, at any depth")
    func allFeedsRecursive() throws {
        let document = try parse(SampleFeeds.opml)
        let news = try #require(document.roots.first { $0.title == "News" })

        #expect(news.allFeeds.map(\.title) == ["Reuters", "AP", "The Guardian"])
    }
}
