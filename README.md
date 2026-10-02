# RSS Quick

A fast, accessible RSS reader for Windows and macOS, built first for people who use a screen
reader, a braille display, or only the keyboard. An iPhone and iPad version is in public testing through TestFlight.

RSS Quick does one thing: it lets you move through a lot of headlines quickly and open the ones
you want. There are two panels, your feeds on the left and their headlines on the right, and
articles open in your own web browser, where your reading setup already is.

## What it does

- **Reads your feeds.** RSS and Atom feeds, organised in folders. It comes with a starter list
  of news, business, technology, science, health, culture, sports and accessibility feeds.
- **Loads a whole folder at once.** Press Enter on a folder and every feed in it is fetched
  together and merged into one list, newest first. As you move through it, RSS Quick tells you
  which feed each headline came from. If a few feeds fail, you still get the rest, and you are
  told which ones failed.
- **Uses your own feed list.** Import any OPML file, the format every feed reader exports, and
  make it your default, so it opens every time RSS Quick starts.
- **Opens articles in your browser.** There is no built-in web view to learn; the article opens
  wherever you normally read.
- **Keeps itself up to date.** The Windows installer downloads new versions and installs them
  when you close RSS Quick. The portable Windows copy and the Mac tell you when there is one.
- **Keeps nothing about you.** No account, no tracking, no cache. Headlines are fetched fresh
  every time. The only things kept between runs are your default feed list and, on the Mac, your
  text size and window position.

## Why it is built this way

Most feed readers are designed to be looked at. RSS Quick is designed to be heard and felt.

- **Braille-clean headlines.** Invisible characters, odd spaces and control characters that
  publishers leave in titles are removed, because on a braille display they show up as confusing
  blank cells.
- **One voice.** Only the status bar speaks up on its own: loading progress, how many headlines
  arrived, and which feeds failed. On Windows it also gives your position, such as "BBC News - 12
  of 45". On the Mac, VoiceOver already says "12 of 45" for each row, so RSS Quick does not say
  it again.
- **Focus goes where you would expect.** When the headlines you asked for arrive, you are on the
  first one. Tab away and back and you return to the headline you left. Nothing moves you unless
  you asked for it.
- **Browsing is silent.** Arrowing through the feed list fetches nothing. Only Enter loads, so
  you can move through a hundred feeds instantly.
- **Your display settings are respected.** There are no fixed colours anywhere, so Windows high
  contrast themes work, and Windows' "Make text bigger" setting applies. Ctrl+Plus and Ctrl+Minus
  make the text larger or smaller on top of that until RSS Quick closes. On the Mac, text size
  is set in the View menu and remembered.

All of this is checked by automated tests that drive the real window, covering tab order, where
focus lands and what the status bar says, so it does not quietly break.

## Download

