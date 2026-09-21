import Foundation

/// Reads the date formats feeds actually use.
///
/// Dates are the field publishers get wrong most often, so this is written to return nil rather
/// than to complain. On Windows the equivalent property *throws from its getter* for a malformed
/// date, and one bad `pubDate` among fifty items took the whole feed down with it. Nothing here
/// can do that: an unreadable date costs that one article its timestamp and nothing else.
public enum FeedDate {
    /// Parses a feed date, or returns nil when it is absent or unreadable.
    public static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for formatter in rfc822Formatters {
            if let date = formatter.date(from: trimmed) { return date }
        }

        if let date = iso8601WithFractionalSeconds.date(from: trimmed) { return date }
        if let date = iso8601.date(from: trimmed) { return date }

        for formatter in fallbackFormatters {
            if let date = formatter.date(from: trimmed) { return date }
        }

        return nil
    }

    /// RFC 822 as RSS 2.0 requires it, and the ways publishers get it slightly wrong: a
    /// four-digit year where the spec said two, a missing day name, missing seconds, and a
    /// numeric offset where a zone name was expected or the other way round.
    private static let rfc822Formatters: [DateFormatter] = [
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm zzz",
        "dd MMM yyyy HH:mm:ss zzz",
        "dd MMM yyyy HH:mm zzz",
        "EEE, dd MMM yyyy HH:mm:ss",
        "EEE, dd MMM yy HH:mm:ss zzz",
    ].map(fixedFormatter)

    /// Formats with no zone offset at all, and the date-only form RSS 1.0 feeds sometimes carry.
    /// Read as UTC rather than as local time, so the same feed does not sort differently
    /// depending on where it is being read.
    private static let fallbackFormatters: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd",
    ].map(fixedFormatter)

    private static func fixedFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        // Fixed locale, not the reader's. With a French locale, "Wed" and "Mar" in an English
        // feed stop parsing, and every headline in it loses its date.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    // ISO8601DateFormatter is not marked Sendable, but is documented as thread-safe once
    // configured and is only ever read here. Building one per article instead is measurably
    // slower on a folder of twenty feeds.
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
