using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.ServiceModel.Syndication;
using System.Threading;
using System.Threading.Tasks;
using System.Xml;

namespace RSSReaderWPF.Services
{
    /// <summary>One feed that could not be read, and why, in words a reader can act on.</summary>
    public sealed record FeedFailure(string FeedTitle, string Reason);

    /// <summary>The outcome of loading a folder: what arrived, and what did not.</summary>
    public sealed record FolderLoadResult(
        IReadOnlyList<ArticleItem> Articles,
        IReadOnlyList<FeedFailure> Failures,
        int FeedsAttempted)
    {
        public int FeedsSucceeded => FeedsAttempted - Failures.Count;
    }

    /// <summary>
    /// Fetches and parses feeds.
    /// </summary>
    /// <remarks>
    /// <para>This replaced <c>XmlReader.Create(url)</c>, which fetched over the network
    /// synchronously on <c>WebRequest</c>'s default 100-second timeout, with no timeout of its own
    /// and no way to cancel. A folder made it worse by loading its feeds strictly one after
    /// another: twenty feeds with three unresponsive servers took five minutes, with a status bar
    /// that said "Loading feed: ..." throughout and no way out.</para>
    /// </remarks>
    public static class FeedLoader
    {
        /// <summary>
        /// How many of a folder's feeds are fetched at once.
        /// </summary>
        /// <remarks>
        /// Bounded rather than unbounded: a folder can hold dozens of feeds, and opening that many
        /// connections at once is unkind to a shared connection and gets a client rate-limited by
        /// some publishers. Six is enough that one slow server no longer holds up the rest.
        /// </remarks>
        private const int MaxConcurrentFeeds = 6;

        /// <summary>
        /// Long enough for a slow-but-working server, short enough that a dead one does not read
        /// as the application having hung. The old effective limit was 100 seconds.
        /// </summary>
        private static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(15);

        private static readonly HttpClient Http = CreateClient();

        private static HttpClient CreateClient()
        {
            var handler = new SocketsHttpHandler
            {
                // Most feeds are served compressed and are several times smaller for it.
                AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate | DecompressionMethods.Brotli,
                PooledConnectionLifetime = TimeSpan.FromMinutes(5),
            };

            var client = new HttpClient(handler)
            {
                Timeout = RequestTimeout,
                // A hostile or misconfigured server cannot make us buffer an unbounded response.
                MaxResponseContentBufferSize = 16 * 1024 * 1024,
            };

            // Some publishers reject requests with no User-Agent, or serve them a challenge page.
            client.DefaultRequestHeaders.UserAgent.ParseAdd("RSSQuick/1.1 (+https://github.com/kellylford/rssquick)");
            client.DefaultRequestHeaders.Accept.ParseAdd("application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.9, */*;q=0.5");

            return client;
        }

        /// <summary>Loads one feed's articles, newest first.</summary>
        /// <exception cref="OperationCanceledException">The caller cancelled.</exception>
        public static async Task<IReadOnlyList<ArticleItem>> LoadFeedAsync(FeedItem feed, CancellationToken cancellationToken)
        {
            ArgumentNullException.ThrowIfNull(feed);

            return await FetchAsync(feed, cancellationToken).ConfigureAwait(false);
        }