Everything is on the [Releases page](https://github.com/kellylford/rssquick/releases). Each
release also carries files ending in `.nupkg` and `.json` and a file called `RELEASES`; those
are for installed copies to update themselves, and you do not need them.

### Windows 10 and 11

- **The installer**, `RSSQuick-<version>-setup-win-x64.exe`: puts RSS Quick in the Start Menu,
  installs for your account only so there is no administrator prompt, and keeps itself up to
  date.
- **The portable copy**, `RSSQuick-<version>-portable-win-x64.zip`: unzip it and run
  `RSSQuick.exe` from anywhere, including a USB stick. Nothing is installed. It tells you when
  there is a new version but does not update itself. A default feed list you save is kept on the
  computer, in your Windows profile, not on the stick.

Choose the file ending in **x64** for almost any PC, and the one ending in **arm64** only for an
ARM device such as a Surface Pro X or a Snapdragon laptop. Both carry their own copy of .NET, so
there is nothing else to install.

The Windows downloads are code-signed, so Windows knows who they come from. A newly signed
program can still be unfamiliar to Windows for a while; if it says "Windows protected your PC",
activate the **More info** link, then the **Run anyway** button that appears.

### macOS 13 Ventura or newer

`RSSQuick-<version>-macos.dmg`: open it and drag RSS Quick to Applications. One download works
on Apple silicon and Intel Macs. It is signed and notarised by Apple, so there is nothing to
allow in System Settings; the first time you open it, macOS asks once whether you want to open
an app downloaded from the internet.

The Mac version is a native app built for VoiceOver, not a port of the Windows one. It works the
same way, with Mac keys and a full menu bar. See the [macOS notes](macos/README.md).

### iPhone and iPad

An iPhone and iPad version is in public testing and is not yet on the App Store. To try it,
install Apple's TestFlight app, then open the [RSS Quick TestFlight invitation](https://testflight.apple.com/join/6g7MFbHq)
on your iPhone or iPad. It is deliberately simple: your feed list with folders, OPML import, and
articles that open in Safari inside the app. It needs iOS 17 or newer. See the [iPhone and iPad notes](ios/README.md).

## Getting started

1. **Open RSS Quick.** The starter feed list is already loaded, with focus in the feed tree.
2. **Arrow to a feed and press Enter.** Its headlines load and focus moves to the first one.
   Press Enter on a folder to load every feed in it.
3. **Arrow through the headlines.**
4. **Press Enter** to open the article in your browser.

To use your own feeds, import an OPML file and make it your default. On Windows these are the
**Import OPML File** and **Make This My Default** buttons. On the Mac they are **Import OPML
File** and **Make This My Default Feed List** in the File menu. RSS Quick keeps its own copy of
the file, so moving or deleting the original does not matter. **Use Starter Feed List** goes back
to the list RSS Quick comes with.

### Your own feeds

- **Subscribe to Feed** adds a feed by its address, or by its website's address: RSS Quick finds
  the feed the site links to. Choose the folder it goes in; it starts as the folder you are in.
  On Windows it is Ctrl+N or the File menu, on the Mac Command-N or the File menu, and on iPhone
  and iPad the Feed List menu.
- **Remove Feed** takes the selected feed out: Delete in the Windows feed tree, Command-Delete on
  the Mac, or a swipe (the Remove action, with VoiceOver) on iPhone and iPad.
- **Export Feed List** saves your list as an OPML file for another reader or another computer.

Subscribing or removing saves the list as your default straight away, so a change is never lost
when RSS Quick closes. If the list on screen was one you had imported, it becomes your default,
and RSS Quick says so.

### Searching

**Search All Feeds** (**/** or Ctrl+F on Windows, **/** or Command-F on the Mac, the Search All
Feeds button, shown as a magnifying glass, on iPhone and iPad) fetches every feed in your list and shows the headlines containing all
the words you type, in the headline or in the feed's name, ignoring case and accents. "bbc storm"
finds the BBC's storm stories. RSS Quick keeps no copy of any feed, so a search fetches them all,
the way loading a folder does; Escape stops it, and F5 runs it again.

An update replaces the starter list that comes with RSS Quick, so if you want to change it, save
your changes as your own default rather than editing the file in place.

## Keyboard

### Windows

- **Alt** or **F10**: the menu bar - File, Edit, Article, View and Help, the same menus as the
  Mac. Every command is there, with its key.
- **Tab** and **Shift+Tab**: move between the buttons, the feed tree and the headlines.
- **F6** or **Ctrl+Tab**: jump between the feed tree and the headlines.
- **Ctrl+1** and **Ctrl+2**: go straight to the feed tree or the headlines.
- **Arrow keys**: move within a panel. Right and Left open and close folders; Left on a feed
  goes to its folder.
- **Type a few letters**: jump to a feed or headline by name.
- **Enter**: on a feed or folder, load its headlines. On a headline, open it.
- **Alt+B**: open the current headline in your browser.
- **/** or **Ctrl+F**: search the headlines of every feed.
- **F5**: reload what you are reading, or run the search again.
- **Escape**: stop a load or a search that is taking too long.
- **Ctrl+N**: subscribe to a feed.
- **Delete**: in the feed tree, remove the selected feed.
- **Ctrl+E**: export your feed list.
- **Ctrl+O**: import an OPML file.
- **Alt+D**: make the feed list on screen your default.
- **Ctrl+Plus**, **Ctrl+Minus** and **Ctrl+0**: larger, smaller or your usual text, until RSS
  Quick closes.
- **Alt+U**: get a new version, once there is one.
- **F1**: show this list in a window.

The tab ring is usually just the Import button, the feed tree and the headlines. Other buttons
join it only while they have something to do: Open in Browser once a headline is selected, the
two feed list buttons when there is something to save or undo, and the update button when there
is a new version.

### Mac

- **Tab** and **Shift-Tab**: move between the feed tree and the headlines. They reach the
  buttons too if Keyboard Navigation is turned on in System Settings.
- **F6** or **Control-Tab**: jump between the feed tree and the headlines.
- **Command-1** and **Command-2**: go straight to the feed tree or the headlines.
- **Arrow keys**: move within a panel. Right and Left open and close folders.
- **Type a few letters**: jump to a feed or headline by name.
- **Return**: on a feed or folder, load its headlines. On a headline, open it.
- **Command-B**: open the current headline in your browser.
- **/** or **Command-F**: search the headlines of every feed.
- **Command-R** or **F5**: reload what you are reading, or run the search again.
- **Escape** or **Command-Period**: stop a load or a search that is taking too long.
- **Command-N**: subscribe to a feed.
- **Command-Delete**: remove the feed selected in the tree.
- **Command-E**: export your feed list.
- **Command-O**: import an OPML file.
- **Command-D**: make the feed list on screen your default.
- **Command-Plus**, **Command-Minus** and **Command-0**: larger, smaller or standard text.
- **Command-Slash**: show this list in a window.

Every command is also in the menu bar, where VoiceOver and Help's search can find it.

## Staying up to date

A few seconds after it starts, RSS Quick asks GitHub whether there is a newer version.

- **Windows, installed:** the new version downloads in the background and installs when you
  close RSS Quick. The status bar says when it is ready, and the **Restart and Update** button
  (Alt+U) installs it straight away if you would rather not wait.
- **Windows, portable:** the status bar says a new version is out, and the **Download Update**
  button (Alt+U) opens its page.
- **Mac:** the status line says a new version is out. In the RSS Quick menu, **Check for
  Updates** asks at any time; once there is a new version it becomes **Download RSS Quick**
  followed by the version number, which opens its page.

None of this moves focus. If the news arrives while a feed is loading, it is read out after the
load's result rather than over it. The check sends nothing about you or your feeds.

**Have an older copy?** Earlier versions cannot update themselves, so download the current version
once by hand. On Windows, installing it removes the old installed copy. If you had edited the old
copy's feed list, it is kept: it becomes your default, or, if you already have one, it is saved
beside it as `RSS-from-previous-install.opml` for you to import. An old copy that was installed
for all users, in Program Files, is left for you to remove from Installed Apps.

## Found a problem?

Please open an [accessibility issue](https://github.com/kellylford/rssquick/issues/new/choose)
for anything to do with a screen reader, braille display, magnifier or keyboard use. You do not
need to work out the cause; describing what you heard, or what you could not reach, is the
useful part. Bugs and ideas are welcome on the [issue tracker](https://github.com/kellylford/rssquick/issues)
too. Security issues go through the [security policy](SECURITY.md).

## Building from source

The Windows version needs Windows and the [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0):

```bash
dotnet run
```

The Mac version needs macOS 13 and Swift 6; run `./run.sh` in the `macos` folder. The iPhone and
iPad version needs Xcode; see the [iPhone and iPad notes](ios/README.md).

[HOW-TO-BUILD.md](HOW-TO-BUILD.md) covers packaging, [WORKFLOW.md](WORKFLOW.md) the release
process, and [CONTRIBUTING.md](CONTRIBUTING.md) what to know before opening a pull request.

## Licence

MIT. See the [licence](LICENSE).
