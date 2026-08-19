using RSSReaderWPF.Services;

namespace RSSQuick.Tests;

/// <summary>
/// Headline text cleaning - the project's oldest invariant, and until now the least covered.
/// </summary>
/// <remarks>
/// Every character here shows nothing on screen but occupies a cell on a braille display, so a
/// title that looks fine reads as a run of blanks. They are written as escapes rather than pasted
/// in literally: a test for invisible characters whose inputs are themselves invisible in the
/// source is one careless editor save away from silently testing nothing.
/// </remarks>
public class FeedTextTests
{
    [Theory]
    [InlineData("\u200BBreaking news", "Breaking news")]      // zero-width space
    [InlineData("Breaking\u200Cnews", "Breakingnews")]        // zero-width non-joiner
    [InlineData("Breaking\u200Dnews", "Breakingnews")]        // zero-width joiner
    [InlineData("\uFEFFBreaking news", "Breaking news")]      // byte order mark
    [InlineData("Breaking\u2060news", "Breakingnews")]        // word joiner
    public void Invisible_characters_are_removed(string input, string expected) =>
        Assert.Equal(expected, FeedText.CleanTitle(input));

    [Theory]
    [InlineData("Breaking\u00A0news", "Breaking news")]       // non-breaking space
    [InlineData("Breaking\u2009news", "Breaking news")]       // thin space
    [InlineData("Breaking\u202Fnews", "Breaking news")]       // narrow no-break space
    public void Exotic_spaces_become_ordinary_ones(string input, string expected) =>
        Assert.Equal(expected, FeedText.CleanTitle(input));

    [Fact]
    public void Runs_of_whitespace_collapse_to_one_space() =>
        // The shape of the original bug: a title arriving with a block of leading whitespace,
        // which a braille reader had to scrub past before reaching a word.
        Assert.Equal(
            "Lions GM Brad Holmes on the draft",
            FeedText.CleanTitle("   Lions GM\t\tBrad Holmes \r\n on the   draft  "));

    [Fact]
    public void Control_characters_are_removed() =>
        Assert.Equal("Breaking news", FeedText.CleanTitle("Breaking\u0007 news"));

    [Fact]
    public void A_control_character_between_words_does_not_run_them_together() =>
        // It stood in for a separator, so deleting it outright lost the word boundary.
        Assert.Equal("Breaking news", FeedText.CleanTitle("Breaking\u0007news"));

    [Fact]
    public void A_title_made_only_of_invisible_characters_does_not_come_back_empty() =>
        // An empty headline is a row a screen reader announces as nothing at all, which reads as
        // a fault in the reader rather than in the feed.
        Assert.Equal("No Title", FeedText.CleanTitle("\u200B\u200C\uFEFF   "));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public void Missing_titles_get_a_placeholder(string? input) =>
        Assert.Equal("No Title", FeedText.CleanTitle(input));

    [Fact]
    public void Ordinary_text_is_left_alone() =>
        Assert.Equal("Ordinary headline: 50% off", FeedText.CleanTitle("Ordinary headline: 50% off"));
}
