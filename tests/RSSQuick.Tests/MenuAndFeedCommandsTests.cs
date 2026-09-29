using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows.Controls;
using System.Windows.Input;
using RSSReaderWPF;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// The menu bar, and the commands that came with it - search, subscribe, remove, export - in the
/// real window against feeds served on loopback. Each command's dialog is modal and cannot be
/// driven here, so these call what the dialog hands its answer to.
/// </summary>
[Collection(WpfCollection.Name)]
public sealed class MenuAndFeedCommandsTests : IDisposable
{
    public MenuAndFeedCommandsTests() => SavedFeedList.ForThisUser.Forget();

    public void Dispose() => SavedFeedList.ForThisUser.Forget();

    private static string Status(FocusHarness ui) => ((TextBlock)ui.Window.FindName("StatusText")!).Text;

    private static string FeedList(params (string Folder, string Title, Uri Url)[] feeds)
    {
        var body = new StringBuilder();
        foreach (var group in feeds.GroupBy(f => f.Folder))
        {
            body.Append(CultureInfo.InvariantCulture, $"<outline text=\"{group.Key}\">");
            foreach (var (_, title, url) in group) body.Append(CultureInfo.InvariantCulture, $"<outline text=\"{title}\" xmlUrl=\"{url}\"/>");
            body.Append("</outline>");
        }
        return $"<?xml version=\"1.0\"?><opml version=\"2.0\"><head><title>Test</title></head><body>{body}</body></opml>";
    }

    private static void Show(FocusHarness ui, string opml, bool isDefault = false)
    {
        ui.Window.ShowFeedList(OpenedFeedList.Parse(Encoding.UTF8.GetBytes(opml), isSaved: isDefault), isDefault);
        ui.Drain();
    }

    private static FeedItem Selected(FocusHarness ui) => (FeedItem)ui.FeedTree.SelectedItem;

    // ── the menu bar ────────────────────────────────────────────────────────

    [WpfFact]
    public void The_menus_are_the_mac_s_in_the_same_order()
    {
        using var ui = new FocusHarness(populate: false);
        var menu = (Menu)ui.Window.FindName("MainMenu")!;

        Assert.Equal(new[] { "_File", "_Edit", "_Article", "_View", "_Help" },
            menu.Items.OfType<MenuItem>().Select(m => (string)m.Header));
    }

    /// <summary>
    /// A menu item that shows a key must be telling the truth: the key has to do the same thing
    /// from anywhere in the window, which on Windows means an InputBinding.
    /// </summary>
    [WpfFact]
    public void Every_ctrl_key_a_menu_shows_is_bound_in_the_window()
    {
        using var ui = new FocusHarness(populate: false);
        var menu = (Menu)ui.Window.FindName("MainMenu")!;
        var converter = new KeyGestureConverter();

        var shown = menu.Items.OfType<MenuItem>()
            .SelectMany(m => m.Items.OfType<MenuItem>())
            .Select(i => i.InputGestureText.Split(' ').Last())
            .Where(g => g.StartsWith("Ctrl+", StringComparison.Ordinal) || g.StartsWith("Alt+", StringComparison.Ordinal) || g is "F1" or "F5" or "F6")
            .Where(g => g != "Alt+F4" && g != "Alt+U")
            .Select(g => g.Replace("Plus", "OemPlus").Replace("Minus", "OemMinus"))
            .Select(g => (KeyGesture)converter.ConvertFromInvariantString(g)!)
            .ToList();

        Assert.NotEmpty(shown);
        foreach (var gesture in shown)
        {
            Assert.True(ui.Window.InputBindings.OfType<KeyBinding>().Any(b => b.Key == gesture.Key && b.Modifiers == gesture.Modifiers),
                $"The menu shows {gesture.Modifiers}+{gesture.Key}, which does nothing.");
        }
    }

    [WpfFact]
    public void The_menu_bar_is_not_in_the_tab_ring()
    {
        using var ui = new FocusHarness();
        var menu = (Menu)ui.Window.FindName("MainMenu")!;
        ui.ImportButton.Focus();
        ui.Drain();

        for (var i = 0; i < 8; i++)
        {
            ui.Move(forward: true);
            Assert.False(FocusHarness.IsWithin(menu, ui.Focused), $"Tab reached the menu bar, on {FocusHarness.Describe(ui.Focused)}.");
        }
    }

