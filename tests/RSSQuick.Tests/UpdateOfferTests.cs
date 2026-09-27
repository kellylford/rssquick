using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using RSSReaderWPF;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// What the window does when App finds a newer version: a button, one announcement, and nothing
/// that moves the reader.
/// </summary>
[Collection(WpfCollection.Name)]
public class UpdateOfferTests
{
    private static readonly UpdateOffer Downloaded =
        new("1.3.0", new Uri("https://github.com/kellylford/rssquick/releases/tag/v1.3.0"), ReadyToInstall: true);

    private static readonly UpdateOffer Available = Downloaded with { ReadyToInstall = false };

    private const string DownloadedNotice =
        "RSS Quick 1.3.0 has been downloaded and will be installed when you close RSS Quick. "
        + "Restart and Update installs it now";

    private static Button UpdateButton(FocusHarness ui) => (Button)ui.Window.FindName("UpdateButton")!;

    private static string Status(FocusHarness ui) => ((TextBlock)ui.Window.FindName("StatusText")!).Text;

    [WpfFact]
    public void There_is_no_update_button_until_there_is_an_update()
    {
        using var ui = new FocusHarness();

        Assert.Equal(Visibility.Collapsed, UpdateButton(ui).Visibility);
    }

    [WpfFact]
    public void A_downloaded_update_offers_to_restart()
    {
        using var ui = new FocusHarness();

        ui.Window.ShowUpdate(Downloaded, () => { });
        ui.Drain();

        Assert.Equal(Visibility.Visible, UpdateButton(ui).Visibility);
        Assert.Equal("Restart and _Update to 1.3.0", UpdateButton(ui).Content);
        Assert.Equal(DownloadedNotice, Status(ui));
    }

    [WpfFact]
    public void An_update_this_copy_cannot_install_offers_the_download_page()
    {
        using var ui = new FocusHarness();

        ui.Window.ShowUpdate(Available, () => Assert.Fail("A portable copy has nothing to restart into."));
        ui.Drain();

        Assert.Equal("Download _Update 1.3.0", UpdateButton(ui).Content);
        Assert.Equal("RSS Quick 1.3.0 is available. Download Update opens its page in your browser", Status(ui));
    }

