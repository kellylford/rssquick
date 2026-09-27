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

        /// <param name="updater">Owned by <see cref="Program.Main"/>, which disposes it on exit.</param>
        public App(AppUpdater updater) => _updater = updater;

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            var window = new MainWindow();
            MainWindow = window;
            window.Show();

            _ = OfferUpdateAsync(window);
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
            var offer = await _updater.CheckAsync();
            if (offer is null || !window.IsLoaded) return;

            window.ShowUpdate(offer, _updater.RestartAndUpdate);
        }
    }
}
