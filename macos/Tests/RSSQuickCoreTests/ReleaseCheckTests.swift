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
        page: String = "https://github.com/kellylford/rssquick/releases/tag/v1.3.0"
    ) -> String {
        """
        {
          "tag_name": "\(tag)",
          "html_url": "\(page)",
          "draft": \(draft),
          "prerelease": \(prerelease),
          "assets": [
            { "name": "\(asset)" },
            { "name": "RSSQuick-1.3.0-portable-win-x64.zip" }
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
            page: URL(string: "https://github.com/kellylford/rssquick/releases/tag/v1.3.0")!))
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

    // MARK: Over the network

    @Test("A release is read from the server")
    func readFromServer() async throws {
        let server = try LocalFeedServer(routes: [
            "/releases/latest": .init(body: Self.release(), contentType: "application/json"),
        ])
        defer { server.stop() }

        let found = try await ReleaseCheck.check(
            api: URL(string: server.url(for: "/releases/latest"))!, current: Self.running)

        #expect(found?.version == "1.3.0")
    }

    /// At launch this is ignored; from Check for Updates it is reported, because the reader asked.
    @Test("A server error is an error, not an answer")
    func serverErrorThrows() async throws {
        let server = try LocalFeedServer(routes: [
            "/limited": .init(status: 403, body: Self.release(), contentType: "application/json"),
        ])
        defer { server.stop() }

        await #expect(throws: (any Error).self) {
            _ = try await ReleaseCheck.check(api: URL(string: server.url(for: "/limited"))!, current: Self.running)
        }
    }
}
