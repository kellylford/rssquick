# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

RSS Quick — a Windows-only WPF RSS reader (.NET 10) built accessibility-first for screen reader and braille display users. Two panels: a feed TreeView and a headlines ListBox; articles open in the system browser rather than an embedded control. No cache and no settings file — feeds come from an OPML file and content is always fetched fresh. The one thing kept between runs is the reader's saved default feed list (see Startup below). The one request that is not a feed is the check for a newer version a few seconds after startup (see Updates below).

Naming is split on purpose: the C# namespace and project file are `RSSReaderWPF`, the assembly and executable are `RSSQuick` (via `<AssemblyName>`). Keep the namespace as-is.

`docs/IMPROVEMENT-PLAN.md` is the current review of what is wrong and what to do about it, in priority order. Read it before starting substantial work — it will usually say whether the thing you are about to touch is already accounted for.

## Build and run

```bash
dotnet run
```

| Command | Does |
|---|---|
| `run.cmd` | Release build + run — the normal dev loop |
| `build.cmd [debug\|release\|test\|clean]` | Debug is the default |
| `build.cmd test` | `dotnet test tests/RSSQuick.Tests/RSSQuick.Tests.csproj` |
| `package.cmd [x64\|arm64]` | Installer + portable ZIP into `artifacts/`, and the update feed into `artifacts/releases/`, both architectures by default |

`package.cmd` wraps `build/publish.ps1`, which is PowerShell 5.1-compatible on purpose — there is no pwsh 7 on the dev machine. The installer is Velopack's Setup.exe, built by `vpk pack`; vpk is a local tool pinned in `.config/dotnet-tools.json` and restored by the script, so there is nothing to install.

Version lives in `VERSION` and nowhere else. `Directory.Build.props` reads it into the assembly version and `build/publish.ps1` reads it for artefact filenames. `build/prepare-release.ps1 <x.y.z>` is the only thing that should write it.

## Architecture

The application lives in `src/RSSQuick/`:

```
Models/         FeedItem, ArticleItem (with the FromSyndication factory)
Services/       FeedLoader, FeedText, OpmlParser, TextScale, SavedFeedList,
                ReleaseCheck, AppUpdater (Velopack), PreviousInstall
ViewModels/     MainViewModel, RelayCommand
Converters.cs   IValueConverters, exposed as static Instance singletons and
                referenced from XAML via {x:Static}
Program.cs      the entry point: Velopack first, then WPF
MainWindow.*    the window, and all the focus management
```

`MainWindow.xaml.cs` is ~800 lines and is now almost entirely focus and event handling. Everything in `Services/` is a pure function or a stateless static, which is why it is all directly tested.

Flow:

1. **Startup** — `LoadDefaultOpml()` calls `StartupFeedList.Choose()`, which opens the reader's saved default (`%APPDATA%\RSSQuick\Default.opml`) if there is a readable one, and otherwise the starter list from `FindStarterOpml()`: the working directory first (so a portable copy uses the list beside it) then `AppContext.BaseDirectory` (so a Start Menu shortcut, whose working directory is not guaranteed, still finds the installed list). The saved list must come first, because the installed build always has the shipped `RSS.opml` beside it. An unreadable saved list is reported and left in place, never deleted. Missing file is not an error; focus goes to the Import button.
2. **OPML → tree** — `OpmlParser.Parse()` walks `<outline>` elements recursively into a `FeedItem` tree. An outline with an `xmlUrl` is a feed, anything else is a folder; nesting is arbitrary depth, and feeds listed loose at the top level are gathered into an "Uncategorized" folder so every feed sits at the same kind of level.
3. **Feed → headlines** — Enter in the tree calls `LoadFeedAsync` (one feed) or `LoadAllFeedsInCategoryAsync` (a folder). Both call `BeginLoad`, which cancels whatever load was already running, then hand off to `FeedLoader`. A folder fetches six feeds at a time and reports per-feed failures rather than failing as a whole.
4. **Headline → browser** — Enter or Alt+B runs `Process.Start` on the article link.
5. **Updates** — `Program.Main` runs `VelopackApp.Build().Run()` before WPF starts (Setup launches the executable with its own arguments to install and update, and that call handles them and exits), then retires any old Inno Setup install. Five seconds after the window opens, `App.OfferUpdateAsync` asks `AppUpdater`: an installed copy checks and downloads through Velopack and installs on exit; a portable or dev copy only asks `ReleaseCheck` whether GitHub has something newer. Either way the window gets `ShowUpdate`. The check lives in App, not the window, so the tests — which build windows directly — never reach GitHub.

