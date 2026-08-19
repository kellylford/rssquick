using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Diagnostics.CodeAnalysis;
using System.IO;
using System.Linq;
using System.Net;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Media3D;
using System.Windows.Navigation;
using System.Windows.Threading;
using System.Xml.Linq;
using Microsoft.Win32;
using RSSReaderWPF.Services;

namespace RSSReaderWPF
{
    /// <summary>
    /// Main Window ViewModel
    /// </summary>
    public class MainViewModel : INotifyPropertyChanged
    {
        private string _statusMessage = "Ready - Import an OPML file or select a feed from the default list";
        private ArticleItem? _selectedArticle;
        private FeedItem? _selectedFeed;

        public ObservableCollection<FeedItem> FeedCategories { get; } = new();
        public ObservableCollection<ArticleItem> Headlines { get; } = new();

        public string StatusMessage
        {
            get => _statusMessage;
            set { _statusMessage = value; OnPropertyChanged(); }
        }

        public ArticleItem? SelectedArticle
        {
            get => _selectedArticle;
            set { _selectedArticle = value; OnPropertyChanged(); }
        }

        public FeedItem? SelectedFeed
        {
            get => _selectedFeed;
            set { _selectedFeed = value; OnPropertyChanged(); }
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }

    /// <summary>
    /// Main Window Code-behind
    /// </summary>
    [SuppressMessage("Design", "CA1001:Types that own disposable fields should be disposable",
        Justification = "A Window's disposal point is OnClosed, which cancels and disposes the " +
                        "token source. Implementing IDisposable would add a method nothing calls.")]
    public partial class MainWindow : Window
    {
        private readonly MainViewModel _viewModel;
        private readonly Dictionary<string, Dictionary<string, FeedItem>> _feedCategories = new();
        private bool _isLoadingFeed; // Suppresses focus side effects while a load is in progress

        /// <summary>
        /// Cancels the load in flight.
        /// </summary>
        /// <remarks>
        /// Without this, pressing Enter on a second feed before the first returned left both
        /// completions appending to the same list: the headlines interleaved, and the status bar
        /// reported whichever finished last. Easy to hit with a slow feed, which is exactly when
        /// someone is most likely to give up and try a different one.
        /// </remarks>
        private CancellationTokenSource? _loadCancellation;
        private int _lastSelectedHeadlineIndex = -1; // Track last selected headline for focus retention
        private FeedItem? _currentlyLoadedFeed = null; // Track which feed is currently loaded

        public MainWindow()
        {
            InitializeComponent();
            // The only view model. MainWindow.xaml used to declare a second one in
            // <Window.DataContext>, which this line then replaced - so any binding evaluated
            // during InitializeComponent was reading a different object from the one every
            // handler below writes to.
            _viewModel = new MainViewModel();
            DataContext = _viewModel;

            // Set up simplified interface (WebBrowser removed)
            // ArticleContent.Navigated += ArticleContent_Navigated;

            // Load default OPML file
            LoadDefaultOpml();

            // Set up keyboard navigation
            SetupKeyboardNavigation();
        }

        private void SetupKeyboardNavigation()
        {
            // F5 for refresh
            var refreshBinding = new KeyBinding(new RelayCommand(RefreshCurrentFeed), Key.F5, ModifierKeys.None);
            InputBindings.Add(refreshBinding);

            // F6 for section cycling
            var cycleSectionBinding = new KeyBinding(new RelayCommand(CycleSections), Key.F6, ModifierKeys.None);
            InputBindings.Add(cycleSectionBinding);

            // Ctrl+Tab for section cycling
            var ctrlTabBinding = new KeyBinding(new RelayCommand(CycleSections), Key.Tab, ModifierKeys.Control);
            InputBindings.Add(ctrlTabBinding);

            // Alt+B for opening article in browser
            var openBrowserBinding = new KeyBinding(new RelayCommand(OpenInBrowserCommand), Key.B, ModifierKeys.Alt);
            InputBindings.Add(openBrowserBinding);

            // Escape stops a load. A folder of feeds can take a while even now that they are
            // fetched concurrently, and waiting with no way out is the thing being fixed.
            var cancelBinding = new KeyBinding(new RelayCommand(CancelLoad), Key.Escape, ModifierKeys.None);
            InputBindings.Add(cancelBinding);
        }

