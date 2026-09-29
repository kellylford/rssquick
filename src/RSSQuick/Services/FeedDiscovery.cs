using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace RSSReaderWPF.Services
{
    /// <summary>A feed found for an address the reader typed.</summary>
    /// <param name="Title">The feed's own name, or its site's host name when it gives none.</param>
    /// <param name="Url">The feed's address, which may differ from what was typed.</param>
    public sealed record DiscoveredFeed(string Title, string Url);

    /// <summary>The address answered, but with no feed and no link to one.</summary>
    public sealed class NoFeedFoundException : Exception
    {
        public NoFeedFoundException() : base("has no feed RSS Quick can find") { }
        public NoFeedFoundException(string message) : base(message) { }
        public NoFeedFoundException(string message, Exception inner) : base(message, inner) { }
    }

    /// <summary>
    /// Turns what a reader typed into a feed they can subscribe to.
    /// </summary>
    /// <remarks>
    /// <para>People know a site's address, rarely its feed's. So an address that answers with a web
    /// page is searched for the <c>&lt;link rel="alternate"&gt;</c> every blog engine and most news
    /// sites put there, and the first feed it names is used. An address that is already a feed is
    /// used as it is. Either way the feed is fetched and read before it is added, so a typing
    /// mistake is caught now rather than on the first Enter.</para>
    /// <para>The macOS and iOS version is <c>macos/Sources/RSSQuickCore/FeedDiscovery.swift</c>.</para>
    /// </remarks>
    public static partial class FeedDiscovery
    {
        /// <summary>
        /// The address as a web address, or null when it cannot be one.
        /// </summary>
        /// <remarks>
        /// "example.com" gets https://, which is what a browser's address bar would do, and the
        /// <c>feed:</c> scheme some sites still link with becomes the http address it stands for.
        /// </remarks>
        public static Uri? Normalize(string input)
        {
            var text = input.Trim();
            if (text.Length == 0) return null;

            if (text.StartsWith("feed://", StringComparison.OrdinalIgnoreCase)) text = "http://" + text[7..];
            else if (text.StartsWith("feed:", StringComparison.OrdinalIgnoreCase)) text = text[5..];

            if (!text.Contains("://", StringComparison.Ordinal)) text = "https://" + text;

            return Uri.TryCreate(text, UriKind.Absolute, out var address)
                   && (address.Scheme == Uri.UriSchemeHttp || address.Scheme == Uri.UriSchemeHttps)
                   && address.Host.Length > 0
                ? address
                : null;
        }

        /// <summary>
        /// Fetches the address and finds the feed it is, or the feed its page links to.
        /// </summary>
        /// <exception cref="UriFormatException">The input cannot be made into a web address.</exception>
        /// <exception cref="NoFeedFoundException">It answered, with no feed to be found.</exception>
        /// <remarks>Network and server failures are thrown as they are, for <see cref="FeedLoader.DescribeFailure"/>.</remarks>
        public static async Task<DiscoveredFeed> FindAsync(string input, CancellationToken cancellationToken)
        {
            var address = Normalize(input) ?? throw new UriFormatException($"{input} is not a web address.");

            // Where it ended up, not what was typed: "example.com" that redirects to
            // www.example.com/blog/ has links relative to the blog, and the feed's own address is
            // the one worth keeping.
            var (payload, landed) = await FeedLoader.DownloadFromAsync(address, cancellationToken).ConfigureAwait(false);
            if (TryReadFeed(payload, landed) is { } feed) return feed;

            foreach (var link in FeedLinks(Decode(payload), landed).Take(3))
            {
                byte[] linked;
                try
                {
                    linked = await FeedLoader.DownloadAsync(link, cancellationToken).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    throw;
                }
                catch (Exception)
                {
                    // A page can name a feed that has since gone. Try the next one it names.
                    continue;
                }

                if (TryReadFeed(linked, link) is { } found) return found;
            }

            throw new NoFeedFoundException();
        }

        /// <summary>The feed, when the document is one.</summary>
        internal static DiscoveredFeed? TryReadFeed(byte[] payload, Uri address)
        {
            try
            {
                using var stream = new MemoryStream(payload, writable: false);
                var (title, _) = FeedLoader.ParseFeed(stream, preferredTitle: string.Empty);
                return new DiscoveredFeed(
                    title == "No Title" ? address.Host : title,
                    address.AbsoluteUri);
            }
            // Whatever the reason - a web page's DOCTYPE, HTML that is not XML, XML that is not a
            // feed - the answer is the same: this is not the feed, so look for a link to one.
            catch (Exception)
            {
                return null;
            }
        }

        /// <summary>
        /// The feeds a web page names in its head, in the order it names them.
        /// </summary>
        /// <remarks>
        /// A regular expression over the tags rather than an HTML parser, deliberately: all that is
        /// wanted is <c>&lt;link&gt;</c> elements, which do not nest, and a page is third-party input
        /// that an HTML parser would have to be trusted with in full.
        /// </remarks>
        public static IReadOnlyList<Uri> FeedLinks(string html, Uri page)
        {
            var found = new List<Uri>();
            foreach (Match tag in LinkTags().Matches(html))
            {
                var attributes = Attributes().Matches(tag.Value)
                    .GroupBy(a => a.Groups["name"].Value.ToLowerInvariant())
                    .ToDictionary(g => g.Key, g => WebUtility.HtmlDecode(g.First().Groups["value"].Value.Trim('"', '\'')));

                if (!attributes.TryGetValue("rel", out var rel)
                    || !rel.Split(' ', StringSplitOptions.RemoveEmptyEntries).Contains("alternate", StringComparer.OrdinalIgnoreCase))
                    continue;
                if (!attributes.TryGetValue("type", out var type) || !FeedTypes.Contains(type.Trim())) continue;
                if (!attributes.TryGetValue("href", out var href)) continue;

                if (Uri.TryCreate(page, href.Trim(), out var link)
                    && (link.Scheme == Uri.UriSchemeHttp || link.Scheme == Uri.UriSchemeHttps)
                    && !found.Contains(link))
                    found.Add(link);
            }
            return found;
        }

        private static readonly HashSet<string> FeedTypes = new(StringComparer.OrdinalIgnoreCase)
        {
            "application/rss+xml", "application/atom+xml", "application/rdf+xml",
        };

        /// <summary>The page as text. UTF-8 unless it says otherwise, which is all that matters for tags.</summary>
        private static string Decode(byte[] payload) => Encoding.UTF8.GetString(payload);

        [GeneratedRegex(@"<link\b[^>]*>", RegexOptions.IgnoreCase)]
        private static partial Regex LinkTags();

        [GeneratedRegex(@"(?<name>[a-zA-Z-]+)\s*=\s*(?<value>""[^""]*""|'[^']*'|[^\s>]+)")]
        private static partial Regex Attributes();
    }
}
