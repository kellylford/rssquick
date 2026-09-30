using System;
using System.Threading.Tasks;
using System.Windows;
using RSSReaderWPF.Services;

namespace RSSReaderWPF
{
    /// <summary>
    /// Interaction logic for App.xaml
    /// </summary>
    public partial class App : Application
    {
        /// <summary>
        /// How long after startup to look for a newer version.
        /// </summary>
        /// <remarks>
        /// Long enough that startup has finished announcing the feed list and placing focus, so
        /// the check never competes with either for the reader's attention or the connection.
        /// </remarks>
        private static readonly TimeSpan UpdateCheckDelay = TimeSpan.FromSeconds(5);

        private readonly AppUpdater _updater;

        /// <summary>The check in progress, so Check for Updates during the startup one joins it.</summary>
        private Task<UpdateOffer?>? _checking;

        /// <param name="updater">Owned by <see cref="Program.Main"/>, which disposes it on exit.</param>
        public App(AppUpdater updater) => _updater = updater;

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            var window = new MainWindow();
            MainWindow = window;
            window.Show();

            // Windows updates a Store copy. Offering a download from GitHub as well would leave
            // the reader with two copies, and the Store does not allow it.
            if (PackageIdentity.IsPackaged)
            {
                window.UpdatedByStore = true;
                return;
            }

            // Help, Check for Updates asks the same question on demand.
            window.CheckForUpdates = () => CheckNowAsync(window);

            _ = OfferUpdateAsync(window);
        }

        /// <summary>Asks now, and tells the window about anything newer.</summary>
        private async Task<UpdateOffer?> CheckNowAsync(MainWindow window)
        {
            var offer = await CheckOnceAsync();
            if (offer is not null && window.IsLoaded) window.ShowUpdate(offer, _updater.RestartAndUpdate);
            return offer;
        }

        /// <summary>
        /// One check at a time. Two at once would have an installed copy download the same
        /// update twice, into the same place.
        /// </summary>
        private Task<UpdateOffer?> CheckOnceAsync()
        {
            if (_checking is { IsCompleted: false } running) return running;
            return _checking = _updater.CheckAsync();
        }

        /// <summary>
        /// Looks for a newer version and, if there is one, tells the window.
        /// </summary>
        /// <remarks>
        /// Here rather than in the window so that the tests, which build windows by the hundred,
        /// never reach GitHub.
        /// </remarks>
        private async Task OfferUpdateAsync(MainWindow window)
        {
            await Task.Delay(UpdateCheckDelay);

            // Back on the UI thread after each await: this started on it.
            var offer = await CheckOnceAsync();
            if (offer is null || !window.IsLoaded) return;

            window.ShowUpdate(offer, _updater.RestartAndUpdate);
        }
    }
}
