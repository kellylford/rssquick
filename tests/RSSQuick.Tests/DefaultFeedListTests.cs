using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Threading;
using RSSReaderWPF;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// Make This My Default and Use Starter Feed List, in the real window: when each is greyed out,
/// what each writes, and where focus goes when the button holding it greys itself out.
/// </summary>
[Collection(WpfCollection.Name)]
public sealed class DefaultFeedListTests : IDisposable
{
    private const string Mine = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline text="Mine">
              <outline text="My feed" xmlUrl="https://example.com/mine.xml"/>
            </outline>
          </body>
        </opml>
        """;

    private static SavedFeedList Saved => SavedFeedList.ForThisUser;

    public DefaultFeedListTests() => Saved.Forget();

    public void Dispose() => Saved.Forget();

    private sealed class Window : IDisposable
    {
        public MainWindow Main { get; } = new();
        public TreeView Tree => (TreeView)Main.FindName("FeedTree")!;
        public Button MakeDefault => (Button)Main.FindName("MakeDefaultButton")!;
        public Button UseStarter => (Button)Main.FindName("UseStarterListButton")!;
        public string Status => ((MainViewModel)Main.DataContext).StatusMessage;

        public Window()
        {
            Main.Show();
            Drain();
        }

        public string FirstRootTitle => ((FeedItem)Tree.Items[0]!).Title;

        public object? Focused => FocusManager.GetFocusedElement(Main);

        public void Click(Button button)
        {
            button.Focus();
            button.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent, button));
            Drain();
        }

        public void Drain() => Main.Dispatcher.Invoke(() => { }, DispatcherPriority.SystemIdle);

        public void Dispose() => Main.Close();
    }

    [WpfFact]
    public void With_nothing_saved_both_buttons_are_greyed_out()
    {
        using var ui = new Window();

        Assert.NotEmpty(ui.Tree.Items);
        Assert.False(ui.MakeDefault.IsEnabled, "The starter list is already what opens at startup.");
        Assert.False(ui.UseStarter.IsEnabled, "There is no saved list to forget.");
    }

    [WpfFact]
    public void A_saved_list_opens_at_startup()
    {
        Saved.Save(Encoding.UTF8.GetBytes(Mine));

        using var ui = new Window();

        Assert.Equal("Mine", ui.FirstRootTitle);
        Assert.False(ui.MakeDefault.IsEnabled, "The saved list is already the default.");
        Assert.True(ui.UseStarter.IsEnabled);
    }

    [WpfFact]
    public void An_unreadable_saved_list_is_reported_and_can_be_replaced()
    {
        Saved.Save(Encoding.UTF8.GetBytes("not OPML"));

        using var ui = new Window();

        Assert.NotEmpty(ui.Tree.Items);
        Assert.Contains("could not be read", ui.Status);
        Assert.True(ui.MakeDefault.IsEnabled, "The starter list on screen is not what would open next time.");
    }

    [WpfFact]
    public void Make_this_my_default_saves_the_list_on_screen_and_greys_itself_out()
    {
        Saved.Save(Encoding.UTF8.GetBytes("not OPML"));
        using var ui = new Window();

        ui.Click(ui.MakeDefault);

        var starter = File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "RSS.opml"));
        Assert.Equal(starter, File.ReadAllBytes(Saved.Path));
        Assert.False(ui.MakeDefault.IsEnabled);
        Assert.Contains("Saved as your default feed list", ui.Status);
    }

    [WpfFact]
    public void Focus_moves_to_the_feed_tree_when_the_focused_button_greys_itself_out()
    {
        Saved.Save(Encoding.UTF8.GetBytes("not OPML"));
        using var ui = new Window();

        ui.Click(ui.MakeDefault);

        Assert.IsType<TreeViewItem>(ui.Focused);
    }

    [WpfFact]
    public void Use_starter_feed_list_forgets_the_saved_list_and_shows_the_starter()
    {
        Saved.Save(Encoding.UTF8.GetBytes(Mine));
        using var ui = new Window();

        ui.Click(ui.UseStarter);

        Assert.False(Saved.Exists);
        Assert.NotEqual("Mine", ui.FirstRootTitle);
        Assert.False(ui.UseStarter.IsEnabled);
        Assert.False(ui.MakeDefault.IsEnabled, "The starter list is now what opens at startup.");
        Assert.IsType<TreeViewItem>(ui.Focused);
        Assert.Contains("Showing the starter feed list", ui.Status);
    }

    [WpfFact]
    public void Alt_D_says_why_when_there_is_nothing_to_save()
    {
        using var ui = new Window();

        var binding = ui.Main.InputBindings.OfType<KeyBinding>()
            .Single(b => b.Key == Key.D && b.Modifiers == ModifierKeys.Alt);
        binding.Command.Execute(null);

        Assert.Equal("This feed list is already your default", ui.Status);
        Assert.False(Saved.Exists);
    }
}
