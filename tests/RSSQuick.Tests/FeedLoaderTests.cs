using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net;
using System.Threading;
using System.Threading.Tasks;
using RSSReaderWPF;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// The loader against a server whose behaviour the test controls.
/// </summary>
/// <remarks>
/// These are the properties the loader exists for — a folder keeps going when one feed is down,
/// fetches are bounded and concurrent, cancellation stops the work — and none of them are visible
/// from a parsing test. Running against a loopback stub rather than the internet makes them fast
/// and deterministic enough to run on every build.
/// </remarks>
public class FeedLoaderTests
{
    private static FeedItem Feed(string title, Uri url) => new() { Title = title, Url = url.ToString() };

    [Fact]
    public async Task A_feed_loads()
    {
        using var server = new LocalFeedServer();
        var url = server.Serve("news.xml", SampleFeed.WithItems("News", "First", "Second"));

        var articles = await FeedLoader.LoadFeedAsync(Feed("News", url), CancellationToken.None);

        Assert.Equal(new[] { "First", "Second" }, articles.Select(a => a.Title));
        Assert.All(articles, a => Assert.Equal("News", a.FeedTitle));
    }

    // ── a folder keeps going when a feed does not ────────────────────────────

    [Fact]
    public async Task One_failing_feed_does_not_cost_the_rest_of_the_folder()
    {
        using var server = new LocalFeedServer();
        var feeds = new List<FeedItem>
        {
            Feed("Good", server.Serve("good.xml", SampleFeed.WithItems("Good", "A"))),
            Feed("Gone", server.Missing("gone.xml")),
            Feed("Also good", server.Serve("also.xml", SampleFeed.WithItems("Also good", "B"))),
        };

        var result = await FeedLoader.LoadFolderAsync(feeds, progress: null, CancellationToken.None);

        Assert.Equal(new[] { "A", "B" }, result.Articles.Select(a => a.Title).Order());
        Assert.Equal(3, result.FeedsAttempted);
        Assert.Equal(2, result.FeedsSucceeded);

        var failure = Assert.Single(result.Failures);
        Assert.Equal("Gone", failure.FeedTitle);
        // The status bar reads this out, so it has to mean something to a reader.
        Assert.Contains("404", failure.Reason, StringComparison.Ordinal);
    }

    [Fact]
    public async Task A_feed_serving_something_that_is_not_a_feed_is_reported_not_thrown()
    {
        using var server = new LocalFeedServer();
        var feeds = new List<FeedItem>
        {
            Feed("Moved", server.Serve("moved.html", "<html><body>We have moved</body></html>", contentType: "text/html")),
        };

        var result = await FeedLoader.LoadFolderAsync(feeds, progress: null, CancellationToken.None);

        Assert.Empty(result.Articles);
        Assert.Single(result.Failures);
    }

    [Fact]
    public async Task Progress_is_reported_once_per_feed()
    {
        using var server = new LocalFeedServer();
        var feeds = Enumerable.Range(0, 5)
            .Select(i => Feed($"Feed {i}", server.Serve($"f{i}.xml", SampleFeed.WithItems($"Feed {i}", "One"))))
            .ToList();

        var reported = new List<int>();
        var progress = new Progress<int>(done => { lock (reported) reported.Add(done); });

        await FeedLoader.LoadFolderAsync(feeds, progress, CancellationToken.None);

        // Progress marshals through the synchronization context, so give it a moment to drain.
        await WaitFor(() => { lock (reported) return reported.Count == feeds.Count; },
            "progress to be reported for every feed");

        lock (reported) Assert.Equal(Enumerable.Range(1, 5), reported.Order());
    }

    // ── the concurrency cap ──────────────────────────────────────────────────

    [Fact]
    public async Task A_folder_fetches_feeds_concurrently_rather_than_one_at_a_time()
    {
        using var server = new LocalFeedServer();
        var feeds = Enumerable.Range(0, 12)
            .Select(i => Feed($"Feed {i}", server.Serve(
                $"f{i}.xml",
                SampleFeed.WithItems($"Feed {i}", "One"),
                delay: TimeSpan.FromMilliseconds(150))))
            .ToList();

        await FeedLoader.LoadFolderAsync(feeds, progress: null, CancellationToken.None);

        // Serial fetching was the fault: twenty feeds with three dead servers took five minutes.
        Assert.True(server.PeakConcurrentRequests > 1,
            "Feeds were fetched one at a time.");
    }

    [Fact]
    public async Task Concurrency_is_capped_rather_than_opening_a_connection_per_feed()
    {
        using var server = new LocalFeedServer();
        var feeds = Enumerable.Range(0, 20)
            .Select(i => Feed($"Feed {i}", server.Serve(
                $"f{i}.xml",
                SampleFeed.WithItems($"Feed {i}", "One"),
                delay: TimeSpan.FromMilliseconds(150))))
            .ToList();

        await FeedLoader.LoadFolderAsync(feeds, progress: null, CancellationToken.None);

        // Unbounded fan-out is unkind to a shared connection and gets a client rate-limited.
        Assert.True(server.PeakConcurrentRequests <= 6,
            $"{server.PeakConcurrentRequests} feeds were in flight at once; the cap is 6.");
    }

    // ── cancellation ─────────────────────────────────────────────────────────

    [Fact]
    public async Task Cancelling_stops_a_folder_load()
    {
        using var server = new LocalFeedServer();
        var feeds = Enumerable.Range(0, 12)
            .Select(i => Feed($"Feed {i}", server.Serve(
                $"f{i}.xml",
                SampleFeed.WithItems($"Feed {i}", "One"),
                delay: TimeSpan.FromSeconds(5))))
            .ToList();

        using var cancellation = new CancellationTokenSource();
        var load = FeedLoader.LoadFolderAsync(feeds, progress: null, cancellation.Token);

        await cancellation.CancelAsync();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => load);
        // Cancelling means stopping, not waiting for the slow feeds to finish first.
        Assert.True(server.RequestsFor("f11.xml") < 12);
    }

    [Fact]
    public async Task An_already_cancelled_token_does_no_work_at_all()
    {
        using var server = new LocalFeedServer();
        var url = server.Serve("news.xml", SampleFeed.WithItems("News", "First"));

        using var cancellation = new CancellationTokenSource();
        await cancellation.CancelAsync();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => FeedLoader.LoadFeedAsync(Feed("News", url), cancellation.Token));

        Assert.Equal(0, server.RequestsFor("news.xml"));
    }

    /// <summary>Polls until <paramref name="condition"/> holds, or fails the test.</summary>
    private static async Task WaitFor(Func<bool> condition, string what)
    {
        var clock = Stopwatch.StartNew();
        while (clock.Elapsed < TimeSpan.FromSeconds(5))
        {
            if (condition()) return;
            await Task.Delay(20);
        }

        Assert.Fail($"Timed out waiting for {what}.");
    }
}
