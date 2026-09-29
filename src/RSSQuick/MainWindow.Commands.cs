using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Win32;
using RSSReaderWPF.Services;

namespace RSSReaderWPF
{
    /// <summary>
    /// The menu bar, and the commands that arrived with it: searching every feed, subscribing,
    /// removing a feed, and exporting the list.
    /// </summary>
    /// <remarks>
    /// Each command comes in two halves. The first asks - a dialog, a confirmation - and is all a
    /// test cannot drive. The second does the work and is <c>internal</c>, so the tests reach it
    /// directly: they call <see cref="SearchAsync"/> rather than typing into a modal window that
    /// would block the dispatcher. The macOS window has the same split.
    /// </remarks>
    public partial class MainWindow
    {
        // ── the menu bar ────────────────────────────────────────────────────

        private void ExportFeedList_Click(object sender, RoutedEventArgs e) => ExportFeedList();
        private void Subscribe_Click(object sender, RoutedEventArgs e) => Subscribe();
        private void RemoveFeed_Click(object sender, RoutedEventArgs e) => RemoveSelectedFeed();
        private void Refresh_Click(object sender, RoutedEventArgs e) => RefreshCurrentFeed();
        private void Exit_Click(object sender, RoutedEventArgs e) => Close();
        private void Search_Click(object sender, RoutedEventArgs e) => SearchAllFeeds();
        private void FocusFeedTree_Click(object sender, RoutedEventArgs e) => FocusFeedTree();
        private void FocusHeadlines_Click(object sender, RoutedEventArgs e) => FocusHeadlinesList();
        private void NextPane_Click(object sender, RoutedEventArgs e) => CycleSections();
        private void LargerText_Click(object sender, RoutedEventArgs e) => SetTextSize(TextScale.Larger(_textSize));
        private void SmallerText_Click(object sender, RoutedEventArgs e) => SetTextSize(TextScale.Smaller(_textSize));
        private void ActualSize_Click(object sender, RoutedEventArgs e) => SetTextSize(1.0);
        private void KeyboardShortcuts_Click(object sender, RoutedEventArgs e) => ShowKeyboardShortcuts();

        /// <summary>
        /// File, Stop Loading. Escape stays silent when nothing is loading, because it is pressed
        /// for all sorts of reasons; choosing this from the menu is only ever meant for a load.
        /// </summary>
        private void StopLoading_Click(object sender, RoutedEventArgs e)
        {
            if (_isLoadingFeed) CancelLoad();
            else _viewModel.StatusMessage = "Nothing is loading";
        }

        /// <summary>Help, Check for Updates - or the update itself once one has been found.</summary>
        private async void CheckForUpdates_Click(object sender, RoutedEventArgs e)
        {
            if (_update is not null)
            {
                Update_Click(sender, e);
                return;
            }

            var version = AppUpdater.CurrentVersion.ToString(3);
            if (CheckForUpdates is not { } check)
            {
                _viewModel.StatusMessage = $"This copy of RSS Quick cannot check for updates. It is version {version}";
                return;
            }

            _viewModel.StatusMessage = "Checking for a newer version...";
            try
            {
                // A newer one arrives through ShowUpdate, which says so itself.
                if (await check() is null)
                    _viewModel.StatusMessage = $"No newer version of RSS Quick was found. This is version {version}";
            }
            catch (Exception ex)
            {
                _viewModel.StatusMessage = $"Could not check for a newer version: {ex.Message}";
            }
        }

        private void About_Click(object sender, RoutedEventArgs e)
        {
            MessageBox.Show(this,
                $"RSS Quick {AppUpdater.CurrentVersion.ToString(3)}\n\n"
                + "An RSS reader built for screen reader and braille display users.\n\n"
                + AppUpdater.RepositoryUrl,
                "About RSS Quick", MessageBoxButton.OK, MessageBoxImage.Information);
        }

        // ── search ──────────────────────────────────────────────────────────

        /// <summary>/, Ctrl+F, or Edit, Search All Feeds: ask what to look for, then look.</summary>
        private void SearchAllFeeds()
        {
            var dialog = new InputDialog(this, "Search All Feeds", "_Search the headlines of every feed for:", "_Search", _lastSearch);
            if (dialog.ShowDialog() != true) return;

            _ = SearchAsync(dialog.Text);
        }

