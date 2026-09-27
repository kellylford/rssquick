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
/// The Windows version is `src/RSSQuick/Services/ReleaseCheck.cs`. The two answer the same
/// questions, and their tests should change together.
public enum ReleaseCheck {
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/kellylford/rssquick/releases/latest")!

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
            "User-Agent": "RSSQuick (+https://github.com/kellylford/rssquick)",
            "Accept": "application/vnd.github+json",
        ]
        return URLSession(configuration: configuration)
    }()

    /// The release at `api`, if it is newer than `current` and carries an asset whose name ends
    /// with `assetSuffix`.
    ///
    /// - Returns: nil when there is nothing newer for this copy.
    /// - Throws: When the question could not be answered - no network, a GitHub outage, a rate
    ///   limit. The check at launch ignores that, because none of it is worth interrupting anyone
    ///   for and the next launch asks again; Check for Updates says so, because the reader asked.
    ///   The Windows version has no Check for Updates, so it returns null for both.
    public static func check(
        api: URL = latestReleaseAPI, current: String, assetSuffix: String = macAssetSuffix
    ) async throws -> AvailableRelease? {
        let (data, response) = try await session.data(from: api)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw FeedLoader.HTTPFailure(status: http.statusCode) }
        return parse(data, current: current, assetSuffix: assetSuffix)
    }

    /// Reads a GitHub release document. Everything `check` decides, without the network.
    public static func parse(_ data: Data, current: String, assetSuffix: String) -> AvailableRelease? {
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else { return nil }

        // /releases/latest never returns either, but a document from anywhere else might.
        if release.draft == true || release.prerelease == true { return nil }

        guard let tag = release.tag_name, let published = Self.version(fromTag: tag),
              let running = Self.version(fromTag: current), running.lexicographicallyPrecedes(published)
        else { return nil }

        guard let pageText = release.html_url, let page = URL(string: pageText), page.scheme == "https" else { return nil }

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
