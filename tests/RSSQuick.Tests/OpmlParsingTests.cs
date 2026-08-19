using System;
using System.Linq;
using System.Xml;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// OPML in, feed tree out. This is user-supplied XML exported by other readers, so the shapes it
/// arrives in vary more than the spec suggests.
/// </summary>
public class OpmlParsingTests
{
    private const string Nested = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>My feeds</title></head>
          <body>
            <outline text="News">
              <outline text="BBC" xmlUrl="https://example.com/bbc.xml"/>
              <outline text="Sport">
                <outline text="Cricket" xmlUrl="https://example.com/cricket.xml"/>
              </outline>
            </outline>
            <outline text="Tech">
              <outline text="Ars" xmlUrl="https://example.com/ars.xml"/>
            </outline>
          </body>
        </opml>
        """;

    [Fact]
    public void Folders_and_feeds_come_back_in_the_order_the_file_listed_them()
    {
        var opml = OpmlParser.Parse(Nested);

        Assert.Equal(new[] { "News", "Tech" }, opml.Roots.Select(r => r.Title));
        Assert.All(opml.Roots, r => Assert.True(r.IsCategory));
    }

    [Fact]
    public void Folders_nest_to_any_depth()
    {
        var news = OpmlParser.Parse(Nested).Roots.First();
        var sport = news.Children.Single(c => c.Title == "Sport");

        Assert.True(sport.IsCategory);
        Assert.Equal("Cricket", sport.Children.Single().Title);
        Assert.Equal("https://example.com/cricket.xml", sport.Children.Single().Url);
    }

    [Fact]
    public void Feeds_at_any_depth_are_counted_but_folders_are_not() =>
        Assert.Equal(3, OpmlParser.Parse(Nested).FeedCount);

    [Fact]
    public void An_outline_with_a_feed_url_is_a_feed_and_one_without_is_a_folder()
    {
        var news = OpmlParser.Parse(Nested).Roots.First();
        var bbc = news.Children.Single(c => c.Title == "BBC");

        Assert.False(bbc.IsCategory);
        Assert.Empty(bbc.Children);
    }

    [Fact]
    public void A_feed_listed_outside_any_folder_gets_one()
    {
        // Every feed sits inside a folder so Enter means the same thing at every visible level.
        var opml = OpmlParser.Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0"><body>
              <outline text="Loose" xmlUrl="https://example.com/loose.xml"/>
            </body></opml>
            """);

        var folder = Assert.Single(opml.Roots);
        Assert.True(folder.IsCategory);
        Assert.Equal("Uncategorized", folder.Title);
        Assert.Equal("Loose", folder.Children.Single().Title);
    }

    [Fact]
    public void Several_loose_feeds_share_one_folder_rather_than_getting_one_each()
    {
        var opml = OpmlParser.Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0"><body>
              <outline text="One" xmlUrl="https://example.com/1.xml"/>
              <outline text="Two" xmlUrl="https://example.com/2.xml"/>
            </body></opml>
            """);

        Assert.Equal(2, Assert.Single(opml.Roots).Children.Count);
    }

    [Fact]
    public void Title_is_used_when_there_is_no_text_attribute()
    {
        // The spec says text; plenty of exporters write only title.
        var opml = OpmlParser.Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0"><body>
              <outline title="Named by title" xmlUrl="https://example.com/a.xml"/>
            </body></opml>
            """);

        Assert.Equal("Named by title", opml.Roots.Single().Children.Single().Title);
    }

    [Fact]
    public void An_outline_with_no_usable_name_still_appears()
    {
        // Better a row called Unknown than a feed that silently vanishes from the tree.
        var opml = OpmlParser.Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0"><body>
              <outline xmlUrl="https://example.com/a.xml"/>
            </body></opml>
            """);

        Assert.Equal("Unknown", opml.Roots.Single().Children.Single().Title);
    }

    [Fact]
    public void Names_are_cleaned_the_way_headlines_are()
    {
        // Feed names come from the same exporters as headlines and carry the same invisible
        // characters, and they are read aloud just as often.
        var opml = OpmlParser.Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0"><body>
              <outline text="  Messy&#8203;   name  " xmlUrl="https://example.com/a.xml"/>
            </body></opml>
            """);

        Assert.Equal("Messy name", opml.Roots.Single().Children.Single().Title);
    }

    [Fact]
    public void An_empty_body_yields_an_empty_tree()
    {
        var opml = OpmlParser.Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0"><body></body></opml>
            """);

        Assert.Empty(opml.Roots);
        Assert.Equal(0, opml.FeedCount);
    }

    [Fact]
    public void A_document_with_no_body_is_refused_with_something_readable()
    {
        var ex = Assert.Throws<InvalidOperationException>(() => OpmlParser.Parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0"><head><title>No body</title></head></opml>
            """));

        Assert.Contains("body", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Malformed_xml_is_refused() =>
        Assert.ThrowsAny<XmlException>(() => OpmlParser.Parse("<opml><body><outline"));

    [Fact]
    public void A_document_declaring_a_dtd_is_refused() =>
        // OPML is user-supplied XML like feed content, and gets the same treatment.
        Assert.ThrowsAny<XmlException>(() => OpmlParser.Parse("""
            <?xml version="1.0"?>
            <!DOCTYPE opml [<!ENTITY x "expanded">]>
            <opml version="2.0"><body></body></opml>
            """));
}