        /// <summary>
        /// Fetches every feed in the tree and shows the headlines that match.
        /// </summary>
        /// <remarks>
        /// A load in all but name, and it goes through the same path - BeginLoad, ShowArticles,
        /// Escape to stop it - so the status bar and focus behave exactly as they do for a folder.
        /// F5 runs the search again.
        /// </remarks>
        internal async Task SearchAsync(string query)
        {
            if (HeadlineSearch.Words(query).Count == 0) return;
            _lastSearch = query;

            var feeds = HeadlineSearch.FeedsToSearch(FeedTree.Items.OfType<FeedItem>());
            if (feeds.Count == 0)
            {
                _viewModel.StatusMessage = "There are no feeds to search - import a feed list first";
                return;
            }

            // Before BeginLoad, which empties the list and takes the focused row with it.
            var hadHeadlineFocus = IsWithin(HeadlinesList, FocusManager.GetFocusedElement(this) as DependencyObject);

            var token = BeginLoad(new FeedItem { Title = query, IsCategory = true });
            _currentSearch = query;
            _viewModel.StatusMessage = HeadlineSearch.DescribeStart(query, feeds.Count);

            try
            {
                var result = await FeedLoader.LoadFolderAsync(feeds, progress: null, token);
                if (token.IsCancellationRequested) return;

                var matches = HeadlineSearch.Filter(result.Articles, query);

                ShowArticles(matches, HeadlineSearch.Describe(query, matches.Count, result));

                // Nothing matched and the row focus was on has gone with the old list; the tree is
                // the one place left to be. Moved without a word, so the result is what is heard.
                if (matches.Count == 0 && hadHeadlineFocus && FeedTree.Items.Count > 0 && !FocusSelectedFeed())
                    FeedTree.Focus();
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested)
            {
                EndCancelledLoad(token);
            }
            catch (Exception ex)
            {
                if (token.IsCancellationRequested) return;

                _isLoadingFeed = false;
                ReportLoadOutcome($"Could not search: {ex.Message}");
            }
        }

        // ── subscribing ─────────────────────────────────────────────────────

        /// <summary>Ctrl+N, or File, Subscribe to Feed: ask for an address and a folder.</summary>
        private void Subscribe()
        {
            var roots = CurrentRoots();
            var folders = OpmlEditor.Folders(roots);
            var dialog = new InputDialog(this, "Subscribe to Feed", "_Address of the feed or its website:", "_Subscribe",
                folders: folders,
                folder: OpmlEditor.Suggest(folders, roots, FeedTree.SelectedItem as FeedItem));
            if (dialog.ShowDialog() != true) return;

            _ = SubscribeAsync(dialog.Text, dialog.Folder);
        }

        /// <summary>
        /// Finds the feed at an address, adds it to the list, and saves the list as the default.
        /// </summary>
        /// <param name="folder">Where it goes. Null for the top level.</param>
        /// <remarks>
        /// <para>Saving is not optional. A subscription that vanished the next time RSS Quick
        /// started would be worse than none, and the saved default is the only thing RSS Quick
        /// keeps - so subscribing to a feed in an imported list makes that list the default, and
        /// the status bar says so.</para>
        /// <para>Nothing changes until the feed has been found and the list saved: a typing
        /// mistake or a full disk leaves the tree exactly as it was.</para>
        /// </remarks>
        internal async Task SubscribeAsync(string address, FolderChoice? folder)
        {
            _subscribeCancellation?.Cancel();
            _subscribeCancellation?.Dispose();
            _subscribeCancellation = new CancellationTokenSource();
            var token = _subscribeCancellation.Token;

            // Before the network: the same address pasted twice is caught without a fetch.
            if (FeedDiscovery.Normalize(address) is { } typed
                && OpmlEditor.FindFeed(CurrentRoots(), typed.AbsoluteUri) is { } known)
            {
                AlreadySubscribed(known);
                return;
            }

            _viewModel.StatusMessage = $"Looking for a feed at {address}...";

            // The folder's path is a position in this list. If the list changes while the feed is
            // being looked for - a feed removed, another list imported - the path would point
            // somewhere else, or into a list the reader never meant to change.
            var listAtStart = _currentFeedList?.Content;

            DiscoveredFeed feed;
            try
            {
                feed = await FeedDiscovery.FindAsync(address, token);
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                _viewModel.StatusMessage = $"Could not subscribe: {address} {FeedLoader.DescribeFailure(ex)}";
                return;
            }

            if (token.IsCancellationRequested) return;

            if (!ReferenceEquals(_currentFeedList?.Content, listAtStart))
            {
                _viewModel.StatusMessage = $"Your feed list changed while RSS Quick was looking for {feed.Title}, so it was not added. Subscribe again to add it";
                return;
            }

            // Again, now the real address is known: a website's address leads to a feed that may
            // already be in the list under its own.
            if (OpmlEditor.FindFeed(CurrentRoots(), feed.Url) is { } existing)
            {
                AlreadySubscribed(existing);
                return;
            }

            var into = folder ?? OpmlEditor.Folders(CurrentRoots()).First(f => f.Path is null);
            if (ChangeFeedList(content => OpmlEditor.AddFeed(content, into.Path, feed.Title, feed.Url),
                               $"Could not add {feed.Title} to your feed list") is not { } result)
                return;

            if (OpmlEditor.FindFeed(result.List.Document.Roots, feed.Url) is { } added) SelectInTree(added);

            _viewModel.StatusMessage = $"Subscribed to {feed.Title} in {into.Name}.{result.DefaultNote}";
        }

