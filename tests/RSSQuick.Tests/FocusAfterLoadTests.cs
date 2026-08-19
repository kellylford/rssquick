using System.Linq;
using System.Windows.Controls;
using RSSReaderWPF;

namespace RSSQuick.Tests;

/// <summary>
/// Where focus goes once a feed has loaded, and whether it stays there.
/// </summary>
/// <remarks>
/// The whole point of the application is arrowing through headlines, so landing on the first one
/// after a load — and coming back to the one you were on — is the interaction that matters most.
/// It is also the part with the most moving pieces: an unawaited load, a dispatcher continuation,
/// and containers that are not realised at the moment the data arrives.
///
/// Enter is raised as a real routed event against a real window, and the feeds are served by a
/// loopback stub, so this exercises the actual load path rather than a stand-in for it.
/// </remarks>
[Collection(WpfCollection.Name)]
public class FocusAfterLoadTests
{
    private static FeedItem Feed(string title, System.Uri url) =>
        new() { Title = title, Url = url.ToString() };

    [WpfFact]
    public void Loading_a_feed_puts_focus_on_the_first_headline()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);

        ui.SetFeeds(Feed("News", server.Serve("news.xml",
            SampleFeed.WithItems("News", "First story", "Second story", "Third story"))));

        ui.PressEnterOnFeed(0);
        ui.PumpUntil(() => ui.Headlines.Items.Count == 3, "the feed to load");

        // Not the list container, which announces nothing, and not the feed tree the user
        // pressed Enter in — the point of Enter is to get to the headlines.
        var focused = Assert.IsType<ListBoxItem>(ui.Focused);
        Assert.Equal("First story", ((ArticleItem)focused.DataContext).Title);
    }

    [WpfFact]
    public void The_status_bar_reports_what_loaded()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);

        ui.SetFeeds(Feed("News", server.Serve("news.xml", SampleFeed.WithItems("News", "A", "B"))));

        ui.PressEnterOnFeed(0);
        ui.PumpUntil(() => ui.Headlines.Items.Count == 2, "the feed to load");

        // The only live region in the window, so this is the whole of what gets announced.
        //
        // Asserted as the whole string rather than as substrings. The position announcement that
        // the load's own selection triggers is "News - 1 of 2", which contains both "News" and
        // "2" - so a substring check passed against the summary being wiped out entirely.
        var status = (TextBlock)ui.Window.FindName("StatusText")!;
        Assert.Equal("Loaded 2 headlines from News", status.Text);
    }

    [WpfFact]
    public void Moving_off_the_first_headline_hands_the_status_bar_over_to_position()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);

        ui.SetFeeds(Feed("News", server.Serve("news.xml", SampleFeed.WithItems("News", "A", "B", "C"))));

        ui.PressEnterOnFeed(0);
        ui.PumpUntil(() => ui.Headlines.Items.Count == 3, "the feed to load");

        var status = (TextBlock)ui.Window.FindName("StatusText")!;
        Assert.Equal("Loaded 3 headlines from News", status.Text);

        // The summary holds only until the reader moves. Suppressing it for good would cost the
        // position announcement, which is the status bar's main job while browsing.
        ui.Headlines.SelectedIndex = 1;
        ui.Drain();

        Assert.Equal("News - 2 of 3", status.Text);
    }

    [WpfFact]
    public void Tabbing_away_and_back_returns_to_the_headline_you_were_on()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);

        ui.SetFeeds(Feed("News", server.Serve("news.xml",
            SampleFeed.WithItems("News", "First story", "Second story", "Third story"))));

        ui.PressEnterOnFeed(0);
        ui.PumpUntil(() => ui.Headlines.Items.Count == 3, "the feed to load");

        // Arrow down to the third headline, the way a reader browsing the list would.
        ui.Headlines.SelectedIndex = 2;
        ui.FocusItem(ui.Headlines, 2);
        Assert.Equal("Third story", SelectedTitle(ui));

        ui.Move(forward: true);      // out to Open in Browser
        ui.Move(forward: false);     // and back

        var focused = Assert.IsType<ListBoxItem>(ui.Focused);
        Assert.Equal("Third story", ((ArticleItem)focused.DataContext).Title);
    }

    [WpfFact]
    public void Loading_a_second_feed_starts_from_its_first_headline()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);

        ui.SetFeeds(
            Feed("News", server.Serve("news.xml", SampleFeed.WithItems("News", "N1", "N2", "N3", "N4"))),
            Feed("Sport", server.Serve("sport.xml", SampleFeed.WithItems("Sport", "S1", "S2"))));

        ui.PressEnterOnFeed(0);
        ui.PumpUntil(() => ui.Headlines.Items.Count == 4, "the first feed to load");

        // Move down the first feed, so a remembered index would be out of place in the second.
        ui.Headlines.SelectedIndex = 3;
        ui.FocusItem(ui.Headlines, 3);

        ui.PressEnterOnFeed(1);
        ui.PumpUntil(() => ui.Headlines.Items.Count == 2, "the second feed to load");

        // The remembered row belongs to the list that was thrown away. Landing on index 3 of the
        // old feed, or on nothing at all, is the failure this guards.
        var focused = Assert.IsType<ListBoxItem>(ui.Focused);
        Assert.Equal("S1", ((ArticleItem)focused.DataContext).Title);
    }

    /// <remarks>
    /// The folder path rather than a single feed, deliberately. A single feed that fails puts up a
    /// modal MessageBox, which a test cannot get past and which behaves differently on a machine
    /// with no interactive session — so driving it here would be slow locally and unpredictable on
    /// CI. The folder path reports into the status bar instead, which is the behaviour worth
    /// asserting anyway.
    /// </remarks>
    [WpfFact]
    public void A_folder_reports_the_feeds_that_failed_and_still_shows_the_ones_that_worked()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);

        var folder = new FeedItem { Title = "Mixed", IsCategory = true };
        folder.Children.Add(Feed("Good", server.Serve("good.xml", SampleFeed.WithItems("Good", "Worked"))));
        folder.Children.Add(Feed("Gone", server.Missing("gone.xml")));
        ui.SetFeeds(folder);

        ui.PressEnterOnFeed(0);
        ui.PumpUntil(() => ui.Headlines.Items.Count == 1, "the folder to load");

        var status = ((TextBlock)ui.Window.FindName("StatusText")!).Text;

        // The failure used to go to a console a windowed application does not have, leaving a
        // short list and no explanation.
        Assert.Contains("Gone", status, System.StringComparison.Ordinal);
        Assert.Contains("1 of 2", status, System.StringComparison.Ordinal);

        // And the headlines that did arrive are focused, not abandoned because of the one failure.
        var focused = Assert.IsType<ListBoxItem>(ui.Focused);
        Assert.Equal("Worked", ((ArticleItem)focused.DataContext).Title);
    }

    private static string SelectedTitle(FocusHarness ui) =>
        ((ArticleItem)ui.Headlines.SelectedItem).Title;
}
