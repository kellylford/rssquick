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
using System.Windows.Automation;
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
    /// Main Window Code-behind
    /// </summary>
    [SuppressMessage("Design", "CA1001:Types that own disposable fields should be disposable",
        Justification = "A Window's disposal point is OnClosed, which cancels and disposes the " +
                        "token source. Implementing IDisposable would add a method nothing calls.")]
    public partial class MainWindow : Window
    {
        private readonly MainViewModel _viewModel;
        private bool _isLoadingFeed; // Suppresses focus side effects while a load is in progress

        /// <summary>
        /// Set while a load hands focus to its first headline, so the selection that causes does
        /// not overwrite the summary the load just put in the status bar.
        /// </summary>
        /// <remarks>
        /// The status bar is the only live region in the window, and two things want it at the
        /// same moment: what the load did, and where you now are in the list. The load summary
        /// was losing, silently — including "3 of 20 feeds failed", which is the one message
        /// there is no other way to discover. Position takes over from the first arrow key.
        /// </remarks>
        private bool _keepLoadSummary;

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

        /// <summary>The feed list in the tree, kept so it can be saved as the default.</summary>
        private OpenedFeedList? _currentFeedList;

        /// <summary>True while the tree shows the list RSS Quick opens at startup.</summary>
        private bool _currentListIsDefault;

        /// <summary>The newer version UpdateButton offers, once App has found one.</summary>
        private UpdateOffer? _update;

        /// <summary>Installs <see cref="_update"/> now. Only used when it is ready to install.</summary>
        private Action? _restartAndUpdate;

        /// <summary>
        /// Word of an update that arrived during a load, held until the load has said what it did.
        /// </summary>
        /// <remarks>
        /// The update check finishes a few seconds after startup, which is exactly when someone is
        /// most likely to have pressed Enter on a feed. Written straight to the status bar, it
        /// would replace "Loading BBC News..." and then be replaced by the load's summary before
        /// anyone heard it.
        /// </remarks>
        private string? _pendingUpdateNotice;

        /// <summary>The window's text size from the Windows setting, before Ctrl+Plus and Minus.</summary>
        private readonly double _baseFontSize;

        /// <summary>Ctrl+Plus and Ctrl+Minus, on top of the Windows setting. Not kept between runs.</summary>
        private double _textSize = 1.0;

        /// <summary>What has been typed for type-ahead in the feed tree, and when.</summary>
        private string _typeAhead = string.Empty;
        private DateTime _typeAheadAt;

        /// <summary>
        /// True while the status bar still holds what a load did, and the reader has not moved since.
        /// </summary>
        /// <remarks>
        /// Word of an update that arrives then is added to the summary rather than replacing it,
        /// for the same reason as <see cref="_keepLoadSummary"/>: "3 of 20 feeds failed" has no
        /// other way to reach the reader.
        /// </remarks>
        private bool _loadSummaryShowing;

        /// <summary>What the headlines list is showing a search for, so F5 runs it again.</summary>
        private string? _currentSearch;

        /// <summary>The last search, to start Search All Feeds with. Not kept between runs.</summary>
        private string _lastSearch = string.Empty;

        /// <summary>Stops a subscription still looking for its feed when another starts.</summary>
        private CancellationTokenSource? _subscribeCancellation;

        /// <summary>
        /// Help, Check for Updates. Set by App, so the tests, which build windows directly, never
        /// reach GitHub.
        /// </summary>
        internal Func<Task<UpdateOffer?>>? CheckForUpdates { get; set; }

        public MainWindow()
        {
            InitializeComponent();
            // The only view model. MainWindow.xaml used to declare a second one in
            // <Window.DataContext>, which this line then replaced - so any binding evaluated
            // during InitializeComponent was reading a different object from the one every
            // handler below writes to.
            _viewModel = new MainViewModel();
            DataContext = _viewModel;

            // Windows' "Make text bigger" setting. WPF ignores it on its own, so a user who has
            // asked for 200% text would otherwise get none of it here. Everything in the window
            // inherits from this, so one line covers the whole UI.
            _baseFontSize = SystemFonts.MessageFontSize * TextScale.Current;
            FontSize = _baseFontSize;

            // Set up simplified interface (WebBrowser removed)
            // ArticleContent.Navigated += ArticleContent_Navigated;

            // Load default OPML file
            LoadDefaultOpml();

            // Set up keyboard navigation
            SetupKeyboardNavigation();

            // Nothing stops a second copy of RSS Quick saving or forgetting the default, so the
            // buttons are re-checked whenever this window comes back to the front.
            Activated += (_, _) => UpdateFeedListButtons();

            PreviewTextInput += Window_PreviewTextInput;
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

            // Alt+D saves the list on screen as the default. A binding rather than an access key
            // so it can say why when the button is greyed out, instead of doing nothing.
            var makeDefaultBinding = new KeyBinding(new RelayCommand(MakeCurrentListDefault), Key.D, ModifierKeys.Alt);
            InputBindings.Add(makeDefaultBinding);

            // The rest match the Mac's menu keys, with Ctrl for Command: Import, the two panels
            // directly, and text size. F1 is where Windows readers look for help, as Command-/
            // and the Help menu are on the Mac.
            InputBindings.Add(new KeyBinding(new RelayCommand(ImportOpml), Key.O, ModifierKeys.Control));
            InputBindings.Add(new KeyBinding(new RelayCommand(() => FocusFeedTree()), Key.D1, ModifierKeys.Control));
            InputBindings.Add(new KeyBinding(new RelayCommand(() => FocusHeadlinesList()), Key.D2, ModifierKeys.Control));
            InputBindings.Add(new KeyBinding(new RelayCommand(ShowKeyboardShortcuts), Key.F1, ModifierKeys.None));
            foreach (var key in new[] { Key.OemPlus, Key.Add })
                InputBindings.Add(new KeyBinding(new RelayCommand(() => SetTextSize(TextScale.Larger(_textSize))), key, ModifierKeys.Control));
            // On a US keyboard the plus is Shift+=, so "Ctrl+Plus" is really Ctrl+Shift+=.
            InputBindings.Add(new KeyBinding(new RelayCommand(() => SetTextSize(TextScale.Larger(_textSize))), Key.OemPlus, ModifierKeys.Control | ModifierKeys.Shift));
            foreach (var key in new[] { Key.OemMinus, Key.Subtract })
                InputBindings.Add(new KeyBinding(new RelayCommand(() => SetTextSize(TextScale.Smaller(_textSize))), key, ModifierKeys.Control));
            foreach (var key in new[] { Key.D0, Key.NumPad0 })
                InputBindings.Add(new KeyBinding(new RelayCommand(() => SetTextSize(1.0)), key, ModifierKeys.Control));

            // Subscribing, exporting and searching: Command-N, Command-E and Command-F on the Mac.
            // Search is also /, which is handled as typed text rather than as a key - see
            // Window_PreviewTextInput - so it is the / key on every keyboard layout, not just the
            // one where / happens to be Key.OemQuestion.
            InputBindings.Add(new KeyBinding(new RelayCommand(Subscribe), Key.N, ModifierKeys.Control));
            InputBindings.Add(new KeyBinding(new RelayCommand(ExportFeedList), Key.E, ModifierKeys.Control));
            InputBindings.Add(new KeyBinding(new RelayCommand(SearchAllFeeds), Key.F, ModifierKeys.Control));
        }

        /// <summary>
        /// /: Search All Feeds, from anywhere in the window except a text box or the open menu.
        /// </summary>
        /// <remarks>
        /// Preview, on the window, so it runs before the feed tree's type-ahead and the headline
        /// list's TextSearch can take the / as the start of a name. Deferred, so the dialog does
        /// not open in the middle of the keystroke that asked for it.
        /// </remarks>
        private void Window_PreviewTextInput(object sender, TextCompositionEventArgs e)
        {
            if (e.Text != "/") return;

            var focused = FocusManager.GetFocusedElement(this) as DependencyObject;
            if (focused is System.Windows.Controls.Primitives.TextBoxBase || IsWithin(MainMenu, focused)) return;

            e.Handled = true;
            Dispatcher.BeginInvoke(new Action(SearchAllFeeds), DispatcherPriority.Input);
        }

        private void LoadDefaultOpml()
        {
            // Set initial status message for simplified RSS reader
            _viewModel.StatusMessage = "Ready - Import OPML file or select a feed to begin";

            try
            {
                var startup = StartupFeedList.Choose(SavedFeedList.ForThisUser, FindStarterOpml());
                if (startup.List is { } list)
                {
                    // A saved list that could not be read is not what is on screen, so offer to
                    // replace it with what is.
                    ShowFeedList(list, isDefault: startup.SavedListProblem is null);

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

                            // The one startup message that must survive: without it the reader
                            // has no way to know the list in front of them is not their own.
                            _viewModel.StatusMessage = startup.SavedListProblem is { } problem
                                ? $"{problem} - showing the starter feed list instead"
                                : "Focus set to feed tree - use arrow keys to navigate";
                        }
                    }), System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                }
                else
                {
                    UpdateFeedListButtons();
                    _viewModel.StatusMessage = "Default RSS.opml file not found - use Import OPML File button";

                    // Set focus to Import button if no default file
                    this.Dispatcher.BeginInvoke(new Action(() => {
                        ImportOpmlButton.Focus();
                        _viewModel.StatusMessage = startup.SavedListProblem is { } problem
                            ? $"{problem} - press Enter to import an OPML file"
                            : "No default feeds found - press Enter to import OPML file";
                    }), System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                }
            }
            catch (Exception ex)
            {
                UpdateFeedListButtons();
                _viewModel.StatusMessage = $"Error loading default OPML: {ex.Message}";

                // Focus Import button on error too
                this.Dispatcher.BeginInvoke(new Action(() => {
                    ImportOpmlButton.Focus();
                }), System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            }
        }

        /// <summary>
        /// Locates the feed list RSS Quick ships with, or null when there is none.
        /// </summary>
        /// <remarks>
        /// The working directory comes first, so "drop an rss.opml beside the program and launch it
        /// there" keeps working, and so a portable copy on a USB stick uses its own list. The
        /// install directory is the fallback: a Start Menu or desktop shortcut does not reliably
        /// set the working directory to the install folder, and without this the installed build
        /// opened with an empty feed tree even though RSS.opml sat right next to the executable.
        /// Both come after the reader's saved default; see <see cref="StartupFeedList.Choose"/>.
        /// </remarks>
        private static string? FindStarterOpml()
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

        /// <summary>
        /// Replaces the feed tree with a feed list.
        /// </summary>
        /// <param name="isDefault">
        /// True when this is the list RSS Quick opens at startup, which is what greys out
        /// Make This My Default.
        /// </param>
        internal void ShowFeedList(OpenedFeedList list, bool isDefault)
        {
            _viewModel.FeedCategories.Clear();
            foreach (var root in list.Document.Roots) _viewModel.FeedCategories.Add(root);

            _currentFeedList = list;
            _currentListIsDefault = isDefault;
            UpdateFeedListButtons();

            _viewModel.StatusMessage = list.IsSaved
                ? $"Loaded {Feeds(list.Document.FeedCount)} from your default feed list"
                : $"Loaded {Feeds(list.Document.FeedCount)} from OPML file";

            FeedTree.ItemsSource = _viewModel.FeedCategories;
        }

        private static string Feeds(int count) => count == 1 ? "1 feed" : $"{count} feeds";

        /// <summary>
        /// Greys out the two default-list buttons when they would do nothing.
        /// </summary>
        /// <remarks>
        /// A disabled button leaves the tab order, so the Alt+D binding stays live and explains
        /// itself in the status bar rather than doing nothing silently.
        /// </remarks>
        private void UpdateFeedListButtons()
        {
            MakeDefaultButton.IsEnabled = _currentFeedList is not null && !_currentListIsDefault;
            UseStarterListButton.IsEnabled = SavedFeedList.ForThisUser.Exists;
        }

        private void MakeDefault_Click(object sender, RoutedEventArgs e) => MakeCurrentListDefault();

        /// <summary>
        /// Alt+D, or the button: open the list on screen every time RSS Quick starts.
        /// </summary>
        private void MakeCurrentListDefault()
        {
            if (_currentFeedList is not { } list)
            {
                _viewModel.StatusMessage = "There is no feed list to make your default - import one first";
                return;
            }
            if (_currentListIsDefault)
            {
                _viewModel.StatusMessage = "This feed list is already your default";
                return;
            }

            try
            {
                SavedFeedList.ForThisUser.Save(list.Content);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                _viewModel.StatusMessage = $"Could not save your default feed list: {ex.Message}";
                return;
            }

            _currentFeedList = list with { IsSaved = true };
            _currentListIsDefault = true;
            MoveFocusOffDisabledButton();
            UpdateFeedListButtons();

            _viewModel.StatusMessage =
                $"Saved as your default feed list, {Feeds(list.Document.FeedCount)}. It will open every time RSS Quick starts.";
        }

        /// <summary>
        /// Forget the saved default and go back to the list RSS Quick ships with.
        /// </summary>
        private void UseStarterList_Click(object sender, RoutedEventArgs e)
        {
            // Reachable from the File menu when there is nothing to forget, where the button
            // would be greyed out.
            if (!SavedFeedList.ForThisUser.Exists)
            {
                _viewModel.StatusMessage = "You have no default feed list of your own, so the starter feed list already opens at startup";
                return;
            }

            try
            {
                SavedFeedList.ForThisUser.Forget();
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                _viewModel.StatusMessage = $"Could not remove your default feed list: {ex.Message}";
                return;
            }

            // Before the tree is replaced, while the button still has focus to give up.
            MoveFocusOffDisabledButton();

            string message;
            try
            {
                if (FindStarterOpml() is { } starter)
                {
                    var list = OpenedFeedList.Parse(File.ReadAllBytes(starter), isSaved: false);
                    CancelLoad();
                    _viewModel.Headlines.Clear();
                    _currentlyLoadedFeed = null;
                    _lastSelectedHeadlineIndex = -1;
                    OpenInBrowserButton.IsEnabled = false;
                    ShowFeedList(list, isDefault: true);
                    FocusSelectedFeed();
                    message = $"Removed your default feed list. Showing the starter feed list, {Feeds(list.Document.FeedCount)}.";
                }
                else
                {
                    // The old list stays on screen but no longer opens at startup, so let it be
                    // saved again.
                    _currentListIsDefault = false;
                    UpdateFeedListButtons();
                    message = "Removed your default feed list. The starter feed list is missing from this copy of RSS Quick.";
                }
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException
                                           or System.Xml.XmlException or InvalidOperationException)
            {
                _currentListIsDefault = false;
                UpdateFeedListButtons();
                message = $"Removed your default feed list, but the starter feed list could not be read: {ex.Message}";
            }

            _viewModel.StatusMessage = message;
        }

        /// <summary>
        /// Offers a newer version: shows UpdateButton and says so in the status bar.
        /// </summary>
        /// <param name="offer">What App found.</param>
        /// <param name="restartAndUpdate">Installs it now. Used only when it is ready to install.</param>
        /// <remarks>
        /// Focus is left where it is. An update is not a reason to move a reader who is in the
        /// middle of something; the button joins the tab ring beside the other feed list
        /// buttons, and Alt+U reaches it from anywhere.
        /// </remarks>
        internal void ShowUpdate(UpdateOffer offer, Action restartAndUpdate)
        {
            _update = offer;
            _restartAndUpdate = restartAndUpdate;

            string notice;
            if (offer.ReadyToInstall)
            {
                UpdateButton.Content = $"Restart and _Update to {offer.Version}";
                AutomationProperties.SetHelpText(UpdateButton, $"Close RSS Quick, install version {offer.Version} and start it again");
                UpdateButton.ToolTip = $"Close RSS Quick, install version {offer.Version} and start it again (Alt+U)";
                notice = $"RSS Quick {offer.Version} has been downloaded and will be installed when you close RSS Quick. "
                       + "Restart and Update installs it now";
            }
            else
            {
                UpdateButton.Content = $"Download _Update {offer.Version}";
                AutomationProperties.SetHelpText(UpdateButton, $"Open the RSS Quick {offer.Version} download page in your browser");
                UpdateButton.ToolTip = $"Open the RSS Quick {offer.Version} download page in your browser (Alt+U)";
                notice = $"RSS Quick {offer.Version} is available. Download Update opens its page in your browser";
            }
            AutomationProperties.SetAcceleratorKey(UpdateButton, "Alt+U");
            UpdateButton.Visibility = Visibility.Visible;
            // Help's item says so too, as the Mac's RSS Quick menu does.
            UpdateMenuItem.Header = UpdateButton.Content;
            UpdateMenuItem.InputGestureText = "Alt+U";

            if (_isLoadingFeed) _pendingUpdateNotice = notice;
            else if (_loadSummaryShowing) _viewModel.StatusMessage = $"{_viewModel.StatusMessage}. {notice}";
            else _viewModel.StatusMessage = notice;
        }

        private void Update_Click(object sender, RoutedEventArgs e)
        {
            if (_update is not { } offer) return;

            if (!offer.ReadyToInstall)
            {
                try
                {
                    Process.Start(new ProcessStartInfo(offer.Page.AbsoluteUri) { UseShellExecute = true });
                    _viewModel.StatusMessage = $"Opened the RSS Quick {offer.Version} page in your browser";
                }
                catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException)
                {
                    _viewModel.StatusMessage = $"Could not open your browser: {ex.Message}. The page is {offer.Page.AbsoluteUri}";
                }
                return;
            }

            _viewModel.StatusMessage = $"Installing RSS Quick {offer.Version} and restarting";
            try
            {
                // Ends this process when it works.
                _restartAndUpdate?.Invoke();
            }
            catch (Exception ex)
            {
                // Not "when you close": a failed attempt is not retried at exit, in case it had
                // already started the installer. The next launch downloads it again.
                _viewModel.StatusMessage =
                    $"Could not install RSS Quick {offer.Version} now ({ex.Message}). It will be offered again the next time RSS Quick starts";
            }
        }

        /// <summary>
        /// Moves focus to the feed tree before the button holding it is disabled.
        /// </summary>
        /// <remarks>
        /// A disabled control cannot keep keyboard focus, and WPF does not move it anywhere: it
        /// is simply dropped, and a screen reader user is left with no idea where they are.
        /// </remarks>
        private void MoveFocusOffDisabledButton()
        {
            if (!MakeDefaultButton.IsKeyboardFocusWithin && !UseStarterListButton.IsKeyboardFocusWithin
                && !ReferenceEquals(FocusManager.GetFocusedElement(this), MakeDefaultButton)
                && !ReferenceEquals(FocusManager.GetFocusedElement(this), UseStarterListButton)) return;
            if (!FocusSelectedFeed()) ImportOpmlButton.Focus();
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
            else if (e.Key == Key.Delete && Keyboard.Modifiers == ModifierKeys.None)
            {
                RemoveSelectedFeed();
                e.Handled = true;
            }
        }

        /// <summary>
        /// Right and Left, the way other trees on Windows and the Mac's outline behave.
        /// </summary>
        /// <remarks>
        /// Right opens a closed folder, and on an open one moves to its first feed. Left closes an
        /// open folder, and anywhere else moves to the folder above. WPF's TreeView does only the
        /// opening and closing, so Left on a feed used to do nothing at all: the only way back to
        /// its folder was to arrow up through every feed above it. Preview, so this runs before
        /// the TreeViewItem's own handling can swallow the key.
        /// </remarks>
        private void FeedTree_PreviewKeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key is not (Key.Left or Key.Right) || Keyboard.Modifiers != ModifierKeys.None) return;
            if (FeedTree.SelectedItem is not FeedItem selected || GetTreeViewItemFromFeedItem(selected) is not { } node) return;

            if (e.Key == Key.Right)
            {
                // Nothing to do on a feed, but still handled, so the key cannot fall through to
                // the tree's scroll viewer and scroll it sideways.
                if (!selected.IsCategory) { e.Handled = true; return; }
                if (!node.IsExpanded)
                {
                    node.IsExpanded = true;
                }
                else
                {
                    node.UpdateLayout();
                    if (node.ItemContainerGenerator.ContainerFromIndex(0) is TreeViewItem first) Select(first);
                }
            }
            else if (selected.IsCategory && node.IsExpanded)
            {
                node.IsExpanded = false;
            }
            else if (ItemsControl.ItemsControlFromItemContainer(node) is TreeViewItem parent)
            {
                Select(parent);
            }

            e.Handled = true;

            static void Select(TreeViewItem item)
            {
                item.IsSelected = true;
                item.Focus();
                item.BringIntoView();
            }
        }

        /// <summary>
        /// Type-ahead: typing the start of a name moves to the next feed or folder that has it.
        /// </summary>
        /// <remarks>
        /// The headlines list gets this from ListBox's own TextSearch; TreeView has none, and the
        /// Mac's outline has always had it. Only rows that are showing are searched, so a feed
        /// inside a closed folder is not jumped into. Letters typed within a second of each other
        /// build a longer prefix; one letter pressed again moves on to the next match.
        /// </remarks>
        private void FeedTree_PreviewTextInput(object sender, TextCompositionEventArgs e)
        {
            if (string.IsNullOrEmpty(e.Text) || char.IsControl(e.Text[0])) return;

            var now = DateTime.UtcNow;
            _typeAhead = (now - _typeAheadAt).TotalSeconds > 1 ? e.Text : _typeAhead + e.Text;
            _typeAheadAt = now;

            var rows = VisibleRows(FeedTree).ToList();
            if (rows.Count == 0) return;

            var current = rows.FindIndex(row => ReferenceEquals(row.DataContext, FeedTree.SelectedItem));
            // A fresh search starts after the current row, so pressing the same letter again moves
            // on; a longer prefix may still match the row already selected.
            var start = _typeAhead.Length == 1 ? current + 1 : Math.Max(current, 0);

            for (var i = 0; i < rows.Count; i++)
            {
                var row = rows[(start + i) % rows.Count];
                if (row.DataContext is FeedItem { Title: var title }
                    && title.StartsWith(_typeAhead, StringComparison.CurrentCultureIgnoreCase))
                {
                    row.IsSelected = true;
                    row.Focus();
                    row.BringIntoView();
                    e.Handled = true;
                    return;
                }
            }
        }

        /// <summary>The tree's rows in reading order, skipping those inside closed folders.</summary>
        private static IEnumerable<TreeViewItem> VisibleRows(ItemsControl parent)
        {
            for (var i = 0; i < parent.Items.Count; i++)
            {
                if (parent.ItemContainerGenerator.ContainerFromIndex(i) is not TreeViewItem row) continue;
                yield return row;
                if (row.IsExpanded)
                {
                    foreach (var child in VisibleRows(row)) yield return child;
                }
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
            _loadSummaryShowing = false;
            _currentlyLoadedFeed = target;
            _currentSearch = null;
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
            // Not once the load has finished. The token source outlives it, and without this Escape
            // afterwards replaced the load's summary with "Loading cancelled" for a load that was
            // not running. The Mac had the same bug.
            if (!_isLoadingFeed || _loadCancellation is not { IsCancellationRequested: false }) return;

            _loadCancellation.Cancel();
            ReportLoadOutcome("Loading cancelled");
        }

        /// <summary>A cancelled load has finished unwinding.</summary>
        /// <remarks>
        /// Clears the loading flag only if this was still the current load. When it was replaced
        /// by a newer one, that one is running and owns the flag - clearing it here stopped Escape
        /// cancelling the newer load, because CancelLoad now checks the flag.
        /// </remarks>
        private void EndCancelledLoad(CancellationToken token)
        {
            if (_loadCancellation is { } current && current.Token == token) _isLoadingFeed = false;
        }

        /// <summary>
        /// Writes how a load ended - loaded, failed, cancelled - to the status bar.
        /// </summary>
        /// <remarks>
        /// Every way a load can end comes through here, so word of an update held back during the
        /// load is always read out once it is over, whichever way that was.
        /// </remarks>
        private void ReportLoadOutcome(string status)
        {
            // One announcement rather than two, with what the reader asked for first.
            if (_pendingUpdateNotice is { } notice)
            {
                status = $"{status}. {notice}";
                _pendingUpdateNotice = null;
            }

            _viewModel.StatusMessage = status;
            _loadSummaryShowing = true;
        }

        /// <summary>Puts articles on screen and hands focus to the first of them.</summary>
        private void ShowArticles(IReadOnlyList<ArticleItem> articles, string status)
        {
            foreach (var article in articles) _viewModel.Headlines.Add(article);

            ReportLoadOutcome(status);

            // Cleared before focusing, so the selection this makes is allowed to do its other
            // work - tracking the row, enabling the browser button - rather than being suppressed
            // as part of the load.
            _isLoadingFeed = false;

            if (articles.Count == 0) return;

            _keepLoadSummary = true;
            try
            {
                FocusSelectedHeadline();
            }
            finally
            {
                _keepLoadSummary = false;
            }
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
                ReportLoadOutcome($"{categoryItem.Title} has no feeds in it");
                return;
            }

            _viewModel.StatusMessage = $"Loading {feeds.Count} feeds in {categoryItem.Title}...";

            // No progress count. The status bar is the live region, so every change to it is
            // spoken, and a twenty-feed folder said "Loading News - 3 of 20 feeds" twenty times on
            // the way to the one message that matters. The Mac writes its count without
            // announcing it; Windows has no way to write the status bar silently, so it says when
            // the load starts and what it found, and nothing in between.
            IProgress<int>? progress = null;

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
                EndCancelledLoad(token);
            }
            catch (Exception ex)
            {
                if (token.IsCancellationRequested) return;

                _isLoadingFeed = false;
                ReportLoadOutcome($"Could not load {categoryItem.Title}: {ex.Message}");
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
                EndCancelledLoad(token);
            }
            catch (Exception ex)
            {
                if (token.IsCancellationRequested) return;

                _isLoadingFeed = false;
                // The same words a folder uses for a feed that failed, and the Mac for either:
                // "server said 404 not found" rather than .NET's own exception text.
                var reason = FeedLoader.DescribeFailure(ex);
                ReportLoadOutcome($"Could not load {feedItem.Title}: {reason}");

                // A modal box only where the user asked for one specific thing and got nothing.
                // The folder path deliberately does not do this; see DescribeFolderLoad.
                MessageBox.Show(
                    $"Could not load {feedItem.Title}.\n\nThis feed {reason}.",
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
            if (HeadlinesList.SelectedIndex >= 0 && !_keepLoadSummary)
            {
                var position = HeadlinesList.SelectedIndex + 1;
                var total = HeadlinesList.Items.Count;
                var source = string.IsNullOrWhiteSpace(selectedArticle.FeedTitle)
                    ? _currentlyLoadedFeed?.Title ?? "Headlines"
                    : selectedArticle.FeedTitle;

                _viewModel.StatusMessage = $"{source} - {position} of {total}";
                _loadSummaryShowing = false;
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

        private void ImportOpml_Click(object sender, RoutedEventArgs e) => ImportOpml();

        /// <summary>The Import button, or Ctrl+O.</summary>
        private void ImportOpml()
        {
            var dialog = new OpenFileDialog
            {
                Title = "Import OPML File",
                Filter = "OPML Files (*.opml;*.xml)|*.opml;*.xml|All Files (*.*)|*.*",
                DefaultExt = "opml"
            };

            if (dialog.ShowDialog() == true)
            {
                // The file's name, not its whole path: the status bar is read aloud, and a path is
                // a long way to go to hear which list arrived. The same wording as the Mac.
                var name = Path.GetFileName(dialog.FileName);
                try
                {
                    var list = OpenedFeedList.Parse(File.ReadAllBytes(dialog.FileName), isSaved: false);
                    ShowFeedList(list, isDefault: false);
                    // Into the list just imported, which is where the reader will want to be next.
                    FocusSelectedFeed();
                    _viewModel.StatusMessage =
                        $"Imported {Feeds(list.Document.FeedCount)} from {name} - Alt+D makes it your default feed list";
                }
                catch (Exception ex)
                {
                    _viewModel.StatusMessage = $"Could not import {name}: {ex.Message}";
                    MessageBox.Show($"Could not import {name}.\n\n{ex.Message}", "Import Error",
                                   MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }

        private void OpenInBrowser_Click(object sender, RoutedEventArgs e)
        {
            // Said rather than silently ignored, as on the Mac: Alt+B or Enter that does nothing
            // leaves a screen reader user wondering whether the key was heard at all.
            if (HeadlinesList.SelectedItem is not ArticleItem article)
            {
                _viewModel.StatusMessage = "Select a headline first";
                return;
            }
            if (string.IsNullOrEmpty(article.Link))
            {
                _viewModel.StatusMessage = $"{article.Title} has no link to open";
                return;
            }

            {
                try
                {
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = article.Link,
                        UseShellExecute = true
                    });
                    _viewModel.StatusMessage = $"Opened article in browser: {article.Title}";
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
            if (_currentSearch is { } search)
            {
                _ = SearchAsync(search);
                return;
            }

            if (_currentlyLoadedFeed is not { } loaded)
            {
                _viewModel.StatusMessage = "Nothing to refresh yet - press Enter on a feed first";
                return;
            }

            if (loaded.IsCategory) _ = LoadAllFeedsInCategoryAsync(loaded);
            else _ = LoadFeedAsync(loaded);
        }

        /// <summary>Alt+B. Runs even while the button is greyed out, so it can say why.</summary>
        private void OpenInBrowserCommand() => OpenInBrowser_Click(OpenInBrowserButton, new RoutedEventArgs());

        /// <summary>Ctrl+1, and F6 from the headlines.</summary>
        /// <returns>False when there was nothing to go to.</returns>
        /// <remarks>
        /// Nothing is written when focus moves: the screen reader already says where it landed.
        /// Only an empty panel is worth a message, because otherwise the key seems to do nothing.
        /// </remarks>
        private bool FocusFeedTree()
        {
            if (FeedTree.Items.Count == 0)
            {
                _viewModel.StatusMessage = "Feed tree is empty - import an OPML file";
                return false;
            }
            if (!FocusSelectedFeed()) FeedTree.Focus();
            return true;
        }

        /// <summary>Ctrl+2, and F6 from the feed tree.</summary>
        /// <returns>False when there was nothing to go to.</returns>
        private bool FocusHeadlinesList()
        {
            if (HeadlinesList.Items.Count == 0)
            {
                _viewModel.StatusMessage = "Headlines list is empty - press Enter on a feed to load it";
                return false;
            }
            if (!FocusSelectedHeadline()) HeadlinesList.Focus();
            return true;
        }

        /// <summary>Ctrl+Plus, Ctrl+Minus and Ctrl+0.</summary>
        private void SetTextSize(double size)
        {
            _textSize = size;
            FontSize = _baseFontSize * size;
            _viewModel.StatusMessage = $"Text size {(int)Math.Round(size * 100)} percent";
        }

        /// <summary>
        /// F1: the keys, in a window rather than in a README nobody has open. The Mac's is
        /// Help, Keyboard Shortcuts.
        /// </summary>
        private void ShowKeyboardShortcuts()
        {
            var version = AppUpdater.CurrentVersion.ToString(3);
            MessageBox.Show(this, KeyboardShortcuts(version), "RSS Quick Keyboard Shortcuts",
                MessageBoxButton.OK, MessageBoxImage.Information);
        }

        internal static string KeyboardShortcuts(string version) => $"""
            Moving around
              Alt or F10: the menu bar, where every command is
              Tab or Shift+Tab: the buttons, the feed tree and the headlines
              F6 or Ctrl+Tab: switch between the feed tree and the headlines
              Ctrl+1 or Ctrl+2: go straight to the feed tree or the headlines
              Arrow keys: move within a list. Right and Left open and close folders
              Type a few letters: jump to a feed or headline by name

            Reading
              Enter: on a feed, load its headlines. On a folder, load all of them.
                On a headline, open it in your browser.
              Alt+B: open the selected headline in your browser
              / or Ctrl+F: search the headlines of every feed
              F5: reload what is on screen, or run the search again
              Escape: stop a load or a search that is taking too long

            Feeds and files
              Ctrl+N: subscribe to a feed, by its address or its website's
              Delete: in the feed tree, remove the selected feed
              Ctrl+E: export your feed list as an OPML file
              Ctrl+O: import a different OPML feed list
              Alt+D: make the feed list on screen your default
              Alt+U: get a new version, once there is one

            Text size
              Ctrl+Plus or Ctrl+Minus: larger or smaller text, until RSS Quick closes
              Ctrl+0: back to your Windows text size

            Selecting a feed never fetches anything. Only Enter does.

            RSS Quick {version}
            """;

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
            // The same two words as the Mac, and only when focus actually moved: an empty panel's
            // own message is the one worth hearing.
            // Logical focus first: it is what the rest of the window tracks, and unlike keyboard
            // focus it is set even when the window is not in the foreground.
            var focused = (FocusManager.GetFocusedElement(this) ?? Keyboard.FocusedElement) as DependencyObject;
            if (IsWithin(FeedTree, focused))
            {
                if (FocusHeadlinesList()) _viewModel.StatusMessage = "Headlines";
            }
            else
            {
                if (FocusFeedTree()) _viewModel.StatusMessage = "Feed tree";
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

}
