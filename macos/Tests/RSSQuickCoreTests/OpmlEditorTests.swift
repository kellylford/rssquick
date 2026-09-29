import Foundation
import Testing
@testable import RSSQuickCore

/// Subscribing and unsubscribing edit the OPML file itself. The Windows version answers the same
/// questions in tests/RSSQuick.Tests/OpmlEditorTests.cs; the two should change together.
@Suite("Editing a feed list")
struct OpmlEditorTests {
    private static let list = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Mine</title><ownerName>Someone</ownerName></head>
          <body>
            <outline text="News">
              <outline text="Wires">
                <outline text="Reuters" xmlUrl="https://example.com/reuters.xml" htmlUrl="https://example.com/"/>
              </outline>
              <outline text="Guardian" xmlUrl="https://example.com/guardian.xml"/>
            </outline>
            <outline text="Loose" xmlUrl="https://example.com/loose.xml"/>
            <outline text="Sport">
              <outline text="Scores" xmlUrl="https://example.com/scores.xml"/>
            </outline>
          </body>
        </opml>
        """.utf8)

    private func read(_ data: Data) throws -> OpmlDocument { try OpmlParser.parse(data) }

    private func all(_ nodes: [FeedItem]) -> [FeedItem] {
        nodes.flatMap { [$0] + all($0.children) }
    }

    private func folder(_ document: OpmlDocument, _ title: String) throws -> FeedItem {
        try #require(all(document.roots).first { $0.isCategory && $0.title == title })
    }

    private func feed(_ document: OpmlDocument, _ title: String) throws -> FeedItem {
        try #require(all(document.roots).first { !$0.isCategory && $0.title == title })
    }

    @Test("The parser records where each outline is")
    func outlinePaths() throws {
        let document = try read(Self.list)

        #expect(try folder(document, "News").outlinePath == [0])
        #expect(try feed(document, "Reuters").outlinePath == [0, 0, 0])
        #expect(try feed(document, "Loose").outlinePath == [1])
        #expect(try feed(document, "Scores").outlinePath == [2, 0])
        // Made up by the parser for loose feeds, so it has no element of its own.
        #expect(try folder(document, "Uncategorized").outlinePath == nil)
    }

    @Test("A feed added to a nested folder goes at its end")
    func addToNestedFolder() throws {
        let wires = try folder(read(Self.list), "Wires")

        let changed = try read(OpmlEditor.addFeed(to: Self.list, folder: wires.outlinePath, title: "AP", url: "https://example.com/ap.xml"))

        let after = try folder(changed, "Wires")
        #expect(after.children.map(\.title) == ["Reuters", "AP"])
        #expect(after.children[1].url == "https://example.com/ap.xml")
        #expect(changed.feedCount == 5)
    }

    @Test("A feed added at the top level is shown as Uncategorized")
    func addAtTopLevel() throws {
        let changed = try read(OpmlEditor.addFeed(to: Self.list, folder: nil, title: "New", url: "https://example.com/new.xml"))

        #expect(try folder(changed, "Uncategorized").children.map(\.title) == ["Loose", "New"])
    }

    @Test("Adding keeps everything the parser does not read")
    func keepsUnreadContent() throws {
        let text = String(decoding: try OpmlEditor.addFeed(to: Self.list, folder: nil, title: "New", url: "https://example.com/new.xml"), as: UTF8.self)

        #expect(text.contains("<ownerName>Someone</ownerName>"))
        #expect(text.contains("htmlUrl=\"https://example.com/\""))
    }

    @Test("A title with markup characters is escaped, not broken")
    func escaping() throws {
        let changed = try read(OpmlEditor.addFeed(to: Self.list, folder: nil, title: "Q&A <live>", url: "https://example.com/qa.xml?a=1&b=2"))

        #expect(try feed(changed, "Q&A <live>").url == "https://example.com/qa.xml?a=1&b=2")
    }

    @Test("Removing takes out exactly that feed")
    func removeFeed() throws {
        let guardian = try feed(read(Self.list), "Guardian")

        let changed = try read(OpmlEditor.remove(from: Self.list, at: try #require(guardian.outlinePath)))

        #expect(try folder(changed, "News").children.map(\.title) == ["Wires"])
        #expect(changed.feedCount == 3)
    }

    @Test("Removing a loose feed leaves the folders alone")
    func removeLooseFeed() throws {
        let loose = try feed(read(Self.list), "Loose")

        let changed = try read(OpmlEditor.remove(from: Self.list, at: try #require(loose.outlinePath)))

        #expect(!changed.roots.contains { $0.title == "Uncategorized" })
        #expect(try feed(changed, "Scores").title == "Scores")
    }

    @Test("A path that is not there is refused rather than guessed")
    func missingPath() {
        #expect(throws: OpmlEditor.Failure.self) { try OpmlEditor.remove(from: Self.list, at: [9, 9]) }
    }

    @Test("An empty list takes a first feed")
    func emptyList() throws {
        let changed = try read(OpmlEditor.addFeed(to: OpmlEditor.empty, folder: nil, title: "First", url: "https://example.com/first.xml"))

        #expect(changed.feedCount == 1)
        #expect(try feed(changed, "First").title == "First")
    }

    @Test("A list with a DOCTYPE is refused, as it is on import")
    func doctype() {
        let hostile = Data(#"<?xml version="1.0"?><!DOCTYPE opml [<!ENTITY x "x">]><opml><body/></opml>"#.utf8)

        #expect(throws: XMLSafety.DoctypeRejected.self) {
            try OpmlEditor.addFeed(to: hostile, folder: nil, title: "A", url: "https://example.com/a.xml")
        }
    }

    @Test("Folders are named with the folders above them, and include the top level")
    func folderNames() throws {
        let folders = OpmlEditor.folders(try read(Self.list).roots)

        #expect(folders.map(\.name) == ["News", "News / Wires", "Uncategorized", "Sport"])
        #expect(folders.first { $0.name == "Uncategorized" }?.path == nil)
    }

    @Test("A list with no loose feeds still offers the top level, last")
    func topLevelLast() throws {
        let folders = OpmlEditor.folders(try read(OpmlEditor.remove(from: Self.list, at: [1])).roots)

        #expect(folders.last == FolderChoice(name: "Uncategorized", path: nil))
    }

    @Test("The suggested folder is the one the reader is in")
    func suggestion() throws {
        let document = try read(Self.list)
        let folders = OpmlEditor.folders(document.roots)

        #expect(OpmlEditor.suggest(folders, roots: document.roots, selected: try feed(document, "Reuters")).name == "News / Wires")
        #expect(OpmlEditor.suggest(folders, roots: document.roots, selected: try folder(document, "Sport")).name == "Sport")
        #expect(OpmlEditor.suggest(folders, roots: document.roots, selected: nil).name == "Uncategorized")
    }

    @Test("An address already in the list is found, whatever its case or trailing slash")
    func findFeed() throws {
        let roots = try read(Self.list).roots

        #expect(OpmlEditor.findFeed(roots, url: "HTTPS://example.com/scores.xml/")?.title == "Scores")
        #expect(OpmlEditor.findFeed(roots, url: "https://example.com/other.xml") == nil)
    }
}