    [Fact]
    public void The_shortcuts_list_names_the_new_keys()
    {
        var text = MainWindow.KeyboardShortcuts("1.0.0");

        foreach (var key in new[] { "/ or Ctrl+F", "Ctrl+N", "Ctrl+E", "Delete", "Alt or F10" })
            Assert.Contains(key, text, StringComparison.Ordinal);
    }

    // ── search ──────────────────────────────────────────────────────────────

    [WpfFact]
    public void Search_fetches_every_feed_and_shows_only_what_matches()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);
        Show(ui, FeedList(
            ("News", "One", server.Serve("one.xml", SampleFeed.WithItems("One", "Storm closes schools", "Election night"))),
            ("Sport", "Two", server.Serve("two.xml", SampleFeed.WithItems("Two", "Storm delays match", "Transfer news")))));

        _ = ui.Window.SearchAsync("storm");
        ui.PumpUntil(() => ui.Headlines.Items.Count == 2, "the search to finish");

        Assert.Equal(new[] { "Storm closes schools", "Storm delays match" },
            ui.Headlines.Items.OfType<ArticleItem>().Select(a => a.Title).OrderBy(t => t));
        Assert.Equal("Found 2 headlines matching storm in 2 feeds", Status(ui));
        Assert.True(FocusHarness.IsWithin(ui.Headlines, ui.Focused), "Focus should be on the first result.");
    }

    [WpfFact]
    public void A_search_with_no_results_says_so_and_names_what_failed()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);
        Show(ui, FeedList(
            ("News", "One", server.Serve("one.xml", SampleFeed.WithItems("One", "Election night"))),
            ("News", "Gone", server.Missing("gone.xml"))));

        _ = ui.Window.SearchAsync("storm");
        ui.PumpUntil(() => Status(ui).StartsWith("No headlines", StringComparison.Ordinal), "the search to finish");

        Assert.Equal("No headlines match storm in 1 of 2 feeds; 1 could not be loaded", Status(ui));
    }

    [WpfFact]
    public void F5_runs_the_search_again()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);
        Show(ui, FeedList(("News", "One", server.Serve("one.xml", SampleFeed.WithItems("One", "Storm")))));

        _ = ui.Window.SearchAsync("storm");
        ui.PumpUntil(() => ui.Headlines.Items.Count == 1, "the search to finish");
        ui.Window.InputBindings.OfType<KeyBinding>().First(b => b.Key == Key.F5).Command.Execute(null);
        ui.PumpUntil(() => server.RequestsFor("one.xml") == 2 && ui.Headlines.Items.Count == 1, "the search to run again");

        Assert.Equal("Found 1 headline matching storm in 1 feed", Status(ui));
    }

    // ── subscribing ─────────────────────────────────────────────────────────

    [WpfFact]
    public void Subscribing_adds_the_feed_saves_the_list_and_selects_the_new_feed()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);
        Show(ui, FeedList(("News", "One", server.Serve("one.xml", SampleFeed.WithItems("One", "A")))));
        var added = server.Serve("new.xml", SampleFeed.WithItems("Brand New", "B"));
        var news = OpmlEditor.Folders(ui.FeedTree.Items.OfType<FeedItem>()).First(f => f.Name == "News");

        _ = ui.Window.SubscribeAsync(added.ToString(), news);
        ui.PumpUntil(() => Status(ui).StartsWith("Subscribed", StringComparison.Ordinal), "the subscription to finish");

        Assert.Equal("Subscribed to Brand New in News. This feed list is now your default, so it opens every time RSS Quick starts.", Status(ui));
        Assert.Equal("Brand New", Selected(ui).Title);
        Assert.True(ui.Focused is TreeViewItem { DataContext: FeedItem { Title: "Brand New" } }, "Focus should be on the new feed.");

        var saved = OpenedFeedList.Parse(SavedFeedList.ForThisUser.Load()!, isSaved: true).Document;
        Assert.Equal(new[] { "One", "Brand New" }, saved.Roots[0].Children.Select(f => f.Title));
    }

    [WpfFact]
    public void Subscribing_to_a_feed_already_there_selects_it_and_changes_nothing()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);
        var one = server.Serve("one.xml", SampleFeed.WithItems("One", "A"));
        Show(ui, FeedList(("News", "One", one)));

        _ = ui.Window.SubscribeAsync(one.ToString(), null);
        ui.Drain();

        Assert.Equal("You already subscribe to One, in News", Status(ui));
        Assert.Equal("One", Selected(ui).Title);
        Assert.False(SavedFeedList.ForThisUser.Exists);
        Assert.Equal(0, server.RequestsFor("one.xml"));
    }

    [WpfFact]
    public void An_address_with_no_feed_says_why_and_changes_nothing()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);
        Show(ui, FeedList(("News", "One", server.Serve("one.xml", SampleFeed.WithItems("One", "A")))));
        var page = server.Serve("page.html", "<!DOCTYPE html><html><body>No feeds</body></html>", contentType: "text/html");

        _ = ui.Window.SubscribeAsync(page.ToString(), null);
        ui.PumpUntil(() => Status(ui).StartsWith("Could not", StringComparison.Ordinal), "the subscription to fail");

        Assert.Equal($"Could not subscribe: {page} has no feed RSS Quick can find", Status(ui));
        Assert.False(SavedFeedList.ForThisUser.Exists);
    }

    // ── removing ────────────────────────────────────────────────────────────

    [WpfFact]
    public void Removing_a_feed_saves_the_list_and_moves_to_the_next_feed()
    {
        using var ui = new FocusHarness(populate: false);
        Show(ui, FeedList(
            ("News", "One", new Uri("https://example.com/one.xml")),
            ("News", "Two", new Uri("https://example.com/two.xml")),
            ("News", "Three", new Uri("https://example.com/three.xml"))), isDefault: true);
        var two = ui.FeedTree.Items.OfType<FeedItem>().First().Children[1];

        ui.Window.RemoveFeed(two);
        ui.Drain();

        Assert.Equal("Removed Two.", Status(ui));
        Assert.Equal("Three", Selected(ui).Title);
        var saved = OpenedFeedList.Parse(SavedFeedList.ForThisUser.Load()!, isSaved: true).Document;
        Assert.Equal(new[] { "One", "Three" }, saved.Roots[0].Children.Select(f => f.Title));
    }

    [WpfFact]
    public void Removing_the_only_feed_in_a_folder_moves_to_the_folder()
    {
        using var ui = new FocusHarness(populate: false);
        Show(ui, FeedList(
            ("News", "One", new Uri("https://example.com/one.xml")),
            ("Sport", "Two", new Uri("https://example.com/two.xml"))), isDefault: true);
        var two = ui.FeedTree.Items.OfType<FeedItem>().Last().Children[0];

        ui.Window.RemoveFeed(two);
        ui.Drain();

        Assert.Equal("Sport", Selected(ui).Title);
    }

    // ── exporting ───────────────────────────────────────────────────────────

    [WpfFact]
    public void Export_writes_the_list_on_screen_including_a_new_subscription()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);
        Show(ui, FeedList(("News", "One", server.Serve("one.xml", SampleFeed.WithItems("One", "A")))));
        _ = ui.Window.SubscribeAsync(server.Serve("new.xml", SampleFeed.WithItems("Brand New", "B")).ToString(), null);
        ui.PumpUntil(() => Status(ui).StartsWith("Subscribed", StringComparison.Ordinal), "the subscription to finish");
        var path = Path.Join(TestStorage.Directory, "Exported.opml");

        ui.Window.ExportFeedList(path);

        Assert.Equal("Exported 2 feeds to Exported.opml", Status(ui));
        var exported = OpenedFeedList.Parse(File.ReadAllBytes(path), isSaved: false).Document;
        Assert.Equal(2, exported.FeedCount);
        Assert.Equal(SavedFeedList.ForThisUser.Load(), File.ReadAllBytes(path));
    }
}
