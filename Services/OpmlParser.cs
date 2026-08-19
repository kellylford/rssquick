using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Xml;
using System.Xml.Linq;

namespace RSSReaderWPF.Services
{
    /// <summary>The feed tree an OPML file describes.</summary>
    /// <param name="Roots">Top-level nodes, in the order the file listed them.</param>
    /// <param name="FeedCount">Feeds at any depth. Folders are not counted.</param>
    public sealed record OpmlDocument(IReadOnlyList<FeedItem> Roots, int FeedCount);

    /// <summary>
    /// Reads an OPML feed list into a tree.
    /// </summary>
    /// <remarks>
    /// A pure function over a string, deliberately: this used to be two methods on the window that
    /// mutated the view model as they walked, which is why none of it could be tested.
    /// </remarks>
    public static class OpmlParser
    {
        /// <summary>Name given to an outline that carries no usable label.</summary>
        private const string UnnamedOutline = "Unknown";

        /// <summary>Holds feeds the file listed at the top level, outside any folder.</summary>
        private const string UncategorizedFolder = "Uncategorized";

        /// <summary>
        /// Parses OPML content.
        /// </summary>
        /// <exception cref="System.Xml.XmlException">The content is not well-formed XML.</exception>
        /// <exception cref="InvalidOperationException">There is no OPML body element.</exception>
        public static OpmlDocument Parse(string opmlContent)
        {
            // Not XDocument.Parse, which accepts a DTD. An OPML file is user-supplied XML from
            // wherever they exported it, and entity expansion is the standard way to turn parsing
            // one into a denial of service. Feed content is already parsed under the same rule;
            // this was the one door left open.
            using var reader = XmlReader.Create(new StringReader(opmlContent), new XmlReaderSettings
            {
                DtdProcessing = DtdProcessing.Prohibit,
                XmlResolver = null,
            });

            var document = XDocument.Load(reader);

            var body = document.Descendants("body").FirstOrDefault()
                ?? throw new InvalidOperationException(
                    "This does not look like an OPML file - it has no <body> element.");

            var roots = new List<FeedItem>();
            var feedCount = ReadOutlines(body.Elements("outline"), parent: null, roots);

            return new OpmlDocument(roots, feedCount);
        }

        /// <summary>Walks one level of outlines, recursing into folders. Returns feeds added.</summary>
        private static int ReadOutlines(IEnumerable<XElement> outlines, FeedItem? parent, List<FeedItem> roots)
        {
            var feedCount = 0;

            foreach (var outline in outlines)
            {
                var title = ReadTitle(outline);
                var url = outline.Attribute("xmlUrl")?.Value;

                // An outline with a feed URL is a feed; anything else is a folder. That is how OPML
                // distinguishes them - there is no type attribute worth trusting, and plenty of
                // exporters omit the type="rss" the old docs told people to look for.
                if (!string.IsNullOrWhiteSpace(url))
                {
                    AddFeed(new FeedItem
                    {
                        Title = title,
                        Url = url,
                        Category = parent?.Title ?? UncategorizedFolder,
                        IsCategory = false,
                    }, parent, roots);

                    feedCount++;
                }
                else
                {
                    var folder = new FeedItem
                    {
                        Title = title,
                        Category = title,
                        IsCategory = true,
                    };

                    if (parent is null) roots.Add(folder);
                    else parent.Children.Add(folder);

                    feedCount += ReadOutlines(outline.Elements("outline"), folder, roots);
                }
            }

            return feedCount;
        }

        /// <summary>
        /// Puts a feed under its folder, or under "Uncategorized" when the file listed it loose.
        /// </summary>
        /// <remarks>
        /// Every feed ends up inside a folder so the tree has one shape rather than two. A mix of
        /// feeds and folders at the top level makes Enter mean different things at the same
        /// apparent level, which is exactly the sort of inconsistency that makes a tree hard to
        /// navigate without sight.
        /// </remarks>
        private static void AddFeed(FeedItem feed, FeedItem? parent, List<FeedItem> roots)
        {
            if (parent is not null)
            {
                parent.Children.Add(feed);
                return;
            }

            var uncategorized = roots.FirstOrDefault(r => r.IsCategory && r.Title == UncategorizedFolder);
            if (uncategorized is null)
            {
                uncategorized = new FeedItem { Title = UncategorizedFolder, IsCategory = true };
                roots.Add(uncategorized);
            }

            uncategorized.Children.Add(feed);
        }

        /// <summary>
        /// The label to show, preferring <c>text</c> over <c>title</c> as the OPML spec does.
        /// </summary>
        /// <remarks>
        /// Cleaned the same way headlines are. Feed names come from the same exporters and carry
        /// the same invisible characters, and they are read out just as often.
        /// </remarks>
        private static string ReadTitle(XElement outline)
        {
            var raw = outline.Attribute("text")?.Value ?? outline.Attribute("title")?.Value;

            return string.IsNullOrWhiteSpace(raw) ? UnnamedOutline : FeedText.CleanTitle(raw);
        }
    }
}