### Traps this codebase has already fallen into

- **The two load paths used to build articles independently** and drifted every time either was touched — title cleaning applied on one path only (the original braille bug), then differing date formats. `ArticleItem.FromSyndication` is now the only place a syndication item becomes an article. Keep it that way.
- **`SyndicationItem.PublishDate` throws from its getter** when the feed's date is malformed, rather than returning a default. `PickDate` catches it. Reading any syndication date property unguarded reintroduces "one bad entry loses the whole feed".
- **`HttpClient` reports its own timeout as `TaskCanceledException`**, which derives from `OperationCanceledException`. Every `catch (OperationCanceledException)` here is filtered on `IsCancellationRequested` for our own token, so a timeout is reported as a failure rather than swallowed as a user cancellation. Dropping that filter brings back "one slow feed kills the folder".
- **Control characters in headline text are replaced with a space, not deleted.** Tabs and newlines fall in that range and are usually separating words.
- **`System.Version` treats a missing part as less than zero**, so the assembly's 1.2.0.0 is "newer" than the tag's 1.2.0 and every copy would be offered its own release. `ReleaseCheck.Normalize` makes both three parts; compare nothing else.
- **The x64 update channel is Velopack's default `win` and must never be renamed.** Every installed x64 copy polls `releases.win.json` on GitHub; a new name strands them all on their current version, silently. ARM64 is `win-arm64`. The same rule QuickMail learned.
- **The `Velopack` package and the `vpk` tool move in lockstep**, like xunit.v3 and StaFact: the library reads what the tool writes. Dependabot's `velopack` group bumps both.

### Accessibility constraints — treat these as load-bearing

- **Neither items control is its own tab stop.** `IsTabStop="False"` on both `FeedTree` and `HeadlinesList`, plus an `ItemContainerStyle` that sets `IsTabStop="True"` on `TreeViewItem` (unlike `ListBoxItem`, it is not one by default). With `TabNavigation="Once"` each panel is a single stop that lands on an item. Setting `IsTabStop="True"` on a container reintroduces the 1.1.0 Shift+Tab bug: focus lands on a container that reports no name, value or state, and the `GotFocus` handler pushes it straight back in, so Shift+Tab appears to do nothing. `tests/RSSQuick.Tests/TabOrderTests.cs` measures this — every test there was verified to fail against the unfixed window.
- **The `GotFocus` handlers are guarded on `e.OriginalSource`.** They redirect only focus that landed on the container itself. Without the guard they run for every focus change bubbling through the panel, so each arrow-key step re-focuses the row it just left.
- `FeedText.CleanTitle()` strips zero-width characters (U+200B/C/D, U+FEFF, U+2060), normalizes exotic spaces (U+00A0, U+2009, U+202F) to plain spaces, replaces control characters with a space, and collapses whitespace. Invisible characters and stray whitespace render as confusing blank cells on a braille display. Do not bypass it for text that reaches a headline.
- Tab order is explicit and fixed: Import (0) → Make This My Default (1) → Use Starter Feed List (2) → Update (3) → FeedTree (4) → HeadlinesList (5) → Open in Browser (6). The two default-list buttons are disabled when they have nothing to do, and a disabled button leaves the tab ring; the Update button is `Collapsed` until `ShowUpdate` offers a newer version. So the ring is usually four stops. Adding a focusable control means renumbering deliberately and updating `TabOrderTests` (and `UpdateOfferTests`, which walks the ring with the Update button showing).
- **A button that disables itself must move focus first.** WPF drops keyboard focus from a control that becomes disabled and moves it nowhere. `MoveFocusOffDisabledButton()` sends it to the feed tree; `DefaultFeedListTests` fails without it.
- **Two things compete for the status bar**: what a load just did, and where you are in the list. `_keepLoadSummary` stops the selection a load makes from overwriting the summary it just wrote — without it, "3 of 20 feeds failed" is replaced by "BBC News - 1 of 45" before anyone can read it. Position takes over from the first arrow key.
- **A third thing is word of an update**, which arrives a few seconds after startup — exactly when a reader is likely to be waiting on their first feed. `ShowUpdate` holds it in `_pendingUpdateNotice` while a load runs, and `ShowArticles` appends it to the load summary, so it is neither lost nor interrupts. An update never moves focus.
- The status bar `TextBlock` is the **only** live region (`AutomationProperties.LiveSetting="Polite"`). Update `_viewModel.StatusMessage` rather than adding announcement channels. It reports position as `<feed> - <n> of <m>`, named from the article's own `FeedTitle` so merged folder views stay readable.
- Focus is managed by hand. `_isLoadingFeed` suppresses `SelectionChanged` side effects during a load, `_lastSelectedHeadlineIndex` restores the user's place on return, `_currentlyLoadedFeed` is what F5 reloads. Startup focus is set through `Dispatcher.BeginInvoke` at `ApplicationIdle` because WPF containers are not realized when the data arrives — removing that deferral breaks focus silently. After a load, `FocusSelectedHeadline()` lays out and scrolls the row into view before focusing it, which replaced a 100 ms `DispatcherTimer` that was guessing at the same thing.
- Selecting a feed does **not** load it; Enter does. Intentional, so arrow-key browsing never triggers network fetches.
- **No literal colours anywhere in the XAML.** Everything is a `DynamicResource` on a `SystemColors.*BrushKey`, so a Windows high contrast theme works and follows a live theme switch. Folders are marked out by font weight, never colour. `ThemeTests` asserts this against the live visual tree — and note that `ReadLocalValue` is useless for checking it, because content inside a `DataTemplate` records its values as `ParentTemplate` rather than `Local`; use `DependencyPropertyHelper.GetValueSource`.
- **`TextScale.Current` is applied to the window's `FontSize` in the constructor.** WPF honours display scaling through the manifest's per-monitor DPI awareness, but ignores the Accessibility "Make text bigger" setting completely. Removing that one line silently drops text-scaling support.