        /// <summary>
        /// Loads every feed in a folder concurrently and merges the results, newest first.
        /// </summary>
        /// <param name="progress">Reports the number of feeds finished, for the status bar.</param>
        /// <remarks>
        /// A feed that fails does not fail the folder. Its reason is collected into
        /// <see cref="FolderLoadResult.Failures"/> so the caller can say so — those failures used
        /// to go to <c>Console.WriteLine</c>, which in a WinExe goes nowhere at all, leaving a
        /// short list and no explanation.
        /// </remarks>
        public static async Task<FolderLoadResult> LoadFolderAsync(
            IReadOnlyList<FeedItem> feeds,
            IProgress<int>? progress,
            CancellationToken cancellationToken)
        {
            ArgumentNullException.ThrowIfNull(feeds);

            var failures = new ConcurrentBag<FeedFailure>();
            var articles = new ConcurrentBag<ArticleItem>();
            var completed = 0;

            using var gate = new SemaphoreSlim(MaxConcurrentFeeds);

            var work = feeds.Select(async feed =>
            {
                await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
                try
                {
                    foreach (var article in await FetchAsync(feed, cancellationToken).ConfigureAwait(false))
                        articles.Add(article);
                }
                // Only a cancellation the caller actually asked for. HttpClient reports its own
                // timeout as a TaskCanceledException, which derives from this and carries a token
                // that is not ours -- rethrowing that took the whole folder down over one slow
                // server, which is the fault this class exists to fix. The filter is what tells
                // the two apart.
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    failures.Add(new FeedFailure(feed.Title, DescribeFailure(ex)));
                }
                finally
                {
                    gate.Release();
                    progress?.Report(Interlocked.Increment(ref completed));
                }
            });

            await Task.WhenAll(work).ConfigureAwait(false);

            return new FolderLoadResult(SortNewestFirst(articles), failures.ToArray(), feeds.Count);
        }

        private static async Task<IReadOnlyList<ArticleItem>> FetchAsync(FeedItem feed, CancellationToken cancellationToken)
        {
            using var response = await Http
                .GetAsync(feed.Url, HttpCompletionOption.ResponseContentRead, cancellationToken)
                .ConfigureAwait(false);

            response.EnsureSuccessStatusCode();

            // Buffered before parsing, because SyndicationFeed.Load reads synchronously and would
            // otherwise block a thread pool thread on the network for the length of the download.
            var payload = await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);

            using var stream = new MemoryStream(payload, writable: false);
            return Parse(stream, feed.Title);
        }

        /// <summary>
        /// Turns feed XML into articles, newest first. Separated from fetching so it can be tested
        /// against saved feeds, including the malformed ones.
        /// </summary>
        /// <param name="preferredTitle">
        /// The name from the OPML file, which is what the user chose to call the feed. The feed's
        /// own title is the fallback for an OPML entry that gave none.
        /// </param>
        /// <exception cref="XmlException">The document is not well-formed XML.</exception>
        public static IReadOnlyList<ArticleItem> Parse(Stream stream, string preferredTitle)
        {
            using var reader = XmlReader.Create(stream, new XmlReaderSettings
            {
                // Feed XML is third-party input. Prohibiting DTDs closes entity expansion and
                // external entity resolution; a null resolver means no network fetch can be
                // triggered by the document itself.
                DtdProcessing = DtdProcessing.Prohibit,
                XmlResolver = null,
                CloseInput = false,
            });

            var parsed = SyndicationFeed.Load(reader);
            var feedTitle = string.IsNullOrWhiteSpace(preferredTitle)
                ? FeedText.CleanTitle(parsed.Title?.Text)
                : preferredTitle;

            return SortNewestFirst(parsed.Items.Select(item => ArticleItem.FromSyndication(item, feedTitle)));
        }

        private static ArticleItem[] SortNewestFirst(IEnumerable<ArticleItem> articles) =>
            articles
                // Dated articles first, newest to oldest, then undated ones in the order the feed
                // gave them — which for a feed with no dates is its own idea of newest first.
                .OrderByDescending(a => a.PublishedOn.HasValue)
                .ThenByDescending(a => a.PublishedOn ?? DateTimeOffset.MinValue)
                .ToArray();

        /// <summary>Turns an exception into something worth putting in the status bar.</summary>
        private static string DescribeFailure(Exception ex) => ex switch
        {
            // HttpClient surfaces its own timeout as a cancellation with no token attached.
            TaskCanceledException or TimeoutException => "timed out",
            HttpRequestException { StatusCode: { } status } => $"server said {(int)status} {status}",
            HttpRequestException => "could not be reached",
            XmlException => "is not valid XML",
            // SyndicationFeed.Load throws this for a well-formed document that is not RSS or Atom,
            // with a message about serializers that means nothing to a reader.
            NotSupportedException => "is not a feed RSS Quick understands",
            _ => ex.Message,
        };
    }
}
