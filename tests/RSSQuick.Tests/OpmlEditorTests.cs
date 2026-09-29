using System;
using System.Linq;
using System.Text;
using RSSReaderWPF;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// Subscribing and unsubscribing edit the OPML file itself. The macOS and iOS versions answer the
/// same questions in macos/Tests/RSSQuickCoreTests/OpmlEditorTests.swift; the two should change
/// together.
/// </summary>
public class OpmlEditorTests
{
    private const string List = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Mine</title><ownerName>Someone</ownerName></head>
          <body>
            <outline text="News">
              <outline text="Wires">
                <outline text="Reuters" xmlUrl="https://example.com/reuters.xml" htmlUrl="https://example.com/"/>
              </outline>
              <outline text="Guardian" xmlUrl="https://example.com/guardian.xml"/>
            </outline>
            <outline text="Loose" xmlUrl="https://example.com/loose.xml"/>
            <outline text="Sport">
              <outline text="Scores" xmlUrl="https://example.com/scores.xml"/>
            </outline>
          </body>
        </opml>
        """;

    private static byte[] Bytes(string text) => Encoding.UTF8.GetBytes(text);

    private static OpmlDocument Read(byte[] content) => OpenedFeedList.Parse(content, isSaved: false).Document;

    private static FeedItem Folder(OpmlDocument document, string title) =>
        Flatten(document.Roots).First(n => n.IsCategory && n.Title == title);

    private static FeedItem Feed(OpmlDocument document, string title) =>
        Flatten(document.Roots).First(n => !n.IsCategory && n.Title == title);

    private static System.Collections.Generic.IEnumerable<FeedItem> Flatten(System.Collections.Generic.IEnumerable<FeedItem> nodes) =>
        nodes.SelectMany(n => new[] { n }.Concat(Flatten(n.Children)));

    [Fact]
    public void The_parser_records_where_each_outline_is()
    {
        var document = Read(Bytes(List));

        Assert.Equal(new[] { 0 }, Folder(document, "News").OutlinePath);
        Assert.Equal(new[] { 0, 0, 0 }, Feed(document, "Reuters").OutlinePath);
        Assert.Equal(new[] { 1 }, Feed(document, "Loose").OutlinePath);
        Assert.Equal(new[] { 2, 0 }, Feed(document, "Scores").OutlinePath);
        // Made up by the parser for loose feeds, so it has no element of its own.
        Assert.Null(Folder(document, "Uncategorized").OutlinePath);
    }

    [Fact]
    public void A_feed_added_to_a_nested_folder_goes_at_its_end()
    {
        var document = Read(Bytes(List));

        var changed = Read(OpmlEditor.AddFeed(Bytes(List), Folder(document, "Wires").OutlinePath, "AP", "https://example.com/ap.xml"));

        var wires = Folder(changed, "Wires");
        Assert.Equal(new[] { "Reuters", "AP" }, wires.Children.Select(c => c.Title));
        Assert.Equal("https://example.com/ap.xml", wires.Children[1].Url);
        Assert.Equal(5, changed.FeedCount);
    }

    [Fact]
    public void A_feed_added_at_the_top_level_is_shown_as_uncategorized()
    {
        var changed = Read(OpmlEditor.AddFeed(Bytes(List), null, "New", "https://example.com/new.xml"));

        Assert.Equal(new[] { "Loose", "New" }, Folder(changed, "Uncategorized").Children.Select(c => c.Title));
    }

    [Fact]
    public void Adding_keeps_everything_the_parser_does_not_read()
    {
        var text = Encoding.UTF8.GetString(OpmlEditor.AddFeed(Bytes(List), null, "New", "https://example.com/new.xml"));

        Assert.Contains("<ownerName>Someone</ownerName>", text, StringComparison.Ordinal);
        Assert.Contains("htmlUrl=\"https://example.com/\"", text, StringComparison.Ordinal);
    }

    [Fact]
    public void A_title_with_markup_characters_is_escaped_not_broken()
    {
        var changed = Read(OpmlEditor.AddFeed(Bytes(List), null, "Q&A <live>", "https://example.com/qa.xml?a=1&b=2"));

        var feed = Feed(changed, "Q&A <live>");
        Assert.Equal("https://example.com/qa.xml?a=1&b=2", feed.Url);
    }

    [Fact]
    public void Removing_takes_out_exactly_that_feed()
    {
        var document = Read(Bytes(List));

        var changed = Read(OpmlEditor.Remove(Bytes(List), Feed(document, "Guardian").OutlinePath!));

        Assert.Equal(new[] { "Wires" }, Folder(changed, "News").Children.Select(c => c.Title));
        Assert.Equal(3, changed.FeedCount);
    }

    [Fact]
    public void Removing_a_loose_feed_leaves_the_folders_alone()
    {
        var document = Read(Bytes(List));

        var changed = Read(OpmlEditor.Remove(Bytes(List), Feed(document, "Loose").OutlinePath!));

        Assert.DoesNotContain(changed.Roots, r => r.Title == "Uncategorized");
        Assert.Equal("Scores", Feed(changed, "Scores").Title);
    }

    [Fact]
    public void A_path_that_is_not_there_is_refused_rather_than_guessed()
    {
        Assert.Throws<InvalidOperationException>(() => OpmlEditor.Remove(Bytes(List), new[] { 9, 9 }));
    }

    [Fact]
    public void An_empty_list_takes_a_first_feed()
    {
        var changed = Read(OpmlEditor.AddFeed(OpmlEditor.Empty, null, "First", "https://example.com/first.xml"));

        Assert.Equal(1, changed.FeedCount);
        Assert.Equal("First", Feed(changed, "First").Title);
    }

    [Fact]
    public void A_list_with_a_doctype_is_refused_as_it_is_on_import()
    {
        var hostile = """<?xml version="1.0"?><!DOCTYPE opml [<!ENTITY x "x">]><opml><body/></opml>""";

        Assert.Throws<System.Xml.XmlException>(() => OpmlEditor.AddFeed(Bytes(hostile), null, "A", "https://example.com/a.xml"));
    }

    [Fact]
    public void Folders_are_named_with_the_folders_above_them_and_include_the_top_level()
    {
        var folders = OpmlEditor.Folders(Read(Bytes(List)).Roots);

        Assert.Equal(new[] { "News", "News / Wires", "Uncategorized", "Sport" }, folders.Select(f => f.Name));
        Assert.Null(folders.Single(f => f.Name == "Uncategorized").Path);
    }

    [Fact]
    public void A_list_with_no_loose_feeds_still_offers_the_top_level_last()
    {
        var folders = OpmlEditor.Folders(Read(OpmlEditor.Remove(Bytes(List), new[] { 1 })).Roots);

        Assert.Equal("Uncategorized", folders[^1].Name);
        Assert.Null(folders[^1].Path);
    }

    [Fact]
    public void The_suggested_folder_is_the_one_the_reader_is_in()
    {
        var document = Read(Bytes(List));
        var folders = OpmlEditor.Folders(document.Roots);

        Assert.Equal("News / Wires", OpmlEditor.Suggest(folders, document.Roots, Feed(document, "Reuters")).Name);
        Assert.Equal("Sport", OpmlEditor.Suggest(folders, document.Roots, Folder(document, "Sport")).Name);
        Assert.Equal("Uncategorized", OpmlEditor.Suggest(folders, document.Roots, null).Name);
    }

    [Fact]
    public void An_address_already_in_the_list_is_found_whatever_its_case_or_trailing_slash()
    {
        var roots = Read(Bytes(List)).Roots;

        Assert.Equal("Scores", OpmlEditor.FindFeed(roots, "HTTPS://example.com/scores.xml/")?.Title);
        Assert.Null(OpmlEditor.FindFeed(roots, "https://example.com/other.xml"));
    }
}
