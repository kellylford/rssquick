using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Runtime.CompilerServices;
using System.ServiceModel.Syndication;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Navigation;
using System.Windows.Threading;
using System.Xml;
using System.Xml.Linq;
using Microsoft.Win32;

namespace RSSReaderWPF
{
    /// <summary>
    /// RSS Feed item for data binding
    /// </summary>
    public class FeedItem : INotifyPropertyChanged
    {
        private string _title = string.Empty;
        private string _url = string.Empty;
        private string _category = string.Empty;
        private bool _isCategory = false;

        public string Title
        {
            get => _title;
            set { _title = value; OnPropertyChanged(); }
        }

        public string Url
        {
            get => _url;
            set { _url = value; OnPropertyChanged(); }
        }

        public string Category
        {
            get => _category;
            set { _category = value; OnPropertyChanged(); }
        }

        public bool IsCategory
        {
            get => _isCategory;
            set { _isCategory = value; OnPropertyChanged(); }
        }

        public ObservableCollection<FeedItem> Children { get; } = new();

        public event PropertyChangedEventHandler? PropertyChanged;
        protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }

    /// <summary>
    /// RSS Article item for data binding
    /// </summary>
    public class ArticleItem : INotifyPropertyChanged
    {
        private string _title = string.Empty;
        private string _link = string.Empty;
        private string _summary = string.Empty;
        private string _content = string.Empty;
        private string _published = string.Empty;
        private string _author = string.Empty;
        private string _feedTitle = string.Empty;

        public string Title
        {
            get => _title;
            set { _title = value; OnPropertyChanged(); }
        }

        public string Link
        {
            get => _link;
            set { _link = value; OnPropertyChanged(); }
        }

        public string Summary
        {
            get => _summary;
            set { _summary = value; OnPropertyChanged(); }
        }

        public string Content
        {
            get => _content;
            set { _content = value; OnPropertyChanged(); }
        }

        public string Published
        {
            get => _published;
            set { _published = value; OnPropertyChanged(); }
        }

        public string Author
        {
            get => _author;
            set { _author = value; OnPropertyChanged(); }
        }

        public string FeedTitle
        {
            get => _feedTitle;
            set { _feedTitle = value; OnPropertyChanged(); }
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }

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
    public partial class MainWindow : Window
    {
        private readonly MainViewModel _viewModel;
        private readonly Dictionary<string, Dictionary<string, FeedItem>> _feedCategories = new();
        private bool _isLoadingFeed = false; // Flag to prevent unwanted focus changes during feed loading
        private int _lastSelectedHeadlineIndex = -1; // Track last selected headline for focus retention
        private FeedItem? _currentlyLoadedFeed = null; // Track which feed is currently loaded

        public MainWindow()
        {
            InitializeComponent();
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
        }