Key bindings are registered in `SetupKeyboardNavigation()` as `InputBindings`: F5 refresh, F6 / Ctrl+Tab cycle panels, Ctrl+1 / Ctrl+2 go to a panel, Alt+B open in browser, Alt+D make the list on screen the default, Ctrl+O import, Ctrl+Plus / Minus / 0 text size for the session, F1 the shortcuts list. They mirror the Mac's menu keys with Ctrl for Command, and `ParityTests` holds them to it. Alt+D and Alt+B are bindings rather than access keys so they can say in the status bar why they did nothing when their button is disabled. Left/Right are handled in `FeedTree_PreviewKeyDown` - Left on a feed goes to its folder, which WPF's TreeView does not do - and type-ahead in `FeedTree_PreviewTextInput`, because TreeView has none; the headlines list gets it from `TextSearch.TextPath`.

**A folder load does not report progress.** Every change to the status bar is spoken, so "3 of 20 feeds" twenty times buried the result. The Mac writes its count without announcing it; Windows has no silent way to write the status bar, so it says only when a load starts and what it found.

## Tests

`tests/RSSQuick.Tests` uses xunit.v3 with `Xunit.StaFact` for `[WpfFact]`. `FocusHarness` builds a real `MainWindow`, populates both panels with fixed items, and walks focus with `MoveFocus` — the same traversal Tab performs.

It reads focus through `FocusManager`, not `Keyboard.FocusedElement`: logical focus is what the window's `GotFocus` handlers respond to, and unlike keyboard focus it does not require the window to be foreground, which it never is under a test runner or on CI.

`global.json` selects the Microsoft.Testing.Platform runner for `dotnet test`. That is required rather than preferred — MTP 2.x, which xunit.v3 4.x pulls in, refuses to run under the VSTest target on the .NET 10 SDK. It changes the command line: pass the project with `--project`, and use `-- --report-xunit-trx` in place of `--logger trx`. VSTest spellings are silently ignored rather than failing, so a broken invocation looks like a passing run that reported nothing.

`Xunit.StaFact` and `xunit.v3` move in lockstep across majors: StaFact compiles against xunit internals, so a mismatched pair fails every `[WpfFact]` at discovery. That is why the Dependabot `test-tooling` group bumps them together — never merge one without the other.

`TestStorage` redirects `SavedFeedList.ForThisUser` to a temporary folder with a module initializer, before any test runs. Every window reads the saved list at startup, so without it the suite would open, and could overwrite, the real saved list of whoever runs it. The macOS `FocusHarness` does the same with `MainWindowController.savedFeedList`.

