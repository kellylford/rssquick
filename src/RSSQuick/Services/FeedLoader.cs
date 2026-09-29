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
using System.Xml.Linq;

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
            // Checked here rather than left to HttpClient, whose InvalidOperationException for a
            // bad address is too general a type to translate safely further up.
            if (!Uri.TryCreate(feed.Url, UriKind.Absolute, out var address)
                || (address.Scheme != Uri.UriSchemeHttp && address.Scheme != Uri.UriSchemeHttps))
                throw new UriFormatException($"{feed.Url} is not a web address.");

            var payload = await DownloadAsync(address, cancellationToken).ConfigureAwait(false);

            using var stream = new MemoryStream(payload, writable: false);
            return Parse(stream, feed.Title);
        }

        /// <summary>
        /// Fetches a document whole, on the same client, timeout and size limit as a feed.
        /// </summary>
        /// <remarks>
        /// Buffered before parsing, because SyndicationFeed.Load reads synchronously and would
        /// otherwise block a thread pool thread on the network for the length of the download.
        /// <see cref="FeedDiscovery"/> uses it for web pages as well as feeds.
        /// </remarks>
        internal static async Task<byte[]> DownloadAsync(Uri address, CancellationToken cancellationToken) =>
            (await DownloadFromAsync(address, cancellationToken).ConfigureAwait(false)).Payload;

        /// <summary>
        /// <see cref="DownloadAsync"/>, and the address the document came from once redirects
        /// were followed - which is what a web page's relative links are relative to.
        /// </summary>
        internal static async Task<(byte[] Payload, Uri Address)> DownloadFromAsync(Uri address, CancellationToken cancellationToken)
        {
            using var response = await Http
                .GetAsync(address, HttpCompletionOption.ResponseContentRead, cancellationToken)
                .ConfigureAwait(false);

            response.EnsureSuccessStatusCode();

            var payload = await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);
            return (payload, response.RequestMessage?.RequestUri ?? address);
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
        public static IReadOnlyList<ArticleItem> Parse(Stream stream, string preferredTitle) =>
            ParseFeed(stream, preferredTitle).Articles;

        /// <summary>
        /// <see cref="Parse"/>, and the feed's own title as well, cleaned: what
        /// <see cref="FeedDiscovery"/> names a new subscription, since a feed with no entries
        /// today has no article to carry it.
        /// </summary>
        internal static (string OwnTitle, IReadOnlyList<ArticleItem> Articles) ParseFeed(Stream stream, string preferredTitle)
        {
            // Read twice - once to see what kind of feed it is, once to read it - so buffered.
            // The syndication formatters need an ordinary reader over the text: handed one built
            // from an XDocument they fail on the first text node.
            using var buffer = new MemoryStream();
            stream.CopyTo(buffer);

            SyndicationFeed parsed;
            using (var probe = CreateReader(buffer))
            {
                probe.MoveToContent();
                if (probe.LocalName == "RDF" && probe.NamespaceURI == Rdf.NamespaceName)
                {
                    parsed = ReadRdf(XElement.Load(probe));
                }
                else
                {
                    using var reader = CreateReader(buffer);
                    parsed = ReadRssOrAtom(reader);
                }
            }

            var ownTitle = FeedText.CleanTitle(parsed.Title?.Text);
            var feedTitle = string.IsNullOrWhiteSpace(preferredTitle) ? ownTitle : preferredTitle;

            return (ownTitle, SortNewestFirst(parsed.Items.Select(item => ArticleItem.FromSyndication(item, feedTitle))));
        }

        /// <summary>A reader over the whole buffer, from the start.</summary>
        private static XmlReader CreateReader(MemoryStream buffer)
        {
            buffer.Position = 0;
            return XmlReader.Create(buffer, new XmlReaderSettings
            {
                // Feed XML is third-party input. Prohibiting DTDs closes entity expansion and
                // external entity resolution; a null resolver means no network fetch can be
                // triggered by the document itself.
                DtdProcessing = DtdProcessing.Prohibit,
                XmlResolver = null,
                CloseInput = false,
            });
        }

        private static readonly XNamespace Rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
        private static readonly XNamespace Rss1 = "http://purl.org/rss/1.0/";
        internal static readonly XNamespace DublinCore = "http://purl.org/dc/elements/1.1/";

        /// <summary>RSS 2.0 or Atom, with <see cref="FeedDate"/> behind the library's own dates.</summary>
        /// <remarks>
        /// <para>The formatters are used directly rather than through SyndicationFeed.Load only so
        /// that <see cref="FeedDate"/> can be added as a second chance for a date the library
        /// cannot read. It is added, not substituted: the library's own parser is lenient in ways
        /// FeedDate is not (full month names, two-digit years, a single-digit hour, the current
        /// culture), and replacing it lost dates that had always parsed.</para>
        /// <para>Anything neither formatter reads still goes through Load, so a document that is
        /// not a feed fails exactly as it always has.</para>
        /// </remarks>
        private static SyndicationFeed ReadRssOrAtom(XmlReader reader)
        {
            var atom = new Atom10FeedFormatter();
            atom.DateTimeParser = ThenFeedDate(atom.DateTimeParser);
            if (atom.CanRead(reader))
            {
                atom.ReadFrom(reader);
                return atom.Feed;
            }

            var rss = new Rss20FeedFormatter();
            rss.DateTimeParser = ThenFeedDate(rss.DateTimeParser);
            if (rss.CanRead(reader))
            {
                rss.ReadFrom(reader);
                return rss.Feed;
            }

            return SyndicationFeed.Load(reader);
        }

        /// <summary>The library's own date parser, then <see cref="FeedDate"/> if it gives up.</summary>
        private static TryParseDateTimeCallback ThenFeedDate(TryParseDateTimeCallback library) =>
            (XmlDateTimeData data, out DateTimeOffset date) =>
                library(data, out date) || FeedDate.TryParse(data, out date);

        /// <summary>
        /// RSS 1.0, which is RDF, and which the syndication library does not read at all.
        /// </summary>
        /// <remarks>
        /// Built into a <see cref="SyndicationFeed"/> so that it becomes articles through
        /// <see cref="ArticleItem.FromSyndication"/> like every other feed, rather than growing a
        /// second way to build one. Nature, in the starter list, is an RSS 1.0 feed; the macOS
        /// version has always read it.
        /// </remarks>
        private static SyndicationFeed ReadRdf(XElement root)
        {
            var feed = new SyndicationFeed(
                root.Element(Rss1 + "channel")?.Element(Rss1 + "title")?.Value ?? string.Empty,
                string.Empty,
                feedAlternateLink: null);

            var items = new List<SyndicationItem>();
            foreach (var element in root.Elements(Rss1 + "item"))
            {
                var item = new SyndicationItem
                {
                    Title = new TextSyndicationContent(element.Element(Rss1 + "title")?.Value ?? string.Empty),
                };

                if (Uri.TryCreate(element.Element(Rss1 + "link")?.Value.Trim(), UriKind.Absolute, out var link))
                    item.Links.Add(new SyndicationLink(link));

                if (element.Element(Rss1 + "description")?.Value is { } description)
                    item.Summary = new TextSyndicationContent(description);

                if (FeedDate.Parse(element.Element(DublinCore + "date")?.Value) is { } date)
                    item.PublishDate = date;

                if (element.Element(DublinCore + "creator")?.Value is { Length: > 0 } creator)
                    item.Authors.Add(new SyndicationPerson(null, creator, null));

                items.Add(item);
            }

            feed.Items = items;
            return feed;
        }

        private static ArticleItem[] SortNewestFirst(IEnumerable<ArticleItem> articles) =>
            articles
                // Dated articles first, newest to oldest, then undated ones in the order the feed
                // gave them — which for a feed with no dates is its own idea of newest first.
                .OrderByDescending(a => a.PublishedOn.HasValue)
                .ThenByDescending(a => a.PublishedOn ?? DateTimeOffset.MinValue)
                .ToArray();

        /// <summary>
        /// Turns an exception into something worth putting in the status bar.
        /// </summary>
        /// <remarks>
        /// Every result finishes the sentence "this feed ...", for a folder's failures and a single
        /// feed's alike. The macOS version is <c>ErrorText.describe</c>, and the two say the same
        /// things: raw exception text such as "Response status code does not indicate success"
        /// tells a reader nothing they can act on.
        /// </remarks>
        internal static string DescribeFailure(Exception ex) => ex switch
        {
            // HttpClient surfaces its own timeout as a cancellation with no token attached.
            TaskCanceledException or TimeoutException => "timed out",
            HttpRequestException { StatusCode: { } status } => $"server said {(int)status} {Words(status)}",
            HttpRequestException when !System.Net.NetworkInformation.NetworkInterface.GetIsNetworkAvailable()
                => "could not be reached - there is no network",
            HttpRequestException => "could not be reached",
            // Thrown by FetchAsync for an address it cannot make a request from.
            UriFormatException => "has an address RSS Quick cannot read",
            XmlException => "is not valid XML",
            // SyndicationFeed.Load throws this for a well-formed document that is not RSS or Atom,
            // with a message about serializers that means nothing to a reader.
            NotSupportedException => "is not a feed RSS Quick understands",
            _ => ex.Message,
        };

        /// <summary>"NotFound" as "not found", the way the Mac says it.</summary>
        private static string Words(HttpStatusCode status) =>
            System.Text.RegularExpressions.Regex.Replace(status.ToString(), "(?<=[a-z])(?=[A-Z])", " ").ToLowerInvariant();
    }
}
