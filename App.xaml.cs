using System;
using System.Windows;

namespace RSSReaderWPF
{
    /// <summary>
    /// Interaction logic for App.xaml
    /// </summary>
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            
            // Set application properties for better accessibility
            this.MainWindow = new MainWindow();
            this.MainWindow.Show();
        }
    }
}
