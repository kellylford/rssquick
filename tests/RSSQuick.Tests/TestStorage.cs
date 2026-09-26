using System;
using System.IO;
using System.Runtime.CompilerServices;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// Keeps the tests away from the real saved feed list.
/// </summary>
/// <remarks>
/// Every window a test builds reads the saved default at startup, and the default-list tests
/// write one. Pointed at the real %APPDATA%, the suite would open whatever list the person
/// running it had saved, and could replace it. A module initializer runs before any test, so
/// no test can forget.
/// </remarks>
internal static class TestStorage
{
    public static string Directory { get; } =
        System.IO.Directory.CreateTempSubdirectory("rssquick-tests-").FullName;

    [ModuleInitializer]
    internal static void Redirect() =>
        SavedFeedList.ForThisUser = new SavedFeedList(Path.Combine(Directory, "Default.opml"));
}
