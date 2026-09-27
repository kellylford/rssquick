using System;
using System.Net;
using System.Threading.Tasks;
using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// When a published release counts as a newer version for this copy. The macOS version answers
/// the same questions in macos/Tests/RSSQuickCoreTests/ReleaseCheckTests.swift; the two should
/// change together.
/// </summary>
public sealed class ReleaseCheckTests
{
    private const string Zip = "-portable-win-x64.zip";

    private static readonly Version Running = new(1, 2, 0);

    private static string Release(
        string tag = "v1.3.0",
        string asset = "RSSQuick-1.3.0-portable-win-x64.zip",
        bool draft = false,
        bool prerelease = false,
        string page = "https://github.com/kellylford/rssquick/releases/tag/v1.3.0") => $$"""
        {
          "tag_name": "{{tag}}",
          "html_url": "{{page}}",
          "draft": {{(draft ? "true" : "false")}},
          "prerelease": {{(prerelease ? "true" : "false")}},
          "assets": [
            { "name": "{{asset}}" },
            { "name": "RSSQuick-1.3.0-macos.dmg" }
          ]
        }
        """;

    // ── what counts as newer ────────────────────────────────────────────────

    [Fact]
    public void A_newer_release_with_a_download_for_this_copy_is_offered()
    {
        var release = ReleaseCheck.Parse(Release(), Running, Zip);

        Assert.NotNull(release);
        Assert.Equal(new Version(1, 3, 0), release.Version);
        Assert.Equal("https://github.com/kellylford/rssquick/releases/tag/v1.3.0", release.Page.AbsoluteUri);
    }

    [Fact]
    public void The_release_that_is_running_is_not_offered() =>
        Assert.Null(ReleaseCheck.Parse(Release(tag: "v1.2.0"), Running, Zip));

    [Fact]
    public void An_older_release_is_not_offered() =>
        Assert.Null(ReleaseCheck.Parse(Release(tag: "v1.1.0"), Running, Zip));

    /// <summary>
    /// The assembly says 1.2.0.0 and the tag says 1.2.0. Compared as they stand, System.Version
    /// calls the tag older, and a four-part tag would be offered to the copy it came from.
    /// </summary>
    [Fact]
    public void A_four_part_running_version_matches_its_three_part_tag()
    {
        Assert.Null(ReleaseCheck.Parse(Release(tag: "v1.2.0"), new Version(1, 2, 0, 0), Zip));
        Assert.NotNull(ReleaseCheck.Parse(Release(tag: "v1.2.1"), new Version(1, 2, 0, 0), Zip));
    }

    [Fact]
    public void Versions_compare_as_numbers_not_text() =>
        Assert.NotNull(ReleaseCheck.Parse(Release(tag: "v1.10.0"), new Version(1, 9, 0), Zip));

    [Fact]
    public void A_tag_without_a_leading_v_is_read() =>
        Assert.NotNull(ReleaseCheck.Parse(Release(tag: "1.3.0"), Running, Zip));

    // ── what does not count at all ──────────────────────────────────────────

    /// <summary>A Mac-only fix, say. Nothing on the page would be of use to this copy.</summary>
    [Fact]
    public void A_release_with_no_download_for_this_copy_is_not_offered() =>
        Assert.Null(ReleaseCheck.Parse(Release(asset: "RSSQuick-1.3.0-portable-win-arm64.zip"), Running, Zip));

    [Fact]
    public void Drafts_and_prereleases_are_not_offered()
    {
        Assert.Null(ReleaseCheck.Parse(Release(draft: true), Running, Zip));
        Assert.Null(ReleaseCheck.Parse(Release(prerelease: true), Running, Zip));
    }

    [Fact]
    public void A_tag_that_is_not_a_version_is_ignored() =>
        Assert.Null(ReleaseCheck.Parse(Release(tag: "nightly"), Running, Zip));

    [Fact]
    public void A_page_that_is_not_https_is_never_opened() =>
        Assert.Null(ReleaseCheck.Parse(Release(page: "file:///C:/Windows/System32/calc.exe"), Running, Zip));

    [Theory]
    [InlineData("")]
    [InlineData("not json")]
    [InlineData("[]")]
    [InlineData("{}")]
    [InlineData("""{ "tag_name": 13, "html_url": "https://github.com/", "assets": [] }""")]
    [InlineData("""{ "message": "API rate limit exceeded" }""")]
    public void Anything_else_is_nothing_rather_than_an_error(string json) =>
        Assert.Null(ReleaseCheck.Parse(json, Running, Zip));

    // ── over the network ────────────────────────────────────────────────────

    [Fact]
    public async Task A_release_is_read_from_the_server()
    {
        using var server = new LocalFeedServer();
        var api = server.Serve("/releases/latest", Release(), contentType: "application/json");

        var release = await ReleaseCheck.CheckAsync(api, Running, Zip, TestContext.Current.CancellationToken);

        Assert.Equal(new Version(1, 3, 0), release?.Version);
    }

    /// <summary>What GitHub answers for a repository with no published release yet.</summary>
    [Fact]
    public async Task A_server_error_is_nothing_rather_than_an_error()
    {
        using var server = new LocalFeedServer();
        var missing = server.Serve("/releases/latest", """{ "message": "Not Found" }""", HttpStatusCode.NotFound, "application/json");
        var limited = server.Serve("/limited", Release(), HttpStatusCode.Forbidden, "application/json");

        Assert.Null(await ReleaseCheck.CheckAsync(missing, Running, Zip, TestContext.Current.CancellationToken));
        Assert.Null(await ReleaseCheck.CheckAsync(limited, Running, Zip, TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task No_server_is_nothing_rather_than_an_error()
    {
        var server = new LocalFeedServer();
        var gone = server.Missing("/releases/latest");
        server.Dispose();

        Assert.Null(await ReleaseCheck.CheckAsync(gone, Running, Zip, TestContext.Current.CancellationToken));
    }
}
