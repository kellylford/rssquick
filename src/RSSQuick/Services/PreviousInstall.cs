using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using Microsoft.Win32;

namespace RSSReaderWPF.Services
{
    /// <summary>
    /// Retires a copy installed by the old Inno Setup installer.
    /// </summary>
    /// <remarks>
    /// <para>Versions 1.1.0 and 1.2.0 were installed by Inno Setup into
    /// <c>%LocalAppData%\Programs\RSS Quick</c>. The Velopack installer that replaced it puts
    /// RSS Quick in <c>%LocalAppData%\RSSQuick</c> and knows nothing about the old copy, so
    /// without this a reader who installs the new version ends up with two "RSS Quick" entries in
    /// the Start Menu and Installed Apps, one of which never updates.</para>
    /// <para>Only a per-user install is retired. An all-users install is in Program Files, and
    /// removing it needs an administrator prompt nobody asked for; it is left alone.</para>
    /// </remarks>
    public static class PreviousInstall
    {
        /// <summary>Where Inno Setup registered it: the installer's fixed AppId, plus "_is1".</summary>
        internal const string UninstallKey =
            @"Software\Microsoft\Windows\CurrentVersion\Uninstall\{5E4A8895-C857-4BD4-AD08-2DD5F8CC2533}_is1";

        /// <summary>
        /// The starter list every Inno Setup release shipped, LF line endings, SHA-256.
        /// </summary>
        /// <remarks>
        /// It has not changed since the first installer (1.1.0). Kept as a hash, rather than only
        /// compared with the copy beside this program, so a later change to the starter list does
        /// not make an old, untouched one look edited.
        /// </remarks>
        private static readonly string[] ShippedStarterLists =
        [
            "619975ae4fd56d143f6372d77568b1541a88fdd42b2123cf2cde48ea7f8e7f99",
        ];

        /// <summary>The old installer's uninstaller and folder, as its registry entry records them.</summary>
        internal sealed record OldInstall(string Uninstaller, string Folder);

        /// <summary>
        /// Keeps the reader's feed list, then removes the old copy. Does nothing when there is none.
        /// </summary>
        /// <remarks>
        /// Called at every start of an installed copy rather than only the first, so an uninstall
        /// that could not run — because the old copy was open at the time — is tried again.
        /// </remarks>
        public static void Retire()
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(UninstallKey);
                if (Find(key) is not { } old) return;

                // First, and allowed to throw: if the list cannot be kept, the old copy stays.
                KeepEditedList(old, SavedFeedList.ForThisUser, Path.Join(AppContext.BaseDirectory, "RSS.opml"));

                // Not waited for. Inno's uninstaller copies itself to %TEMP% and runs from there,
                // and it needs nothing more from us.
                Process.Start(new ProcessStartInfo(old.Uninstaller, "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART")
                {
                    UseShellExecute = false,
                });
            }
            catch (Exception)
            {
                // Everything, deliberately: this runs before the window exists and again on every
                // start, so anything it let through would stop RSS Quick opening at all. Two
                // copies installed is untidy, not broken, and the next start tries again.
            }
        }

        /// <summary>Reads the old installer's registry entry.</summary>
        internal static OldInstall? Find(RegistryKey? key)
        {
            if (key?.GetValue("UninstallString") is not string command) return null;
            if (key.GetValue("InstallLocation") is not string folder) return null;

            // Inno writes the path in quotes.
            var uninstaller = command.Trim().Trim('"');
            return File.Exists(uninstaller) ? new OldInstall(uninstaller, folder) : null;
        }

        /// <summary>Beside the saved default: where an edited list goes when there already is one.</summary>
        internal const string KeptListName = "RSS-from-previous-install.opml";

        /// <summary>
        /// Keeps the old copy's feed list, if the reader had edited it.
        /// </summary>
        /// <returns>Where it was kept, or null when there was nothing to keep.</returns>
        /// <remarks>
        /// <para>The old installer deletes <c>RSS.opml</c> on uninstall whether or not it was
        /// edited, and editing it in place was how a reader kept their own list before Make This
        /// My Default existed. Without this, retiring the old copy would silently throw their list
        /// away.</para>
        /// <para>It becomes the default when there is none. When there is one, that is the list
        /// the reader chose most recently and it stays; the old one is copied beside it, where
        /// Import can open it, rather than lost.</para>
        /// </remarks>
        internal static string? KeepEditedList(OldInstall old, SavedFeedList saved, string shippedStarter)
        {
            var oldList = Path.Join(old.Folder, "RSS.opml");
            if (!File.Exists(oldList)) return null;

            var content = File.ReadAllBytes(oldList);
            var shipped = File.Exists(shippedStarter) ? File.ReadAllBytes(shippedStarter) : null;
            if (IsUntouchedStarter(content, shipped)) return null;

            if (!saved.Exists)
            {
                saved.Save(content);
                return saved.Path;
            }

            var aside = Path.Join(Path.GetDirectoryName(saved.Path)!, KeptListName);
            File.WriteAllBytes(aside, content);
            return aside;
        }

        /// <summary>
        /// True when <paramref name="list"/> is a starter list as shipped, ignoring line endings.
        /// </summary>
        internal static bool IsUntouchedStarter(byte[] list, byte[]? shippedStarter)
        {
            var normalized = WithoutCarriageReturns(list);
            if (shippedStarter is not null && normalized.SequenceEqual(WithoutCarriageReturns(shippedStarter)))
                return true;

            var hash = Convert.ToHexStringLower(SHA256.HashData(normalized));
            return ShippedStarterLists.Contains(hash);
        }

        private static byte[] WithoutCarriageReturns(byte[] bytes) =>
            bytes.Where(b => b != (byte)'\r').ToArray();
    }
}
