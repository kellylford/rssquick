# RSS Quick for macOS

A native AppKit port of RSS Quick, built to the same brief as the Windows original: a two-panel
RSS reader for screen reader and braille display users, with no persistent storage, no cache, and
articles opened in the system browser rather than in an embedded view.

It shares the Windows build's `RSS.opml` and its behaviour, not its code — there is no .NET here.
Everything is Swift, and the accessibility decisions have been re-made for VoiceOver rather than
translated from UI Automation, because several of them do not carry over.

## Build and run

```bash
./run.sh
```

| Command | Does |
|---|---|
| `./run.sh` | Debug build + launch — the normal development loop |
| `./build.sh [debug\|release\|test\|clean]` | Debug is the default |
| `./build.sh test` | `swift test` — 84 tests |
| `./build.sh release` | Universal (arm64 + x86_64) `artifacts/RSS Quick.app` |
| `./build.sh dist` | Signed, notarised, stapled `artifacts/RSSQuick-<version>-macos.dmg` |

### From Finder

If you would rather not use a terminal, double-click one of these in the `macos` folder:

| File | Does |
|---|---|
| `Run RSS Quick.command` | Builds and launches it |
| `Build RSS Quick (Release).command` | Builds `artifacts/RSS Quick.app` |
| `Run the Tests.command` | Runs the tests |

They are `.command` files rather than `.sh` because that is the extension Finder runs on a
double-click — a `.sh` opens in an editor instead. Each one opens a Terminal window, reports
whether it worked, and waits for Return before closing, so the output is still there to read.
The first time you open one macOS may ask you to confirm; the shell scripts they call are the
same ones above.

There is no Xcode project, on purpose: this is a Swift package, so the whole build is a
`Package.swift` and one shell script you can read in a sitting. `build/make-app.sh` does the part
an Xcode project would otherwise do — the `Info.plist`, the bundle layout, and copying `RSS.opml`
in beside the program. The bundle is ad-hoc signed so it will open locally; shipping it to anyone
else needs a Developer ID and notarisation, which is what `./build.sh dist` does — see
*Signing and release* below.

Version comes from `VERSION` at the repository root, the same file the Windows build reads.
Requires macOS 13 and a Swift 6 toolchain.

## Signing and release

`./build.sh dist` produces the artefact that goes to other people: a signed, notarised and
stapled disk image in `artifacts/`. It runs the tests, builds the universal app, signs it,
notarises it, builds the image, signs and notarises that, and verifies the result. Any step
failing ends the run with nothing to publish, which is the intent — a half-signed build is worse
than none, because it looks finished.

Why this matters more here than on a normal app: without notarisation macOS tells the reader the
app cannot be opened safely and sends them to System Settings to allow it. Talking a VoiceOver
user through a Gatekeeper override is not an acceptable first-run experience for a program whose
whole purpose is being easy to use without sight.

### What you need, once

Both come from a paid Apple Developer membership.

**A Developer ID Application certificate** in your keychain. Check with:

```bash
security find-identity -v -p codesigning
```

It is the entry reading `Developer ID Application: <name> (<team id>)`. `sign.sh` picks the first
such identity on its own; set `RSSQUICK_SIGNING_IDENTITY` to the full string to choose between
several.

**An App Store Connect API key** for notarisation, created under Users and Access → Integrations
→ App Store Connect API with the Developer role. It gives you three things: a downloadable
`AuthKey_XXXXXXXXXX.p8` (once only — Apple will not offer it again), a 10-character Key ID, and
an Issuer ID. Keep the `.p8` outside the repository.

```bash
export NOTARY_KEY_PATH=~/keys/AuthKey_XXXXXXXXXX.p8
export NOTARY_KEY_ID=XXXXXXXXXX
export NOTARY_ISSUER_ID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
```

These variable names are the ones `GHManage/scripts/notarize_macos.sh` uses, so one set of
exports covers both projects. A `notarytool` keychain profile works too — set `NOTARY_PROFILE`
instead — but the key is the form that also works unattended in CI.

### Running it

```bash
./build.sh dist                 # the real thing, 5–30 minutes
./build.sh dist --no-notarize   # signing only, to check the certificate works
./build.sh dist --no-test       # skip the tests, to retry a failed notarisation
```

Most of the time is Apple's: each submission takes two to fifteen minutes, and there are two of
them.

### Why two notarisation round trips

The app is notarised and stapled, and then the image is notarised and stapled. Each ticket
answers a different question.

