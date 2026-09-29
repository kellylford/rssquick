using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// Turning what a reader typed into a feed. The macOS and iOS versions answer the same questions
/// in macos/Tests/RSSQuickCoreTests/FeedDiscoveryTests.swift.
/// </summary>
public class FeedDiscoveryTests
{
    [Theory]
    [InlineData("example.com/feed.xml", "https://example.com/feed.xml")]
    [InlineData("  http://example.com/rss  ", "http://example.com/rss")]
    [InlineData("feed://example.com/rss", "http://example.com/rss")]
    [InlineData("feed:https://example.com/rss", "https://example.com/rss")]
    public void An_address_is_made_into_a_web_address(string typed, string expected) =>
        Assert.Equal(expected, FeedDiscovery.Normalize(typed)?.AbsoluteUri);

    [Theory]
    [InlineData("")]
    [InlineData("ftp://example.com/feed.xml")]
    [InlineData("file:///C:/feeds.xml")]
    public void Something_that_cannot_be_a_web_address_is_refused(string typed) =>
        Assert.Null(FeedDiscovery.Normalize(typed));

    [Fact]
    public void A_page_s_feed_links_are_found_in_order_and_made_absolute()
    {
        const string page = """
            <html><head>
              <link rel="stylesheet" href="/style.css">
              <link rel="alternate" type="application/rss+xml" title="Posts" href="/feed.xml">
              <LINK REL='alternate' TYPE='application/atom+xml' HREF='https://other.example.com/atom?a=1&amp;b=2'>
              <link rel="alternate" type="text/html" href="/fr/">
              <link rel="alternate" type="application/rss+xml" href="/feed.xml">
            </head></html>
            """;

        var links = FeedDiscovery.FeedLinks(page, new Uri("https://example.com/blog/"));

        Assert.Equal(new[] { "https://example.com/feed.xml", "https://other.example.com/atom?a=1&b=2" },
            links.Select(l => l.AbsoluteUri));
    }

    [Fact]
    public async Task A_feed_address_is_used_as_it_is_and_named_by_the_feed()
    {
        using var server = new LocalFeedServer();
        var feed = server.Serve("news.xml", SampleFeed.WithItems("Example News", "One"));

        var found = await FeedDiscovery.FindAsync(feed.ToString(), CancellationToken.None);

        Assert.Equal(new DiscoveredFeed("Example News", feed.AbsoluteUri), found);
    }

    [Fact]
    public async Task A_website_address_leads_to_the_feed_it_links_to()
    {
        using var server = new LocalFeedServer();
        server.Serve("feed.xml", SampleFeed.WithItems("The Blog", "Post"));
        var page = server.Serve("index.html", """
            <!DOCTYPE html>
            <html><head><link rel="alternate" type="application/rss+xml" href="feed.xml"></head><body>Hi</body></html>
            """, contentType: "text/html");

        var found = await FeedDiscovery.FindAsync(page.ToString(), CancellationToken.None);

        Assert.Equal("The Blog", found.Title);
        Assert.Equal(new Uri(server.BaseAddress, "feed.xml").AbsoluteUri, found.Url);
    }

    [Fact]
    public async Task A_page_with_no_feed_says_so()
    {
        using var server = new LocalFeedServer();
        var page = server.Serve("plain.html", "<!DOCTYPE html><html><body>Nothing here</body></html>", contentType: "text/html");

        var ex = await Assert.ThrowsAsync<NoFeedFoundException>(() => FeedDiscovery.FindAsync(page.ToString(), CancellationToken.None));

        Assert.Equal("has no feed RSS Quick can find", FeedLoader.DescribeFailure(ex));
    }

    [Fact]
    public async Task A_missing_page_reports_what_the_server_said()
    {
        using var server = new LocalFeedServer();

        var ex = await Assert.ThrowsAnyAsync<Exception>(() => FeedDiscovery.FindAsync(server.Missing("gone").ToString(), CancellationToken.None));

        Assert.Equal("server said 404 not found", FeedLoader.DescribeFailure(ex));
    }
}
