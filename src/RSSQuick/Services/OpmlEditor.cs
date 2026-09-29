using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml;
using System.Xml.Linq;

namespace RSSReaderWPF.Services
{
    /// <summary>A folder a new feed can go into.</summary>
    /// <param name="Name">The folder's name with the folders above it, "News / Wires".</param>
    /// <param name="Path">
    /// The folder's <see cref="FeedItem.OutlinePath"/>. Null for the top level, which the tree
    /// shows as "Uncategorized".
    /// </param>
    public sealed record FolderChoice(string Name, IReadOnlyList<int>? Path)
    {
        /// <summary>The name alone.</summary>
        /// <remarks>
        /// Load-bearing: WPF names a list item for a screen reader by its ToString, and a record's
        /// is every field - so the Folder list in Subscribe to Feed read each folder out as
        /// "FolderChoice { Name = News, Path = System.Int32[] }".
        /// </remarks>
        public override string ToString() => Name;
    }

    /// <summary>
    /// Adds feeds to an OPML file and takes them out again.
    /// </summary>
    /// <remarks>
    /// <para>Edits the file's own XML rather than writing a new file from the tree, for the reason
    /// <see cref="SavedFeedList"/> keeps exact bytes: everything the parser does not read - a
    /// <c>htmlUrl</c>, a <c>category</c>, the head, another program's attributes - survives a
    /// subscription. The tree finds its way back to the XML through
    /// <see cref="FeedItem.OutlinePath"/>.</para>
    /// <para>The macOS and iOS versions are <c>macos/Sources/RSSQuickCore/OpmlEditor.swift</c>, and
    /// their tests ask the same questions as <c>OpmlEditorTests</c>.</para>
    /// </remarks>
    public static class OpmlEditor
    {
        /// <summary>A feed list with nothing in it, for subscribing when there is no list at all.</summary>
        public static byte[] Empty { get; } = Encoding.UTF8.GetBytes("""
            <?xml version="1.0" encoding="utf-8"?>
            <opml version="2.0">
              <head>
                <title>RSS Quick feeds</title>
              </head>
              <body />
            </opml>
            """);

        /// <summary>
        /// Adds a feed to the end of a folder, or to the top level when <paramref name="folderPath"/> is null.
        /// </summary>
        /// <returns>The whole file, changed.</returns>
        /// <exception cref="XmlException">The content is not well-formed XML.</exception>
        /// <exception cref="InvalidOperationException">No body, or no outline at the path.</exception>
        public static byte[] AddFeed(byte[] content, IReadOnlyList<int>? folderPath, string title, string url)
        {
            var document = Load(content);
            var parent = folderPath is null ? Body(document) : Find(document, folderPath);

            parent.Add(new XElement("outline",
                new XAttribute("text", title),
                new XAttribute("title", title),
                new XAttribute("type", "rss"),
                new XAttribute("xmlUrl", url)));

            return Save(document);
        }

        /// <summary>Takes out the outline at <paramref name="path"/>, and anything inside it.</summary>
        /// <returns>The whole file, changed.</returns>
        /// <exception cref="InvalidOperationException">No body, or no outline at the path.</exception>
        public static byte[] Remove(byte[] content, IReadOnlyList<int> path)
        {
            var document = Load(content);
            Find(document, path).Remove();
            return Save(document);
        }

        /// <summary>
        /// Every folder in the tree, in reading order, and the top level.
        /// </summary>
        /// <remarks>
        /// The top level is named "Uncategorized" because that is where the tree shows a feed added
        /// there. It sits where the tree shows it when the file has loose feeds already, and last
        /// otherwise, so the list reads in the same order as the tree.
        /// </remarks>
        public static IReadOnlyList<FolderChoice> Folders(IEnumerable<FeedItem> roots)
        {
            var choices = new List<FolderChoice>();
            var sawTopLevel = false;

            void Walk(IEnumerable<FeedItem> nodes, string prefix)
            {
                foreach (var node in nodes.Where(n => n.IsCategory))
                {
                    var name = prefix.Length == 0 ? node.Title : $"{prefix} / {node.Title}";
                    choices.Add(new FolderChoice(name, node.OutlinePath));
                    if (node.OutlinePath is null) sawTopLevel = true;
                    Walk(node.Children, name);
                }
            }

            Walk(roots, string.Empty);
            if (!sawTopLevel) choices.Add(new FolderChoice(OpmlParser.UncategorizedFolder, null));
            return choices;
        }

        /// <summary>The folder a feed or folder is in, or itself when it is a folder.</summary>
        /// <returns>
        /// The choice from <paramref name="choices"/> to start a subscription in, so it goes where
        /// the reader already is. The top level when nothing is selected.
        /// </returns>
        public static FolderChoice Suggest(IReadOnlyList<FolderChoice> choices, IEnumerable<FeedItem> roots, FeedItem? selected)
        {
            var folder = selected switch
            {
                null => null,
                { IsCategory: true } => selected,
                _ => ParentOf(roots, selected),
            };

            return choices.FirstOrDefault(c => folder is not null && SamePath(c.Path, folder.OutlinePath))
                ?? choices.First(c => c.Path is null);
        }

        /// <summary>The first feed in the tree with this address, or null.</summary>
        /// <remarks>
        /// Compared as addresses, ignoring case and a trailing slash, so pasting the same feed
        /// again is caught rather than giving the reader two copies of every headline.
        /// </remarks>
        public static FeedItem? FindFeed(IEnumerable<FeedItem> roots, string url)
        {
            foreach (var node in roots)
            {
                if (!node.IsCategory && SameAddress(node.Url, url)) return node;
                if (FindFeed(node.Children, url) is { } found) return found;
            }
            return null;
        }

        /// <summary>The folder directly holding <paramref name="child"/>, or null at the top level.</summary>
        public static FeedItem? ParentOf(IEnumerable<FeedItem> roots, FeedItem child)
        {
            foreach (var node in roots)
            {
                if (node.Children.Contains(child)) return node;
                if (ParentOf(node.Children, child) is { } found) return found;
            }
            return null;
        }

        private static bool SameAddress(string a, string b) =>
            string.Equals(a.Trim().TrimEnd('/'), b.Trim().TrimEnd('/'), StringComparison.OrdinalIgnoreCase);

        private static bool SamePath(IReadOnlyList<int>? a, IReadOnlyList<int>? b) =>
            a is null ? b is null : b is not null && a.SequenceEqual(b);

        private static XDocument Load(byte[] content)
        {
            // The same rule as the parser: a DTD in a feed list is refused, never expanded.
            using var text = new StreamReader(new MemoryStream(content), Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
            using var reader = XmlReader.Create(text, new XmlReaderSettings
            {
                DtdProcessing = DtdProcessing.Prohibit,
                XmlResolver = null,
            });
            return XDocument.Load(reader);
        }

        private static XElement Body(XDocument document) =>
            document.Descendants("body").FirstOrDefault()
            ?? throw new InvalidOperationException("This does not look like an OPML file - it has no <body> element.");

        private static XElement Find(XDocument document, IReadOnlyList<int> path)
        {
            var element = Body(document);
            foreach (var index in path)
            {
                element = element.Elements("outline").ElementAtOrDefault(index)
                    ?? throw new InvalidOperationException("The feed list has changed since it was read. Open it again and retry.");
            }
            return element;
        }

        private static byte[] Save(XDocument document)
        {
            using var stream = new MemoryStream();
            using (var writer = XmlWriter.Create(stream, new XmlWriterSettings
            {
                Encoding = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false),
                Indent = true,
            }))
            {
                document.Save(writer);
            }
            return stream.ToArray();
        }
    }
}