    [WpfFact]
    public void Restart_and_update_installs_it()
    {
        using var ui = new FocusHarness();
        var installed = false;
        ui.Window.ShowUpdate(Downloaded, () => installed = true);
        ui.Drain();

        UpdateButton(ui).RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent, UpdateButton(ui)));

        Assert.True(installed);
    }

    /// <summary>
    /// If Velopack cannot install now, the reader is told, and told it is not lost - but not
    /// that it will install on close. A failed attempt is not retried at exit, in case it had
    /// already started the installer, so that would be a promise nothing keeps.
    /// </summary>
    [WpfFact]
    public void An_update_that_cannot_install_now_says_it_will_be_offered_again()
    {
        using var ui = new FocusHarness();
        ui.Window.ShowUpdate(Downloaded, () => throw new InvalidOperationException("Update.exe is missing"));
        ui.Drain();

        UpdateButton(ui).RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent, UpdateButton(ui)));

        Assert.Equal(
            "Could not install RSS Quick 1.3.0 now (Update.exe is missing). It will be offered again the next time RSS Quick starts",
            Status(ui));
    }

    // ── focus and the tab ring ──────────────────────────────────────────────

    [WpfFact]
    public void An_update_does_not_move_focus()
    {
        using var ui = new FocusHarness();
        ui.FocusItem(ui.Headlines, 0);
        var before = ui.Focused;

        ui.Window.ShowUpdate(Downloaded, () => { });
        ui.Drain();

        Assert.Same(before, ui.Focused);
    }

    [WpfFact]
    public void The_update_button_joins_the_ring_after_the_feed_list_buttons()
    {
        using var ui = new FocusHarness();
        ui.Window.ShowUpdate(Downloaded, () => { });
        ui.ImportButton.Focus();
        ui.Drain();

        var stops = ui.WalkRing(forward: true);

        Assert.Equal(
            new[]
            {
                "button \"Restart and _Update to 1.3.0\"",
                "feed \"Feed one\"", "headline \"Headline one\"", "button \"Open in _Browser (Alt+B)\"",
            },
            stops);
    }

    // ── the status bar ──────────────────────────────────────────────────────

    /// <summary>
    /// The check finishes a few seconds after startup, which is when a reader is most likely to
    /// be waiting on their first feed. Announced then, it would be overwritten by the load
    /// summary before it was heard — or overwrite "Loading..." and leave the reader unsure the
    /// load had started.
    /// </summary>
    [WpfFact]
    public void An_update_found_during_a_load_is_announced_after_the_load()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);
        ui.SetFeeds(new FeedItem
        {
            Title = "News",
            Url = server.Serve("news.xml", SampleFeed.WithItems("News", "A", "B"), delay: TimeSpan.FromMilliseconds(500)).ToString(),
        });

        ui.PressEnterOnFeed(0);
        ui.Window.ShowUpdate(Downloaded, () => { });
        ui.Drain();

        Assert.Equal("Loading feed: News...", Status(ui));

        ui.PumpUntil(() => ui.Headlines.Items.Count == 2, "the feed to load");

        Assert.Equal($"Loaded 2 headlines from News. {DownloadedNotice}", Status(ui));
    }

    /// <summary>
    /// Every way a load can end reads out the held notice, not only success. Otherwise a load
    /// the reader gave up on keeps it until some unrelated later load.
    /// </summary>
    [WpfFact]
    public void An_update_found_during_a_load_is_announced_when_the_load_is_cancelled()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);
        var url = server.Serve("slow.xml", SampleFeed.WithItems("Slow", "A"), delay: TimeSpan.FromSeconds(10));
        ui.SetFeeds(new FeedItem { Title = "Slow", Url = url.ToString() });

        ui.PressEnterOnFeed(0);
        ui.Window.ShowUpdate(Downloaded, () => { });
        var escape = ui.Window.InputBindings.OfType<System.Windows.Input.KeyBinding>()
            .Single(b => b.Key == System.Windows.Input.Key.Escape);
        escape.Command.Execute(null);
        ui.Drain();

        Assert.Equal($"Loading cancelled. {DownloadedNotice}", Status(ui));
    }

    /// <summary>
    /// A load that has just finished has something to say that nothing else will repeat, such as
    /// how many feeds failed. Word of an update that lands straight afterwards is added to it.
    /// </summary>
    [WpfFact]
    public void An_update_found_just_after_a_load_is_added_to_its_summary()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);
        ui.SetFeeds(new FeedItem { Title = "News", Url = server.Serve("news.xml", SampleFeed.WithItems("News", "A", "B")).ToString() });
        ui.PressEnterOnFeed(0);
        ui.PumpUntil(() => ui.Headlines.Items.Count == 2, "the feed to load");

        ui.Window.ShowUpdate(Downloaded, () => { });

        Assert.Equal($"Loaded 2 headlines from News. {DownloadedNotice}", Status(ui));
    }

    /// <summary>Once the reader has moved, the summary has been heard and the notice stands alone.</summary>
    [WpfFact]
    public void An_update_found_after_the_reader_has_moved_stands_alone()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);
        ui.SetFeeds(new FeedItem { Title = "News", Url = server.Serve("news.xml", SampleFeed.WithItems("News", "A", "B")).ToString() });
        ui.PressEnterOnFeed(0);
        ui.PumpUntil(() => ui.Headlines.Items.Count == 2, "the feed to load");
        ui.Headlines.SelectedIndex = 1;
        ui.Drain();

        ui.Window.ShowUpdate(Downloaded, () => { });

        Assert.Equal(DownloadedNotice, Status(ui));
    }

    [WpfFact]
    public void An_update_is_announced_once()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);
        var url = server.Serve("news.xml", SampleFeed.WithItems("News", "A", "B"), delay: TimeSpan.FromMilliseconds(300));
        ui.SetFeeds(new FeedItem { Title = "News", Url = url.ToString() });

        ui.PressEnterOnFeed(0);
        ui.Window.ShowUpdate(Downloaded, () => { });
        ui.PumpUntil(() => ui.Headlines.Items.Count == 2, "the first load");

        ui.PressEnterOnFeed(0);
        ui.PumpUntil(() => ui.Headlines.Items.Count == 2 && !Status(ui).StartsWith("Loading", StringComparison.Ordinal), "the second load");

        Assert.Equal("Loaded 2 headlines from News", Status(ui));
    }
}