`LocalFeedServer` serves canned feeds on a loopback port, so tests exercise the real `FeedLoader` against a server they control rather than the internet. Use it for anything touching a load; `FeedLoaderNetworkTests` reaches real servers and stays opt-in behind `RSSQUICK_RUN_NETWORK_TESTS=1`.

`FocusHarness.PressEnterOnFeed` raises a real routed `KeyDown`, and `PumpUntil` runs the dispatcher until a load's continuations have arrived — a load is started and never awaited, so a test cannot simply await it.

Do not write a test that drives the single-feed failure path: it puts up a modal `MessageBox` that blocks the dispatcher. Test failure handling through a folder, which reports into the status bar instead.

Test classes that build a `MainWindow` must carry `[Collection(WpfCollection.Name)]`. Loading compiled XAML is not thread-safe — `PackagePart` tidies its stream list without a lock — so two STA test threads constructing a window at once corrupt it and one dies inside `Application.LoadComponent`. That collection disables parallelisation; without it the suite fails intermittently, and it will pass locally while failing on CI.

`Directory.Build.props` keeps `bin/**;obj/**` out of the default globs. It has to live there rather than in a csproj, because the SDK computes default items before the project body is evaluated, and WPF's XAML wpftmp project otherwise double-counts every generated `.g.cs` — which breaks Dependabot's clean-clone build even though ordinary builds survive it.

## Packaging

Both artefacts are **self-contained single-file** builds, so neither needs .NET installed. That is deliberate: "app won't start, missing .NET Runtime" was the dominant support problem with the framework-dependent packages this replaced. The cost is ~55 MB per artefact.

The installer is Velopack's, and it is what makes an installed copy update itself. `build/publish.ps1` runs `vpk pack` over the same single-file build the portable ZIP holds, installing per-user into `%LocalAppData%\RSSQuick` (no UAC prompt, and no prompt to update either), and renames Setup.exe to the `RSSQuick-<version>-setup-win-<arch>.exe` pattern the Inno Setup installer used. The update feed — `.nupkg` packages plus `releases.*.json`, `assets.*.json` and `RELEASES*` for both channels — goes on the GitHub release alongside the downloads; `release.yml` lists each file with `fail_on_unmatched_files`, so a change in what vpk writes fails the release rather than publishing one installed copies cannot read. It also runs `vpk download github` first, so each release carries a delta against the last.

**Code signing** is Azure Artifact Signing, the same account (`kellylford`) and certificate profile (`kellyford-public`) as QuickMail, on `v*` tags only. There is no certificate in the repository or in a secret: the release job runs in the `azure-signing` environment, `azure/login` trades its OIDC token for Azure credentials (the federated credential trusts the subject `repo:kellylford/rssquick:environment:azure-signing`), and the signing tools use that session. The job runs `publish.ps1 -Step Publish`, signs `RSSQuick.exe` in `artifacts/staging` with `azure/artifact-signing-action`, then `-Step Package -AzureSignFile`, where vpk signs Setup, the updater and its launcher stub, and skips the program because it is already signed. Signing between the steps is what gets a signed program into the portable ZIP. A last step fails the release if any downloadable `.exe`, the program inside either ZIP, or any program inside a full update package is not validly signed. Never add protection rules to the `azure-signing` environment; it exists only to match the OIDC subject.

Installed copies read the feed from the latest *published* release. `release.yml` makes a draft, so nothing updates until a person has checked the build and published it.

Velopack replaces the whole program folder on update, so the `RSS.opml` beside the executable is always the shipped one; a reader's own list lives in `Default.opml`. Versions 1.1.0 and 1.2.0 were installed by Inno Setup, and `PreviousInstall.Retire` removes that copy on every start of an installed copy until it is gone — first keeping its `RSS.opml` if it was edited (as `Default.opml` when nothing is saved yet, otherwise beside it as `RSS-from-previous-install.opml`), because Inno's uninstaller deletes it. An all-users Inno install is left alone: removing it would need an administrator prompt.

`RSSQUICK_UPDATE_FEED` points an installed copy at a folder of `vpk pack` output instead of GitHub; HOW-TO-BUILD.md has the steps for trying an update end to end.

## The macOS port

`macos/` is a native AppKit version, sharing `RSS.opml` and the behaviour but none of the code —
there is no .NET in it. It is a Swift package with no Xcode project: `./build.sh test` runs its
116 tests, `./run.sh` builds and launches it, and `build/make-app.sh` assembles the bundle. It
reads `VERSION` from the repository root like everything else.