The image's ticket is what stops Gatekeeper warning about the download. The app's ticket is what
keeps it valid *after* the reader has dragged it to Applications and thrown the image away —
stapling writes Apple's verdict into the bundle, so it no longer has to be asked for over the
network. Skip it and the first launch on a machine with no connection, or behind a firewall that
blocks Apple's endpoints, reports an app that cannot be verified. The extra ten minutes buys the
offline case.

### Checking the result

```bash
spctl --assess --type open --context context:primary-signature -v artifacts/RSSQuick-*.dmg
xcrun stapler validate artifacts/RSSQuick-*.dmg
```

`--context context:primary-signature` is the part people leave off. Without it `spctl` assesses
the image as something to execute rather than something that was downloaded, and reports a
rejection that says nothing about what the reader's Mac will actually do.

The test that matters more than any of these is opening the image on a Mac that has never run
RSS Quick, with VoiceOver on, and confirming there is no security prompt anywhere in it.

### In CI

`.github/workflows/macos-release.yml` runs the same scripts on a `macos-15` runner, on a `v*` tag
or on demand, and attaches the image to the same draft release the Windows job uses. It needs
five repository secrets:

| Secret | Is |
|---|---|
| `MACOS_CERTIFICATE_P12` | The Developer ID certificate and key, exported as a `.p12` and base64-encoded |
| `MACOS_CERTIFICATE_PASSWORD` | The password set when exporting that `.p12` |
| `NOTARY_KEY_P8` | The `AuthKey_XXXXXXXXXX.p8`, base64-encoded |
| `NOTARY_KEY_ID` | The 10-character Key ID |
| `NOTARY_ISSUER_ID` | The Issuer ID |

`MACOS_SIGNING_IDENTITY` is optional and only needed if the certificate has to be chosen by name.

Export the `.p12` from Keychain Access by selecting the *private key* under the certificate —
exporting the certificate alone produces a file with no key in it, which imports without
complaint and then fails at the first `codesign`. Base64-encode both files with
`base64 -i <file> | pbcopy`.

The workflow imports the certificate into a throwaway keychain whose password it generates
itself, and deletes that keychain in an `always()` step, so a cancelled run does not leave the
signing key behind on a runner that may be reused.


## Keyboard

| Key | Does |
|---|---|
| Tab / Shift-Tab | Import button → feed tree → headlines → Open in Browser |
| F6, Control-Tab | Switch between the two panels |
| Command-1 / Command-2 | Go straight to the feed tree or the headlines |
| Arrow keys | Move within a panel; Left and Right collapse and expand folders |
| Type a few letters | Jump to a feed or a headline by name |
| Return | On a feed, load it. On a folder, load every feed under it. On a headline, open it. |
| Command-B | Open the selected headline in the browser |
| Command-R, F5 | Reload what is on screen |
| Escape, Command-. | Stop a load that is taking too long |
| Command-Plus / Minus / 0 | Larger, smaller, standard text |
| Command-O | Import a different OPML file |
| Command-/ | The list above, in a window |

Selecting a feed never fetches anything. Only Return does — so arrow-key browsing of a hundred
and ninety feeds never touches the network.

## Architecture

```
Sources/RSSQuickCore/     Pure functions and value types. No AppKit.
  FeedText, FeedDate, XMLSafety, ErrorText
  FeedItem, ArticleItem
  OpmlParser, FeedParser, FeedLoader
Sources/RSSQuickUI/       The window, the menus, and all the focus management.
Sources/rssquick/         Ten lines that start the application.
Sources/RSSQuickTestSupport/  A loopback HTTP server and the sample feeds.
```

The executable is a thin shell so a test can build the real window without launching an
application — the same reasoning behind the Windows `FocusHarness`, and the reason focus
behaviour here is tested rather than eyeballed.

`RSSQuickCore` builds under Swift 6 language mode with full concurrency checking. The UI is Swift
5 mode: AppKit delegate conformances are not worth the annotations.

### What replaced what

| Windows | macOS |
|---|---|
| `TreeView` | `NSOutlineView` |
| `ListBox` | `NSTableView`, view-based, automatic row heights |
| Status bar with `LiveSetting="Polite"` | `NSAccessibility.post(.announcementRequested)` |
| `TabIndex` | An explicit `nextKeyView` ring, with `autorecalculatesKeyViewLoop` off |
| `System.ServiceModel.Syndication` | `FeedParser`, a hand-written reader over `XMLParser` |
| `HttpClient` + `SemaphoreSlim` | `URLSession` + a `TaskGroup` capped at six |
| `CancellationTokenSource` | `Task` cancellation |
| Registry text scale | A remembered setting in the View menu |
| `SystemColors.*BrushKey` | `NSColor.labelColor` and friends |

