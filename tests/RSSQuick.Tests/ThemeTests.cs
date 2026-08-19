using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using RSSReaderWPF;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// Colours and text size come from Windows, not from literals in the XAML.
/// </summary>
/// <remarks>
/// A hardcoded brush looks fine in the default theme and is the reason an app is unusable in a
/// Windows high contrast one — dark blue on black, or a fixed grey on black. Nothing about that
/// shows up in a screenshot taken on the developer's machine, so it is asserted here instead.
/// These tests fail against the pre-1.1.0 window, which hardcoded DarkBlue, Gray and LightGray.
/// </remarks>
[Collection(WpfCollection.Name)]
public class ThemeTests
{
    [WpfFact]
    public void The_window_applies_the_Windows_text_size_setting()
    {
        using var ui = new FocusHarness();

        // WPF already defaults the font size to SystemFonts.MessageFontSize, so the arithmetic
        // alone proves nothing on a machine with text scaling off. The value source is the part
        // that bites: it is Local only because the window sets it, and reverts to Default the
        // moment that line is removed. What the multiplier should be is covered by TextScaleTests.
        var source = DependencyPropertyHelper
            .GetValueSource(ui.Window, Control.FontSizeProperty)
            .BaseValueSource;

        Assert.True(source == BaseValueSource.Local,
            "The window is not setting its own font size, so the Windows text size setting is "
            + $"being ignored (source: {source}).");
        Assert.Equal(SystemFonts.MessageFontSize * TextScale.Current, ui.Window.FontSize);
    }

    [WpfFact]
    public void The_status_bar_uses_system_colours()
    {
        using var ui = new FocusHarness();
        var statusBar = (StatusBar)ui.Window.FindName("MainStatusBar")!;

        Assert.Equal(SystemColors.ControlBrush, statusBar.Background);
        Assert.Equal(SystemColors.ControlTextBrush, statusBar.Foreground);
    }

    [WpfFact]
    public void The_headline_date_uses_the_system_dimmed_text_colour()
    {
        using var ui = new FocusHarness();

        // Selected by its bound text rather than by position: a TreeViewItem or ListBoxItem
        // template contributes TextBlocks of its own, so "the first one" is not the row's.
        var date = TextBlockShowing(ui.Headlines, 0, "");

        // GrayText, not a literal grey: Windows keeps this legible in a high contrast theme,
        // where a fixed grey sits almost invisibly against black.
        Assert.Equal(SystemColors.GrayTextBrush, date.Foreground);
    }

    [WpfFact]
    public void The_headline_title_does_not_override_the_system_text_colour()
    {
        using var ui = new FocusHarness();

        var title = TextBlockShowing(ui.Headlines, 0, "Headline one");

        AssertForegroundIsInherited(title);
    }

    [WpfFact]
    public void Folders_are_distinguished_by_weight_rather_than_colour()
    {
        using var ui = new FocusHarness();

        var node = TextBlockShowing(ui.FeedTree, 0, "Feed one");

        // Colour says nothing to a screen reader, nothing to a colour-blind user, and the wrong
        // thing in high contrast. The tree structure already marks folders out.
        AssertForegroundIsInherited(node);
    }

    /// <summary>
    /// Asserts the element takes its foreground from the theme rather than setting its own.
    /// </summary>
    /// <remarks>
    /// The value source, not <c>ReadLocalValue</c>. Content inside a DataTemplate has its
    /// attribute values recorded as <c>ParentTemplate</c> rather than <c>Local</c>, so
    /// <c>ReadLocalValue</c> comes back unset whether or not the XAML hardcodes a brush — which is
    /// how the first version of this test passed against a literal Foreground="Black".
    /// </remarks>
    private static void AssertForegroundIsInherited(TextBlock element)
    {
        var source = DependencyPropertyHelper
            .GetValueSource(element, TextBlock.ForegroundProperty)
            .BaseValueSource;

        Assert.True(
            source is BaseValueSource.Inherited or BaseValueSource.Default,
            $"\"{element.Text}\" sets its own foreground ({source}), so it will not follow a high "
            + $"contrast theme. Leave it to inherit.");
    }

    /// <summary>
    /// The TextBlock in one row that is showing <paramref name="text"/>.
    /// </summary>
    /// <remarks>
    /// Matched on content because the container templates contribute TextBlocks of their own, so
    /// indexing into the visual tree finds chrome rather than the row's own text — which is how
    /// the first version of these tests passed against colours it was written to reject.
    /// </remarks>
    private static TextBlock TextBlockShowing(ItemsControl owner, int index, string text)
    {
        owner.UpdateLayout();
        var container = owner.ItemContainerGenerator.ContainerFromIndex(index) as DependencyObject;
        Assert.NotNull(container);

        var matches = Descendants(container!).OfType<TextBlock>().Where(t => t.Text == text).ToList();
        Assert.True(matches.Count == 1,
            $"Expected exactly one TextBlock showing \"{text}\", found {matches.Count}. " +
            $"Row contains: {string.Join(" | ", Descendants(container!).OfType<TextBlock>().Select(t => $"\"{t.Text}\""))}");

        return matches[0];
    }

    private static IEnumerable<DependencyObject> Descendants(DependencyObject node)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(node); i++)
        {
            var child = VisualTreeHelper.GetChild(node, i);
            yield return child;
            foreach (var grandchild in Descendants(child)) yield return grandchild;
        }
    }
}
