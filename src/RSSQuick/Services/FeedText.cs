using System.Text.RegularExpressions;

namespace RSSReaderWPF.Services
{
    /// <summary>
    /// Cleaning applied to any text that reaches a headline.
    /// </summary>
    public static partial class FeedText
    {
        /// <summary>
        /// Strips characters that make a headline unreadable on a braille display.
        /// </summary>
        /// <remarks>
        /// Feeds carry a lot of invisible punctuation. A zero-width space or a word joiner shows
        /// nothing on screen, so it is easy to believe the text is fine, but each one occupies a
        /// cell on a braille display and reads as a blank. Runs of them, or a stray non-breaking
        /// space at the start of a title, present as a gap the reader has to scrub past before
        /// reaching a word. That is the fault this exists for; see DEVELOPMENT-NOTES.md.
        /// </remarks>
        public static string CleanTitle(string? title)
        {
            if (string.IsNullOrEmpty(title)) return "No Title";

            var cleaned = title
                .Replace("\u200B", "")   // zero-width space
                .Replace("\u200C", "")   // zero-width non-joiner
                .Replace("\u200D", "")   // zero-width joiner
                .Replace("\uFEFF", "")   // byte order mark / zero-width no-break space
                .Replace("\u2060", "")   // word joiner
                .Replace("\u00A0", " ")  // non-breaking space
                .Replace("\u2009", " ")  // thin space
                .Replace("\u202F", " "); // narrow no-break space

            // Control characters become a space rather than nothing. Tabs and newlines fall in this
            // range and are usually separating words: deleting them ran the words either side
            // together, so "Lions GM		Brad Holmes" came out as "Lions GMBrad Holmes". The
            // whitespace pass below then removes whatever this leaves doubled up.
            cleaned = ControlCharacters().Replace(cleaned, " ");

            // Any remaining run of whitespace, including newlines and tabs, becomes one space.
            cleaned = WhitespaceRuns().Replace(cleaned, " ").Trim();

            return string.IsNullOrWhiteSpace(cleaned) ? "No Title" : cleaned;
        }

        [GeneratedRegex(@"[\x00-\x1F\x7F-\x9F]")]
        private static partial Regex ControlCharacters();

        [GeneratedRegex(@"\s+")]
        private static partial Regex WhitespaceRuns();
    }
}
