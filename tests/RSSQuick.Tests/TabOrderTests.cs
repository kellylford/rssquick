using System.Linq;
using System.Windows.Controls;

namespace RSSQuick.Tests;

/// <summary>
/// The window's tab ring, measured by walking focus rather than by reading the XAML.
///
/// <para>Tab order is the whole of how a screen reader user moves between the two panels, so it is
/// worth asserting directly. Every test here was checked to fail against the pre-fix window, where
/// the TreeView and the ListBox were each <c>IsTabStop="True"</c> and so were tab stops in their
/// own right, on top of the item inside them.</para>
/// </summary>
public class TabOrderTests
{
    // ── the reported bug ──────────────────────────────────────────────────────

    [WpfFact]
    public void ShiftTab_from_a_headline_leaves_the_headlines_list()
    {
        using var ui = new FocusHarness();
        ui.FocusItem(ui.Headlines, 0);
        ui.ClearLog();

        ui.Move(forward: false);

        Assert.False(
            FocusHarness.IsWithin(ui.Headlines, ui.Focused),
            $"Shift+Tab from a headline stayed inside the headlines list, on " +
            $"{FocusHarness.Describe(ui.Focused)}. Focus was handed to: " +
            $"{string.Join(" -> ", ui.FocusLog.Select(FocusHarness.Describe))}");

        Assert.True(
            FocusHarness.IsWithin(ui.FeedTree, ui.Focused),
            $"Shift+Tab from a headline should reach the feed tree, but landed on " +
            $"{FocusHarness.Describe(ui.Focused)}.");
    }

    [WpfFact]
    public void ShiftTab_from_the_feed_tree_reaches_the_import_button()
    {
        using var ui = new FocusHarness();
        ui.FocusItem(ui.FeedTree, 0);
        ui.ClearLog();

        ui.Move(forward: false);

        Assert.Same(ui.ImportButton, ui.Focused);
    }

    // ── the cause: a tab stop on the container as well as on the item ─────────

    [WpfFact]
    public void Neither_panel_container_is_a_tab_stop()
    {
        using var ui = new FocusHarness();

        Assert.False(ui.FeedTree.IsTabStop, "The feed tree container is its own tab stop.");
        Assert.False(ui.Headlines.IsTabStop, "The headlines list container is its own tab stop.");
    }

    [WpfFact]
    public void Tab_into_a_panel_lands_on_an_item_not_on_the_container()
    {
        using var ui = new FocusHarness();
        ui.ImportButton.Focus();
        ui.Drain();

        ui.Move(forward: true);
        Assert.IsType<TreeViewItem>(ui.Focused);

        ui.Move(forward: true);
        Assert.IsType<ListBoxItem>(ui.Focused);
    }

    // ── the ring as a whole ──────────────────────────────────────────────────

    [WpfFact]
    public void The_tab_ring_is_four_stops_and_wraps()
    {
        using var ui = new FocusHarness();
        ui.ImportButton.Focus();
        ui.Drain();

        var stops = ui.WalkRing(forward: true);

        Assert.Equal(
            new[] { "feed \"Feed one\"", "headline \"Headline one\"", "button \"Open in _Browser (Alt+B)\"" },
            stops);
    }

    [WpfFact]
    public void The_ring_walks_the_same_stops_backwards()
    {
        using var ui = new FocusHarness();
        ui.ImportButton.Focus();
        ui.Drain();

        var stops = ui.WalkRing(forward: false);

        Assert.Equal(
            new[] { "button \"Open in _Browser (Alt+B)\"", "headline \"Headline one\"", "feed \"Feed one\"" },
            stops);
    }
}
