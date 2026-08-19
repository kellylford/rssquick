using System;
using System.IO;
using System.Windows.Controls;
using RSSReaderWPF;

namespace RSSQuick.Tests;

/// <summary>
/// What the window has done by the time it is on screen.
/// </summary>
public class StartupTests
{
    [WpfFact]
    public void The_shipped_feed_list_is_loaded_at_startup()
    {
        var window = new MainWindow();
        try
        {
            window.Show();
            var tree = (TreeView)window.FindName("FeedTree")!;

            Assert.NotEmpty(tree.Items);
        }
        finally
        {
            window.Close();
        }
    }

    /// <summary>
    /// The installed build used to open with an empty tree: it looked for RSS.opml in the working
    /// directory only, and a Start Menu shortcut does not reliably set one to the install folder.
    /// </summary>
    [WpfFact]
    public void The_feed_list_is_found_beside_the_executable_when_the_working_directory_has_none()
    {
        var elsewhere = Directory.CreateTempSubdirectory("rssquick-cwd-");
        var original = Directory.GetCurrentDirectory();

        Assert.False(
            File.Exists(Path.Combine(elsewhere.FullName, "RSS.opml")),
            "The temporary directory is supposed to be the case where the working directory has no feed list.");

        MainWindow? window = null;
        try
        {
            Directory.SetCurrentDirectory(elsewhere.FullName);

            window = new MainWindow();
            window.Show();
            var tree = (TreeView)window.FindName("FeedTree")!;

            Assert.NotEmpty(tree.Items);
        }
        finally
        {
            Directory.SetCurrentDirectory(original);
            window?.Close();
            try { elsewhere.Delete(recursive: true); } catch (IOException) { /* best effort */ }
        }
    }
}
