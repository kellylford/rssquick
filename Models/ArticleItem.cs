using System;
using System.ComponentModel;
using System.Globalization;
using System.Linq;
using System.Runtime.CompilerServices;
using System.ServiceModel.Syndication;
using System.Xml;
using RSSReaderWPF.Services;

namespace RSSReaderWPF
{
    /// <summary>
    /// One headline, as shown in the list.
    /// </summary>
    public class ArticleItem : INotifyPropertyChanged
    {
        private string _title = string.Empty;
        private string _link = string.Empty;
        private string _summary = string.Empty;
        private string _content = string.Empty;
        private DateTimeOffset? _publishedOn;
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

        /// <summary>
        /// When the article was published, or null when the feed did not say.
        /// </summary>
        /// <remarks>
        /// Kept as a real instant rather than as text. Sorting used to run
        /// <c>DateTime.TryParse</c> over a string this class had just formatted, so an article
        /// whose formatted date failed to parse back sorted to <c>DateTime.MinValue</c> and landed
        /// at the bottom whatever its real date. The format was culture-sensitive, so which
        /// articles that happened to depended on the reader's regional settings.
        /// </remarks>
        public DateTimeOffset? PublishedOn
        {
            get => _publishedOn;
            set
            {
                _publishedOn = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(Published));
            }
        }

        /// <summary>
        /// <see cref="PublishedOn"/> for display, in the reader's own locale.
        /// </summary>
        /// <remarks>
        /// Empty when the feed gave no date. Silence is better than noise here: this string is
        /// spoken as part of every headline, and a feed with no date used to announce
        /// "0001-01-01 00:00" on each one.
        /// </remarks>
        public string Published =>
            _publishedOn is { } when
                ? when.ToLocalTime().ToString("g", CultureInfo.CurrentCulture)
                : string.Empty;

        public string Author
        {
            get => _author;
            set { _author = value; OnPropertyChanged(); }
        }

        /// <summary>
        /// The feed this article came from. Always set, including for a single-feed load, because
        /// the status bar names it and a merged folder view has no other way to say where a
        /// headline came from.
        /// </summary>
        public string FeedTitle
        {
            get => _feedTitle;
            set { _feedTitle = value; OnPropertyChanged(); }
        }

        /// <summary>
        /// The one place a syndication item becomes an <see cref="ArticleItem"/>.
        /// </summary>
        /// <remarks>
        /// Both loading paths used to build these by hand, and they drifted every time either was
        /// touched: title cleaning was applied on one path only, which is the original braille
        /// whitespace bug in DEVELOPMENT-NOTES.md, and the two later disagreed on date format and
        /// on whether Summary and Author were populated at all. Routing both through here is what
        /// stops that recurring.
        /// </remarks>
        public static ArticleItem FromSyndication(SyndicationItem item, string feedTitle)
        {
            ArgumentNullException.ThrowIfNull(item);

            return new ArticleItem
            {
                Title = FeedText.CleanTitle(item.Title?.Text),
                Link = PickLink(item),
                Summary = item.Summary?.Text ?? string.Empty,
                Content = (item.Content as TextSyndicationContent)?.Text ?? item.Summary?.Text ?? string.Empty,
                PublishedOn = PickDate(item),
                Author = item.Authors.FirstOrDefault()?.Name ?? string.Empty,
                FeedTitle = feedTitle,
            };
        }

        /// <summary>
        /// The article's own page.
        /// </summary>
        /// <remarks>
        /// Prefers the "alternate" relationship rather than taking the first link. Feeds commonly
        /// carry an enclosure — a podcast audio file, an image — ahead of the article link, and
        /// taking the first one meant Enter opened a media file instead of the story.
        /// </remarks>
        private static string PickLink(SyndicationItem item)
        {
            var alternate = item.Links.FirstOrDefault(l =>
                string.IsNullOrEmpty(l.RelationshipType) ||
                string.Equals(l.RelationshipType, "alternate", StringComparison.OrdinalIgnoreCase));

            return (alternate ?? item.Links.FirstOrDefault())?.Uri?.ToString() ?? string.Empty;
        }

        /// <summary>
        /// Publication date, falling back to the updated time, and null when the feed gave neither
        /// or gave something unreadable.
        /// </summary>
        /// <remarks>
        /// <para>Both properties return <see cref="DateTimeOffset.MinValue"/> when the element is
        /// absent, which is why they are compared rather than null-checked.</para>
        /// <para>When the element is present but malformed they do something worse: they throw
        /// <see cref="XmlException"/>, from a property getter, the first time it is read. A feed
        /// with one bad pubDate among fifty items would take the whole feed down with it. Dates
        /// are the field publishers get wrong most often, so this is not a hypothetical.</para>
        /// </remarks>
        private static DateTimeOffset? PickDate(SyndicationItem item)
        {
            var published = ReadOrIgnore(() => item.PublishDate);
            if (published > DateTimeOffset.MinValue) return published;

            var updated = ReadOrIgnore(() => item.LastUpdatedTime);
            if (updated > DateTimeOffset.MinValue) return updated;

            return null;

            static DateTimeOffset ReadOrIgnore(Func<DateTimeOffset> read)
            {
                try { return read(); }
                catch (XmlException) { return DateTimeOffset.MinValue; }
            }
        }

        public event PropertyChangedEventHandler? PropertyChanged;

        protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
