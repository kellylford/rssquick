using System;
using System.IO;
using System.Linq;
using System.Text;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// Which feed list opens at startup, and what saving one keeps. The macOS and iOS versions answer
/// the same questions in macos/Tests/RSSQuickCoreTests/SavedFeedListTests.swift; the two should
/// change together.
/// </summary>
public sealed class SavedFeedListTests : IDisposable
{
    private const string Mine = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline text="Mine">
              <outline text="My feed" xmlUrl="https://example.com/mine.xml" category="kept"/>
            </outline>
          </body>
        </opml>
        """;

    private const string Starter = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline text="Starter">
              <outline text="One" xmlUrl="https://example.com/one.xml"/>
              <outline text="Two" xmlUrl="https://example.com/two.xml"/>
            </outline>
          </body>
        </opml>
        """;

    private readonly DirectoryInfo _folder = Directory.CreateTempSubdirectory("rssquick-saved-");

    private SavedFeedList Saved => new(Path.Combine(_folder.FullName, "RSSQuick", "Default.opml"));

    private string WriteStarter()
    {
        var path = Path.Combine(_folder.FullName, "RSS.opml");
        File.WriteAllText(path, Starter);
        return path;
    }

    public void Dispose()
    {
        try { _folder.Delete(recursive: true); } catch (IOException) { /* best effort */ }
    }

    [Fact]
    public void With_nothing_saved_the_starter_list_opens()
    {
        var startup = StartupFeedList.Choose(Saved, WriteStarter());

        Assert.NotNull(startup.List);
        Assert.False(startup.List!.IsSaved);
        Assert.Equal(2, startup.List.Document.FeedCount);
        Assert.Null(startup.SavedListProblem);
    }

    [Fact]
    public void A_saved_list_opens_ahead_of_the_starter_list()
    {
        Saved.Save(Encoding.UTF8.GetBytes(Mine));

        var startup = StartupFeedList.Choose(Saved, WriteStarter());

        Assert.True(startup.List!.IsSaved);
        Assert.Equal("Mine", startup.List.Document.Roots.Single().Title);
        Assert.Null(startup.SavedListProblem);
    }

    [Fact]
    public void An_unreadable_saved_list_falls_back_to_the_starter_list_and_says_so()
    {
        Saved.Save(Encoding.UTF8.GetBytes("this is not OPML"));

        var startup = StartupFeedList.Choose(Saved, WriteStarter());

        Assert.False(startup.List!.IsSaved);
        Assert.Equal(2, startup.List.Document.FeedCount);
        Assert.NotNull(startup.SavedListProblem);
    }

    [Fact]
    public void An_unreadable_saved_list_is_left_for_the_reader_to_clear()
    {
        Saved.Save(Encoding.UTF8.GetBytes("this is not OPML"));

        StartupFeedList.Choose(Saved, WriteStarter());

        Assert.True(Saved.Exists);
    }

    [Fact]
    public void With_neither_list_there_is_nothing_to_show()
    {
        var startup = StartupFeedList.Choose(Saved, starterPath: null);

        Assert.Null(startup.List);
        Assert.Null(startup.SavedListProblem);
    }

    [Fact]
    public void Saving_keeps_the_exact_bytes_of_the_file()
    {
        // A byte order mark, and an attribute the parser ignores: rebuilding the file from the
        // tree would lose both.
        var original = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(Mine)).ToArray();

        Saved.Save(original);

        Assert.Equal(original, File.ReadAllBytes(Saved.Path));
    }

    [Fact]
    public void Saving_again_replaces_the_previous_default()
    {
        Saved.Save(Encoding.UTF8.GetBytes(Starter));
        Saved.Save(Encoding.UTF8.GetBytes(Mine));

        Assert.Equal(Mine, File.ReadAllText(Saved.Path));
        Assert.Single(Directory.GetFiles(Path.GetDirectoryName(Saved.Path)!));
    }

    [Fact]
    public void Forgetting_removes_the_saved_list()
    {
        Saved.Save(Encoding.UTF8.GetBytes(Mine));

        Saved.Forget();

        Assert.False(Saved.Exists);
        var startup = StartupFeedList.Choose(Saved, WriteStarter());
        Assert.False(startup.List!.IsSaved);
    }

    [Fact]
    public void Forgetting_when_nothing_is_saved_does_nothing()
    {
        Saved.Forget();

        Assert.False(Saved.Exists);
    }
}
