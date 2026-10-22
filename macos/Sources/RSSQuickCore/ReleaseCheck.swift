import Foundation

/// A published release newer than the one running.
public struct AvailableRelease: Sendable, Equatable {
    /// Three parts, as the tag has it: "1.3.0".
    public let version: String

    /// The release's page on GitHub, which carries its notes and the disk image.
    public let page: URL

    public init(version: String, page: URL) {
        self.version = version
        self.page = page
    }
}

/// Asks GitHub whether there is a newer release than the one running.
///
/// The Mac version does not update itself: that would mean Sparkle, and with it a nested framework
/// and helper services inside a bundle that is otherwise one signed binary. It says a newer version
/// exists and offers the page, which is also what the Windows portable copy does.
///
/// A release only counts if it carries a disk image. Windows and macOS are released from the same
/// tag, but a fix for one can go out alone, and telling a Mac user about a release with nothing in
/// it for them sends them to a page they cannot use.
///
/// So it reads the list of recent releases rather than only the latest one. A Windows-only 1.4.3
/// published after a Mac-only 1.4.2 is the latest release, and a Mac still on 1.4.0 that looked
/// only at it would never hear about 1.4.2.
///
/// The Windows version is `src/RSSQuick/Services/ReleaseCheck.cs`. The two answer the same
/// questions, and their tests should change together.
public enum ReleaseCheck {
    /// The ten newest releases. Drafts appear only to an authenticated caller. Ten, because each
    /// release's entry lists every file on it, about 36 KB apiece, and this is fetched at every
    /// launch; fixes on three platforms are never ten releases apart.
    public static let releasesAPI = URL(string: "https://api.github.com/repos/TheIdeaPlace/rssquick/releases?per_page=10")!

    /// The end of the disk image's name, which `build/make-dmg.sh` gives every release.
    public static let macAssetSuffix = "-macos.dmg"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = [
            // GitHub's API refuses requests with no User-Agent.
            "User-Agent": "RSSQuick (+https://github.com/TheIdeaPlace/rssquick)",
            "Accept": "application/vnd.github+json",
        ]
        return URLSession(configuration: configuration)
    }()

    /// The newest release listed at `api` that is newer than `current` and carries an asset whose
    /// name ends with `assetSuffix`.
    ///
    /// - Returns: nil when there is nothing newer for this copy.
    /// - Throws: When the question could not be answered - no network, a GitHub outage, a rate
    ///   limit. The check at launch ignores that, because none of it is worth interrupting anyone
    ///   for and the next launch asks again; Check for Updates says so, because the reader asked.
    ///   The Windows version has no Check for Updates, so it returns null for both.
    public static func check(
        api: URL = releasesAPI, current: String, assetSuffix: String = macAssetSuffix
    ) async throws -> AvailableRelease? {
        let (data, response) = try await session.data(from: api)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw FeedLoader.HTTPFailure(status: http.statusCode) }
        return parse(data, current: current, assetSuffix: assetSuffix)
    }

    /// Reads a GitHub list of releases, or a single release. Everything `check` decides, without
    /// the network.
    public static func parse(_ data: Data, current: String, assetSuffix: String) -> AvailableRelease? {
        if let release = try? JSONDecoder().decode(Release.self, from: data) {
            return parse(release, current: current, assetSuffix: assetSuffix)
        }
        guard let list = try? JSONDecoder().decode([Release].self, from: data) else { return nil }

        // Newest by version, not by position: the list is in order of creation, and a patch can be
        // cut after a later version's tag.
        var newest: (numbers: [Int], release: AvailableRelease)?
        for release in list {
            guard let found = parse(release, current: current, assetSuffix: assetSuffix),
                  let numbers = version(fromTag: found.version) else { continue }
            if newest == nil || newest!.numbers.lexicographicallyPrecedes(numbers) {
                newest = (numbers, found)
            }
        }
        return newest?.release
    }

    private static func parse(_ release: Release, current: String, assetSuffix: String) -> AvailableRelease? {
        // A draft is listed only for an authenticated caller, and a prerelease is not for
        // everyone; neither is offered.
        if release.draft == true || release.prerelease == true { return nil }

        guard let tag = release.tag_name, let published = Self.version(fromTag: tag),
              let running = Self.version(fromTag: current), running.lexicographicallyPrecedes(published)
        else { return nil }

        // Opened in the reader's browser, so only ever a page on GitHub.
        guard let pageText = release.html_url, let page = URL(string: pageText), page.scheme == "https",
              page.host?.lowercased() == "github.com"
        else { return nil }

        let suffix = assetSuffix.lowercased()
        guard (release.assets ?? []).contains(where: { $0.name?.lowercased().hasSuffix(suffix) == true }) else { return nil }

        return AvailableRelease(version: published.map(String.init).joined(separator: "."), page: page)
    }

    /// "v1.3.0" or "1.3.0" to three numbers, compared as numbers rather than as text; anything
    /// else to nil. A two-part version gains a zero, so "1.3" and "1.3.0" are the same release.
    static func version(fromTag tag: String) -> [Int]? {
        var text = Substring(tag)
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count) else { return nil }

        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        while numbers.count < 3 { numbers.append(0) }
        return Array(numbers.prefix(3))
    }

    /// The fields that matter, all optional: a document missing one is not a release, not an error.
    private struct Release: Decodable {
        let tag_name: String?
        let html_url: String?
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]?
    }

    private struct Asset: Decodable {
        let name: String?
    }
}
