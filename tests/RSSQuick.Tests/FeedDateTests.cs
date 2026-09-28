using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// The date forms feeds actually use, and the feed formats that carry them. The macOS version
/// answers the same questions in macos/Tests/RSSQuickCoreTests/FeedParserTests.swift
/// (FeedDateTests, and the RDF test); the two should change together.
/// </summary>
public class FeedDateTests
{
    [Fact]
    public void Rfc822_as_rss_2_requires_it()
    {
        Assert.NotNull(FeedDate.Parse("Mon, 02 Mar 2026 09:00:00 GMT"));
        Assert.NotNull(FeedDate.Parse("Mon, 02 Mar 2026 09:00:00 +0000"));
        Assert.NotNull(FeedDate.Parse("02 Mar 2026 09:00:00 GMT"));
        Assert.NotNull(FeedDate.Parse("Mon, 02 Mar 2026 09:00 GMT"));
    }

    [Fact]
    public void Rfc822_zones_are_read_as_the_offsets_they_name()
    {
        Assert.Equal(TimeSpan.FromHours(-5), FeedDate.Parse("Mon, 02 Mar 2026 09:00:00 EST")?.Offset);
        Assert.Equal(TimeSpan.FromHours(-7), FeedDate.Parse("Mon, 02 Mar 2026 09:00:00 -0700")?.Offset);
    }

    [Fact]
    public void Iso_8601_as_atom_requires_it()
    {
        Assert.NotNull(FeedDate.Parse("2026-03-02T09:00:00Z"));
        Assert.NotNull(FeedDate.Parse("2026-03-02T09:00:00+01:00"));
        Assert.NotNull(FeedDate.Parse("2026-03-02T09:00:00.123Z"));
    }

    [Fact]
    public void The_looser_forms_publishers_use_anyway()
    {
        Assert.NotNull(FeedDate.Parse("2026-03-02"));
        Assert.NotNull(FeedDate.Parse("2026-03-02 09:00:00"));
    }

    /// <summary>Read as UTC, so the same feed sorts the same wherever it is read.</summary>
    [Fact]
    public void A_date_with_no_zone_is_read_as_utc() =>
        Assert.Equal(TimeSpan.Zero, FeedDate.Parse("2026-03-02 09:00:00")?.Offset);

    [Theory]
    [InlineData("last Tuesday-ish")]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("   ")]
    public void Nonsense_is_null_rather_than_an_error(string? text) =>
        Assert.Null(FeedDate.Parse(text));

    [Fact]
    public void An_english_feed_parses_whatever_the_reader_s_locale_is()
    {
        var before = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = new CultureInfo("fr-FR");
            Assert.NotNull(FeedDate.Parse("Wed, 04 Mar 2026 09:00:00 GMT"));
        }
        finally
        {
            CultureInfo.CurrentCulture = before;
        }
    }

    /// <summary>
    /// Forms the library reads and FeedDate does not. Replacing the library's parser with
    /// FeedDate, rather than putting FeedDate behind it, lost every one of these.
    /// </summary>
    [Theory]
    [InlineData("Wed, 02 October 2002 13:00:00 GMT")]
    [InlineData("02 Oct 02 13:00:00 GMT")]
    [InlineData("Wed, 02 Oct 2002 1:00:00 GMT")]
    [InlineData("2002-10-02T13:00Z")]
    public void Dates_the_library_always_read_still_parse(string pubDate)
    {
        var article = Assert.Single(Parse($"""
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0">
              <channel><title>c</title>
                <item><title>t</title><link>https://example.com/t</link><pubDate>{pubDate}</pubDate></item>
              </channel>
            </rss>
            """));

        Assert.NotNull(article.PublishedOn);
    }

    // ── in feeds ─────────────────────────────────────────────────────────────

    private static RSSReaderWPF.ArticleItem[] Parse(string xml)
    {
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(xml));
        return FeedLoader.Parse(stream, "Test Feed").ToArray();
    }

    /// <summary>Nature, in the starter list, is one of these.</summary>
    [Fact]
    public void Rss_1_over_rdf_is_read_including_its_dublin_core_date_and_author()
    {
        var articles = Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                     xmlns="http://purl.org/rss/1.0/"
                     xmlns:dc="http://purl.org/dc/elements/1.1/">
              <channel rdf:about="https://example.com"><title>RDF Example</title></channel>
              <item rdf:about="https://example.com/a">
                <title>An RDF item</title>
                <link>https://example.com/a</link>
                <dc:date>2026-03-02T09:00:00Z</dc:date>
                <dc:creator>Someone</dc:creator>
              </item>
            </rdf:RDF>
            """);

        var article = Assert.Single(articles);
        Assert.Equal("An RDF item", article.Title);
        Assert.Equal("https://example.com/a", article.Link);
        Assert.Equal("Someone", article.Author);
        Assert.Equal(new DateTimeOffset(2026, 3, 2, 9, 0, 0, TimeSpan.Zero), article.PublishedOn);
    }

    [Fact]
    public void An_rss_item_dated_only_by_dublin_core_keeps_its_date()
    {
        var article = Assert.Single(Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
              <channel><title>c</title>
                <item><title>t</title><link>https://example.com/t</link><dc:date>2026-03-02T09:00:00Z</dc:date></item>
              </channel>
            </rss>
            """));

        Assert.Equal(new DateTimeOffset(2026, 3, 2, 9, 0, 0, TimeSpan.Zero), article.PublishedOn);
    }

    /// <summary>
    /// The library's own parser reads this; kept as a guard that adding FeedDate behind it did
    /// not take anything away.
    /// </summary>
    [Fact]
    public void An_rss_pubdate_written_as_iso_8601_keeps_its_date()
    {
        var article = Assert.Single(Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0">
              <channel><title>c</title>
                <item><title>t</title><link>https://example.com/t</link><pubDate>2026-03-02T09:00:00Z</pubDate></item>
              </channel>
            </rss>
            """));

        Assert.Equal(new DateTimeOffset(2026, 3, 2, 9, 0, 0, TimeSpan.Zero), article.PublishedOn);
    }
}
