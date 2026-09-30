using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using RSSReaderWPF;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// A Microsoft Store copy is updated by Windows, so it must never look for a newer version
/// itself - and must still say, when asked, how it stays current. docs/STORE-PLAN.md, part 1.
/// </summary>
[Collection(WpfCollection.Name)]
public class StoreCopyTests
{
    private static string Status(FocusHarness ui) => ((TextBlock)ui.Window.FindName("StatusText")!).Text;

    private static void CheckForUpdates(FocusHarness ui)
    {
        var item = (MenuItem)ui.Window.FindName("UpdateMenuItem")!;
        item.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent, item));
        ui.Drain();
    }

    [Fact]
    public void The_test_runner_is_not_a_package()
    {
        Assert.False(PackageIdentity.IsPackaged);
    }

    [WpfFact]
    public void Check_for_updates_in_a_store_copy_says_windows_updates_it()
    {
        using var ui = new FocusHarness();
        ui.Window.UpdatedByStore = true;
        ui.Window.CheckForUpdates = () =>
        {
            Assert.Fail("A Store copy must not look for updates itself.");
            return Task.FromResult<UpdateOffer?>(null);
        };

        CheckForUpdates(ui);

        var version = AppUpdater.CurrentVersion.ToString(3);
        Assert.Equal(
            $"Windows keeps this copy of RSS Quick up to date through the Microsoft Store. This is version {version}",
            Status(ui));
    }

    [WpfFact]
    public void Check_for_updates_elsewhere_still_asks()
    {
        using var ui = new FocusHarness();
        var asked = false;
        ui.Window.CheckForUpdates = () =>
        {
            asked = true;
            return Task.FromResult<UpdateOffer?>(null);
        };

        CheckForUpdates(ui);

        Assert.True(asked);
    }

    [WpfFact]
    public void About_names_the_store_only_for_a_store_copy()
    {
        using var ui = new FocusHarness();
        Assert.DoesNotContain("Microsoft Store", ui.Window.AboutText);

        ui.Window.UpdatedByStore = true;

        Assert.Contains("Installed from the Microsoft Store.", ui.Window.AboutText);
    }
}
