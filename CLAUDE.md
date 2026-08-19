# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

RSS Quick — a Windows-only WPF RSS reader (.NET 10) built accessibility-first for screen reader and braille display users. Two panels: a feed TreeView and a headlines ListBox; articles open in the system browser rather than an embedded control. No persistent storage, no cache, no settings file — feeds come from an OPML file and content is always fetched fresh.

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
| `package.cmd [x64\|arm64]` | Installer + portable ZIP into `artifacts/`, both architectures by default |

`package.cmd` wraps `build/publish.ps1`, which is PowerShell 5.1-compatible on purpose — there is no pwsh 7 on the dev machine. The installer half needs Inno Setup 6; without it the script warns and still produces the portable ZIP.

Version lives in `VERSION` and nowhere else. `Directory.Build.props` reads it into the assembly version and `build/publish.ps1` reads it for artefact filenames. `build/prepare-release.ps1 <x.y.z>` is the only thing that should write it.

## Architecture

`Models/` holds `FeedItem` and `ArticleItem`. `Services/` holds `FeedLoader` (fetching and parsing) and `FeedText` (headline cleaning). `Converters.cs` holds `IValueConverter`s exposed as static `Instance` singletons and referenced from XAML via `{x:Static}`. What remains in `MainWindow.xaml.cs` (~940 lines) is `MainViewModel`, `RelayCommand`, OPML parsing, and all the focus management — finishing that split is item 2.1 in the improvement plan.

Flow:

1. **Startup** — `LoadDefaultOpml()` calls `FindDefaultOpml()`, which checks the working directory first (so a portable copy uses the list beside it) then `AppContext.BaseDirectory` (so a Start Menu shortcut, whose working directory is not guaranteed, still finds the installed list). Missing file is not an error; focus goes to the Import button.
2. **OPML → tree** — `ParseOpml()` / `ProcessOutlines()` walk `<outline>` elements recursively into a `FeedItem` tree. `IsCategory` distinguishes folders from feeds; nesting is arbitrary depth.
3. **Feed → headlines** — Enter in the tree calls `LoadFeedAsync` (one feed) or `LoadAllFeedsInCategoryAsync` (a folder). Both call `BeginLoad`, which cancels whatever load was already running, then hand off to `FeedLoader`. A folder fetches six feeds at a time and reports per-feed failures rather than failing as a whole.
4. **Headline → browser** — Enter or Alt+B runs `Process.Start` on the article link.

### Traps this codebase has already fallen into

- **The two load paths used to build articles independently** and drifted every time either was touched — title cleaning applied on one path only (the original braille bug), then differing date formats. `ArticleItem.FromSyndication` is now the only place a syndication item becomes an article. Keep it that way.
- **`SyndicationItem.PublishDate` throws from its getter** when the feed's date is malformed, rather than returning a default. `PickDate` catches it. Reading any syndication date property unguarded reintroduces "one bad entry loses the whole feed".
- **`HttpClient` reports its own timeout as `TaskCanceledException`**, which derives from `OperationCanceledException`. Every `catch (OperationCanceledException)` here is filtered on `IsCancellationRequested` for our own token, so a timeout is reported as a failure rather than swallowed as a user cancellation. Dropping that filter brings back "one slow feed kills the folder".
- **Control characters in headline text are replaced with a space, not deleted.** Tabs and newlines fall in that range and are usually separating words.

### Accessibility constraints — treat these as load-bearing