        private void LoadDefaultOpml()
        {
            // Set initial status message for simplified RSS reader
            _viewModel.StatusMessage = "Ready - Import OPML file or select a feed to begin";
            
            try
            {
                string opmlPath = "RSS.opml";
                if (File.Exists(opmlPath))
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

        private async Task LoadAllFeedsInCategoryAsync(FeedItem categoryItem)
        {
            try
            {
                _isLoadingFeed = true;
                _currentlyLoadedFeed = categoryItem; // Track the currently loaded category/folder

                // Update UI on main thread
                Dispatcher.Invoke(() =>
                {
                    _viewModel.StatusMessage = $"Loading all feeds in category: {categoryItem.Title}...";
                    _viewModel.Headlines.Clear();
                    OpenInBrowserButton.IsEnabled = false;
                    // ArticleContent.NavigateToString("<html><body style='font-family: Segoe UI; padding: 20px; color: #666;'><h3>Loading articles from all feeds...</h3></body></html>");
                });

                // Collect all feeds under this category (including nested categories)
                var allFeeds = GetAllFeedsRecursive(categoryItem);
                var allArticles = new List<ArticleItem>();

                foreach (var feed in allFeeds)
                {
                    try
                    {
                        // Update status for each feed
                        Dispatcher.Invoke(() =>
                        {
                            _viewModel.StatusMessage = $"Loading feed: {feed.Title}...";
                        });

                        // Load articles from this feed
                        var articles = await Task.Run(() =>
                        {
                            using var reader = XmlReader.Create(feed.Url);
                            var syndicationFeed = SyndicationFeed.Load(reader);

                            var feedArticles = new List<ArticleItem>();
                            foreach (var item in syndicationFeed.Items)
                            {
                                feedArticles.Add(new ArticleItem
                                {
                                    Title = CleanTitleText(item.Title?.Text ?? "No Title"),
                                    Content = item.Content?.ToString() ?? item.Summary?.Text ?? "No content available",
                                    Link = item.Links?.FirstOrDefault()?.Uri?.ToString() ?? "",
                                    Published = item.PublishDate.ToString("MMM dd, yyyy HH:mm"),
                                    FeedTitle = feed.Title // Track which feed this came from
                                });
                            }
                            return feedArticles;
                        });

                        allArticles.AddRange(articles);
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"Failed to load feed {feed.Title}: {ex.Message}");
                        // Continue with other feeds even if one fails
                    }
                }

                // Sort all articles by publication date (newest first)
                var sortedArticles = allArticles.OrderByDescending(a => 
                {
                    // Try to parse the date for proper sorting
                    if (DateTime.TryParse(a.Published, out DateTime date))
                        return date;
                    return DateTime.MinValue;
                }).ToList();

                // Update UI with all articles
                Dispatcher.Invoke(() =>
                {
                    foreach (var article in sortedArticles)
                    {
                        _viewModel.Headlines.Add(article);
                    }

                    _viewModel.StatusMessage = $"Loaded {allArticles.Count} articles from {allFeeds.Count} feeds in category: {categoryItem.Title}";
                    
                    // Focus headlines list after loading
                    HeadlinesList.Focus();
                    
                    _isLoadingFeed = false;
                });
            }
            catch (Exception ex)
            {
                Dispatcher.Invoke(() =>
                {
                    _viewModel.StatusMessage = $"Error loading category feeds: {ex.Message}";
                    MessageBox.Show($"Failed to load feeds in category:\n{ex.Message}", "Feed Load Error", 
                                   MessageBoxButton.OK, MessageBoxImage.Warning);
                    _isLoadingFeed = false;
                });
            }
        }

        private List<FeedItem> GetAllFeedsRecursive(FeedItem categoryItem)
        {
            var feeds = new List<FeedItem>();
            
            if (categoryItem.Children != null)
            {
                foreach (var child in categoryItem.Children)
                {
                    if (child.IsCategory)
                    {
                        // Recursively get feeds from subcategories
                        feeds.AddRange(GetAllFeedsRecursive(child));
                    }
                    else
                    {
                        // This is a feed, add it to the list
                        feeds.Add(child);
                    }
                }
            }
            
            return feeds;
        }

        private async Task LoadFeedAsync(FeedItem feedItem)
        {
            try
            {
                _isLoadingFeed = true; // Set flag to prevent unwanted focus changes
                _currentlyLoadedFeed = feedItem; // Track the currently loaded feed

                // Update UI on main thread
                Dispatcher.Invoke(() =>
                {
                    _viewModel.StatusMessage = $"Loading feed: {feedItem.Title}...";
                    _viewModel.Headlines.Clear();
                    // ArticleContent.NavigateToString("<html><body style='font-family: Segoe UI; padding: 20px; color: #666;'><h3>Select an article to view its content...</h3></body></html>");
                });

                // Load RSS feed on background thread
                var articles = await Task.Run(() =>
                {
                    using var reader = XmlReader.Create(feedItem.Url);
                    var feed = SyndicationFeed.Load(reader);

                    var articleList = new List<ArticleItem>();
                    foreach (var item in feed.Items)
                    {
                        var article = new ArticleItem
                        {
                            Title = CleanTitleText(item.Title?.Text ?? "No Title"),
                            Link = item.Links.FirstOrDefault()?.Uri?.ToString() ?? string.Empty,
                            Summary = item.Summary?.Text ?? string.Empty,
                            Content = item.Content?.ToString() ?? item.Summary?.Text ?? string.Empty,
                            Published = item.PublishDate.ToString("yyyy-MM-dd HH:mm"),
                            Author = item.Authors.FirstOrDefault()?.Name ?? string.Empty,
                            FeedTitle = feedItem.Title
                        };
                        articleList.Add(article);
                    }
                    return articleList;
                });

                // Update UI with results on main thread
                Dispatcher.Invoke(() =>
                {
                    foreach (var article in articles)
                    {
                        _viewModel.Headlines.Add(article);
                    }

                    _viewModel.StatusMessage = $"Loaded {articles.Count} articles from {feedItem.Title}";
                    
                    // Focus headlines list and select first item when feed loads
                    if (articles.Count > 0)
                    {
                        _isLoadingFeed = false; // Clear flag before setting selection to allow SelectionChanged to process
                        HeadlinesList.SelectedIndex = 0;
                        _lastSelectedHeadlineIndex = 0;
                        HeadlinesList.Focus();
                        
                        // Use a timer to ensure UI is fully rendered before focusing the item
                        var timer = new System.Windows.Threading.DispatcherTimer();
                        timer.Interval = TimeSpan.FromMilliseconds(100);
                        timer.Tick += (s, e) =>
                        {
                            timer.Stop();
                            var firstItem = HeadlinesList.ItemContainerGenerator.ContainerFromIndex(0) as ListBoxItem;
                            if (firstItem != null)
                            {
                                firstItem.Focus();
                            }
                        };
                        timer.Start();
                    }
                    else
                    {
                        _isLoadingFeed = false; // Clear flag after loading complete
                    }
                });
            }
            catch (Exception ex)
            {
                // Update UI with error on main thread
                Dispatcher.Invoke(() =>
                {
                    _viewModel.StatusMessage = $"Error loading feed: {ex.Message}";
                    MessageBox.Show($"Failed to load feed:\n{ex.Message}", "Feed Load Error", 
                                   MessageBoxButton.OK, MessageBoxImage.Warning);
                    _isLoadingFeed = false; // Clear flag on error too
                });
            }
        }

        private void HeadlinesList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            // Don't process selection changes while loading feed to prevent unwanted focus changes
            if (_isLoadingFeed) return;
            
            // Track the selected index for focus retention
            var listBox = sender as ListBox;
            if (listBox != null)
            {
                _lastSelectedHeadlineIndex = listBox.SelectedIndex;
                
                // When an item is selected, ensure it has proper focus for keyboard navigation
                if (listBox.SelectedIndex >= 0)
                {
                    Dispatcher.BeginInvoke(new Action(() =>
                    {
                        var selectedItem = listBox.ItemContainerGenerator.ContainerFromIndex(listBox.SelectedIndex) as ListBoxItem;
                        if (selectedItem != null && listBox.IsFocused)
                        {
                            selectedItem.Focus();
                        }
                    }), DispatcherPriority.ApplicationIdle);
                }
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
            
            // Update status bar with headline position and feed information
            if (HeadlinesList.SelectedIndex >= 0)
            {
                var currentPosition = HeadlinesList.SelectedIndex + 1;
                var totalCount = HeadlinesList.Items.Count;
                var currentFeed = FeedTree.SelectedItem as FeedItem;
                var feedName = currentFeed?.Title ?? "Unknown Feed";
                
                _viewModel.StatusMessage = $"{feedName} - {currentPosition} of {totalCount}";
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

        private void HeadlinesList_GotFocus(object sender, RoutedEventArgs e)
        {
            // When HeadlinesList gets focus (via Tab navigation), restore the last selected headline
            if (HeadlinesList.Items.Count > 0)
            {
                if (_lastSelectedHeadlineIndex >= 0 && _lastSelectedHeadlineIndex < HeadlinesList.Items.Count)
                {
                    // Restore the previously selected headline
                    HeadlinesList.SelectedIndex = _lastSelectedHeadlineIndex;
                }
                else if (HeadlinesList.SelectedIndex < 0)
                {
                    // If no selection exists, select the first item
                    HeadlinesList.SelectedIndex = 0;
                    _lastSelectedHeadlineIndex = 0;
                }
                
                // Ensure the selected item actually has keyboard focus for arrow navigation
                var listBoxItem = HeadlinesList.ItemContainerGenerator.ContainerFromIndex(HeadlinesList.SelectedIndex) as ListBoxItem;
                if (listBoxItem != null)
                {
                    listBoxItem.Focus();
                }
            }
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

        private void FeedTree_GotFocus(object sender, RoutedEventArgs e)
        {
            // Simple approach: Just ensure TreeView focus and update status
            Console.WriteLine("DEBUG: FeedTree_GotFocus triggered");
            
            var treeView = sender as TreeView;
            if (treeView == null) return;
            
            if (treeView.SelectedItem is FeedItem selectedFeed)
            {
                Console.WriteLine($"DEBUG: Selected feed: {selectedFeed.Title}");
                _viewModel.StatusMessage = $"Feed Tree - {selectedFeed.Title} selected";
            }
            else
            {
                Console.WriteLine("DEBUG: No feed selected in TreeView");
                _viewModel.StatusMessage = "Feed Tree - Select a feed and press Enter to load headlines";
            }
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

        private void RefreshButton_Click(object sender, RoutedEventArgs e)
        {
            RefreshCurrentFeed();
        }

        private void RefreshCurrentFeed()
        {
            if (_viewModel.SelectedFeed != null && !_viewModel.SelectedFeed.IsCategory)
            {
                _ = LoadFeedAsync(_viewModel.SelectedFeed);
            }
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
            FeedTree.Focus();
            // If there's a selected item, make sure it stays selected
            if (FeedTree.SelectedItem == null && FeedTree.Items.Count > 0)
            {
                // Select the first item if nothing is selected
                var firstItem = FeedTree.ItemContainerGenerator.ContainerFromIndex(0) as TreeViewItem;
                if (firstItem != null)
                {
                    firstItem.IsSelected = true;
                    firstItem.Focus();
                }
            }
            _viewModel.StatusMessage = "Focus on Feed Tree";
        }

        private void FocusHeadlinesList()
        {
            HeadlinesList.Focus();
            // If there are items and something was previously selected, restore that selection
            if (HeadlinesList.Items.Count > 0)
            {
                if (_lastSelectedHeadlineIndex >= 0 && _lastSelectedHeadlineIndex < HeadlinesList.Items.Count)
                {
                    HeadlinesList.SelectedIndex = _lastSelectedHeadlineIndex;
                }
                else if (HeadlinesList.SelectedIndex < 0)
                {
                    // Select first item if nothing is selected
                    HeadlinesList.SelectedIndex = 0;
                }
            }
            _viewModel.StatusMessage = "Focus on Headlines List";
        }

        private void FocusArticleContent()
        {
            // ArticleContent.Focus();
            _viewModel.StatusMessage = "Focus simplified (article viewing removed)";
        }

        private void CycleSections()
        {
            // Simple focus cycling between main sections
            if (FeedTree.IsFocused)
            {
                HeadlinesList.Focus();
                _viewModel.StatusMessage = "Now in Headlines List section";
            }
            else if (HeadlinesList.IsFocused)
            {
                // ArticleContent.Focus();
                _viewModel.StatusMessage = "Simplified interface - article viewing removed";
            }
            else
            {
                FeedTree.Focus();
                _viewModel.StatusMessage = "Now in Feed Tree section";
            }
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
