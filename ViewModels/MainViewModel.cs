using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace RSSReaderWPF
{
    /// <summary>
    /// What the window binds to: the feed tree, the headlines, and what the status bar says.
    /// </summary>
    public class MainViewModel : INotifyPropertyChanged
    {
        private string _statusMessage = "Ready - Import an OPML file or select a feed from the default list";
        private ArticleItem? _selectedArticle;
        private FeedItem? _selectedFeed;

        public ObservableCollection<FeedItem> FeedCategories { get; } = new();
        public ObservableCollection<ArticleItem> Headlines { get; } = new();

        /// <summary>
        /// The status bar text.
        /// </summary>
        /// <remarks>
        /// The only live region in the window (<c>AutomationProperties.LiveSetting="Polite"</c>),
        /// so this is the single channel by which anything is announced without the user asking.
        /// Everything that wants to tell the user something goes through here rather than adding
        /// another one.
        /// </remarks>
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
}
