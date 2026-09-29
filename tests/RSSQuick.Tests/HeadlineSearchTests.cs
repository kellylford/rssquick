using System.Linq;
using RSSReaderWPF;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// Which headlines a search finds, and what it says about them. The macOS and iOS versions answer
/// the same questions in macos/Tests/RSSQuickCoreTests/HeadlineSearchTests.swift.
/// </summary>
public class HeadlineSearchTests
{
    private static ArticleItem Headline(string title, string feed = "BBC News") => new() { Title = title, FeedTitle = feed };

    private static readonly ArticleItem[] Headlines =
    {
        Headline("Storm closes schools"),
        Headline("Café opens in the high street", "Local"),
        Headline("Election results", "The Guardian"),
        Headline("Storm warning for the coast", "The Guardian"),
    };

    private static string[] Find(string query) => HeadlineSearch.Filter(Headlines, query).Select(a => a.Title).ToArray();

    [Fact]
    public void A_word_matches_any_headline_containing_it_whatever_its_case() =>
        Assert.Equal(new[] { "Storm closes schools", "Storm warning for the coast" }, Find("STORM"));

    [Fact]
    public void Every_word_has_to_match_but_not_next_to_each_other() =>
        Assert.Equal(new[] { "Storm warning for the coast" }, Find("coast storm"));

    [Fact]
    public void A_feed_s_name_counts_so_a_search_can_narrow_to_one_publisher() =>
        Assert.Equal(new[] { "Storm closes schools" }, Find("bbc storm"));

    [Fact]
    public void Accents_are_ignored() =>
        Assert.Equal(new[] { "Café opens in the high street" }, Find("cafe"));

    [Fact]
    public void Nothing_to_search_for_finds_nothing()
    {
        Assert.Empty(Find(""));
        Assert.Empty(Find("   "));
    }

    [Fact]
    public void A_feed_in_two_folders_is_searched_once()
    {
        var one = new FeedItem { Title = "One", Url = "https://example.com/one.xml" };
        var again = new FeedItem { Title = "One again", Url = "https://EXAMPLE.com/one.xml" };
        var two = new FeedItem { Title = "Two", Url = "https://example.com/two.xml" };
        var a = new FeedItem { Title = "A", IsCategory = true };
        a.Children.Add(one);
        var b = new FeedItem { Title = "B", IsCategory = true };
        b.Children.Add(again);
        b.Children.Add(two);

        Assert.Equal(new[] { "One", "Two" }, HeadlineSearch.FeedsToSearch(new[] { a, b }).Select(f => f.Title));
    }

    [Fact]
    public void What_it_says_covers_found_nothing_found_and_failures()
    {
        var clean = new FolderLoadResult(Headlines, [], 12);
        var partial = new FolderLoadResult(Headlines, [new FeedFailure("Gone", "timed out")], 12);
        var none = new FolderLoadResult([], [new FeedFailure("A", "x"), new FeedFailure("B", "y")], 2);

        Assert.Equal("Searching 12 feeds for storm...", HeadlineSearch.DescribeStart("storm", 12));
        Assert.Equal("Found 2 headlines matching storm in 12 feeds", HeadlineSearch.Describe("storm", 2, clean));
        Assert.Equal("Found 1 headline matching storm in 12 feeds", HeadlineSearch.Describe("storm", 1, clean));
        Assert.Equal("No headlines match storm in 12 feeds", HeadlineSearch.Describe("storm", 0, clean));
        Assert.Equal("Found 2 headlines matching storm in 11 of 12 feeds; 1 could not be loaded", HeadlineSearch.Describe("storm", 2, partial));
        Assert.Equal("None of the 2 feeds could be loaded, so nothing was searched", HeadlineSearch.Describe("storm", 0, none));
    }
}