        private void AlreadySubscribed(FeedItem feed)
        {
            SelectInTree(feed);
            _viewModel.StatusMessage = $"You already subscribe to {feed.Title}, in {feed.Category}";
        }

        // ── removing ────────────────────────────────────────────────────────

        /// <summary>Delete in the tree, or File, Remove Feed: confirm, then remove.</summary>
        private void RemoveSelectedFeed()
        {
            if (FeedTree.SelectedItem is not FeedItem feed)
            {
                _viewModel.StatusMessage = "Select a feed in the feed tree first";
                return;
            }
            if (feed.IsCategory)
            {
                _viewModel.StatusMessage = $"{feed.Title} is a folder. Remove Feed removes one feed at a time";
                return;
            }

            var answer = MessageBox.Show(this, $"Remove {feed.Title} from your feed list?", "Remove Feed",
                MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.Yes);
            if (answer != MessageBoxResult.Yes)
            {
                FocusSelectedFeed();
                return;
            }

            RemoveFeed(feed);
        }

        /// <summary>
        /// Takes a feed out of the list and saves the list as the default.
        /// </summary>
        /// <remarks>
        /// Focus goes to the feed that took its place, the way deleting from any list does, or the
        /// one before it when it was last, or its folder when it was the only one - never nowhere.
        /// </remarks>
        internal void RemoveFeed(FeedItem feed)
        {
            if (feed.IsCategory || feed.OutlinePath is not { } path) return;

            var roots = CurrentRoots();
            var parent = OpmlEditor.ParentOf(roots, feed);
            var siblings = parent?.Children ?? (IList<FeedItem>)roots.ToList();
            var index = siblings.IndexOf(feed);
            var parentPath = parent?.OutlinePath;

            if (ChangeFeedList(content => OpmlEditor.Remove(content, path),
                               $"Could not remove {feed.Title}") is not { } result)
                return;

            var newRoots = result.List.Document.Roots;
            var newParent = parent is null ? null
                : parentPath is null ? newRoots.FirstOrDefault(r => r.IsCategory && r.OutlinePath is null)
                : FindByPath(newRoots, parentPath);
            var newSiblings = newParent?.Children ?? (IList<FeedItem>)newRoots.ToList();

            var next = newSiblings.Count == 0 ? newParent : newSiblings[Math.Min(index, newSiblings.Count - 1)];
            if (next is null || !SelectInTree(next)) FocusSelectedFeed();

            _viewModel.StatusMessage = $"Removed {feed.Title}.{result.DefaultNote}";
        }

        // ── exporting ───────────────────────────────────────────────────────

        /// <summary>Ctrl+E, or File, Export Feed List: ask where, then write it.</summary>
        private void ExportFeedList()
        {
            if (_currentFeedList is null)
            {
                _viewModel.StatusMessage = "There is no feed list to export - import one first";
                return;
            }

            var dialog = new SaveFileDialog
            {
                Title = "Export Feed List",
                Filter = "OPML Files (*.opml)|*.opml|All Files (*.*)|*.*",
                DefaultExt = "opml",
                AddExtension = true,
                FileName = "RSS Quick Feeds.opml",
            };
            if (dialog.ShowDialog(this) != true) return;

            ExportFeedList(dialog.FileName);
        }

        /// <summary>
        /// Writes the list on screen to a file, exactly as it was read or last changed, so it
        /// imports into another reader - or into RSS Quick on another computer - unchanged.
        /// </summary>
        internal void ExportFeedList(string path)
        {
            if (_currentFeedList is not { } list) return;

            var name = Path.GetFileName(path);
            try
            {
                File.WriteAllBytes(path, list.Content);
                _viewModel.StatusMessage = $"Exported {Feeds(list.Document.FeedCount)} to {name}";
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                _viewModel.StatusMessage = $"Could not export to {name}: {ex.Message}";
            }
        }

        // ── shared ──────────────────────────────────────────────────────────

        /// <summary>The tree as the file describes it, which is what the editor's paths refer to.</summary>
        private IReadOnlyList<FeedItem> CurrentRoots() =>
            _currentFeedList?.Document.Roots ?? (IReadOnlyList<FeedItem>)Array.Empty<FeedItem>();

