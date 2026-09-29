import Foundation

/// A folder a new feed can go into.
public struct FolderChoice: Sendable, Hashable {
    /// The folder's name with the folders above it, "News / Wires".
    public let name: String

    /// The folder's `FeedItem.outlinePath`. Nil for the top level, which the tree shows as
    /// "Uncategorized".
    public let path: [Int]?

    public init(name: String, path: [Int]?) {
        self.name = name
        self.path = path
    }
}

/// Adds feeds to an OPML file and takes them out again.
///
/// Edits the file's own XML rather than writing a new file from the tree, for the reason
/// `SavedFeedList` keeps exact bytes: everything the parser does not read - an `htmlUrl`, a
/// `category`, the head, another program's attributes - survives a subscription. The tree finds
/// its way back to the XML through `FeedItem.outlinePath`.
///
/// Foundation's `XMLDocument` would do the editing on the Mac, but it does not exist on iOS, which
/// compiles this file too. So the document is read into a small tree of its own here and written
/// back out, re-indented, which is also what the Windows version's `XDocument` does.
///
/// The Windows version is `src/RSSQuick/Services/OpmlEditor.cs`, and `OpmlEditorTests` on each
/// side ask the same questions.
public enum OpmlEditor {
    public enum Failure: Error, CustomStringConvertible {
        case notWellFormed(String)
        case noBody
        case changedSinceRead

        public var description: String {
            switch self {
            case .notWellFormed(let detail): "This file is not readable as XML: \(detail)"
            case .noBody: "This does not look like an OPML file - it has no <body> element."
            case .changedSinceRead: "The feed list has changed since it was read. Open it again and retry."
            }
        }
    }

