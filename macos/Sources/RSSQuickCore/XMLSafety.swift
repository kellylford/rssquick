import Foundation

/// Checks applied to XML before it is handed to a parser.
public enum XMLSafety {
    /// Thrown for a document carrying a document type declaration.
    public struct DoctypeRejected: Error, CustomStringConvertible {
        public var description: String { "declares a DOCTYPE, which RSS Quick does not accept" }
    }

    /// Rejects a document with a `<!DOCTYPE` declaration.
    ///
    /// Feed and OPML content is third-party input, and entity expansion is the standard way to
    /// turn parsing a small document into a denial of service. The Windows build gets this from
    /// `DtdProcessing.Prohibit` on every reader it creates; `XMLParser` has no equivalent switch,
    /// so the declaration is caught before parsing starts.
    ///
    /// Only the prolog is examined. A DTD can appear nowhere else, and searching the whole
    /// document would reject a perfectly ordinary feed containing an article about HTML.
    public static func rejectDoctype(in data: Data) throws {
        for (offset, byte) in data.enumerated() {
            guard byte == UInt8(ascii: "<") else { continue }

            let next = offset + 1 < data.count ? data[data.index(data.startIndex, offsetBy: offset + 1)] : 0

            // The root element: a name start character. Everything legal before it is a
            // processing instruction, a comment, or the declaration being looked for.
            if isNameStart(next) { return }

            if matches(data, at: offset, "<!DOCTYPE") { throw DoctypeRejected() }
        }
    }

    private static func isNameStart(_ byte: UInt8) -> Bool {
        (byte | 0x20) >= UInt8(ascii: "a") && (byte | 0x20) <= UInt8(ascii: "z")
            || byte == UInt8(ascii: "_")
    }

    private static func matches(_ data: Data, at offset: Int, _ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard offset + bytes.count <= data.count else { return false }

        for (index, expected) in bytes.enumerated() where data[data.index(data.startIndex, offsetBy: offset + index)] != expected {
            return false
        }
        return true
    }
}
