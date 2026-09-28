using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using RSSReaderWPF;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// Things the Mac version already did that Windows now does too: moving around the tree,
/// type-ahead, the panel and text size keys, and saying something when a key has nothing to do.
/// Each is described in macos/README.md or asserted in the Mac's own UI tests.
/// </summary>
[Collection(WpfCollection.Name)]
public class ParityTests
{
    private static FeedItem Feed(string title, string url = "https://example.com/feed.xml") =>
        new() { Title = title, Url = url };

    private static FeedItem Folder(string title, params FeedItem[] feeds)
    {
        var folder = new FeedItem { Title = title, IsCategory = true };
        foreach (var feed in feeds) folder.Children.Add(feed);
        return folder;
    }

    private static string Status(FocusHarness ui) => ((TextBlock)ui.Window.FindName("StatusText")!).Text;

    /// <summary>
    /// A realised row, once the window's deferred startup work and any expansion have settled.
    /// </summary>
    /// <remarks>
    /// Drained first: the window places its startup focus at ApplicationIdle, and a test that
    /// acts before that has run can have it land in the middle of the assertions - which is how
    /// these tests failed intermittently in a full run but never alone.
    /// </remarks>
    private static TreeViewItem Node(FocusHarness ui, ItemsControl parent, int index)
    {
        ui.Drain();
        parent.UpdateLayout();
        return (TreeViewItem)parent.ItemContainerGenerator.ContainerFromIndex(index)!;
    }

    private static void Press(FocusHarness ui, UIElement target, Key key)
    {
        target.RaiseEvent(new KeyEventArgs(Keyboard.PrimaryDevice, PresentationSource.FromVisual(ui.Window)!, 0, key)
        {
            RoutedEvent = Keyboard.PreviewKeyDownEvent,
        });
        ui.Drain();
    }

    private static void Type(FocusHarness ui, UIElement target, string text)
    {
        target.RaiseEvent(new TextCompositionEventArgs(Keyboard.PrimaryDevice, new TextComposition(InputManager.Current, target, text))
        {
            RoutedEvent = TextCompositionManager.PreviewTextInputEvent,
        });
        ui.Drain();
    }

    /// <summary>Runs the window's key binding for <paramref name="key"/>, as pressing it would.</summary>
    private static void Binding(FocusHarness ui, Key key, ModifierKeys modifiers = ModifierKeys.None)
    {
        ui.Window.InputBindings.OfType<KeyBinding>()
            .First(b => b.Key == key && b.Modifiers == modifiers)
            .Command.Execute(null);
        ui.Drain();
    }

    private static void Select(FocusHarness ui, TreeViewItem node)
    {
        node.IsSelected = true;
        node.Focus();
        ui.Drain();
    }

    // ── the tree ────────────────────────────────────────────────────────────

    /// <summary>
    /// WPF's TreeView only opens and closes folders with Left and Right; Left on a feed did
    /// nothing, so getting back to its folder meant arrowing up past every feed above it.
    /// </summary>
    [WpfFact]
    public void Left_on_a_feed_moves_to_its_folder()
    {
        using var ui = new FocusHarness(populate: false);
        ui.SetFeeds(Folder("News", Feed("One"), Feed("Two")));
        var folder = Node(ui, ui.FeedTree, 0);
        folder.IsExpanded = true;
        var two = Node(ui, folder, 1);
        Select(ui, two);

        Press(ui, two, Key.Left);

        Assert.Equal("News", ((FeedItem)ui.FeedTree.SelectedItem).Title);
        ui.PumpUntil(() => ReferenceEquals(ui.Focused, folder), "focus to reach the folder");
    }

    [WpfFact]
    public void Left_on_an_open_folder_closes_it_and_stays()
    {
        using var ui = new FocusHarness(populate: false);
        ui.SetFeeds(Folder("News", Feed("One")));
        var folder = Node(ui, ui.FeedTree, 0);
        folder.IsExpanded = true;
        Select(ui, folder);

        Press(ui, folder, Key.Left);

        Assert.False(folder.IsExpanded);
        Assert.Equal("News", ((FeedItem)ui.FeedTree.SelectedItem).Title);
    }

    [WpfFact]
    public void Right_opens_a_folder_then_moves_to_its_first_feed()
    {
        using var ui = new FocusHarness(populate: false);
        ui.SetFeeds(Folder("News", Feed("One"), Feed("Two")));
        var folder = Node(ui, ui.FeedTree, 0);
        Select(ui, folder);

        Press(ui, folder, Key.Right);
        Assert.True(folder.IsExpanded);
        Assert.Equal("News", ((FeedItem)ui.FeedTree.SelectedItem).Title);

        Press(ui, folder, Key.Right);
        Assert.Equal("One", ((FeedItem)ui.FeedTree.SelectedItem).Title);
    }

