using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace RSSReaderWPF
{
    /// <summary>
    /// A node in the feed tree: either a feed, or a folder holding more of them.
    /// </summary>
    public class FeedItem : INotifyPropertyChanged
    {
        private string _title = string.Empty;
        private string _url = string.Empty;
        private string _category = string.Empty;
        private bool _isCategory;

        public string Title
        {
            get => _title;
            set { _title = value; OnPropertyChanged(); }
        }

        /// <summary>The feed URL. Empty for a folder.</summary>
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

        /// <summary>True for a folder, which loads every feed beneath it rather than one.</summary>
        public bool IsCategory
        {
            get => _isCategory;
            set { _isCategory = value; OnPropertyChanged(); }
        }

        public ObservableCollection<FeedItem> Children { get; } = new();

        /// <summary>
        /// Where this node's <c>&lt;outline&gt;</c> sits in the OPML file: its index among its
        /// parent's outlines, at each level down from <c>&lt;body&gt;</c>.
        /// </summary>
        /// <remarks>
        /// Null for the "Uncategorized" folder the parser makes up for loose feeds, which has no
        /// element of its own - adding to it adds at the top level. This is what lets
        /// <see cref="Services.OpmlEditor"/> change the file the tree came from rather than
        /// rebuilding one from the tree and losing whatever the parser does not read.
        /// </remarks>
        public IReadOnlyList<int>? OutlinePath { get; init; }

        public event PropertyChangedEventHandler? PropertyChanged;

        protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