`System.ServiceModel.Syndication` has no counterpart on this platform, so `FeedParser` is new
code: RSS 2.0, Atom and RSS 1.0 over RDF, with a date reader that returns nil rather than
throwing. It is the largest single piece of this port and the most thoroughly tested.

## Accessibility decisions — treat these as load-bearing

Most of the Windows constraints carry straight across. These are the ones that changed, and why.

- **The announcement channel is not a live region.** AppKit has no live-region attribute, so the
  status line posts `.announcementRequested` at medium (polite) priority. Everything still goes
  through one place — `setStatus` — rather than growing a second channel.

- **Position is written but not announced.** The Windows status bar announces
  `<feed> - <n> of <m>` on every arrow key. VoiceOver already says "3 of 45" for a table row on
  its own, so announcing it again makes every keystroke speak twice. The status line still shows
  it; only the announcement is suppressed. Load results, failures and focus moves are announced,
  because VoiceOver has no other way to know them.

- **`keepLoadSummary` is still needed, and needs one more guard than Windows.** The status line
  is still written by both the load and the selection the load causes. On this side focus
  arriving at the list is a *second* chance to overwrite it, through `becomeFirstResponder`, so
  both `tableViewSelectionDidChange` and `reportHeadlinesFocus` are guarded. The tests caught
  this; without the second guard, "3 of 20 feeds failed" disappears before it can be read.

- **After a folder load, a row names its feed; after a single feed, it does not.** A merged
  folder of twenty publishers is unusable if you cannot hear whose headline you are on, and
  repeating the same feed name on every row of a single-feed load is noise. The title comes
  first either way, so the braille line starts with the headline.

- **A headline row is one accessibility element, not two.** A braille display shows one line per
  element, and a row reporting as "title" then "12/03/2026, 09:14" costs a line to scrub past on
  every headline. The date is the help text.

- **There is no container/row focus trap to guard against.** The Windows `GotFocus` handlers have
  to check `e.OriginalSource` because the container and its rows are separate focus targets. Here
  the view is the only responder, so `becomeFirstResponder` runs once, on the way in.

- **Tab reaching the buttons depends on the reader's settings, not on this code.** macOS only
  puts buttons in the key view loop when Keyboard Navigation is on in System Settings. The ring
  is defined regardless, and every command also has a menu item with a shortcut — which is why
  the menu bar is not decoration here. It is how a Mac application is expected to be driven, and
  how VoiceOver and Help's search find commands.

- **No literal colours anywhere**, and `ThemeTests` walks the live view tree to prove it —
  including realised table rows, which is where the Windows equivalent went vacuous twice.
  Folders are marked out by weight alone.

- **Text size is the one thing remembered between runs.** macOS ignores its own accessibility
  text size for ordinary views just as WPF ignores the Windows one, so it is the reader's own
  setting here, in the View menu. A low-vision reader re-enlarging the text on every launch is a
  poor trade for the Windows build's tidiness about storage. Window position is remembered too,
  which is standard macOS behaviour.

## Tests

`swift test` — 84 tests, no network.

`LocalFeedServer` serves canned feeds on a loopback port, so the real `FeedLoader` runs against a
server the test controls. Nothing in the application grew an interface to make this possible.

`FocusHarness` builds the real `MainWindowController`, points it at that server, and presses a
real `Return` key event on a tree row. A load is started and never awaited by the window, so the
harness awaits `loadTask` directly.

Things worth knowing before adding tests here:

- **`FocusHarness.make()` is async and settles the run loop first.** The window defers its
  startup focus to the next turn of the run loop, because its views are not laid out during
  construction. A test that acts before that has happened races it, and the deferred block lands
  in the middle of the assertions. Three tests failed this way before the factory existed.
- **Focus is read through `window.firstResponder`**, which does not require the window to be
  on screen — the harness orders it to the back so a test run does not take over the display.
- **Tab order is asserted on the `nextKeyView` chain, not by calling `selectNextKeyView`.**
  Whether Tab reaches a button depends on the developer's System Settings, and a test whose
  answer depends on that is worth nothing.
- **Do not write a test that drives the single-feed failure path.** It puts up a sheet. Test
  failure handling through a folder, which reports into the status line instead — the same
  guidance as on the Windows side.
- Both UI suites are `.serialized`: they share the main actor and a window each.

## Not carried over

- No installer. `build.sh release` produces `RSS Quick.app`; there is no `.dmg` or notarised
  build yet, which is what shipping this to anyone else would need.
- No application icon.
- The Windows build's per-monitor DPI manifest has no counterpart — AppKit handles display
  scaling without being asked.