        /// <summary>A change made and saved.</summary>
        /// <param name="DefaultNote">
        /// What to add to the status message when this made the list the default, which the reader
        /// did not ask for in so many words.
        /// </param>
        private sealed record FeedListChange(OpenedFeedList List, string DefaultNote);

        /// <summary>
        /// Applies an edit to the list on screen, saves it as the default, and shows it.
        /// </summary>
        /// <returns>Null, having said why in the status bar, when it could not be made or saved.</returns>
        private FeedListChange? ChangeFeedList(Func<byte[], byte[]> edit, string failure)
        {
            OpenedFeedList list;
            try
            {
                var content = edit(_currentFeedList?.Content ?? OpmlEditor.Empty);
                list = OpenedFeedList.Parse(content, isSaved: true);
                SavedFeedList.ForThisUser.Save(content);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException
                                           or System.Xml.XmlException or InvalidOperationException)
            {
                _viewModel.StatusMessage = $"{failure}: {ex.Message}";
                return null;
            }

            var note = _currentListIsDefault
                ? string.Empty
                : " This feed list is now your default, so it opens every time RSS Quick starts.";

            var open = OpenFolders();
            ShowFeedList(list, isDefault: true, announce: false);
            Reopen(open);

            // F5 must not bring back a feed that is no longer in the list.
            if (_currentlyLoadedFeed is { IsCategory: false } loaded
                && OpmlEditor.FindFeed(list.Document.Roots, loaded.Url) is null)
                _currentlyLoadedFeed = null;

            return new FeedListChange(list, note);
        }

        /// <summary>The names of the open folders, with the folders above them.</summary>
        /// <remarks>
        /// By name rather than by node, because a change rebuilds every node. Without this, each
        /// subscription or removal closed every folder, and a reader in a large tree lost their
        /// place. iOS keeps its open folders the same way.
        /// </remarks>
        private HashSet<string> OpenFolders()
        {
            var open = new HashSet<string>(StringComparer.Ordinal);
            void Walk(ItemsControl parent, string prefix)
            {
                for (var i = 0; i < parent.Items.Count; i++)
                {
                    if (parent.ItemContainerGenerator.ContainerFromIndex(i) is not TreeViewItem { IsExpanded: true } row
                        || row.DataContext is not FeedItem item) continue;
                    var name = prefix.Length == 0 ? item.Title : $"{prefix} / {item.Title}";
                    open.Add(name);
                    Walk(row, name);
                }
            }
            Walk(FeedTree, string.Empty);
            return open;
        }

        private void Reopen(HashSet<string> open)
        {
            void Walk(ItemsControl parent, string prefix)
            {
                parent.UpdateLayout();
                for (var i = 0; i < parent.Items.Count; i++)
                {
                    if (parent.ItemContainerGenerator.ContainerFromIndex(i) is not TreeViewItem row
                        || row.DataContext is not FeedItem { IsCategory: true } item) continue;
                    var name = prefix.Length == 0 ? item.Title : $"{prefix} / {item.Title}";
                    if (!open.Contains(name)) continue;
                    row.IsExpanded = true;
                    Walk(row, name);
                }
            }
            if (open.Count > 0) Walk(FeedTree, string.Empty);
        }

        private static FeedItem? FindByPath(IEnumerable<FeedItem> roots, IReadOnlyList<int> path)
        {
            foreach (var node in roots)
            {
                if (node.OutlinePath is { } p && p.SequenceEqual(path)) return node;
                if (FindByPath(node.Children, path) is { } found) return found;
            }
            return null;
        }

        /// <summary>
        /// Selects and focuses a node anywhere in the tree, opening the folders above it.
        /// </summary>
        /// <returns>False when it is not in the tree, or its row could not be realised.</returns>
        private bool SelectInTree(FeedItem target)
        {
            var chain = new List<FeedItem>();
            if (!PathTo(FeedTree.Items.OfType<FeedItem>(), target, chain)) return false;

            ItemsControl parent = FeedTree;
            TreeViewItem? node = null;
            foreach (var item in chain)
            {
                parent.UpdateLayout();
                node = parent.ItemContainerGenerator.ContainerFromItem(item) as TreeViewItem;
                if (node is null) return false;
                if (!ReferenceEquals(item, target)) node.IsExpanded = true;
                parent = node;
            }

            node!.IsSelected = true;
            node.BringIntoView();
            return node.Focus();

            static bool PathTo(IEnumerable<FeedItem> nodes, FeedItem wanted, List<FeedItem> path)
            {
                foreach (var n in nodes)
                {
                    path.Add(n);
                    if (ReferenceEquals(n, wanted) || PathTo(n.Children, wanted, path)) return true;
                    path.RemoveAt(path.Count - 1);
                }
                return false;
            }
        }
    }
}
