using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// The Windows "Make text bigger" setting, and what to do with the values it can hold.
/// </summary>
/// <remarks>
/// Tested through the pure conversion rather than the registry read, so it does not depend on how
/// the machine running the tests happens to be configured.
/// </remarks>
public class TextScaleTests
{
    [Theory]
    [InlineData(100, 1.0)]
    [InlineData(125, 1.25)]
    [InlineData(150, 1.5)]
    [InlineData(225, 2.25)]   // the top of the Windows slider
    public void A_scale_Windows_can_produce_is_applied(int percent, double expected) =>
        Assert.Equal(expected, TextScale.FromRegistryValue(percent));

    [Fact]
    public void No_setting_means_no_scaling() =>
        // The value is absent until the user moves the slider off 100%.
        Assert.Equal(1.0, TextScale.FromRegistryValue(null));

    [Theory]
    [InlineData(0)]
    [InlineData(50)]      // would shrink text, which this setting never does
    [InlineData(-100)]
    [InlineData(5000)]    // would make the window unusable
    public void Values_outside_what_Windows_can_set_are_ignored(int percent) =>
        Assert.Equal(1.0, TextScale.FromRegistryValue(percent));

    [Theory]
    [InlineData("150")]   // the value is a DWORD; a string means something else wrote it
    [InlineData(150L)]
    [InlineData(1.5)]
    public void A_value_of_the_wrong_type_is_ignored(object raw) =>
        Assert.Equal(1.0, TextScale.FromRegistryValue(raw));
}
