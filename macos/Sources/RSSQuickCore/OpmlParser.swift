import Foundation

/// The feed tree an OPML file describes.
public struct OpmlDocument: Sendable {
    /// Top-level nodes, in the order the file listed them.
    public let roots: [FeedItem]
    /// Feeds at any depth. Folders are not counted.
    public let feedCount: Int
}

/// Reads an OPML feed list into a tree.
///
/// A pure function over data, deliberately: on Windows this used to be two methods on the window
/// that mutated the view model as they walked, which is why none of it could be tested.
public enum OpmlParser {
    public enum Failure: Error, CustomStringConvertible {
        case notWellFormed(String)
        case noBody

        public var description: String {
            switch self {
            case .notWellFormed(let detail): "This file is not readable as XML: \(detail)"
            case .noBody: "This does not look like an OPML file - it has no <body> element."
            }
        }
    }

    /// Name given to an outline that carries no usable label.
    private static let unnamedOutline = "Unknown"

    /// Holds feeds the file listed at the top level, outside any folder.
    static let uncategorizedFolder = "Uncategorized"

    public static func parse(_ data: Data) throws -> OpmlDocument {
        try XMLSafety.rejectDoctype(in: data)

        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false

        let handler = Handler()
        parser.delegate = handler

        guard parser.parse() else {
            throw Failure.notWellFormed(parser.parserError?.localizedDescription ?? "unreadable")
        }

        guard handler.sawBody else { throw Failure.noBody }

        return OpmlDocument(roots: handler.roots.map(\.frozen), feedCount: handler.feedCount)
    }

    public static func parse(contentsOf url: URL) throws -> OpmlDocument {
        try parse(Data(contentsOf: url))
    }

    /// A node under construction. `FeedItem` is immutable, which is what makes it safe to hand to
    /// a background load, so the tree is assembled here first and frozen at the end.
    fileprivate final class Node {
        let title: String
        let url: String
        let category: String
        let isCategory: Bool
        var children: [Node] = []

        init(title: String, url: String, category: String, isCategory: Bool) {
            self.title = title
            self.url = url
            self.category = category
            self.isCategory = isCategory
        }

        var frozen: FeedItem {
            FeedItem(
                title: title,
                url: url,
                category: category,
                isCategory: isCategory,
                children: children.map(\.frozen)
            )
        }
    }

    private final class Handler: NSObject, XMLParserDelegate {
        var roots: [Node] = []
        var feedCount = 0
        var sawBody = false

        /// Folders currently open, innermost last. A feed goes under the last of them.
        private var openFolders: [Node] = []
        private var uncategorized: Node?
        private var inBody = false

        /// Depth of outlines whose element we have entered but which are feeds, not folders -
        /// tracked so `didEndElement` knows whether to close a folder.
        private var isFolder: [Bool] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            if elementName == "body" {
                sawBody = true
                inBody = true
                return
            }

            guard inBody, elementName == "outline" else { return }

            let title = readTitle(attributes)
            let url = attributes["xmlUrl"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // An outline with a feed URL is a feed; anything else is a folder. That is how OPML
            // distinguishes them - there is no type attribute worth trusting, and plenty of
            // exporters omit the type="rss" the old documentation told people to look for.
            if url.isEmpty {
                let folder = Node(title: title, url: "", category: title, isCategory: true)
                attach(folder)
                openFolders.append(folder)
                isFolder.append(true)
            } else {
                let feed = Node(
                    title: title,
                    url: url,
                    category: openFolders.last?.title ?? OpmlParser.uncategorizedFolder,
                    isCategory: false
                )
                addFeed(feed)
                feedCount += 1
                isFolder.append(false)
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            if elementName == "body" {
                inBody = false
                return
            }

            guard inBody, elementName == "outline", let wasFolder = isFolder.popLast() else { return }
            if wasFolder, !openFolders.isEmpty { openFolders.removeLast() }
        }

        private func attach(_ node: Node) {
            if let parent = openFolders.last { parent.children.append(node) }
            else { roots.append(node) }
        }

        /// Puts a feed under its folder, or under "Uncategorized" when the file listed it loose.
        ///
        /// Every feed ends up inside a folder so the tree has one shape rather than two. A mix of
        /// feeds and folders at the top level makes Enter mean different things at the same
        /// apparent level, which is exactly the sort of inconsistency that makes a tree hard to
        /// navigate without sight.
        private func addFeed(_ feed: Node) {
            if let parent = openFolders.last {
                parent.children.append(feed)
                return
            }

            if uncategorized == nil {
                let folder = Node(
                    title: OpmlParser.uncategorizedFolder,
                    url: "",
                    category: OpmlParser.uncategorizedFolder,
                    isCategory: true
                )
                uncategorized = folder
                roots.append(folder)
            }

            uncategorized?.children.append(feed)
        }

        /// The label to show, preferring `text` over `title` as the OPML spec does.
        ///
        /// Cleaned the same way headlines are. Feed names come from the same exporters and carry
        /// the same invisible characters, and they are read out just as often.
        private func readTitle(_ attributes: [String: String]) -> String {
            let raw = attributes["text"] ?? attributes["title"]

            guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return OpmlParser.unnamedOutline
            }

            return FeedText.cleanTitle(raw)
        }
    }
}
