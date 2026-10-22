using System.Linq;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using RSSReaderWPF;

namespace RSSQuick.Tests;

/// <summary>
/// Every item a screen reader lands on reports the text the reader sees.
/// </summary>
/// <remarks>
/// The feed tree shipped in 1.4.0 with no name on its items, so UI Automation fell back to the
/// data object's ToString and NVDA read "RSSReaderWPF.FeedItem" for every feed and folder. The
/// tree tests only ever checked where focus went, never what it was called. Names are read here
/// through the automation peer, which is what a screen reader asks.
/// </remarks>
[Collection(WpfCollection.Name)]
public class AccessibleNameTests
{
    [WpfFact]
    public void Feed_tree_items_are_named_by_their_title()
    {
        using var ui = new FocusHarness();
        var folder = new FeedItem { Title = "Technology", IsCategory = true };
        folder.Children.Add(new FeedItem { Title = "Ars Technica" });
        ui.SetFeeds(folder, new FeedItem { Title = "BBC News" });

        var top = Enumerable.Range(0, 2)
            .Select(i => (TreeViewItem)ui.FeedTree.ItemContainerGenerator.ContainerFromIndex(i))
            .ToList();
        Assert.Equal(new[] { "Technology", "BBC News" }, top.Select(NameOf));

        top[0].IsExpanded = true;
        ui.Window.UpdateLayout();
        ui.Drain();
        var child = (TreeViewItem)top[0].ItemContainerGenerator.ContainerFromIndex(0);
        Assert.Equal("Ars Technica", NameOf(child));
    }

    [WpfFact]
    public void Headlines_are_named_by_their_title()
    {
        using var ui = new FocusHarness();
        var row = (ListBoxItem)ui.Headlines.ItemContainerGenerator.ContainerFromIndex(0);
        Assert.Equal("Headline one", NameOf(row));
    }

    private static string NameOf(System.Windows.UIElement element) =>
        UIElementAutomationPeer.CreatePeerForElement(element).GetName();
}
