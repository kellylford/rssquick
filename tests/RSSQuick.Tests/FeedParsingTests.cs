using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// Feed XML in, headlines out. Covers the shapes real feeds actually arrive in, including the
/// broken ones — this is third-party input and none of it can be relied on.
/// </summary>
public class FeedParsingTests
{
    private static IReadOnlyList<RSSReaderWPF.ArticleItem> Parse(string xml, string title = "Test Feed")
    {
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(xml));
        return FeedLoader.Parse(stream, title);
    }

    private const string TwoItemRss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Channel title</title>
            <item>
              <title>Older story</title>
              <link>https://example.com/older</link>
              <pubDate>Tue, 04 Aug 2026 09:00:00 GMT</pubDate>
            </item>
            <item>
              <title>Newer story</title>
              <link>https://example.com/newer</link>
              <pubDate>Wed, 05 Aug 2026 09:00:00 GMT</pubDate>
            </item>
          </channel>
        </rss>
        """;

    [Fact]
    public void Rss_items_come_back_newest_first()
    {
        var articles = Parse(TwoItemRss);

        Assert.Equal(new[] { "Newer story", "Older story" }, articles.Select(a => a.Title));
    }

    [Fact]
    public void Atom_feeds_parse_too()
    {
        var articles = Parse("""
            <?xml version="1.0" encoding="utf-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom">
              <title>An Atom feed</title>
              <entry>
                <title>An entry</title>
                <link href="https://example.com/entry"/>
                <updated>2026-08-05T09:00:00Z</updated>
              </entry>
            </feed>
            """);

        var article = Assert.Single(articles);
        Assert.Equal("An entry", article.Title);
        Assert.Equal("https://example.com/entry", article.Link);
    }

    [Fact]
    public void The_name_from_the_opml_file_wins_over_the_feed_s_own()
    {
        // What the user called it is what the status bar should say.
        Assert.All(Parse(TwoItemRss, "My name for it"), a => Assert.Equal("My name for it", a.FeedTitle));
    }

    [Fact]
    public void A_feed_with_no_name_in_the_opml_falls_back_to_its_own_title() =>
        Assert.All(Parse(TwoItemRss, ""), a => Assert.Equal("Channel title", a.FeedTitle));

    [Fact]
    public void Titles_are_cleaned_on_the_way_through()
    {
        // The single place this is guaranteed. Both load paths go through it, which is the point
        // of having one factory — the divergence between them is what caused the original bug.
        var article = Assert.Single(Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>c</title>
              <item><title>  Messy&#8203;   headline  </title><link>https://example.com/a</link></item>
            </channel></rss>
            """));

        Assert.Equal("Messy headline", article.Title);
    }

    [Fact]
    public void An_item_with_no_date_reports_no_date_rather_than_the_year_one()
    {
        var article = Assert.Single(Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>c</title>
              <item><title>Undated</title><link>https://example.com/a</link></item>
            </channel></rss>
            """));

        Assert.Null(article.PublishedOn);
        // Used to announce "0001-01-01 00:00" on every headline of a feed that gives no dates.
        Assert.Equal(string.Empty, article.Published);
    }

    [Fact]
    public void Undated_items_sort_below_dated_ones_instead_of_by_a_failed_parse()
    {
        var articles = Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>c</title>
              <item><title>Undated</title><link>https://example.com/u</link></item>
              <item><title>Dated</title><link>https://example.com/d</link>
                    <pubDate>Wed, 05 Aug 2026 09:00:00 GMT</pubDate></item>
            </channel></rss>
            """);

        Assert.Equal(new[] { "Dated", "Undated" }, articles.Select(a => a.Title));
    }

    [Fact]
    public void The_article_link_is_preferred_over_an_enclosure()
    {
        // Podcast feeds put the audio file first. Taking the first link meant Enter opened an
        // MP3 rather than the episode page.
        var article = Assert.Single(Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>c</title>
              <item>
                <title>An episode</title>
                <enclosure url="https://example.com/audio.mp3" length="1" type="audio/mpeg"/>
                <link>https://example.com/episode</link>
              </item>
            </channel></rss>
            """));

        Assert.Equal("https://example.com/episode", article.Link);
    }

    [Fact]
    public void An_item_with_no_link_parses_rather_than_throwing()
    {
        // The Open in Browser button is disabled for these; losing the whole feed would be worse.
        var article = Assert.Single(Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>c</title>
              <item><title>No link here</title></item>
            </channel></rss>
            """));

        Assert.Equal("No link here", article.Title);
        Assert.Equal(string.Empty, article.Link);
    }

    [Fact]
    public void An_empty_channel_yields_no_articles_rather_than_an_error() =>
        Assert.Empty(Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>c</title></channel></rss>
            """));

    [Fact]
    public void Malformed_xml_throws_something_the_caller_can_describe()
    {
        // FeedLoader turns this into "is not valid XML" rather than a raw parser message.
        Assert.ThrowsAny<XmlException>(() => Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>unclosed
            """));
    }

    [Fact]
    public void A_well_formed_document_that_is_not_a_feed_is_refused() =>
        // A feed URL pointing at an HTML page, which is what a publisher's redirect to a
        // "we have moved" notice looks like from here.
        Assert.ThrowsAny<XmlException>(() => Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <html><body><p>Not a feed.</p></body></html>
            """));

    [Fact]
    public void An_rss_element_with_no_version_is_refused_as_an_unsupported_format() =>
        // Deliberately its own test: this one path throws NotSupportedException rather than
        // XmlException, with a message about RSS serializers that means nothing to a reader, so
        // FeedLoader.DescribeFailure has to translate it separately.
        Assert.Throws<NotSupportedException>(() => Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <rss><channel><title>No version attribute</title></channel></rss>
            """));

    [Fact]
    public void A_document_declaring_a_dtd_is_refused()
    {
        // DtdProcessing.Prohibit. Feed XML is untrusted input and entity expansion is the classic
        // way to turn parsing it into a denial of service.
        Assert.Throws<XmlException>(() => Parse("""
            <?xml version="1.0"?>
            <!DOCTYPE rss [<!ENTITY x "expanded">]>
            <rss version="2.0"><channel><title>c</title></channel></rss>
            """));
    }
}
