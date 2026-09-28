# RSS Quick

A fast, accessible RSS reader for Windows and macOS, built first for people who use a screen
reader, a braille display, or only the keyboard. An iPhone and iPad version is on its way.

RSS Quick does one thing: it lets you move through a lot of headlines quickly and open the ones
you want. There are two panels — your feeds on the left, their headlines on the right — and
articles open in your own web browser, where your reading setup already is.

## What it does

- **Reads your feeds.** RSS and Atom feeds, organised in folders. It comes with a
  starter list of news, technology, science, culture, sports and accessibility feeds.
- **Loads a whole folder at once.** Press Enter on a folder and every feed in it is fetched
  together and merged into one list, newest first, with each headline naming the feed it came
  from. If a few feeds fail, you still get the rest, and the status bar tells you which failed.
- **Uses your own feed list.** Import any OPML file — the format every feed reader exports — and
  make it your default, so it opens every time RSS Quick starts.
- **Opens articles in your browser.** No built-in web view to learn; the article opens wherever
  you normally read.
- **Keeps itself up to date.** The Windows installer downloads new versions and installs them
  when you close RSS Quick. The portable Windows copy and the Mac tell you when there is one.
- **Keeps nothing about you.** No account, no tracking, no cache. Headlines are fetched fresh
  every time. The only things kept between runs are your default feed list and, on the Mac, your
  text size and window position.

## Why it is built this way

Most feed readers are designed to be looked at. RSS Quick is designed to be heard and felt:

- **Braille-clean headlines.** Invisible characters, odd spaces and control characters that
  publishers leave in titles are removed, because on a braille display they show up as confusing
  blank cells.
- **One place for news.** The status bar is the only thing that speaks up on its own — loading
  progress, how many headlines arrived, which feeds failed, and your position, such as
  `BBC News - 12 of 45`. Nothing else interrupts.
- **Focus goes where you would expect.** After a load, you are on the first headline. Tab away
  and back and you return to the headline you left. Nothing ever moves you without asking.
- **Browsing is silent.** Arrowing through the feed list fetches nothing. Only Enter loads, so
  you can move through a hundred feeds instantly.
- **Windows high contrast and text size are respected.** No fixed colours anywhere, and Windows'
  "Make text bigger" setting applies, which it does not by default in this kind of app.

All of this is checked by automated tests that drive the real window — tab order, where focus
lands, what the status bar says — so it does not quietly break.

## Download

Everything is on the [Releases page](https://github.com/kellylford/rssquick/releases).

### Windows 10 and 11

| Download | Use it when |
|---|---|
| **`RSSQuick-<version>-setup-win-x64.exe`** | You want RSS Quick in the Start Menu. Installs for your account only, so there is no administrator prompt, and keeps itself up to date. |
| **`RSSQuick-<version>-portable-win-x64.zip`** | You want to unzip and run it, from anywhere, including a USB stick. Nothing is installed. It tells you when there is a new version but does not update itself. |

Choose **x64** for almost any PC, and **arm64** only for an ARM device such as a Surface Pro X
or a Snapdragon laptop. Both carry their own copy of .NET, so there is nothing else to install.

### macOS 13 Ventura or newer

**`RSSQuick-<version>-macos.dmg`** — open it and drag RSS Quick to Applications. One download
for Apple silicon and Intel, signed and notarised by Apple, so it opens without a security
prompt.

The Mac version is a native app built for VoiceOver, not a port of the Windows one. It works the
same way, with Mac keys and a full menu bar. See [macos/README.md](macos/README.md).

### iPhone and iPad — coming soon

An iPhone and iPad version is in testing and has not yet been through Apple's App Store review,
so it is not available to download yet. It is deliberately simple: your feed list with folders,
OPML import, and articles that open in Safari inside the app. See [ios/README.md](ios/README.md).

## Getting started

1. **Open RSS Quick.** The starter feed list is already loaded, with focus in the feed tree.
2. **Arrow to a feed and press Enter.** Its headlines load and focus moves to the first one.
   Press Enter on a folder to load every feed in it.
3. **Arrow through the headlines.** The status bar says where you are.
4. **Press Enter** (or Alt+B on Windows, Command-B on the Mac) to open the article in your
   browser.

To use your own feeds, choose **Import OPML File**, then **Make This My Default** (Alt+D on
Windows, Command-D on the Mac). RSS Quick keeps its own copy of the file, so moving or deleting
the original does not matter. **Use Starter Feed List** goes back to the list RSS Quick comes
with.

## Keyboard

| Windows | Mac | Does |
|---|---|---|
| Tab / Shift+Tab | Tab / Shift-Tab | Move between the buttons, the feed tree and the headlines |
| F6 or Ctrl+Tab | F6 or Control-Tab | Jump between the feed tree and the headlines |
| — | Command-1 / Command-2 | Go straight to the feed tree or the headlines |
| Arrow keys | Arrow keys | Move within a panel; Right and Left open and close folders |
| Enter | Return | On a feed or folder, load its headlines. On a headline, open it |
| Alt+B | Command-B | Open the current headline in your browser |
| F5 | Command-R or F5 | Reload what you are reading |
| Escape | Escape or Command-. | Stop a load that is taking too long |
| Alt+D | Command-D | Make the feed list on screen your default |
| Alt+U | RSS Quick menu | Get a new version, once there is one |
| — | Command-Plus / Minus / 0 | Larger, smaller or standard text |

On Windows the tab ring is usually four stops: Import, the feed tree, the headlines and Open in
Browser. The feed list buttons and the update button join it only while they have something to
do. On the Mac every command is also in the menu bar, where VoiceOver and Help's search find
them; Command-/ lists the keys.

## Staying up to date

A few seconds after it starts, RSS Quick asks GitHub whether there is a newer version:

- **Windows, installed:** the new version downloads in the background and installs when you
  close RSS Quick. The status bar says when it is ready, and **Restart and Update** (Alt+U)
  installs it straight away if you would rather not wait.
- **Windows, portable:** the status bar says a new version is out, and **Download Update**
  (Alt+U) opens its page.
- **Mac:** the status line says so, and **Download RSS Quick \<version\>…** in the RSS Quick menu
  opens its page. **Check for Updates…** asks at any time.

None of this moves focus. If the news arrives while a feed is loading, it is read out after the
load's result rather than over it. The check sends nothing about you or your feeds.

**On 1.2.0 or earlier?** Those versions cannot update themselves, so download 1.3.0 or later
once by hand. On Windows the new version removes the old copy the first time it starts, and
keeps your feed list if you had edited the old one.

## Found a problem?

Please open an [accessibility issue](https://github.com/kellylford/rssquick/issues/new/choose)
for anything to do with a screen reader, braille display, magnifier or keyboard use. You do not
need to work out the cause — describing what you heard, or what you could not reach, is the
useful part. Bugs and ideas are welcome on the [issue tracker](https://github.com/kellylford/rssquick/issues)
too. Security issues go through [SECURITY.md](SECURITY.md).

## Building from source

The Windows version needs Windows and the [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0):

```bash
dotnet run
```

The Mac version needs macOS 13 and Swift 6; run `./run.sh` in `macos/`. The iPhone and iPad
version needs Xcode; see [ios/README.md](ios/README.md).

[HOW-TO-BUILD.md](HOW-TO-BUILD.md) covers packaging, [WORKFLOW.md](WORKFLOW.md) the release
process, and [CONTRIBUTING.md](CONTRIBUTING.md) what to know before opening a pull request.

## Licence

MIT — see [LICENSE](LICENSE).