        private void LoadDefaultOpml()
        {
            // Set initial status message for simplified RSS reader
            _viewModel.StatusMessage = "Ready - Import OPML file or select a feed to begin";

            try
            {
                string? opmlPath = FindDefaultOpml();
                if (opmlPath != null)
                {
                    string content = File.ReadAllText(opmlPath);
                    ParseOpml(content);
                    _viewModel.StatusMessage = "Loaded default OPML file with feeds";

                    // Set focus to the first item in the tree after successful load
                    this.Dispatcher.BeginInvoke(new Action(() => {
                        if (_viewModel.FeedCategories.Count > 0)
                        {
                            FeedTree.Focus();

                            // Find and select the first item in the tree using TreeViewItem
                            var firstItem = _viewModel.FeedCategories.First();
                            var treeViewItem = GetTreeViewItemFromFeedItem(firstItem);
                            if (treeViewItem != null)
                            {
                                treeViewItem.IsSelected = true;
                                treeViewItem.Focus();
                            }

                            _viewModel.StatusMessage = "Focus set to feed tree - use arrow keys to navigate";
                        }
                    }), System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                }
                else
                {
                    _viewModel.StatusMessage = "Default RSS.opml file not found - use Import OPML File button";

                    // Set focus to Import button if no default file
                    this.Dispatcher.BeginInvoke(new Action(() => {
                        ImportOpmlButton.Focus();
                        _viewModel.StatusMessage = "No default feeds found - press Enter to import OPML file";
                    }), System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                }
            }
            catch (Exception ex)
            {
                _viewModel.StatusMessage = $"Error loading default OPML: {ex.Message}";

                // Focus Import button on error too
                this.Dispatcher.BeginInvoke(new Action(() => {
                    ImportOpmlButton.Focus();
                }), System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            }
        }

        /// <summary>
        /// Locates the feed list to open at startup, or null when there is none.
        /// </summary>
        /// <remarks>
        /// The working directory comes first, so "drop an rss.opml beside the program and launch it
        /// there" keeps working, and so a portable copy on a USB stick uses its own list. The
        /// install directory is the fallback: a Start Menu or desktop shortcut does not reliably
        /// set the working directory to the install folder, and without this the installed build
        /// opened with an empty feed tree even though RSS.opml sat right next to the executable.
        /// </remarks>
        private static string? FindDefaultOpml()
        {
            // Matched case-insensitively by the file system, so this covers RSS.opml and rss.opml.
            const string fileName = "RSS.opml";

            var candidates = new[]
            {
                Path.Combine(Directory.GetCurrentDirectory(), fileName),
                Path.Combine(AppContext.BaseDirectory, fileName),
            };

            return candidates.FirstOrDefault(File.Exists);
        }

        private void ParseOpml(string opmlContent)
        {
            try
            {
                var doc = XDocument.Parse(opmlContent);
                var body = doc.Descendants("body").FirstOrDefault();

                if (body == null)
                    throw new InvalidOperationException("Invalid OPML format - no body element found");

                _viewModel.FeedCategories.Clear();
                _feedCategories.Clear();

                ProcessOutlines(body.Elements("outline"), null);

                int totalFeeds = _feedCategories.Values.Sum(category => category.Count);
                _viewModel.StatusMessage = $"Loaded {totalFeeds} feeds from OPML file";

                // Set TreeView ItemsSource
                FeedTree.ItemsSource = _viewModel.FeedCategories;
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException($"OPML parsing error: {ex.Message}");
            }
        }

        private void ProcessOutlines(IEnumerable<XElement> outlines, FeedItem? parentItem)
        {
            foreach (var outline in outlines)
            {
                string text = outline.Attribute("text")?.Value ??
                             outline.Attribute("title")?.Value ??
                             "Unknown";

                string? xmlUrl = outline.Attribute("xmlUrl")?.Value;

                if (!string.IsNullOrEmpty(xmlUrl))
                {
                    // This is a feed
                    var feedItem = new FeedItem
                    {
                        Title = text,
                        Url = xmlUrl,
                        Category = parentItem?.Title ?? "Uncategorized",
                        IsCategory = false
                    };

                    if (parentItem != null)
                    {
                        parentItem.Children.Add(feedItem);
                    }
                    else
                    {
                        // Add to "Uncategorized" category
                        var uncategorized = _viewModel.FeedCategories.FirstOrDefault(c => c.Title == "Uncategorized");
                        if (uncategorized == null)
                        {
                            uncategorized = new FeedItem { Title = "Uncategorized", IsCategory = true };
                            _viewModel.FeedCategories.Add(uncategorized);
                        }
                        uncategorized.Children.Add(feedItem);
                    }

                    // Store in categories dictionary
                    string categoryName = parentItem?.Title ?? "Uncategorized";
                    if (!_feedCategories.ContainsKey(categoryName))
                        _feedCategories[categoryName] = new Dictionary<string, FeedItem>();

                    _feedCategories[categoryName][text] = feedItem;
                }
                else
                {
                    // This is a category
                    var categoryItem = new FeedItem
                    {
                        Title = text,
                        Category = text,
                        IsCategory = true
                    };

                    if (parentItem != null)
                    {
                        parentItem.Children.Add(categoryItem);
                    }
                    else
                    {
                        _viewModel.FeedCategories.Add(categoryItem);
                    }

                    // Process child outlines
                    ProcessOutlines(outline.Elements("outline"), categoryItem);
                }
            }
        }

        private void FeedTree_SelectedItemChanged(object sender, RoutedPropertyChangedEventArgs<object> e)
        {
            if (e.NewValue is FeedItem selectedFeed && !selectedFeed.IsCategory)
            {
                _viewModel.SelectedFeed = selectedFeed;
                // Don't update status message during navigation - let screen reader announce just the feed name
                // Don't automatically load feed - wait for user to press Enter
                // _ = LoadFeedAsync(selectedFeed); // Removed automatic loading
            }
            else if (e.NewValue is FeedItem selectedCategory && selectedCategory.IsCategory)
            {
                // Don't set status message for category selection during navigation
                // Only announce for categories when they're explicitly selected, not during Tab navigation
            }
        }

        private void FeedTree_KeyDown(object sender, KeyEventArgs e)
        {
            var selectedItem = FeedTree.SelectedItem as FeedItem;

            // Let WPF handle normal Tab navigation via TabIndex
            // Only handle Enter key for feed selection

            if (selectedItem == null) return;

            if (e.Key == Key.Enter)
            {
                if (selectedItem.IsCategory)
                {
                    // Load all feeds under this folder/category
                    _ = LoadAllFeedsInCategoryAsync(selectedItem);
                }
                else
                {
                    // Load individual feed
                    _ = LoadFeedAsync(selectedItem);
                }
                e.Handled = true;
            }
            else if (e.Key == Key.Right)
            {
                // Expand the selected item if it's a category
                if (selectedItem.IsCategory)
                {
                    var treeViewItem = GetTreeViewItemFromFeedItem(selectedItem);
                    if (treeViewItem != null)
                    {
                        treeViewItem.IsExpanded = true;
                    }
                }
                e.Handled = true;
            }
            else if (e.Key == Key.Left)
            {
                // Collapse the selected item if it's a category
                if (selectedItem.IsCategory)
                {
                    var treeViewItem = GetTreeViewItemFromFeedItem(selectedItem);
                    if (treeViewItem != null)
                    {
                        treeViewItem.IsExpanded = false;
                    }
                }
                e.Handled = true;
            }
        }

        private TreeViewItem? GetTreeViewItemFromFeedItem(FeedItem feedItem)
        {
            // Helper method to find the TreeViewItem for a given FeedItem
            return GetTreeViewItemRecursive(FeedTree, feedItem);
        }

        private TreeViewItem? GetTreeViewItemRecursive(ItemsControl container, FeedItem feedItem)
        {
            if (container == null) return null;

            for (int i = 0; i < container.Items.Count; i++)
            {
                var containerItem = container.ItemContainerGenerator.ContainerFromIndex(i) as TreeViewItem;
                if (containerItem?.DataContext == feedItem)
                {
                    return containerItem;
                }

                // Recursively search children
                if (containerItem != null)
                {
                    var childItem = GetTreeViewItemRecursive(containerItem, feedItem);
                    if (childItem != null)
                    {
                        return childItem;
                    }
                }
            }
            return null;
        }

        /// <summary>
        /// Begins a load, cancelling whatever was already running.
        /// </summary>
        /// <returns>The token for this load; results carrying a cancelled one must be discarded.</returns>
        private CancellationToken BeginLoad(FeedItem target)
        {
            _loadCancellation?.Cancel();
            _loadCancellation?.Dispose();
            _loadCancellation = new CancellationTokenSource();

            _isLoadingFeed = true;
            _currentlyLoadedFeed = target;
            _viewModel.Headlines.Clear();
            _lastSelectedHeadlineIndex = -1;
            OpenInBrowserButton.IsEnabled = false;

            return _loadCancellation.Token;
        }

        /// <summary>
        /// Stops any load still running when the window closes, so its continuation does not try
        /// to touch a window that has gone.
        /// </summary>
        protected override void OnClosed(EventArgs e)
        {
            _loadCancellation?.Cancel();
            _loadCancellation?.Dispose();
            _loadCancellation = null;
            base.OnClosed(e);
        }

        /// <summary>Escape: abandon the load in progress.</summary>
        private void CancelLoad()
        {
            if (_loadCancellation is not { IsCancellationRequested: false }) return;

            _loadCancellation.Cancel();
            _viewModel.StatusMessage = "Loading cancelled";
        }

        /// <summary>Puts articles on screen and hands focus to the first of them.</summary>
        private void ShowArticles(IReadOnlyList<ArticleItem> articles, string status)
        {
            foreach (var article in articles) _viewModel.Headlines.Add(article);

            _viewModel.StatusMessage = status;

            // Cleared before focusing, so the selection this makes is allowed to reach the status
            // bar rather than being suppressed as part of the load.
            _isLoadingFeed = false;

            if (articles.Count > 0) FocusSelectedHeadline();
        }

        /// <summary>
        /// Loads every feed under a folder and merges the headlines.
        /// </summary>
        private async Task LoadAllFeedsInCategoryAsync(FeedItem categoryItem)
        {
            var token = BeginLoad(categoryItem);
            var feeds = GetAllFeedsRecursive(categoryItem);

            if (feeds.Count == 0)
            {
                _isLoadingFeed = false;
                _viewModel.StatusMessage = $"{categoryItem.Title} has no feeds in it";
                return;
            }

            _viewModel.StatusMessage = $"Loading {feeds.Count} feeds in {categoryItem.Title}...";

            // Marshalled back to the UI thread by the progress object, which captures the
            // synchronization context where it is constructed - here.
            var progress = new Progress<int>(done =>
            {
                if (!token.IsCancellationRequested)
                    _viewModel.StatusMessage = $"Loading {categoryItem.Title} - {done} of {feeds.Count} feeds...";
            });

            try
            {
                var result = await FeedLoader.LoadFolderAsync(feeds, progress, token);

                if (token.IsCancellationRequested) return;

                ShowArticles(result.Articles, DescribeFolderLoad(categoryItem, result));
            }
            // Filtered on our own token: an HttpClient timeout arrives as a TaskCanceledException
            // too, and swallowing that would report nothing at all for a feed that timed out.
            catch (OperationCanceledException) when (token.IsCancellationRequested)
            {
                // Escape, or a newer load superseding this one. Either way the status bar has
                // already been given something better to say.
                _isLoadingFeed = false;
            }
            catch (Exception ex)
            {
                if (token.IsCancellationRequested) return;

                _isLoadingFeed = false;
                _viewModel.StatusMessage = $"Could not load {categoryItem.Title}: {ex.Message}";
            }
        }

        /// <summary>
        /// One line covering how much of a folder arrived, and what did not.
        /// </summary>
        /// <remarks>
        /// Partial failure is reported here rather than in a message box. A folder of twenty feeds
        /// where one publisher is down is a normal morning, and it does not warrant a modal dialog
        /// standing between the reader and the nineteen that worked.
        /// </remarks>
        private static string DescribeFolderLoad(FeedItem category, FolderLoadResult result)
        {
            if (result.Failures.Count == 0)
                return $"Loaded {result.Articles.Count} headlines from {result.FeedsAttempted} feeds in {category.Title}";

            if (result.FeedsSucceeded == 0)
                return $"None of the {result.FeedsAttempted} feeds in {category.Title} could be loaded";

            // Name them while the list is short enough to be useful rather than a wall of text.
            var named = result.Failures.Count <= 3
                ? ": " + string.Join(", ", result.Failures.Select(f => $"{f.FeedTitle} {f.Reason}"))
                : string.Empty;

            return $"Loaded {result.Articles.Count} headlines from {result.FeedsSucceeded} of "
                 + $"{result.FeedsAttempted} feeds in {category.Title}; "
                 + $"{result.Failures.Count} failed{named}";
        }

        /// <summary>Every feed under a folder, at any depth.</summary>
        private static List<FeedItem> GetAllFeedsRecursive(FeedItem categoryItem)
        {
            var feeds = new List<FeedItem>();

            foreach (var child in categoryItem.Children)
            {
                if (child.IsCategory) feeds.AddRange(GetAllFeedsRecursive(child));
                else feeds.Add(child);
            }

            return feeds;
        }

        /// <summary>Loads a single feed's headlines.</summary>
        private async Task LoadFeedAsync(FeedItem feedItem)
        {
            var token = BeginLoad(feedItem);

            _viewModel.StatusMessage = $"Loading feed: {feedItem.Title}...";

            try
            {
                var articles = await FeedLoader.LoadFeedAsync(feedItem, token);

                if (token.IsCancellationRequested) return;

                ShowArticles(articles, articles.Count > 0
                    ? $"Loaded {articles.Count} headlines from {feedItem.Title}"
                    : $"{feedItem.Title} has no headlines right now");
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested)
            {
                _isLoadingFeed = false;
            }
            catch (Exception ex)
            {
                if (token.IsCancellationRequested) return;

                _isLoadingFeed = false;
                _viewModel.StatusMessage = $"Could not load {feedItem.Title}: {ex.Message}";

                // A modal box only where the user asked for one specific thing and got nothing.
                // The folder path deliberately does not do this; see DescribeFolderLoad.
                MessageBox.Show(
                    $"Could not load {feedItem.Title}.\n\n{ex.Message}",
                    "Feed Load Error", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }

        private void HeadlinesList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            // Don't process selection changes while loading feed to prevent unwanted focus changes
            if (_isLoadingFeed) return;

            // Track the selected index so focus can come back to it.
            if (sender is ListBox listBox)
            {
                _lastSelectedHeadlineIndex = listBox.SelectedIndex;
            }

            if (e.AddedItems.Count == 0)
            {
                // No selection - disable browser button
                OpenInBrowserButton.IsEnabled = false;
                return;
            }

            var selectedArticle = e.AddedItems[0] as ArticleItem;
            if (selectedArticle == null)
            {
                OpenInBrowserButton.IsEnabled = false;
                return;
            }

            _viewModel.SelectedArticle = selectedArticle;

            // Enable the Open in Browser button for the selected article
            OpenInBrowserButton.IsEnabled = !string.IsNullOrEmpty(selectedArticle.Link);

            // Position and source, which is what the status bar exists to tell a screen reader
            // user. The name comes from the article rather than from the tree selection: after a
            // folder load the list holds headlines from many feeds, and arrowing around the tree
            // does not change which feed the headlines came from.
            if (HeadlinesList.SelectedIndex >= 0)
            {
                var position = HeadlinesList.SelectedIndex + 1;
                var total = HeadlinesList.Items.Count;
                var source = string.IsNullOrWhiteSpace(selectedArticle.FeedTitle)
                    ? _currentlyLoadedFeed?.Title ?? "Headlines"
                    : selectedArticle.FeedTitle;

                _viewModel.StatusMessage = $"{source} - {position} of {total}";
            }
        }

        private void HeadlinesList_KeyDown(object sender, KeyEventArgs e)
        {
            // Always track the current selection when it changes
            if (e.Key == Key.Down || e.Key == Key.Up || e.Key == Key.PageDown || e.Key == Key.PageUp || e.Key == Key.Home || e.Key == Key.End)
            {
                // Let the default behavior handle navigation first, then track the new position
                Dispatcher.BeginInvoke(new Action(() =>
                {
                    if (HeadlinesList.SelectedIndex >= 0)
                    {
                        _lastSelectedHeadlineIndex = HeadlinesList.SelectedIndex;
                    }
                }), System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            }
            else if (HeadlinesList.SelectedIndex >= 0)
            {
                // Update the stored index for the current selection
                _lastSelectedHeadlineIndex = HeadlinesList.SelectedIndex;
            }

            if (e.Key == Key.Enter && _viewModel.SelectedArticle != null)
            {
                // Store the current selection index
                var listBox = sender as ListBox;
                if (listBox != null)
                {
                    _lastSelectedHeadlineIndex = listBox.SelectedIndex;
                }

                // When Enter is pressed, open article in browser (simplified behavior)
                OpenInBrowser_Click(sender, new RoutedEventArgs());
                e.Handled = true;
            }
        }

        /// <summary>
        /// Sends focus that landed on the bare list on to a headline.
        /// </summary>
        /// <remarks>
        /// Guarded on the original source. This used to run for every focus change that bubbled
        /// through the list, including focus arriving at a row, so each arrow-key step re-focused
        /// the row it had just left. Tab no longer reaches the container at all (IsTabStop is
        /// false); what still does is FocusHeadlinesList, CycleSections and the end of a feed
        /// load, all of which call HeadlinesList.Focus() directly.
        /// </remarks>
        private void HeadlinesList_GotFocus(object sender, RoutedEventArgs e)
        {
            if (!ReferenceEquals(e.OriginalSource, HeadlinesList)) return;

            if (FocusSelectedHeadline()) e.Handled = true;
        }

        /// <summary>
        /// Puts focus on the headline the user was last on, selecting it if nothing is selected.
        /// </summary>
        /// <returns>False when the list is empty, or the row has not been realised yet.</returns>
        private bool FocusSelectedHeadline()
        {
            if (HeadlinesList.Items.Count == 0) return false;

            var index = _lastSelectedHeadlineIndex >= 0 && _lastSelectedHeadlineIndex < HeadlinesList.Items.Count
                ? _lastSelectedHeadlineIndex
                : 0;

            HeadlinesList.SelectedIndex = index;
            _lastSelectedHeadlineIndex = index;

            // Rows are virtualised; without a layout pass the generator has nothing to hand back
            // when focus arrives before the list has been measured.
            HeadlinesList.ScrollIntoView(HeadlinesList.Items[index]);
            HeadlinesList.UpdateLayout();

            return HeadlinesList.ItemContainerGenerator.ContainerFromIndex(index) is ListBoxItem row
                && row.Focus();
        }

        private void HeadlinesList_Loaded(object sender, RoutedEventArgs e)
        {
            // When HeadlinesList finishes loading, focus the selected item if any
            if (HeadlinesList.Items.Count > 0 && HeadlinesList.SelectedIndex >= 0)
            {
                var selectedItem = HeadlinesList.ItemContainerGenerator.ContainerFromIndex(HeadlinesList.SelectedIndex) as ListBoxItem;
                if (selectedItem != null)
                {
                    selectedItem.Focus();
                }
            }
        }

        /// <summary>
        /// Clean title text to remove problematic whitespace that causes braille "blank" issues
        /// </summary>
        private static string CleanTitleText(string title)
        {
            if (string.IsNullOrEmpty(title))
                return "No Title";

            // Remove zero-width characters that can cause braille display issues first
            var cleaned = title.Replace("\u200B", "") // Zero-width space
                              .Replace("\u200C", "") // Zero-width non-joiner
                              .Replace("\u200D", "") // Zero-width joiner
                              .Replace("\uFEFF", "") // Byte order mark / zero-width no-break space
                              .Replace("\u00A0", " ") // Non-breaking space → regular space
                              .Replace("\u2009", " ") // Thin space → regular space
                              .Replace("\u202F", " ") // Narrow no-break space → regular space
                              .Replace("\u2060", ""); // Word joiner

            // Remove non-printable characters that might cause issues with screen readers
            cleaned = System.Text.RegularExpressions.Regex.Replace(cleaned, @"[\x00-\x1F\x7F-\x9F]", "");

            // More aggressive whitespace normalization
            // Replace any sequence of whitespace characters (including tabs, newlines, etc.) with single space
            cleaned = System.Text.RegularExpressions.Regex.Replace(cleaned, @"[\s\r\n\t]+", " ");

            // Final trim to remove leading/trailing whitespace
            cleaned = cleaned.Trim();

            return string.IsNullOrWhiteSpace(cleaned) ? "No Title" : cleaned;
        }

        /// <summary>
        /// Sends focus that landed on the bare tree on to a node, and reports where focus is.
        /// </summary>
        /// <remarks>See <see cref="HeadlinesList_GotFocus"/> for why the guard is needed.</remarks>
        private void FeedTree_GotFocus(object sender, RoutedEventArgs e)
        {
            if (!ReferenceEquals(e.OriginalSource, FeedTree)) return;

            if (FocusSelectedFeed()) e.Handled = true;

            _viewModel.StatusMessage = FeedTree.SelectedItem is FeedItem selectedFeed
                ? $"Feed Tree - {selectedFeed.Title} selected"
                : "Feed Tree - Select a feed and press Enter to load headlines";
        }

        /// <summary>
        /// Puts focus on the selected feed, or on the first one when nothing is selected.
        /// </summary>
        /// <returns>False when the tree is empty, or the node has not been realised yet.</returns>
        private bool FocusSelectedFeed()
        {
            if (FeedTree.Items.Count == 0) return false;

            FeedTree.UpdateLayout();

            if (FeedTree.SelectedItem is FeedItem selected
                && GetTreeViewItemFromFeedItem(selected) is TreeViewItem selectedNode)
            {
                return selectedNode.Focus();
            }

            if (FeedTree.ItemContainerGenerator.ContainerFromIndex(0) is not TreeViewItem first) return false;

            first.IsSelected = true;
            return first.Focus();
        }

        private void OpenInBrowserButton_KeyDown(object sender, KeyEventArgs e)
        {
            // No need to handle Tab keys - let WPF handle normal tab navigation
            // This will allow normal TabIndex flow: FeedTree -> HeadlinesList -> OpenInBrowserButton -> (cycle)
        }

        private void ImportOpml_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new OpenFileDialog
            {
                Title = "Import OPML File",
                Filter = "OPML Files (*.opml;*.xml)|*.opml;*.xml|All Files (*.*)|*.*",
                DefaultExt = "opml"
            };

            if (dialog.ShowDialog() == true)
            {
                try
                {
                    string content = File.ReadAllText(dialog.FileName);
                    ParseOpml(content);
                    _viewModel.StatusMessage = $"Successfully imported OPML file: {dialog.FileName}";
                }
                catch (Exception ex)
                {
                    MessageBox.Show($"Failed to import OPML file:\n{ex.Message}", "Import Error",
                                   MessageBoxButton.OK, MessageBoxImage.Error);
                    _viewModel.StatusMessage = $"Error importing OPML: {ex.Message}";
                }
            }
        }

        private void OpenInBrowser_Click(object sender, RoutedEventArgs e)
        {
            if (_viewModel.SelectedArticle != null && !string.IsNullOrEmpty(_viewModel.SelectedArticle.Link))
            {
                try
                {
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = _viewModel.SelectedArticle.Link,
                        UseShellExecute = true
                    });
                    _viewModel.StatusMessage = $"Opened article in browser: {_viewModel.SelectedArticle.Title}";
                }
                catch (Exception ex)
                {
                    MessageBox.Show($"Failed to open article in browser:\n{ex.Message}", "Browser Error",
                                   MessageBoxButton.OK, MessageBoxImage.Warning);
                    _viewModel.StatusMessage = $"Error opening browser: {ex.Message}";
                }
            }
        }

        /// <summary>
        /// F5: reload whatever is currently in the headlines list.
        /// </summary>
        /// <remarks>
        /// Keyed on the loaded feed, not the tree selection. Using the selection meant F5 loaded a
        /// different feed from the one on screen whenever the user had arrowed on past it, and did
        /// nothing whatsoever after a folder load, because a category failed the IsCategory guard.
        /// </remarks>
        private void RefreshCurrentFeed()
        {
            if (_currentlyLoadedFeed is not { } loaded)
            {
                _viewModel.StatusMessage = "Nothing to refresh yet - press Enter on a feed first";
                return;
            }

            if (loaded.IsCategory) _ = LoadAllFeedsInCategoryAsync(loaded);
            else _ = LoadFeedAsync(loaded);
        }

        private void OpenInBrowserCommand()
        {
            // Trigger the same action as the button click
            if (OpenInBrowserButton.IsEnabled)
            {
                OpenInBrowser_Click(OpenInBrowserButton, new RoutedEventArgs());
            }
        }

        private void FocusFeedTree()
        {
            if (!FocusSelectedFeed()) FeedTree.Focus();
            _viewModel.StatusMessage = "Focus on Feed Tree";
        }

        private void FocusHeadlinesList()
        {
            if (!FocusSelectedHeadline()) HeadlinesList.Focus();
            _viewModel.StatusMessage = "Focus on Headlines List";
        }

        /// <summary>
        /// F6 and Ctrl+Tab: move to the other panel.
        /// </summary>
        /// <remarks>
        /// Containment, not FeedTree.IsFocused, which is only true while the container itself holds
        /// focus. Focus normally sits on a row or a node, so both IsFocused checks read false and
        /// every press fell through to the same branch: F6 always went to the feed tree and never
        /// came back.
        /// </remarks>
        private void CycleSections()
        {
            if (IsWithin(FeedTree, Keyboard.FocusedElement as DependencyObject))
            {
                FocusHeadlinesList();
                _viewModel.StatusMessage = "Now in Headlines List section";
            }
            else
            {
                FocusFeedTree();
                _viewModel.StatusMessage = "Now in Feed Tree section";
            }
        }

        /// <summary>True when the element is the ancestor, or sits inside it.</summary>
        private static bool IsWithin(DependencyObject ancestor, DependencyObject? element)
        {
            for (var node = element; node is not null; node = Parent(node))
            {
                if (ReferenceEquals(node, ancestor)) return true;
            }
            return false;

            // Focus can rest on a content element that is not in the visual tree, so fall back to
            // the logical parent rather than stopping the walk there.
            static DependencyObject? Parent(DependencyObject node) =>
                node is Visual or Visual3D
                    ? VisualTreeHelper.GetParent(node) ?? LogicalTreeHelper.GetParent(node)
                    : LogicalTreeHelper.GetParent(node);
        }
    }

    /// <summary>
    /// Simple relay command implementation
    /// </summary>
    public class RelayCommand : ICommand
    {
        private readonly Action _execute;
        private readonly Func<bool>? _canExecute;

        public RelayCommand(Action execute, Func<bool>? canExecute = null)
        {
            _execute = execute ?? throw new ArgumentNullException(nameof(execute));
            _canExecute = canExecute;
        }

        public event EventHandler? CanExecuteChanged
        {
            add { CommandManager.RequerySuggested += value; }
            remove { CommandManager.RequerySuggested -= value; }
        }

        public bool CanExecute(object? parameter) => _canExecute?.Invoke() ?? true;
        public void Execute(object? parameter) => _execute();
    }
}
