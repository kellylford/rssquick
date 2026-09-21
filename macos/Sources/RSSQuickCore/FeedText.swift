import Foundation

/// Cleaning applied to any text that reaches a headline.
public enum FeedText {
    /// Name given to a headline or an outline that carries no usable label.
    public static let noTitle = "No Title"

    /// Strips characters that make a headline unreadable on a braille display.
    ///
    /// Feeds carry a lot of invisible punctuation. A zero-width space or a word joiner shows
    /// nothing on screen, so it is easy to believe the text is fine, but each one occupies a cell
    /// on a braille display and reads as a blank. Runs of them, or a stray non-breaking space at
    /// the start of a title, present as a gap the reader has to scrub past before reaching a word.
    /// That is the fault this exists for; see DEVELOPMENT-NOTES.md in the repository root.
    public static func cleanTitle(_ title: String?) -> String {
        guard let title, !title.isEmpty else { return noTitle }

        var cleaned = ""
        cleaned.reserveCapacity(title.unicodeScalars.count)

        for scalar in title.unicodeScalars {
            switch scalar.value {
            // Zero-width space, non-joiner, joiner; word joiner; byte order mark. Dropped
            // outright: they separate nothing, and each one is a blank braille cell.
            case 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF:
                continue

            // Non-breaking, thin and narrow no-break spaces. These are spaces, so they become
            // one; the whitespace pass below then folds them in with their neighbours.
            case 0x00A0, 0x2009, 0x202F:
                cleaned.unicodeScalars.append(" ")

            // Control characters become a space rather than nothing. Tabs and newlines fall in
            // this range and are usually separating words: deleting them ran the words either
            // side together, so "Lions GM\t\tBrad Holmes" came out as "Lions GMBrad Holmes".
            case 0x00...0x1F, 0x7F...0x9F:
                cleaned.unicodeScalars.append(" ")

            default:
                cleaned.unicodeScalars.append(scalar)
            }
        }

        // Any remaining run of whitespace, including the ones just introduced, becomes one space.
        let collapsed = cleaned
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        return collapsed.isEmpty ? noTitle : collapsed
    }
}
