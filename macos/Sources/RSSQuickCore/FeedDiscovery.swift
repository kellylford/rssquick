import Foundation

/// A feed found for an address the reader typed.
public struct DiscoveredFeed: Sendable, Equatable {
    /// The feed's own name, or its site's host name when it gives none.
    public let title: String
    /// The feed's address, which may differ from what was typed.
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

/// Turns what a reader typed into a feed they can subscribe to.
///
/// People know a site's address, rarely its feed's. So an address that answers with a web page is
/// searched for the `<link rel="alternate">` every blog engine and most news sites put there, and
/// the first feed it names is used. An address that is already a feed is used as it is. Either
/// way the feed is fetched and read before it is added, so a typing mistake is caught now rather
/// than on the first Return.
///
/// The Windows version is `src/RSSQuick/Services/FeedDiscovery.cs`.
public enum FeedDiscovery {
    /// The address answered, but with no feed and no link to one.
    public struct NoFeedFound: Error, CustomStringConvertible {
        public init() {}
        public var description: String { "has no feed RSS Quick can find" }
    }

    /// The address as a web address, or nil when it cannot be one.
    ///
    /// "example.com" gets https://, which is what a browser's address bar would do, and the
    /// `feed:` scheme some sites still link with becomes the http address it stands for.
    public static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let lower = text.lowercased()
        if lower.hasPrefix("feed://") {
            text = "http://" + text.dropFirst(7)
        } else if lower.hasPrefix("feed:") {
            text = String(text.dropFirst(5))
        }

        if !text.contains("://") { text = "https://" + text }

        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    /// Fetches the address and finds the feed it is, or the feed its page links to.
    ///
    /// Network and server failures are thrown as they are, for `ErrorText.describe`.
    public static func find(_ input: String) async throws -> DiscoveredFeed {
        guard let address = normalize(input) else { throw FeedLoader.MalformedURL() }

        let data = try await FeedLoader.download(address)
        if let feed = readFeed(data, address: address) { return feed }

        for link in feedLinks(in: String(decoding: data, as: UTF8.self), page: address).prefix(3) {
            try Task.checkCancellation()

            // A page can name a feed that has since gone. Try the next one it names.
            guard let linked = try? await FeedLoader.download(link) else { continue }
            if let found = readFeed(linked, address: link) { return found }
        }

        try Task.checkCancellation()
        throw NoFeedFound()
    }

    /// The feed, when the document is one.
    static func readFeed(_ data: Data, address: URL) -> DiscoveredFeed? {
        // Whatever the reason - a web page's DOCTYPE, HTML that is not XML, XML that is not a
        // feed - the answer is the same: this is not the feed, so look for a link to one.
        guard (try? XMLSafety.rejectDoctype(in: data)) != nil,
              let parsed = try? FeedParser.read(data)
        else { return nil }

        let title = FeedText.cleanTitle(parsed.title)
        return DiscoveredFeed(
            title: title == FeedText.noTitle ? (address.host ?? address.absoluteString) : title,
            url: address.absoluteString
        )
    }

    /// The feeds a web page names in its head, in the order it names them.
    ///
    /// A regular expression over the tags rather than an HTML parser, deliberately: all that is
    /// wanted is `<link>` elements, which do not nest, and a page is third-party input that an
    /// HTML parser would have to be trusted with in full.
    public static func feedLinks(in html: String, page: URL) -> [URL] {
        // Made here rather than kept: they are cheap, and a stored NSRegularExpression is one
        // more thing for Swift 6's concurrency checking to ask about.
        guard let linkTag = try? NSRegularExpression(pattern: linkTagPattern, options: .caseInsensitive),
              let attribute = try? NSRegularExpression(pattern: attributePattern)
        else { return [] }

        let whole = NSRange(html.startIndex..., in: html)
        var found: [URL] = []

        for tag in linkTag.matches(in: html, range: whole) {
            guard let tagRange = Range(tag.range, in: html) else { continue }
            let text = String(html[tagRange])

            var attributes: [String: String] = [:]
            for match in attribute.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let name = Range(match.range(at: 1), in: text),
                      let value = Range(match.range(at: 2), in: text)
                else { continue }
                let key = text[name].lowercased()
                if attributes[key] == nil {
                    attributes[key] = decode(String(text[value]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
                }
            }

            guard let rel = attributes["rel"],
                  rel.split(separator: " ").contains(where: { $0.lowercased() == "alternate" }),
                  let type = attributes["type"], feedTypes.contains(type.trimmingCharacters(in: .whitespaces).lowercased()),
                  let href = attributes["href"],
                  let link = URL(string: href.trimmingCharacters(in: .whitespaces), relativeTo: page)?.absoluteURL,
                  let scheme = link.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  !found.contains(link)
            else { continue }

            found.append(link)
        }
        return found
    }

    private static let feedTypes: Set<String> = ["application/rss+xml", "application/atom+xml", "application/rdf+xml"]

    private static let linkTagPattern = #"<link\b[^>]*>"#
    private static let attributePattern = #"([a-zA-Z-]+)\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#

    /// The character references an href is likely to carry.
    private static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
