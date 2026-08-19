namespace RSSQuick.Tests;

/// <summary>
/// Every test that builds a real <see cref="RSSReaderWPF.MainWindow"/> belongs here, so no two of
/// them run at the same time.
/// </summary>
/// <remarks>
/// <para>Loading compiled XAML is not thread-safe. <c>Application.LoadComponent</c> reads the
/// baml through <c>System.IO.Packaging</c>, whose <c>PackagePart</c> keeps an ordinary
/// <c>List&lt;T&gt;</c> of open streams and cleans it up without a lock. Two STA test threads
/// constructing a window at the same moment corrupt that list, and one of them dies with</para>
/// <code>
/// System.ArgumentOutOfRangeException: Index was out of range (Parameter 'index')
///   at System.Collections.Generic.List`1.RemoveAt(Int32)
///   at System.IO.Packaging.PackagePart.CleanUpRequestedStreamsList()
///   at System.Windows.Application.LoadComponent(Object, Uri)
/// </code>
/// <para>xunit runs test classes in parallel by default, so this became reachable the moment there
/// was more than one WPF test class. It surfaced on CI rather than locally, which is what a race
/// does. The whole suite runs in about two seconds, so serialising these costs nothing worth
/// measuring.</para>
/// <para>Any new class using <c>[WpfFact]</c> needs <c>[Collection(Name)]</c> on it.</para>
/// </remarks>
[CollectionDefinition(Name, DisableParallelization = true)]
public class WpfCollection
{
    public const string Name = "WPF windows";
}
