import Foundation
import Testing
@testable import RSSQuickCore
import RSSQuickTestSupport

/// When a published release counts as a newer version for this copy. The Windows version answers
/// the same questions in tests/RSSQuick.Tests/ReleaseCheckTests.cs; the two should change together.
@Suite("Finding a newer release", .serialized)
struct ReleaseCheckTests {
    private static let dmg = ReleaseCheck.macAssetSuffix
    private static let running = "1.2.0"

    private static func release(
        tag: String = "v1.3.0",
        asset: String = "RSSQuick-1.3.0-macos.dmg",
        draft: Bool = false,
        prerelease: Bool = false,
        page: String = "https://github.com/TheIdeaPlace/rssquick/releases/tag/v1.3.0",
        otherAsset: String = "RSSQuick-1.3.0-portable-win-x64.zip"
    ) -> String {
        """
        {
          "tag_name": "\(tag)",
          "html_url": "\(page)",
          "draft": \(draft),
          "prerelease": \(prerelease),
          "assets": [
            { "name": "\(asset)" },
            { "name": "\(otherAsset)" }
          ]
        }
        """
    }

    private static func parse(_ json: String, current: String = running) -> AvailableRelease? {
        ReleaseCheck.parse(Data(json.utf8), current: current, assetSuffix: dmg)
    }

    // MARK: What counts as newer

    @Test("A newer release with a download for this copy is offered")
    func newerIsOffered() {
        let found = Self.parse(Self.release())

        #expect(found == AvailableRelease(
            version: "1.3.0",
            page: URL(string: "https://github.com/TheIdeaPlace/rssquick/releases/tag/v1.3.0")!))
    }

    @Test("The release that is running is not offered")
    func sameIsNotOffered() {
        #expect(Self.parse(Self.release(tag: "v1.2.0")) == nil)
    }

    @Test("An older release is not offered")
    func olderIsNotOffered() {
        #expect(Self.parse(Self.release(tag: "v1.1.0")) == nil)
    }

    /// The Windows assembly says 1.2.0.0 against a tag of 1.2.0. Info.plist says 1.2.0, but the
    /// rule is kept the same on both sides: the fourth part is not a different release.
    @Test("A four-part running version matches its three-part tag")
    func fourPartsMatchThree() {
        #expect(Self.parse(Self.release(tag: "v1.2.0"), current: "1.2.0.0") == nil)
        #expect(Self.parse(Self.release(tag: "v1.2.1"), current: "1.2.0.0") != nil)
    }

    @Test("Versions compare as numbers, not text")
    func numericComparison() {
        #expect(Self.parse(Self.release(tag: "v1.10.0"), current: "1.9.0") != nil)
    }

    @Test("A tag without a leading v is read")
    func tagWithoutV() {
        #expect(Self.parse(Self.release(tag: "1.3.0")) != nil)
    }

    // MARK: What does not count at all

    /// A Windows-only fix, say. Nothing on the page would be of use to this copy.
    @Test("A release with no download for this copy is not offered")
    func noAssetForThisCopy() {
        #expect(Self.parse(Self.release(asset: "RSSQuick-1.3.0-portable-win-arm64.zip")) == nil)
    }

    @Test("Drafts and prereleases are not offered")
    func draftsAndPrereleases() {
        #expect(Self.parse(Self.release(draft: true)) == nil)
        #expect(Self.parse(Self.release(prerelease: true)) == nil)
    }

    @Test("A tag that is not a version is ignored")
    func tagNotAVersion() {
        #expect(Self.parse(Self.release(tag: "nightly")) == nil)
    }

    @Test("A page that is not https is never opened")
    func pageNotHTTPS() {
        #expect(Self.parse(Self.release(page: "file:///Applications/Calculator.app")) == nil)
    }

    @Test("A page that is not on GitHub is never opened")
    func pageNotOnGitHub() {
        #expect(Self.parse(Self.release(page: "https://example.com/rssquick-1.3.0")) == nil)
    }

    @Test("Anything else is nothing rather than an error", arguments: [
        "",
        "not json",
        "[]",
        "{}",
        #"{ "tag_name": 13, "html_url": "https://github.com/", "assets": [] }"#,
        #"{ "message": "API rate limit exceeded" }"#,
    ])
    func malformed(json: String) {
        #expect(Self.parse(json) == nil)
    }

    // MARK: A list of releases

    private static func list(_ releases: String...) -> String {
        "[" + releases.joined(separator: ",") + "]"
    }

    /// A fix can ship on one platform alone. Here a Windows-only 1.4.3 is the latest release, and
    /// the Mac-only 1.4.2 before it is the one this copy needs.
    @Test("A later release for another platform does not hide one for this copy")
    func laterReleaseForAnotherPlatform() {
        let json = Self.list(
            Self.release(tag: "v1.4.3", asset: "RSSQuick-1.4.3-portable-win-x64.zip", otherAsset: "notes.txt",
                         page: "https://github.com/TheIdeaPlace/rssquick/releases/tag/v1.4.3"),
            Self.release(tag: "v1.4.2", asset: "RSSQuick-1.4.2-macos.dmg", otherAsset: "notes.txt",
                         page: "https://github.com/TheIdeaPlace/rssquick/releases/tag/v1.4.2"))

        #expect(Self.parse(json)?.version == "1.4.2")
    }

    @Test("The newest version in the list wins, whatever its position")
    func newestWins() {
        let json = Self.list(
            Self.release(tag: "v1.3.1", asset: "RSSQuick-1.3.1-macos.dmg"),
            Self.release(tag: "v1.4.0", asset: "RSSQuick-1.4.0-macos.dmg"),
            Self.release(tag: "v1.3.0"))

        #expect(Self.parse(json)?.version == "1.4.0")
    }

    @Test("A list with nothing newer for this copy is nothing")
    func listWithNothingNewer() {
        let json = Self.list(
            Self.release(tag: "v1.5.0", asset: "RSSQuick-1.5.0-portable-win-x64.zip", otherAsset: "notes.txt"),
            Self.release(tag: "v1.4.0", draft: true),
            Self.release(tag: "v1.1.0"))

        #expect(Self.parse(json) == nil)
    }

    @Test("The check reads the list of releases, not only the latest")
    func readsTheList() {
        #expect(ReleaseCheck.releasesAPI.path.hasSuffix("/releases"))
    }

    // MARK: Over the network

    @Test("A release is read from the server")
    func readFromServer() async throws {
        let server = try await LocalFeedServer.start(routes: [
            "/releases": .init(body: Self.list(Self.release(tag: "v1.2.1"), Self.release()), contentType: "application/json"),
        ])
        defer { server.stop() }

        let found = try await ReleaseCheck.check(
            api: URL(string: server.url(for: "/releases"))!, current: Self.running)

        #expect(found?.version == "1.3.0")
    }

    /// At launch this is ignored; from Check for Updates it is reported, because the reader asked.
    @Test("A server error is an error, not an answer")
    func serverErrorThrows() async throws {
        let server = try await LocalFeedServer.start(routes: [
            "/limited": .init(status: 403, body: Self.release(), contentType: "application/json"),
        ])
        defer { server.stop() }

        await #expect(throws: (any Error).self) {
            _ = try await ReleaseCheck.check(api: URL(string: server.url(for: "/limited"))!, current: Self.running)
        }
    }
}
