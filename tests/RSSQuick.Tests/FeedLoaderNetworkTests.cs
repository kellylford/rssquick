using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using RSSReaderWPF;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// Exercises the real network path. Opt-in: set <c>RSSQUICK_RUN_NETWORK_TESTS=1</c> to run them.
/// </summary>
/// <remarks>
/// Off by default because they reach third-party servers, so they are slow and can fail for
/// reasons that have nothing to do with this code. They are worth having anyway — the timeout,
/// the concurrency, and the cancellation are the whole point of the loader and none of them are
/// observable from a parsing test.
/// </remarks>
public class FeedLoaderNetworkTests
{
    private static bool Enabled =>
        Environment.GetEnvironmentVariable("RSSQUICK_RUN_NETWORK_TESTS") == "1";

    private static FeedItem Feed(string title, string url) =>
        new() { Title = title, Url = url };

    [Fact]
    public async Task A_real_feed_loads()
    {
        Assert.SkipUnless(Enabled, "Set RSSQUICK_RUN_NETWORK_TESTS=1 to run network tests.");

        var articles = await FeedLoader.LoadFeedAsync(
            Feed("BBC News", "https://feeds.bbci.co.uk/news/rss.xml"),
            CancellationToken.None);

        Assert.NotEmpty(articles);
        Assert.All(articles, a =>
        {
            Assert.NotEqual("No Title", a.Title);
            Assert.Equal("BBC News", a.FeedTitle);
        });
    }

    [Fact]
    public async Task An_unreachable_host_gives_up_inside_the_timeout()
    {
        Assert.SkipUnless(Enabled, "Set RSSQUICK_RUN_NETWORK_TESTS=1 to run network tests.");

        // The fault being fixed: this used to sit on WebRequest's 100-second default.
        var clock = Stopwatch.StartNew();

        await Assert.ThrowsAnyAsync<Exception>(() => FeedLoader.LoadFeedAsync(
            Feed("Nowhere", "https://10.255.255.1/feed.xml"),
            CancellationToken.None));

        clock.Stop();
        Assert.True(clock.Elapsed < TimeSpan.FromSeconds(30),
            $"Gave up after {clock.Elapsed.TotalSeconds:F0}s, which is past the 15s request timeout.");
    }

    [Fact]
    public async Task One_dead_feed_does_not_cost_the_rest_of_the_folder()
    {
        Assert.SkipUnless(Enabled, "Set RSSQUICK_RUN_NETWORK_TESTS=1 to run network tests.");

        var feeds = new List<FeedItem>
        {
            Feed("BBC News", "https://feeds.bbci.co.uk/news/rss.xml"),
            Feed("Nowhere", "https://10.255.255.1/feed.xml"),
            Feed("The Guardian", "https://www.theguardian.com/world/rss"),
        };

        var result = await FeedLoader.LoadFolderAsync(feeds, progress: null, CancellationToken.None);

        Assert.NotEmpty(result.Articles);
        Assert.Equal(3, result.FeedsAttempted);
        // The dead one is reported rather than swallowed, which is what the status bar reads out.
        var failure = Assert.Single(result.Failures);
        Assert.Equal("Nowhere", failure.FeedTitle);
        Assert.NotEmpty(failure.Reason);
    }

    [Fact]
    public async Task Cancelling_stops_the_load()
    {
        Assert.SkipUnless(Enabled, "Set RSSQUICK_RUN_NETWORK_TESTS=1 to run network tests.");

        using var cancellation = new CancellationTokenSource();
        await cancellation.CancelAsync();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => FeedLoader.LoadFeedAsync(
            Feed("BBC News", "https://feeds.bbci.co.uk/news/rss.xml"),
            cancellation.Token));
    }
}
