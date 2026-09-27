using System;
using System.IO;
using System.Text;
using Microsoft.Win32;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// Retiring a copy installed by the old Inno Setup installer, without losing the feed list its
/// reader may have edited in place.
/// </summary>
public sealed class PreviousInstallTests : IDisposable
{
    private const string Edited = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline text="Mine">
              <outline text="My feed" xmlUrl="https://example.com/mine.xml"/>
            </outline>
          </body>
        </opml>
        """;

    private readonly DirectoryInfo _folder = Directory.CreateTempSubdirectory("rssquick-previous-");

    /// <summary>A throwaway registry key per test, standing in for the Uninstall entry.</summary>
    private readonly string _keyPath = $@"Software\RSSQuickTests-{Guid.NewGuid():N}";

    private string OldFolder => Directory.CreateDirectory(Path.Join(_folder.FullName, "Programs", "RSS Quick")).FullName;

    private SavedFeedList Saved => new(Path.Join(_folder.FullName, "AppData", "Default.opml"));

    /// <summary>The starter list this build ships, read from the repository.</summary>
    private static readonly string Starter = Path.Join(AppContext.BaseDirectory, "RSS.opml");

    private PreviousInstall.OldInstall OldInstallWith(string? list)
    {
        var folder = OldFolder;
        var uninstaller = Path.Join(folder, "unins000.exe");
        File.WriteAllText(uninstaller, "");
        if (list is not null) File.WriteAllText(Path.Join(folder, "RSS.opml"), list);
        return new PreviousInstall.OldInstall(uninstaller, folder + Path.DirectorySeparatorChar);
    }

    // ── finding it ──────────────────────────────────────────────────────────

    [Fact]
    public void The_old_install_is_read_from_its_uninstall_entry()
    {
        var old = OldInstallWith(list: null);
        using (var key = Registry.CurrentUser.CreateSubKey(_keyPath))
        {
            // Quoted, the way Inno Setup writes it.
            key.SetValue("UninstallString", $"\"{old.Uninstaller}\"");
            key.SetValue("InstallLocation", old.Folder);
        }

        using var read = Registry.CurrentUser.OpenSubKey(_keyPath);
        var found = PreviousInstall.Find(read);

        Assert.Equal(old, found);
    }

    [Fact]
    public void No_uninstall_entry_is_no_old_install() =>
        Assert.Null(PreviousInstall.Find(null));

    /// <summary>Left behind by an uninstall that removed the files but not the entry.</summary>
    [Fact]
    public void An_entry_whose_uninstaller_is_gone_is_no_old_install()
    {
        using (var key = Registry.CurrentUser.CreateSubKey(_keyPath))
        {
            key.SetValue("UninstallString", $"\"{Path.Join(_folder.FullName, "gone", "unins000.exe")}\"");
            key.SetValue("InstallLocation", _folder.FullName);
        }

        using var read = Registry.CurrentUser.OpenSubKey(_keyPath);
        Assert.Null(PreviousInstall.Find(read));
    }

    // ── keeping the reader's list ───────────────────────────────────────────

    [Fact]
    public void An_edited_list_becomes_the_default()
    {
        var old = OldInstallWith(Edited);

        Assert.True(PreviousInstall.KeepEditedList(old, Saved, Starter));

        Assert.Equal(Edited, File.ReadAllText(Saved.Path));
    }

    [Fact]
    public void The_starter_list_as_shipped_is_not_kept()
    {
        var old = OldInstallWith(File.ReadAllText(Starter));

        Assert.False(PreviousInstall.KeepEditedList(old, Saved, Starter));
        Assert.False(Saved.Exists);
    }

    /// <summary>
    /// A later release may change the starter list. The one 1.1.0 and 1.2.0 installed must still
    /// be recognised as untouched, or every reader who never edited it would be pinned to it.
    /// </summary>
    [Fact]
    public void The_starter_list_an_old_installer_shipped_is_recognised_without_the_current_one()
    {
        var shipped = File.ReadAllBytes(Starter);

        Assert.True(PreviousInstall.IsUntouchedStarter(shipped, shippedStarter: null));
    }

    [Fact]
    public void Line_endings_alone_do_not_make_a_list_edited()
    {
        var withCrLf = Encoding.UTF8.GetBytes(File.ReadAllText(Starter).ReplaceLineEndings("\r\n"));

        Assert.True(PreviousInstall.IsUntouchedStarter(withCrLf, shippedStarter: null));
    }

    [Fact]
    public void A_default_the_reader_already_saved_is_not_replaced()
    {
        var old = OldInstallWith(Edited);
        Saved.Save(Encoding.UTF8.GetBytes("<opml/>"));

        Assert.False(PreviousInstall.KeepEditedList(old, Saved, Starter));

        Assert.Equal("<opml/>", File.ReadAllText(Saved.Path));
    }

    [Fact]
    public void No_list_in_the_old_folder_is_nothing_to_keep()
    {
        var old = OldInstallWith(list: null);

        Assert.False(PreviousInstall.KeepEditedList(old, Saved, Starter));
        Assert.False(Saved.Exists);
    }

    public void Dispose()
    {
        Registry.CurrentUser.DeleteSubKeyTree(_keyPath, throwOnMissingSubKey: false);
        _folder.Delete(recursive: true);
    }
}
