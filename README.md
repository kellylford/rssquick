# RSS Quick

A fast, accessible RSS reader for Windows. Two panels — feeds on the left, headlines on the right — built for browsing a lot of headlines quickly with a screen reader, a braille display, or just the keyboard.

Articles open in your own browser, where you already have your reading setup the way you want it.

## Download

Get the latest from the [Releases page](https://github.com/kellylford/rssquick/releases). Two packages, both of which carry their own copy of .NET — **you do not need to install anything else**.

| | Use this when |
|---|---|
| **`RSSQuick-<version>-setup-win-x64.exe`** | You want it in the Start Menu. Installs for your account only, so there is no administrator prompt. |
| **`RSSQuick-<version>-portable-win-x64.zip`** | You want to unzip and run it, including from a USB stick. Nothing is installed and nothing is written outside the folder. |

Choose **x64** for almost any PC. Choose **arm64** only for an ARM device such as a Surface Pro X or a Snapdragon laptop.

## Getting started

1. Run RSS Quick. It opens with a starter feed list already loaded, focus on the feed tree.
2. Arrow to a feed and press **Enter** to load its headlines. Focus moves to the first headline.
3. Arrow through the headlines. The status bar reports the feed name and your position, like `BBC News - 12 of 45`.
4. Press **Enter** or **Alt+B** to open the current article in your browser.

Pressing Enter on a *folder* loads every feed inside it and merges the headlines, newest first. The status bar names the feed each headline came from as you arrow through.

To use your own feeds, either replace the `RSS.opml` file next to the program, or use the **Import OPML File** button. Any OPML file exported from another reader will work.

## Keyboard

| Key | Does |
|---|---|
| **Tab** / **Shift+Tab** | Move between Import, feeds, headlines, and Open in Browser |
| **Arrow keys** | Move within the current panel |
| **Right** / **Left** | Expand / collapse a folder in the feed tree |
| **Enter** | On a feed or folder, load headlines. On a headline, open the article |
| **Alt+B** | Open the current article in your browser |
| **F5** | Reload the headlines you are reading |
| **F6** or **Ctrl+Tab** | Jump between the feed tree and the headlines list |

The tab ring is exactly four stops and wraps in both directions. Nothing lands on an empty container.

## Accessibility

This is the point of the project, not a feature of it.

- **Announcements are clean.** Headline text is stripped of zero-width characters, non-breaking and thin spaces, and control characters, all of which render as confusing blank cells on a braille display.
- **The status bar is a polite live region.** It reports loading state, article counts, and your position in the list, without interrupting.
- **Tab order is fixed and tested.** It is asserted by walking focus in the test suite, so it cannot quietly regress.
- **Focus stays where you left it.** Tab away from a headline and back, and you return to the same headline.
- **Selecting a feed never fetches anything.** Only Enter loads, so arrowing through a long feed list is silent and instant.

Found something that does not work with your setup? Please open an [accessibility issue](https://github.com/kellylford/rssquick/issues/new/choose). You do not need to work out the cause — describing what you heard, or what you could not reach, is the useful part.

## Requirements

- Windows 10 or 11 (WPF is Windows-only)
- An internet connection, for fetching feeds
- No .NET install needed for either package

## The sample feed list

`RSS.opml` ships with feeds across Global News, Technology, Science, Culture, Sports, and Accessibility. It is a starting point — edit it, replace it, or import your own.

The installer never overwrites an `RSS.opml` you have edited when you upgrade.

## Building from source

You need Windows and the [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0).

```bash
dotnet run
```

Or double-click `run.cmd`. See [HOW-TO-BUILD.md](HOW-TO-BUILD.md) for packaging, [WORKFLOW.md](WORKFLOW.md) for the release process, and [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Getting involved

Bug reports, accessibility reports, and ideas are all welcome on the [issue tracker](https://github.com/kellylford/rssquick/issues). Security issues go through [SECURITY.md](SECURITY.md) instead.

## Licence

MIT — see [LICENSE](LICENSE).