    [WpfFact]
    public void Typing_the_start_of_a_name_moves_to_it()
    {
        using var ui = new FocusHarness(populate: false);
        ui.SetFeeds(Feed("Ars Technica"), Feed("BBC News"), Feed("BBC Sport"), Feed("Wired"));
        var first = Node(ui, ui.FeedTree, 0);
        Select(ui, first);

        Type(ui, first, "w");
        Assert.Equal("Wired", ((FeedItem)ui.FeedTree.SelectedItem).Title);

        // After a pause a new search starts; letters typed together build a longer name, so
        // "bbc s" passes BBC News for BBC Sport.
        System.Threading.Thread.Sleep(1100);
        Type(ui, (UIElement)ui.Focused!, "b");
        Type(ui, (UIElement)ui.Focused!, "b");
        Type(ui, (UIElement)ui.Focused!, "c");
        Type(ui, (UIElement)ui.Focused!, " ");
        Type(ui, (UIElement)ui.Focused!, "s");
        Assert.Equal("BBC Sport", ((FeedItem)ui.FeedTree.SelectedItem).Title);
    }

    [WpfFact]
    public void The_headlines_list_searches_by_title() =>
        Assert.Equal("Title", TextSearch.GetTextPath(new FocusHarness(populate: false).Headlines));

    // ── keys that used to do nothing ────────────────────────────────────────

    [WpfFact]
    public void Ctrl_1_and_Ctrl_2_go_straight_to_each_panel()
    {
        using var ui = new FocusHarness();
        ui.ImportButton.Focus();
        ui.Drain();

        Binding(ui, Key.D2, ModifierKeys.Control);
        Assert.True(FocusHarness.IsWithin(ui.Headlines, ui.Focused));

        Binding(ui, Key.D1, ModifierKeys.Control);
        Assert.True(FocusHarness.IsWithin(ui.FeedTree, ui.Focused));
    }

    [WpfFact]
    public void Switching_to_an_empty_headlines_list_says_so_and_nothing_else()
    {
        using var ui = new FocusHarness(populate: false);
        ui.SetFeeds(Feed("One"));
        Select(ui, Node(ui, ui.FeedTree, 0));

        Binding(ui, Key.F6);

        Assert.Equal("Headlines list is empty - press Enter on a feed to load it", Status(ui));
    }

    [WpfFact]
    public void Open_in_browser_with_nothing_selected_says_so()
    {
        using var ui = new FocusHarness(populate: false);

        Binding(ui, Key.B, ModifierKeys.Alt);

        Assert.Equal("Select a headline first", Status(ui));
    }

    [WpfFact]
    public void Text_size_steps_up_and_back_and_says_where_it_is()
    {
        using var ui = new FocusHarness(populate: false);
        var standard = ui.Window.FontSize;

        Binding(ui, Key.OemPlus, ModifierKeys.Control);
        Assert.Equal("Text size 125 percent", Status(ui));
        Assert.Equal(standard * 1.25, ui.Window.FontSize, precision: 3);

        Binding(ui, Key.D0, ModifierKeys.Control);
        Assert.Equal("Text size 100 percent", Status(ui));
        Assert.Equal(standard, ui.Window.FontSize, precision: 3);
    }

    [Fact]
    public void Text_size_steps_are_the_mac_s()
    {
        Assert.Equal(1.25, TextScale.Larger(1.0));
        Assert.Equal(4.0, TextScale.Larger(4.0));
        Assert.Equal(1.0, TextScale.Smaller(1.25));
        Assert.Equal(1.0, TextScale.Smaller(1.0));
    }

    [Fact]
    public void The_shortcuts_list_names_every_new_key_and_the_version()
    {
        var text = MainWindow.KeyboardShortcuts("9.8.7");

        foreach (var key in new[] { "Ctrl+1", "Ctrl+O", "Ctrl+Plus", "Alt+U", "Escape", "F5" })
            Assert.Contains(key, text, StringComparison.Ordinal);
        Assert.Contains("RSS Quick 9.8.7", text, StringComparison.Ordinal);
    }

    [WpfFact]
    public void The_window_is_called_rss_quick_with_a_space()
    {
        using var ui = new FocusHarness(populate: false);
        Assert.Equal("RSS Quick", ui.Window.Title);
    }

    // ── loads ───────────────────────────────────────────────────────────────

    /// <summary>
    /// Escape after a load had finished used to replace its summary with "Loading cancelled",
    /// for a load that was not running. The Mac had the same bug.
    /// </summary>
    [WpfFact]
    public void Escape_after_a_load_has_finished_leaves_its_summary_alone()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);
        ui.SetFeeds(Feed("News", server.Serve("news.xml", SampleFeed.WithItems("News", "A", "B")).ToString()));
        ui.PressEnterOnFeed(0);
        ui.PumpUntil(() => ui.Headlines.Items.Count == 2, "the feed to load");

        Binding(ui, Key.Escape);

        Assert.Equal("Loaded 2 headlines from News", Status(ui));
    }

    /// <summary>The words the Mac uses, rather than the enum name run together.</summary>
    [WpfFact]
    public void A_folder_names_a_server_error_in_words()
    {
        using var server = new LocalFeedServer();
        using var ui = new FocusHarness(populate: false);
        ui.SetFeeds(Folder("Mixed",
            Feed("Good", server.Serve("good.xml", SampleFeed.WithItems("Good", "Worked")).ToString()),
            Feed("Gone", server.Missing("gone.xml").ToString())));

        ui.PressEnterOnFeed(0);
        ui.PumpUntil(() => ui.Headlines.Items.Count == 1, "the folder to load");

        Assert.Contains("Gone server said 404 not found", Status(ui), StringComparison.Ordinal);
    }
}