`./build.sh dist` is the release: `build/release.sh` runs the tests, builds the universal app,
then signs, notarises and staples both the app and the disk image it goes out in. The app is
notarised separately from the image on purpose — the image's ticket stops Gatekeeper warning
about the download, the app's ticket keeps it valid once the reader has dragged it out of the
image and deleted it, with no network to ask Apple over. There are no entitlements, and that is
a decision rather than an omission: one Swift binary with no nested libraries, no plugins and no
sandbox needs no exemptions from the hardened runtime. That is also why the Mac does not update
itself: Sparkle would bring a nested framework and XPC services into the bundle. It checks
GitHub at launch with `ReleaseCheck` (the Swift twin of the Windows one) and says so, and the
RSS Quick menu has Check for Updates…, retitled Download RSS Quick <version>… once one is known. `.github/workflows/macos-release.yml`
runs the same scripts on a tag. `macos/README.md` has the credentials and the CI secrets.

Read `macos/README.md` before touching it. The accessibility decisions were re-made for
VoiceOver rather than translated, and four of them differ from the Windows rules above on
purpose — the announcement channel is a notification rather than a live region, position is
written to the status line but deliberately *not* announced, a headline row names its feed only
after a folder load, and text size is remembered between runs. The `keepLoadSummary` invariant
needs one more guard there than here, because focus arriving at the list is a second chance to
overwrite the summary; the tests caught that.

## One feature set, three versions

**Every feature is built for Windows, macOS and iOS in the same piece of work.** The three share
behaviour, not code, so parity is kept by discipline: a feature that lands on one platform and is
"to do" on the others is how they drift. Where a platform must differ — a VoiceOver convention, a
menu bar instead of a button — say so in that platform's README rather than leaving the gap
unexplained.

The pattern that makes this cheap: put the logic in `Services/` on Windows and in
`macos/Sources/RSSQuickCore` for both Apple platforms, keep the two side by side in shape and
name, and give them matching tests that point at each other. `SavedFeedList` is the example —
`src/RSSQuick/Services/SavedFeedList.cs` and `macos/Sources/RSSQuickCore/SavedFeedList.swift`, with
`SavedFeedListTests` on each side asking the same questions. Each window is then only the button
or menu item and where focus goes.

CI proves all three on every pull request: `ci.yml` builds and tests Windows, and `apple-ci.yml`
runs `swift test` for macOS and a simulator build of iOS (unsigned, no secrets — the pattern from
Scores' `ios-build-check.yml`). The Windows dev machine has no Swift toolchain, so for Swift
written there, `apple-ci.yml` is the first compiler to see it.

All four jobs — `build-and-test`, `analyze` (CodeQL), `macOS tests` and `iOS build` — are required
checks on `main`, and auto-merge is on, so a pull request lands by itself once they pass. That is
why `apple-ci.yml` has no paths filter: a required check a filter skips never reports, and the
pull request waits forever. Renaming a job means updating the branch protection to match.

## The iOS version

`ios/` is a SwiftUI app for iPhone and iPad. It is kept simple on purpose: a folder tree, OPML
import, and headlines that open in an in-app Safari view. It has no parser of its own:
`ios/project.yml` compiles `macos/Sources/RSSQuickCore` directly into the app, so a change there
affects both Apple platforms and is tested by `macos/Tests`. The project is generated by XcodeGen,
and the `.xcodeproj` is committed as well, the same arrangement Scores uses. Run `xcodegen` in
`ios/` after editing `project.yml` — and after adding a file to `RSSQuickCore`, because the committed
project lists every source file and a new one is otherwise missing from the iOS build. A `v*` tag also runs
`.github/workflows/ios-release.yml`, which builds on a GitHub Mac, uploads with the next unused build
number, and sends the build to the external "Public Testers" TestFlight group for Beta App Review,
so all three platforms ship the same version. `ios/scripts/asc.py` does the App Store Connect side,
and `ios-testflight-status.yml` reports it read-only - use that rather than guessing what Apple has.
`ios/scripts/release-testflight.sh <build>` still uploads from the Mac by hand. Read `ios/README.md` first: it lists where iOS deliberately differs from
the desktop versions, and it has the one-time App Store Connect setup.

## Historical context

`DEVELOPMENT-NOTES.md` is a record of the original 3-panel → 2-panel rework. It is history, not current documentation: it describes build scripts that no longer exist. The parts still worth reading are the braille whitespace investigation and the screen reader design principles.