- **Neither items control is its own tab stop.** `IsTabStop="False"` on both `FeedTree` and `HeadlinesList`, plus an `ItemContainerStyle` that sets `IsTabStop="True"` on `TreeViewItem` (unlike `ListBoxItem`, it is not one by default). With `TabNavigation="Once"` each panel is a single stop that lands on an item. Setting `IsTabStop="True"` on a container reintroduces the 1.1.0 Shift+Tab bug: focus lands on a container that reports no name, value or state, and the `GotFocus` handler pushes it straight back in, so Shift+Tab appears to do nothing. `tests/RSSQuick.Tests/TabOrderTests.cs` measures this — every test there was verified to fail against the unfixed window.
- **The `GotFocus` handlers are guarded on `e.OriginalSource`.** They redirect only focus that landed on the container itself. Without the guard they run for every focus change bubbling through the panel, so each arrow-key step re-focuses the row it just left.
- `FeedText.CleanTitle()` strips zero-width characters (U+200B/C/D, U+FEFF, U+2060), normalizes exotic spaces (U+00A0, U+2009, U+202F) to plain spaces, replaces control characters with a space, and collapses whitespace. Invisible characters and stray whitespace render as confusing blank cells on a braille display. Do not bypass it for text that reaches a headline.
- Tab order is explicit and fixed: Import (0) → FeedTree (1) → HeadlinesList (2) → Open in Browser (3). Adding a focusable control means renumbering deliberately and updating `TabOrderTests`.
- The status bar `TextBlock` is the **only** live region (`AutomationProperties.LiveSetting="Polite"`). Update `_viewModel.StatusMessage` rather than adding announcement channels. It reports position as `<feed> - <n> of <m>`, named from the article's own `FeedTitle` so merged folder views stay readable.
- Focus is managed by hand. `_isLoadingFeed` suppresses `SelectionChanged` side effects during a load, `_lastSelectedHeadlineIndex` restores the user's place on return, `_currentlyLoadedFeed` is what F5 reloads. Startup focus is set through `Dispatcher.BeginInvoke` at `ApplicationIdle` because WPF containers are not realized when the data arrives — removing that deferral breaks focus silently. After a load, `FocusSelectedHeadline()` lays out and scrolls the row into view before focusing it, which replaced a 100 ms `DispatcherTimer` that was guessing at the same thing.
- Selecting a feed does **not** load it; Enter does. Intentional, so arrow-key browsing never triggers network fetches.
- **No literal colours anywhere in the XAML.** Everything is a `DynamicResource` on a `SystemColors.*BrushKey`, so a Windows high contrast theme works and follows a live theme switch. Folders are marked out by font weight, never colour. `ThemeTests` asserts this against the live visual tree — and note that `ReadLocalValue` is useless for checking it, because content inside a `DataTemplate` records its values as `ParentTemplate` rather than `Local`; use `DependencyPropertyHelper.GetValueSource`.
- **`TextScale.Current` is applied to the window's `FontSize` in the constructor.** WPF honours display scaling through the manifest's per-monitor DPI awareness, but ignores the Accessibility "Make text bigger" setting completely. Removing that one line silently drops text-scaling support.

Key bindings are registered in `SetupKeyboardNavigation()` as `InputBindings`: F5 refresh, F6 / Ctrl+Tab cycle panels, Alt+B open in browser. Left/Right expand/collapse are handled in `FeedTree_KeyDown`.

## Tests

`tests/RSSQuick.Tests` uses xunit.v3 with `Xunit.StaFact` for `[WpfFact]`. `FocusHarness` builds a real `MainWindow`, populates both panels with fixed items, and walks focus with `MoveFocus` — the same traversal Tab performs.

It reads focus through `FocusManager`, not `Keyboard.FocusedElement`: logical focus is what the window's `GotFocus` handlers respond to, and unlike keyboard focus it does not require the window to be foreground, which it never is under a test runner or on CI.

`global.json` selects the Microsoft.Testing.Platform runner for `dotnet test`. That is required rather than preferred — MTP 2.x, which xunit.v3 4.x pulls in, refuses to run under the VSTest target on the .NET 10 SDK. It changes the command line: pass the project with `--project`, and use `-- --report-xunit-trx` in place of `--logger trx`. VSTest spellings are silently ignored rather than failing, so a broken invocation looks like a passing run that reported nothing.

`xunit.v3` is held at 3.x by a Dependabot ignore. 4.x changes internals `Xunit.StaFact` compiles against, and every `[WpfFact]` fails discovery with `MissingMethodException` — that is all eight focus and startup tests. `Xunit.StaFact 4.0.5-beta` does not fix it. Lift the ignore when a stable StaFact supports xunit.v3 4.x.

The app project sits at the repository root, so its default `**/*.cs` glob would otherwise compile the test sources into the app. `Directory.Build.props` excludes `tests/**` and `installer/**` for that reason — and it has to live there, not in the csproj, because the SDK computes default items before the project body is evaluated.

## Packaging

Both artefacts are **self-contained single-file** builds, so neither needs .NET installed. That is deliberate: "app won't start, missing .NET Runtime" was the dominant support problem with the framework-dependent packages this replaced. The cost is ~55 MB per artefact.

`installer/rssquick.iss` takes every value through `/D` defines from `build/publish.ps1`. It installs per-user (`PrivilegesRequired=lowest`) so the common case raises no UAC prompt, uses a fixed `AppId` so upgrades replace rather than stack, and installs `RSS.opml` with `onlyifdoesntexist` so an edited feed list survives an upgrade. `AppMutex` matches the named mutex `App.OnStartup` holds purely as a running-marker — it does not enforce a single instance.

## Historical context

`DEVELOPMENT-NOTES.md` is a record of the original 3-panel → 2-panel rework. It is history, not current documentation: it describes build scripts that no longer exist. The parts still worth reading are the braille whitespace investigation and the screen reader design principles.
