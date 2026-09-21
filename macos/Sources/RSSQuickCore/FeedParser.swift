import Foundation

/// One entry as a feed document gave it, before any cleaning.
public struct FeedEntry: Sendable {
    public var title: String?
    public var link: String = ""
    public var summary: String = ""
    public var publishedOn: Date?
    public var author: String = ""
}

/// What a feed document contained.
public struct ParsedFeed: Sendable {
    /// The feed's own title, used only when the OPML entry gave none.
    public let title: String?
    public let entries: [FeedEntry]
}

/// Turns feed XML into entries.
///
/// There is no `SyndicationFeed` on this platform, so this is a hand-written reader over
/// `XMLParser` covering the three formats in circulation: RSS 2.0, Atom, and RSS 1.0 / RDF.
/// It is deliberately forgiving about everything except well-formedness - a feed that is merely
/// unusual should still be readable.
public enum FeedParser {
    public enum Failure: Error, CustomStringConvertible {
        /// The document is not well-formed XML.
        case notWellFormed(String)
        /// Well-formed, but not a feed - the case `SyndicationFeed.Load` reports with a message
        /// about serializers that means nothing to a reader.
        case notAFeed

        public var description: String {
            switch self {
            case .notWellFormed: "is not valid XML"
            case .notAFeed: "is not a feed RSS Quick understands"
            }
        }
    }

    /// Parses feed XML into articles, newest first.
    ///
    /// - Parameter preferredTitle: The name from the OPML file, which is what the user chose to
    ///   call the feed. The feed's own title is the fallback for an OPML entry that gave none.
    public static func parse(_ data: Data, preferredTitle: String) throws -> [ArticleItem] {
        try XMLSafety.rejectDoctype(in: data)

        let parsed = try read(data)

        let feedTitle = preferredTitle.trimmingCharacters(in: .whitespaces).isEmpty
            ? FeedText.cleanTitle(parsed.title)
            : preferredTitle

        return parsed.entries
            .map { ArticleItem.from($0, feedTitle: feedTitle) }
            .sortedNewestFirst()
    }

    static func read(_ data: Data) throws -> ParsedFeed {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        // No network fetch can be triggered by the document itself.
        parser.shouldResolveExternalEntities = false

        let handler = Handler()
        parser.delegate = handler

        guard parser.parse() else {
            throw Failure.notWellFormed(parser.parserError?.localizedDescription ?? "unreadable")
        }

        guard handler.sawFeedRoot else { throw Failure.notAFeed }

        return ParsedFeed(title: handler.feedTitle, entries: handler.entries)
    }
}

/// The SAX handler. Kept private to the parser: nothing outside needs its state machine.
private final class Handler: NSObject, XMLParserDelegate {
    private(set) var entries: [FeedEntry] = []
    private(set) var feedTitle: String?
    private(set) var sawFeedRoot = false

    private var text = ""

    private var entry: FeedEntry?
    /// Atom carries its links as attributes on empty elements, so they are collected as they
    /// appear and resolved once the entry ends.
    private var entryLinks: [(href: String, rel: String)] = []
    private var entryGuid: String?
    private var entryGuidIsPermalink = true
    private var entryContent: String?
    /// Set once the entry has given a real publication date, so a later update time cannot
    /// replace it. Atom entries carry both, and `updated` is usually the later of the two.
    private var entryHasPublicationDate = false

    private static let atomNamespace = "http://www.w3.org/2005/Atom"

    /// True while inside a channel image or text input, whose `title` and `link` would otherwise
    /// be mistaken for the channel's own.
    private var inChannelDecoration = false

    private var inAuthor = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        text = ""

        switch elementName {
        case "rss", "RDF":
            sawFeedRoot = true

        case "feed" where namespaceURI == Handler.atomNamespace:
            sawFeedRoot = true

        case "item", "entry":
            entry = FeedEntry()
            entryLinks = []
            entryGuid = nil
            entryGuidIsPermalink = true
            entryContent = nil
            entryHasPublicationDate = false

        case "image", "textInput", "textinput":
            inChannelDecoration = true

        case "author":
            inAuthor = true

        case "link":
            // Atom's form. RSS puts the URL in the element's text instead, which is read on the
            // way out; an href here means there is no text to wait for.
            if let href = attributes["href"], !href.isEmpty {
                entryLinks.append((href, attributes["rel"] ?? ""))
            }

        case "guid":
            // Absent means true, per the RSS profile.
            entryGuidIsPermalink = (attributes["isPermaLink"] ?? "true").lowercased() != "false"

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        // A CDATA block that is not valid UTF-8 is dropped rather than replaced with
        // substitution characters, which read as noise on a braille display.
        if let decoded = String(data: CDATABlock, encoding: .utf8) { text += decoded }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        defer { text = "" }

        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "item", "entry":
            finishEntry()
            return

        case "image", "textInput", "textinput":
            inChannelDecoration = false
            return

        case "author":
            inAuthor = false
            // RSS puts an address straight in <author>; Atom nests <name> inside it, which the
            // "name" case below has already picked up.
            if entry != nil, entry?.author.isEmpty == true, !value.isEmpty { entry?.author = value }
            return

        default:
            break
        }

        guard entry != nil else {
            // Channel level. The feed's own title, ignoring the one on its logo.
            if elementName == "title", !inChannelDecoration, feedTitle == nil, !value.isEmpty {
                feedTitle = value
            }
            return
        }

        switch elementName {
        case "title":
            if entry?.title == nil { entry?.title = value }

        case "link":
            if !value.isEmpty { entryLinks.append((value, "")) }

        case "guid", "id":
            entryGuid = value

        case "description", "summary":
            if entry?.summary.isEmpty == true { entry?.summary = value }

        // RSS 2.0 carries the full body in content:encoded, Atom in content. Held separately so
        // it is only used as a summary when the feed offered nothing shorter.
        case "encoded", "content":
            if entryContent == nil, !value.isEmpty { entryContent = value }

        // Publication date if the feed gave one, falling back to the update time, and nil when
        // it gave neither or gave something unreadable.
        case "pubDate", "date", "published":
            if let parsed = FeedDate.parse(value), !entryHasPublicationDate {
                entry?.publishedOn = parsed
                entryHasPublicationDate = true
            }

        case "updated", "modified":
            if let parsed = FeedDate.parse(value), entry?.publishedOn == nil {
                entry?.publishedOn = parsed
            }

        case "creator":
            if entry?.author.isEmpty == true { entry?.author = value }

        case "name" where inAuthor:
            if entry?.author.isEmpty == true { entry?.author = value }

        default:
            break
        }
    }

    private func finishEntry() {
        guard var finished = entry else { return }

        finished.link = pickLink()
        if finished.summary.isEmpty, let entryContent { finished.summary = entryContent }

        entries.append(finished)
        entry = nil
        entryLinks = []
        entryContent = nil
    }

    /// The article's own page.
    ///
    /// Prefers the "alternate" relationship rather than taking the first link. Feeds commonly
    /// carry an enclosure - a podcast audio file, an image - ahead of the article link, and
    /// taking the first one meant Enter opened a media file instead of the story.
    private func pickLink() -> String {
        let alternate = entryLinks.first { $0.rel.isEmpty || $0.rel.caseInsensitiveCompare("alternate") == .orderedSame }
        if let alternate { return alternate.href }
        if let first = entryLinks.first { return first.href }

        // A permalink guid is a URL and is the last thing left to try; a feed that marks it
        // otherwise is saying it is an identifier, not an address.
        if entryGuidIsPermalink, let entryGuid, entryGuid.hasPrefix("http") { return entryGuid }

        return ""
    }
}
