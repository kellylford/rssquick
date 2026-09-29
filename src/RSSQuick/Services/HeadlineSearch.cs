using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace RSSReaderWPF.Services
{
    /// <summary>
    /// Search across every feed in the list: which feeds to fetch, which headlines match, and what
    /// to say about it.
    /// </summary>
    /// <remarks>
    /// <para>There is no cache, so searching all feeds means fetching them all, the way a folder
    /// load does, and keeping the headlines that match. A headline matches when every word of the
    /// search appears in its title or in its feed's name, ignoring case and accents - so "bbc
    /// storm" finds the BBC's storm stories, and "cafe" finds "Café".</para>
    /// <para>The macOS and iOS version is <c>macos/Sources/RSSQuickCore/HeadlineSearch.swift</c>, and
    /// the two say the same things in the same words.</para>
    /// </remarks>
    public static class HeadlineSearch
    {
        private const CompareOptions Loose = CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace;

        /// <summary>The words of a search, cleaned the way a headline is.</summary>
        public static IReadOnlyList<string> Words(string query) =>
            string.IsNullOrWhiteSpace(query)
                ? Array.Empty<string>()
                : FeedText.CleanTitle(query).Split(' ', StringSplitOptions.RemoveEmptyEntries);

        /// <summary>True when every word appears in the headline's title or its feed's name.</summary>
        public static bool Matches(ArticleItem article, IReadOnlyList<string> words)
        {
            var compare = CultureInfo.InvariantCulture.CompareInfo;
            return words.Count > 0 && words.All(word =>
                compare.IndexOf(article.Title, word, Loose) >= 0
                || compare.IndexOf(article.FeedTitle, word, Loose) >= 0);
        }

        /// <summary>The matching headlines, in the order given.</summary>
        public static IReadOnlyList<ArticleItem> Filter(IEnumerable<ArticleItem> articles, string query)
        {
            var words = Words(query);
            return articles.Where(a => Matches(a, words)).ToArray();
        }

        /// <summary>
        /// Every feed in the tree once, in reading order.
        /// </summary>
        /// <remarks>
        /// The same feed can sit in two folders - the starter list has several - and fetching it
        /// twice would list each of its matches twice.
        /// </remarks>
        public static IReadOnlyList<FeedItem> FeedsToSearch(IEnumerable<FeedItem> roots)
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var feeds = new List<FeedItem>();

            void Walk(IEnumerable<FeedItem> nodes)
            {
                foreach (var node in nodes)
                {
                    if (node.IsCategory) Walk(node.Children);
                    else if (seen.Add(node.Url.Trim())) feeds.Add(node);
                }
            }

            Walk(roots);
            return feeds;
        }

        /// <summary>What the search is doing, for the status bar while it runs.</summary>
        public static string DescribeStart(string query, int feedCount) =>
            $"Searching {Feeds(feedCount)} for {query}...";

        /// <summary>
        /// One line covering what was found, and how much of the list could be searched.
        /// </summary>
        public static string Describe(string query, int matches, FolderLoadResult result)
        {
            if (result.FeedsAttempted > 0 && result.FeedsSucceeded == 0)
                return $"None of the {Feeds(result.FeedsAttempted)} could be loaded, so nothing was searched";

            var found = matches switch
            {
                0 => $"No headlines match {query}",
                1 => $"Found 1 headline matching {query}",
                _ => $"Found {matches} headlines matching {query}",
            };

            var searched = result.Failures.Count == 0
                ? $" in {Feeds(result.FeedsAttempted)}"
                : $" in {result.FeedsSucceeded} of {Feeds(result.FeedsAttempted)}; {result.Failures.Count} could not be loaded";

            return found + searched;
        }

        private static string Feeds(int count) => count == 1 ? "1 feed" : $"{count} feeds";
    }
}
