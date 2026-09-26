using System;
using System.IO;
using System.Text;

namespace RSSReaderWPF.Services
{
    /// <summary>
    /// The feed list the reader chose to open every time RSS Quick starts.
    /// </summary>
    /// <remarks>
    /// <para>The one thing RSS Quick keeps between runs. It is a copy of the file, not a note of
    /// where the file was, so moving or deleting the original does not break startup — and it is
    /// what the macOS and iOS versions do as well, where iOS has no choice: a file picked from
    /// Files is only lent to the app for the moment it was picked.</para>
    /// <para>The copy is the file's exact bytes, never a list rebuilt from the tree, so nothing
    /// the parser does not understand is lost by saving it.</para>
    /// </remarks>
    public sealed class SavedFeedList
    {
        public SavedFeedList(string path) => Path = path;

        /// <summary>Where the copy lives.</summary>
        public string Path { get; }

        /// <summary>%APPDATA%\RSSQuick\Default.opml</summary>
        public static string DefaultPath => System.IO.Path.Join(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "RSSQuick", "Default.opml");

        /// <summary>
        /// The copy the window uses.
        /// </summary>
        /// <remarks>
        /// Settable so the tests can point it at a temporary folder. Without that, every test
        /// that builds a window would read — and could overwrite — the real saved list of
        /// whoever runs the suite.
        /// </remarks>
        public static SavedFeedList ForThisUser { get; set; } = new(DefaultPath);

        public bool Exists => File.Exists(Path);

        /// <summary>The saved bytes, or null when nothing has been saved.</summary>
        /// <exception cref="IOException">A list was saved but cannot be read.</exception>
        public byte[]? Load() => Exists ? File.ReadAllBytes(Path) : null;

        /// <summary>Replaces the saved list.</summary>
        /// <remarks>
        /// Written beside the old copy and then moved over it, so a failure part way through
        /// leaves the previous default intact rather than half a file.
        /// </remarks>
        public void Save(byte[] content)
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
            var temporary = Path + ".saving";
            try
            {
                File.WriteAllBytes(temporary, content);
                File.Move(temporary, Path, overwrite: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Rethrown for the caller to report. This only stops a failed save leaving a
                // half-written file beside the real one.
                if (File.Exists(temporary)) File.Delete(temporary);
                throw;
            }
        }

        /// <summary>Removes the saved list, so the starter list opens next time.</summary>
        public void Forget()
        {
            if (Exists) File.Delete(Path);
        }
    }

    /// <summary>A feed list as it was opened: the tree, and the bytes it came from.</summary>
    /// <param name="Content">Kept so the list on screen can be saved exactly as it was read.</param>
    /// <param name="IsSaved">True when this is the reader's saved default.</param>
    public sealed record OpenedFeedList(OpmlDocument Document, byte[] Content, bool IsSaved)
    {
        /// <summary>Reads OPML from a file's bytes, the way File.ReadAllText would decode them.</summary>
        public static OpenedFeedList Parse(byte[] content, bool isSaved)
        {
            using var reader = new StreamReader(new MemoryStream(content), Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
            return new OpenedFeedList(OpmlParser.Parse(reader.ReadToEnd()), content, isSaved);
        }
    }

    /// <summary>What to show at startup.</summary>
    /// <param name="List">Null when there is nothing to show.</param>
    /// <param name="SavedListProblem">
    /// Set when a saved list exists but could not be used, so the reader can be told why they are
    /// looking at the starter list instead of their own.
    /// </param>
    public sealed record StartupFeedList(OpenedFeedList? List, string? SavedListProblem)
    {
        /// <summary>
        /// The saved list if there is a usable one, otherwise the starter list.
        /// </summary>
        /// <remarks>
        /// The saved list has to come first: the installed build always has the shipped RSS.opml
        /// beside it, so anything that looked there first would never reach the reader's own.
        /// A saved list that cannot be read is left where it is rather than deleted. It is the
        /// reader's, and Use Starter Feed List is there for them to clear it deliberately.
        /// </remarks>
        /// <param name="starterPath">The shipped or portable RSS.opml, or null when there is none.</param>
        public static StartupFeedList Choose(SavedFeedList saved, string? starterPath)
        {
            string? problem = null;
            try
            {
                if (saved.Load() is { } content) return new(OpenedFeedList.Parse(content, isSaved: true), null);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException
                                           or System.Xml.XmlException or InvalidOperationException)
            {
                problem = $"Your default feed list could not be read ({ex.Message})";
            }

            if (starterPath is null) return new(null, problem);

            // A starter list that will not parse is reported by the caller exactly as it was before
            // there was such a thing as a saved list - unless the saved list failed first, in which
            // case that has to survive into the message too, or the reader never learns their own
            // list was the first thing to go wrong.
            try
            {
                return new(OpenedFeedList.Parse(File.ReadAllBytes(starterPath), isSaved: false), problem);
            }
            catch (Exception ex) when (problem is not null && (ex is IOException or UnauthorizedAccessException
                                           or System.Xml.XmlException or InvalidOperationException))
            {
                throw new InvalidOperationException(
                    $"{problem}, and the starter feed list could not be read either ({ex.Message})", ex);
            }
        }
    }
}
