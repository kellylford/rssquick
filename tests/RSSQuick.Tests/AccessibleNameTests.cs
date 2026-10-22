using System.Linq;
using System.Windows;
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
/// the way a screen reader reaches them: as the children of the tree's or list's own automation
/// peer, which are wrappers around the data items rather than the containers themselves.
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

        var top = ChildrenOf(ui.FeedTree);
        Assert.Equal(new[] { "Technology", "BBC News" }, top.Select(p => p.GetName()));

        var container = (TreeViewItem)ui.FeedTree.ItemContainerGenerator.ContainerFromIndex(0);
        container.IsExpanded = true;
        ui.Window.UpdateLayout();
        ui.Drain();
        Assert.Equal("Ars Technica", ChildrenOf(ui.FeedTree)[0].GetChildren()
            .Single(p => p.GetAutomationControlType() == AutomationControlType.TreeItem).GetName());
    }

    [WpfFact]
    public void Headlines_are_named_by_their_title()
    {
        using var ui = new FocusHarness();
        Assert.Equal(new[] { "Headline one", "Headline two" },
            ChildrenOf(ui.Headlines).Select(p => p.GetName()));
    }

    [Fact]
    public void Items_without_a_container_fall_back_to_their_title_not_the_class_name()
    {
        // A row scrolled out of a virtualized list has no container, and WPF then names it by
        // the item's ToString.
        Assert.Equal("BBC News", new FeedItem { Title = "BBC News" }.ToString());
        Assert.Equal("Storm warning", new ArticleItem { Title = "Storm warning" }.ToString());
    }

    private static AutomationPeer[] ChildrenOf(UIElement control) =>
        UIElementAutomationPeer.CreatePeerForElement(control).GetChildren()
            .Where(p => p.GetAutomationControlType() is AutomationControlType.TreeItem
                                                     or AutomationControlType.ListItem)
            .ToArray();
}
