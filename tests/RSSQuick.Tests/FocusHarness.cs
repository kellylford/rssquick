using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Diagnostics;
using System.Threading;
using System.Windows.Media;
using System.Windows.Threading;
using RSSReaderWPF;

namespace RSSQuick.Tests;

/// <summary>
/// Builds a live <see cref="MainWindow"/> with both panels populated, and walks focus through it
/// the same way Tab and Shift+Tab do.
/// </summary>
/// <remarks>
/// Focus is read through <see cref="FocusManager"/> rather than <c>Keyboard.FocusedElement</c>.
/// Logical focus is what the window's own <c>GotFocus</c> handlers respond to, and unlike keyboard
/// focus it does not depend on the window being the foreground window — which it is not under a
/// test runner, and is not on a CI agent.
/// </remarks>
internal sealed class FocusHarness : IDisposable
{
    public MainWindow Window { get; }
    public TreeView FeedTree { get; }
    public ListBox Headlines { get; }
    public Button ImportButton { get; }
    public Button BrowserButton { get; }

    /// <summary>Every element focus has been handed to since the last <see cref="ClearLog"/>.</summary>
    public List<object> FocusLog { get; } = new();

    /// <param name="populate">
    /// False leaves the headlines list bound to the view model rather than overriding its
    /// ItemsSource, which a test that actually loads a feed needs — overriding it replaces the
    /// binding, so headlines added by a load would never appear.
    /// </param>
    public FocusHarness(bool populate = true)
    {
        Window = new MainWindow();
        Window.Show();

        // The constructor queues its initial tree focus at ApplicationIdle; let that finish before
        // replacing the contents underneath it.
        Drain();

        FeedTree      = (TreeView)Window.FindName("FeedTree")!;
        Headlines     = (ListBox)Window.FindName("HeadlinesList")!;
        ImportButton  = (Button)Window.FindName("ImportOpmlButton")!;
        BrowserButton = (Button)Window.FindName("OpenInBrowserButton")!;

        if (populate)
        {
            // Fixed contents, so the walk does not depend on the shipped RSS.opml or the network.
            FeedTree.ItemsSource = new[]
            {
                new FeedItem { Title = "Feed one" },
                new FeedItem { Title = "Feed two" },
            };
            Headlines.ItemsSource = new[]
            {
                new ArticleItem { Title = "Headline one" },
                new ArticleItem { Title = "Headline two" },
            };

            // Starts disabled, and a disabled control is not a tab stop. The tab order under test
            // is the one the user sees once a headline is selected, so enable it.
            BrowserButton.IsEnabled = true;
        }
        else
        {
            // The shipped RSS.opml is loaded by the constructor and points at real servers.
            // Replace it so nothing here reaches the network by accident.
            FeedTree.ItemsSource = Array.Empty<FeedItem>();
        }

        Window.UpdateLayout();
        Drain();
        Window.UpdateLayout();

        Window.AddHandler(
            UIElement.GotFocusEvent,
            new RoutedEventHandler((_, e) => FocusLog.Add(e.OriginalSource)),
            handledEventsToo: true);
    }

    /// <summary>Runs everything already queued on the dispatcher, including ApplicationIdle work.</summary>
    public void Drain() => Window.Dispatcher.Invoke(() => { }, DispatcherPriority.SystemIdle);

    public void ClearLog() => FocusLog.Clear();

    public IInputElement? Focused => FocusManager.GetFocusedElement(Window);

    /// <summary>Puts focus on a realised container inside an items control, the way arriving by Tab does.</summary>
    public void FocusItem(ItemsControl owner, int index)
    {
        owner.UpdateLayout();
        var container = owner.ItemContainerGenerator.ContainerFromIndex(index) as FrameworkElement
            ?? throw new InvalidOperationException(
                $"{Describe(owner)} has no realised container at index {index}.");
        container.Focus();
        Drain();
    }

