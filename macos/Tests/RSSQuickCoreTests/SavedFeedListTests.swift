import Foundation
import Testing
@testable import RSSQuickCore

/// Which feed list opens at startup, and what saving one keeps. The Windows version answers the
/// same questions in tests/RSSQuick.Tests/SavedFeedListTests.cs; the two should change together.
@Suite("The saved default feed list")
struct SavedFeedListTests {
    private static let mine = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline text="Mine">
              <outline text="My feed" xmlUrl="https://example.com/mine.xml" category="kept"/>
            </outline>
          </body>
        </opml>
        """

    private static let starter = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline text="Starter">
              <outline text="One" xmlUrl="https://example.com/one.xml"/>
              <outline text="Two" xmlUrl="https://example.com/two.xml"/>
            </outline>
          </body>
        </opml>
        """

    /// A fresh folder per test, so tests running in parallel never share a saved list.
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("rssquick-saved-\(UUID().uuidString)")

    private var saved: SavedFeedList {
        SavedFeedList(url: folder.appendingPathComponent("RSSQuick/Default.opml"))
    }

    private func writeStarter() throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("RSS.opml")
        try Data(Self.starter.utf8).write(to: url)
        return url
    }

    @Test("With nothing saved, the starter list opens")
    func starterWhenNothingSaved() throws {
        let startup = try StartupFeedList.choose(saved: saved, starter: writeStarter())

        let list = try #require(startup.list)
        #expect(!list.isSaved)
        #expect(list.document.feedCount == 2)
        #expect(startup.savedListProblem == nil)
    }

    @Test("A saved list opens ahead of the starter list")
    func savedComesFirst() throws {
        try saved.save(Data(Self.mine.utf8))

        let startup = try StartupFeedList.choose(saved: saved, starter: writeStarter())

        let list = try #require(startup.list)
        #expect(list.isSaved)
        #expect(list.document.roots.map(\.title) == ["Mine"])
        #expect(startup.savedListProblem == nil)
    }

    @Test("An unreadable saved list falls back to the starter list, and says so")
    func unreadableFallsBack() throws {
        try saved.save(Data("this is not OPML".utf8))

        let startup = try StartupFeedList.choose(saved: saved, starter: writeStarter())

        let list = try #require(startup.list)
        #expect(!list.isSaved)
        #expect(list.document.feedCount == 2)
        #expect(startup.savedListProblem != nil)
    }

    @Test("An unreadable saved list is left for the reader to clear")
    func unreadableIsKept() throws {
        try saved.save(Data("this is not OPML".utf8))

        _ = try StartupFeedList.choose(saved: saved, starter: writeStarter())

        #expect(saved.exists)
    }

    @Test("When both lists fail, the saved list is still named")
    func bothFail() throws {
        try saved.save(Data("this is not OPML".utf8))
        let starter = try writeStarter()
        try Data("nor is this".utf8).write(to: starter)

        do {
            _ = try StartupFeedList.choose(saved: saved, starter: starter)
            Issue.record("Expected startup to fail when both lists are unreadable")
        } catch {
            let message = "\(error)"
            #expect(message.contains("Your default feed list could not be read"))
            #expect(message.contains("starter feed list could not be read either"))
        }
    }

    @Test("With neither list, there is nothing to show")
    func neither() throws {
        let startup = try StartupFeedList.choose(saved: saved, starter: nil)

        #expect(startup.list == nil)
        #expect(startup.savedListProblem == nil)
    }

    @Test("Saving keeps the exact bytes of the file")
    func exactBytes() throws {
        // A byte order mark, and an attribute the parser ignores: rebuilding the file from the
        // tree would lose both.
        let original = Data([0xEF, 0xBB, 0xBF]) + Data(Self.mine.utf8)

        try saved.save(original)

        #expect(try Data(contentsOf: saved.url) == original)
    }

    @Test("Saving again replaces the previous default")
    func replaces() throws {
        try saved.save(Data(Self.starter.utf8))
        try saved.save(Data(Self.mine.utf8))

        #expect(try Data(contentsOf: saved.url) == Data(Self.mine.utf8))
        let files = try FileManager.default.contentsOfDirectory(atPath: saved.url.deletingLastPathComponent().path)
        #expect(files == ["Default.opml"])
    }

    @Test("Forgetting removes the saved list")
    func forget() throws {
        try saved.save(Data(Self.mine.utf8))

        try saved.forget()

        #expect(!saved.exists)
        let startup = try StartupFeedList.choose(saved: saved, starter: writeStarter())
        #expect(startup.list?.isSaved == false)
    }

    @Test("Forgetting when nothing is saved does nothing")
    func forgetNothing() throws {
        try saved.forget()
        #expect(!saved.exists)
    }
}
