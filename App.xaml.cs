using System;
using System.Threading;
using System.Windows;

namespace RSSReaderWPF
{
    /// <summary>
    /// Interaction logic for App.xaml
    /// </summary>
    public partial class App : Application
    {
        /// <summary>
        /// Held for the lifetime of the process purely so the installer can tell whether RSS Quick
        /// is running. Inno Setup's AppMutex directive checks for this name and asks the user to
        /// close the app rather than failing partway through on a locked executable.
        /// </summary>
        /// <remarks>
        /// Deliberately not used to enforce a single instance. Two copies running at once is
        /// harmless here, and an installed copy should not stop a portable one on a USB stick.
        /// </remarks>
        private Mutex? _runningMarker;

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            _runningMarker = new Mutex(initiallyOwned: false, name: "RSSQuick.SingleInstance");

            MainWindow = new MainWindow();
            MainWindow.Show();
        }

        protected override void OnExit(ExitEventArgs e)
        {
            _runningMarker?.Dispose();
            _runningMarker = null;
            base.OnExit(e);
        }
    }
}
