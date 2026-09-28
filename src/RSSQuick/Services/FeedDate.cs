using System;
using System.Globalization;
using System.ServiceModel.Syndication;
using System.Text.RegularExpressions;

namespace RSSReaderWPF.Services
{
    /// <summary>
    /// Reads the date formats feeds actually use.
    /// </summary>
    /// <remarks>
    /// <para>Used on its own for RSS 1.0 and Dublin Core dates, which the syndication library
    /// never sees, and as a second chance behind the library's parser for RSS and Atom - never
    /// in place of it, because the library accepts forms this does not.</para>
    /// <para>The macOS version is <c>macos/Sources/RSSQuickCore/FeedDate.swift</c>, and the two
    /// accept the same forms. Like it, this returns nothing rather than complaining: an unreadable
    /// date costs that one article its timestamp and nothing else.</para>
    /// </remarks>
    public static partial class FeedDate
    {
        /// <summary>Parses a feed date, or returns null when it is absent or unreadable.</summary>
        public static DateTimeOffset? Parse(string? text)
        {
            if (string.IsNullOrWhiteSpace(text)) return null;
            var trimmed = text.Trim();

            var rfc822 = NormalizeZone(trimmed);
            if (DateTimeOffset.TryParseExact(rfc822, Rfc822Formats, CultureInfo.InvariantCulture,
                    DateTimeStyles.AllowWhiteSpaces | DateTimeStyles.AssumeUniversal, out var date))
                return date;

            // ISO 8601 with or without fractions and zone, and the plain forms with no zone at all.
            // A time with no zone is read as UTC rather than local time, so the same feed does not
            // sort differently depending on where it is being read.
            if (DateTimeOffset.TryParseExact(trimmed, IsoFormats, CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal, out date))
                return date;

            return null;
        }

        /// <summary>
        /// Plugged into the syndication library's formatters, so RSS and Atom dates go through
        /// <see cref="Parse"/> too.
        /// </summary>
        internal static bool TryParse(XmlDateTimeData data, out DateTimeOffset date)
        {
            if (Parse(data.DateTimeString) is { } parsed)
            {
                date = parsed;
                return true;
            }
            date = default;
            return false;
        }

        /// <summary>
        /// RFC 822 as RSS 2.0 requires it, and the ways publishers get it slightly wrong: a
        /// four-digit year where the spec said two, a missing day name, missing seconds.
        /// </summary>
        /// <remarks>
        /// Parsed with the invariant culture, not the reader's. With a French locale "Wed" and
        /// "Mar" in an English feed stop parsing, and every headline in it loses its date.
        /// </remarks>
        private static readonly string[] Rfc822Formats =
        [
            "ddd, d MMM yyyy HH:mm:ss zzz",
            "ddd, d MMM yyyy HH:mm zzz",
            "d MMM yyyy HH:mm:ss zzz",
            "d MMM yyyy HH:mm zzz",
            "ddd, d MMM yyyy HH:mm:ss",
            "ddd, d MMM yy HH:mm:ss zzz",
        ];

        private static readonly string[] IsoFormats =
        [
            "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFK",
            "yyyy-MM-dd'T'HH:mm:ssK",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
        ];

        /// <summary>
        /// Turns RFC 822's zone names and "+0000" offsets into the "+00:00" that .NET reads.
        /// </summary>
        private static string NormalizeZone(string text)
        {
            var named = ZoneName().Match(text);
            if (named.Success && ZoneOffsets.TryGetValue(named.Groups[1].Value, out var offset))
                return text[..named.Groups[1].Index] + offset;

            var numeric = NumericZone().Match(text);
            if (numeric.Success)
                return text[..numeric.Index] + $" {numeric.Groups[1].Value}{numeric.Groups[2].Value}:{numeric.Groups[3].Value}";

            return text;
        }

        private static readonly System.Collections.Generic.Dictionary<string, string> ZoneOffsets =
            new(StringComparer.OrdinalIgnoreCase)
            {
                ["GMT"] = "+00:00", ["UT"] = "+00:00", ["UTC"] = "+00:00", ["Z"] = "+00:00",
                ["EST"] = "-05:00", ["EDT"] = "-04:00",
                ["CST"] = "-06:00", ["CDT"] = "-05:00",
                ["MST"] = "-07:00", ["MDT"] = "-06:00",
                ["PST"] = "-08:00", ["PDT"] = "-07:00",
            };

        [GeneratedRegex(@"\s([A-Za-z]{1,3})$")]
        private static partial Regex ZoneName();

        [GeneratedRegex(@"\s([+-])(\d{2}):?(\d{2})$")]
        private static partial Regex NumericZone();
    }
}