    /// <summary>Puts feeds in the tree, the way a parsed OPML file does.</summary>
    public void SetFeeds(params FeedItem[] feeds)
    {
        FeedTree.ItemsSource = feeds;
        Window.UpdateLayout();
        Drain();
    }

    /// <summary>
    /// Presses Enter on a row, which is what loads a feed.
    /// </summary>
    /// <remarks>
    /// Raised as a real routed event rather than by calling the handler, so the wiring in the
    /// XAML is part of what is under test. Selecting first because the handler reads
    /// <c>FeedTree.SelectedItem</c>, exactly as it does when the user arrows onto a row.
    /// </remarks>
    public void PressEnterOnFeed(int index)
    {
        FeedTree.UpdateLayout();
        var node = (TreeViewItem)FeedTree.ItemContainerGenerator.ContainerFromIndex(index)!;
        node.IsSelected = true;
        node.Focus();
        Drain();

        node.RaiseEvent(new KeyEventArgs(
            Keyboard.PrimaryDevice,
            PresentationSource.FromVisual(Window)!,
            timestamp: 0,
            Key.Enter)
        {
            RoutedEvent = Keyboard.KeyDownEvent,
        });

        Drain();
    }

    /// <summary>
    /// Runs the dispatcher until <paramref name="condition"/> holds, or fails the test.
    /// </summary>
    /// <remarks>
    /// A feed load is started and not awaited, so its continuations arrive on the dispatcher some
    /// time later. Pumping is the only way for a single-threaded test to let them run.
    /// </remarks>
    public void PumpUntil(Func<bool> condition, string what, int timeoutSeconds = 15)
    {
        var deadline = Stopwatch.StartNew();
        while (deadline.Elapsed < TimeSpan.FromSeconds(timeoutSeconds))
        {
            if (condition()) return;
            Window.Dispatcher.Invoke(() => { }, DispatcherPriority.Background);
            Thread.Sleep(10);
        }

        Assert.Fail($"Timed out after {timeoutSeconds}s waiting for {what}.");
    }

    /// <summary>One Tab (<paramref name="forward"/>) or Shift+Tab press from wherever focus is now.</summary>
    public void Move(bool forward)
    {
        if (Focused is not FrameworkElement current)
            throw new InvalidOperationException("Nothing has focus, so there is nowhere to move from.");

        current.MoveFocus(new TraversalRequest(
            forward ? FocusNavigationDirection.Next : FocusNavigationDirection.Previous));
        Drain();
    }

    /// <summary>Presses Tab (or Shift+Tab) until focus returns to where it started, or gives up.</summary>
    public List<string> WalkRing(bool forward, int limit = 12)
    {
        var start = Focused;
        var stops = new List<string>();

        for (var i = 0; i < limit; i++)
        {
            Move(forward);
            if (ReferenceEquals(Focused, start)) break;
            stops.Add(Describe(Focused));
        }

        return stops;
    }

    /// <summary>True when <paramref name="element"/> is <paramref name="ancestor"/> or sits inside it.</summary>
    public static bool IsWithin(DependencyObject ancestor, object? element)
    {
        for (var node = element as DependencyObject; node is not null; node = VisualTreeHelperParent(node))
            if (ReferenceEquals(node, ancestor)) return true;
        return false;
    }

    private static DependencyObject? VisualTreeHelperParent(DependencyObject node) =>
        node is Visual or System.Windows.Media.Media3D.Visual3D
            ? VisualTreeHelper.GetParent(node)
            : LogicalTreeHelper.GetParent(node);

    /// <summary>A name a failure message can be read against.</summary>
    public static string Describe(object? element) => element switch
    {
        null => "(nothing)",
        ListBoxItem { DataContext: ArticleItem a } => $"headline \"{a.Title}\"",
        TreeViewItem { DataContext: FeedItem f } => $"feed \"{f.Title}\"",
        Button b => $"button \"{b.Content}\"",
        FrameworkElement { Name.Length: > 0 } fe => $"{fe.GetType().Name} {fe.Name} (the container itself)",
        var other => other.GetType().Name,
    };

    public void Dispose() => Window.Close();
}
