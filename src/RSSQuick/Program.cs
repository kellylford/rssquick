using System;
using RSSReaderWPF.Services;
using Velopack;

namespace RSSReaderWPF
{
    /// <summary>
    /// The entry point, written by hand rather than generated from App.xaml.
    /// </summary>
    /// <remarks>
    /// Velopack has to run before WPF does. When Setup installs, updates or uninstalls RSS Quick
    /// it starts this executable with its own arguments, and <c>VelopackApp.Run</c> handles them
    /// and ends the process; on an ordinary launch it returns at once. The csproj names this class
    /// as <c>StartupObject</c>, which is what makes the compiler use it rather than the
    /// <c>Main</c> WPF generates for App.
    /// </remarks>
    public static class Program
    {
        [STAThread]
        public static void Main()
        {
            VelopackApp.Build().Run();

            // Before the window reads the saved feed list, because retiring the old install can
            // put one there. Never from a Store copy: Velopack did not install it, so IsInstalled
            // is already false, but a Store app uninstalling other software must not be one
            // assumption away.
            using var updater = new AppUpdater(UpdateFeedOverride());
            if (updater.IsInstalled && !PackageIdentity.IsPackaged) PreviousInstall.Retire();

            var app = new App(updater);
            app.InitializeComponent();
            app.Run();
        }

        /// <summary>
        /// RSSQUICK_UPDATE_FEED, for trying the whole update cycle against a folder of
        /// <c>vpk pack</c> output instead of GitHub. See HOW-TO-BUILD.md.
        /// </summary>
        private static string? UpdateFeedOverride() =>
            Environment.GetEnvironmentVariable("RSSQUICK_UPDATE_FEED") is { Length: > 0 } feed ? feed : null;
    }
}