    /// A feed list with nothing in it, for subscribing when there is no list at all.
    public static let empty = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <opml version="2.0">
          <head>
            <title>RSS Quick feeds</title>
          </head>
          <body />
        </opml>
        """.utf8)

    /// Adds a feed to the end of a folder, or to the top level when `folder` is nil.
    ///
    /// - Returns: The whole file, changed.
    public static func addFeed(to data: Data, folder path: [Int]?, title: String, url: String) throws -> Data {
        let document = try XMLTree.parse(data)
        let parent = try path.map { try find($0, in: document) } ?? body(of: document)

        parent.children.append(.element(XMLTree.Element(name: "outline", attributes: [
            ("text", title), ("title", title), ("type", "rss"), ("xmlUrl", url),
        ])))

        return document.serialized()
    }

    /// Takes out the outline at `path`, and anything inside it.
    ///
    /// - Returns: The whole file, changed.
    public static func remove(from data: Data, at path: [Int]) throws -> Data {
        guard let index = path.last else { throw Failure.changedSinceRead }

        let document = try XMLTree.parse(data)
        let parent = try path.count == 1 ? body(of: document) : find(Array(path.dropLast()), in: document)

        var seen = -1
        guard let position = parent.children.firstIndex(where: { node in
            guard case .element(let element) = node, element.name == "outline" else { return false }
            seen += 1
            return seen == index
        }) else { throw Failure.changedSinceRead }

        parent.children.remove(at: position)
        return document.serialized()
    }

    /// Every folder in the tree, in reading order, and the top level.
    ///
    /// The top level is named "Uncategorized" because that is where the tree shows a feed added
    /// there. It sits where the tree shows it when the file has loose feeds already, and last
    /// otherwise, so the list reads in the same order as the tree.
    public static func folders(_ roots: [FeedItem]) -> [FolderChoice] {
        var choices: [FolderChoice] = []
        var sawTopLevel = false

        func walk(_ nodes: [FeedItem], _ prefix: String) {
            for node in nodes where node.isCategory {
                let name = prefix.isEmpty ? node.title : "\(prefix) / \(node.title)"
                choices.append(FolderChoice(name: name, path: node.outlinePath))
                if node.outlinePath == nil { sawTopLevel = true }
                walk(node.children, name)
            }
        }

        walk(roots, "")
        if !sawTopLevel { choices.append(FolderChoice(name: OpmlParser.uncategorizedFolder, path: nil)) }
        return choices
    }

    /// The folder to start a subscription in, so it goes where the reader already is: the folder
    /// selected, or the one holding the feed selected. The top level when nothing is.
    public static func suggest(_ choices: [FolderChoice], roots: [FeedItem], selected: FeedItem?) -> FolderChoice {
        var folder: FeedItem?
        if let selected { folder = selected.isCategory ? selected : parent(of: selected, in: roots) }

        if let folder, let match = choices.first(where: { $0.path == folder.outlinePath }) { return match }
        return choices.first { $0.path == nil } ?? FolderChoice(name: OpmlParser.uncategorizedFolder, path: nil)
    }

    /// The first feed in the tree with this address, or nil.
    ///
    /// Compared as addresses, ignoring case and a trailing slash, so pasting the same feed again
    /// is caught rather than giving the reader two copies of every headline.
    public static func findFeed(_ roots: [FeedItem], url: String) -> FeedItem? {
        for node in roots {
            if !node.isCategory, sameAddress(node.url, url) { return node }
            if let found = findFeed(node.children, url: url) { return found }
        }
        return nil
    }

    /// The folder directly holding `child`, or nil at the top level.
    public static func parent(of child: FeedItem, in roots: [FeedItem]) -> FeedItem? {
        for node in roots {
            if node.children.contains(where: { $0 === child }) { return node }
            if let found = parent(of: child, in: node.children) { return found }
        }
        return nil
    }

    /// The node at an outline path, or nil.
    public static func find(path: [Int], in roots: [FeedItem]) -> FeedItem? {
        for node in roots {
            if node.outlinePath == path { return node }
            if let found = find(path: path, in: node.children) { return found }
        }
        return nil
    }

    private static func sameAddress(_ a: String, _ b: String) -> Bool {
        func key(_ s: String) -> String {
            var text = s.trimmingCharacters(in: .whitespacesAndNewlines)
            while text.hasSuffix("/") { text.removeLast() }
            return text.lowercased()
        }
        return key(a) == key(b)
    }

    private static func body(of document: XMLTree) throws -> XMLTree.Element {
        guard let body = document.root?.first(named: "body") else { throw Failure.noBody }
        return body
    }

    private static func find(_ path: [Int], in document: XMLTree) throws -> XMLTree.Element {
        var element = try body(of: document)
        for index in path {
            let outlines = element.elements(named: "outline")
            guard outlines.indices.contains(index) else { throw Failure.changedSinceRead }
            element = outlines[index]
        }
        return element
    }
}

/// Just enough of an XML document model to change an OPML file and write it back.
///
/// Elements, text, comments, CDATA and processing instructions are kept; whitespace between
/// elements is not, and the output is indented afresh. Attribute order is the one thing
/// `XMLParser` does not report, so the usual OPML attributes come first in their usual order and
/// the rest follow alphabetically.
final class XMLTree {
    final class Element {
        let name: String
        var attributes: [(String, String)]
        var children: [Node] = []

        init(name: String, attributes: [(String, String)]) {
            self.name = name
            self.attributes = attributes
        }

        func elements(named name: String) -> [Element] {
            children.compactMap { node in
                if case .element(let element) = node, element.name == name { return element }
                return nil
            }
        }

        /// The first element with this name at any depth, this one included, in document order.
        func first(named name: String) -> Element? {
            if self.name == name { return self }
            for case .element(let child) in children {
                if let found = child.first(named: name) { return found }
            }
            return nil
        }
    }

    enum Node {
        case element(Element)
        case text(String)
        case comment(String)
        case cdata(String)
        case instruction(target: String, data: String)

        var text: String? {
            if case .text(let value) = self { return value }
            return nil
        }
    }

    /// Everything outside the root element - comments, processing instructions - and the root.
    var nodes: [Node] = []

    var root: Element? {
        for case .element(let element) in nodes { return element }
        return nil
    }

    static func parse(_ data: Data) throws -> XMLTree {
        // The same rule as the parser: a DTD in a feed list is refused, never expanded.
        try XMLSafety.rejectDoctype(in: data)

        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        let builder = Builder()
        parser.delegate = builder

        guard parser.parse() else {
            throw OpmlEditor.Failure.notWellFormed(parser.parserError?.localizedDescription ?? "unreadable")
        }
        return builder.tree
    }

    func serialized() -> Data {
        var out = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        for node in nodes { Self.write(node, indent: "", to: &out) }
        return Data(out.utf8)
    }

    private static let attributeOrder = ["version", "text", "title", "type", "xmlUrl", "htmlUrl"]

    private static func write(_ node: Node, indent: String, to out: inout String) {
        switch node {
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out += indent + escape(trimmed, quotes: false) + "\n" }
        case .comment(let text):
            out += "\(indent)<!--\(text)-->\n"
        case .cdata(let text):
            out += "\(indent)<![CDATA[\(text)]]>\n"
        case .instruction(let target, let data):
            out += "\(indent)<?\(target) \(data)?>\n"
        case .element(let element):
            out += indent + "<" + element.name
            for (name, value) in element.attributes {
                out += " \(name)=\"\(escape(value, quotes: true))\""
            }

            let texts = element.children.compactMap(\.text)
            if element.children.isEmpty {
                out += " />\n"
            } else if texts.count == element.children.count {
                out += ">" + escape(texts.joined(), quotes: false) + "</\(element.name)>\n"
            } else {
                out += ">\n"
                for child in element.children { write(child, indent: indent + "  ", to: &out) }
                out += "\(indent)</\(element.name)>\n"
            }
        }
    }

    private static func escape(_ text: String, quotes: Bool) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"" where quotes: result += "&quot;"
            case "\n" where quotes: result += "&#10;"
            case "\r" where quotes: result += "&#13;"
            case "\t" where quotes: result += "&#9;"
            default: result.append(character)
            }
        }
        return result
    }

    private final class Builder: NSObject, XMLParserDelegate {
        let tree = XMLTree()
        private var open: [Element] = []

        private func append(_ node: Node) {
            if let parent = open.last { parent.children.append(node) } else { tree.nodes.append(node) }
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            let ordered = attributes.sorted { a, b in
                let ia = XMLTree.attributeOrder.firstIndex(of: a.key) ?? Int.max
                let ib = XMLTree.attributeOrder.firstIndex(of: b.key) ?? Int.max
                return ia != ib ? ia < ib : a.key < b.key
            }
            let element = Element(name: elementName, attributes: ordered.map { ($0.key, $0.value) })
            append(.element(element))
            open.append(element)
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            open.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            // Text arrives in pieces; keep it as one node so it is written as one.
            if let parent = open.last, case .text(let existing)? = parent.children.last {
                parent.children[parent.children.count - 1] = .text(existing + string)
            } else if !open.isEmpty {
                append(.text(string))
            }
        }

        func parser(_ parser: XMLParser, foundComment comment: String) {
            append(.comment(comment))
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            append(.cdata(String(decoding: CDATABlock, as: UTF8.self)))
        }

        func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
            append(.instruction(target: target, data: data ?? ""))
        }
    }
}
