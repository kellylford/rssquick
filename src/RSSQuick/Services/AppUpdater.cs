using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Velopack;
using Velopack.Sources;

namespace RSSReaderWPF.Services
{
    /// <summary>What the window is told about a newer version.</summary>
    /// <param name="Version">1.3.0</param>
    /// <param name="Page">The release notes.</param>
    /// <param name="ReadyToInstall">
    /// True when it has been downloaded and will be installed when RSS Quick closes. False when
    /// this copy cannot update itself, and the most it can do is say where to get it.
    /// </param>
    public sealed record UpdateOffer(string Version, Uri Page, bool ReadyToInstall);

    /// <summary>
    /// Keeps RSS Quick up to date.
    /// </summary>
    /// <remarks>
    /// <para>An installed copy updates itself through Velopack: it checks GitHub's releases,
    /// downloads a newer version in the background, and installs it when RSS Quick closes — or
    /// at once, if the reader chooses Restart and Update. Nothing is interrupted to do it.</para>
    /// <para>A portable copy cannot replace itself: it may be on a read-only share or a USB
    /// stick, and it has no installer to run. It only finds out that a newer version exists,
    /// through <see cref="ReleaseCheck"/>, and offers the download page.</para>
    /// <para>The same arrangement as QuickMail's <c>UpdateCheckService</c>, which found the
    /// problems first.</para>
    /// </remarks>
    public sealed class AppUpdater : IDisposable
    {
        public const string RepositoryUrl = "https://github.com/kellylford/rssquick";

        private readonly UpdateManager? _manager;
        private readonly CancellationTokenSource _lifetime = new();
        private UpdateInfo? _downloaded;
        private bool _restarting;
        private bool _disposed;

        /// <summary>Connects to Velopack when this copy was installed by Setup.</summary>
        /// <param name="feed">
        /// A folder or URL holding <c>vpk pack</c> output, in place of GitHub. For trying the
        /// whole download-and-install cycle without publishing a release.
        /// </param>
        public AppUpdater(string? feed = null)
        {
            try
            {
                var manager = feed is null
                    ? new UpdateManager(new GithubSource(RepositoryUrl, accessToken: null, prerelease: false))
                    : new UpdateManager(feed);
                _manager = manager.IsInstalled ? manager : null;
            }
            catch (Exception)
            {
                // Not installed by Velopack, or its files are not where it expects them. Either
                // way this copy falls back to only saying that a newer version exists.
                _manager = null;
            }
        }

        /// <summary>True when this copy was installed by Setup and can update itself.</summary>
        public bool IsInstalled => _manager is not null;

        /// <summary>The running version, three parts.</summary>
        public static Version CurrentVersion =>
            ReleaseCheck.Normalize(typeof(AppUpdater).Assembly.GetName().Version ?? new Version(0, 0, 0));

        /// <summary>
        /// Looks for a newer version and, where this copy can install it, downloads it.
        /// </summary>
        /// <returns>Null when there is nothing newer, or the question could not be answered.</returns>
        public async Task<UpdateOffer?> CheckAsync()
        {
            if (_manager is { } manager)
            {
                try
                {
                    // CheckForUpdatesAsync takes no token, so abandon the wait instead when the
                    // app closes rather than holding the process open for it.
                    var update = await manager.CheckForUpdatesAsync().WaitAsync(_lifetime.Token).ConfigureAwait(false);
                    if (update is null) return null;

                    await manager.DownloadUpdatesAsync(update, cancelToken: _lifetime.Token).ConfigureAwait(false);
                    _downloaded = update;

                    var version = update.TargetFullRelease.Version.ToString();
                    return new UpdateOffer(version, ReleasePage(version), ReadyToInstall: true);
                }
                catch (Exception)
                {
                    // A failed check or download is retried on the next launch. It is not worth
                    // telling anyone about: nothing they are doing depends on it.
                    return null;
                }
            }

            var release = await ReleaseCheck.CheckAsync(
                ReleaseCheck.LatestReleaseApi, CurrentVersion, PortableAssetSuffix, _lifetime.Token).ConfigureAwait(false);
            return release is null
                ? null
                : new UpdateOffer(release.Version.ToString(3), release.Page, ReadyToInstall: false);
        }

        /// <summary>Installs the downloaded version now and starts it again.</summary>
        /// <remarks>Does not return when it works: Velopack ends this process to replace it.</remarks>
        public void RestartAndUpdate()
        {
            if (_manager is not { } manager || _downloaded is not { } update) return;

            // Set first and never cleared. If the call throws we cannot know whether it had
            // already started the installer, and arming a second one at exit is the worse risk.
            _restarting = true;
            manager.ApplyUpdatesAndRestart(update);
        }

        /// <summary>
        /// The ZIP a portable copy on this processor would download. A release without one has
        /// nothing for this copy, so it is not offered.
        /// </summary>
        internal static string PortableAssetSuffix =>
            RuntimeInformation.ProcessArchitecture == Architecture.Arm64
                ? "-portable-win-arm64.zip"
                : "-portable-win-x64.zip";

        private static Uri ReleasePage(string version) => new($"{RepositoryUrl}/releases/tag/v{version}");

        /// <summary>
        /// Called as RSS Quick exits. A downloaded update that was not installed by Restart and
        /// Update is installed now, once this process has gone, so the next launch runs it.
        /// </summary>
        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;

            if (!_restarting && _manager is { } manager && _downloaded is { } update)
            {
                try
                {
                    manager.WaitExitThenApplyUpdates(update, silent: true, restart: false);
                }
                catch (Exception)
                {
                    // Nothing is lost: the next launch checks again.
                }
            }

            _lifetime.Cancel();
            _lifetime.Dispose();
        }
    }
}
