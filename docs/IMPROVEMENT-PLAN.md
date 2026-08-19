# RSS Quick — code review and improvement plan

Originally written 19 August 2026. Priority 1 is now done; what follows is what is left.

The application works, and the accessibility instincts behind it are sound — the status bar as a polite live region, headline text cleaning for braille, select-does-not-fetch. What follows is what is holding it back, in the order worth doing.

Line references are to `MainWindow.xaml.cs` unless noted.

---

## Done

### In the 1.1.0 accessibility pass

The Shift+Tab trap, F6/Ctrl+Tab only moving one way, F5 refreshing the wrong feed, the status bar naming the wrong feed, the installed build starting with an empty tree, and a handful of dead handlers and bindings.

### Priority 1 — the network rewrite

All of it, in `Services/FeedLoader.cs`, `Services/FeedText.cs` and `Models/ArticleItem.cs`:

- **1.1 Slow feeds no longer freeze the app.** `XmlReader.Create(url)` is replaced by a shared `HttpClient` on a 15-second timeout with a real `User-Agent` and gzip/brotli decompression. A folder's feeds are fetched six at a time instead of one after another. The old effective limit was `WebRequest`'s 100-second default with no cancellation, and a twenty-feed folder with three dead servers took five minutes.
- **1.2 Cancellation.** Each load cancels the one before it, so two loads can no longer interleave their results into the same list. Escape cancels.
- **1.3 Failures are visible.** Per-feed failures are collected and reported in the status bar — "Loaded 380 headlines from 17 of 20 feeds; 3 failed" — rather than going to a `Console.WriteLine` that a WinExe discards. The modal box now appears only when a single feed the user explicitly asked for produced nothing.
- **1.4 Dates are real instants.** `PublishedOn` is a `DateTimeOffset?`, sorted on directly rather than by parsing back a string this code had just formatted. Undated articles sort below dated ones instead of by a failed parse, and show nothing rather than `0001-01-01 00:00`.
- **1.5 One article factory.** `ArticleItem.FromSyndication` is the single place a syndication item becomes an article, so the two load paths can no longer drift.

Three bugs surfaced while writing the tests for this, none of which were in the original review:

- `SyndicationItem.PublishDate` **throws** `XmlException` from its getter when the feed's date is malformed rather than returning a default. One bad `pubDate` among fifty items destroyed the entire feed. Dates are the field publishers most often get wrong.
- `CleanTitleText` deleted control characters outright, and tabs and newlines fall in that range. `"Lions GM\t\tBrad Holmes"` came out as `"Lions GMBrad Holmes"` — words run together in a headline, in the method whose whole job is headline legibility. They now become a space.
- `HttpClient` reports its own timeout as `TaskCanceledException`, which derives from `OperationCanceledException`. The first version of the new loader rethrew that as a user cancellation, so one slow server still took down the whole folder — the exact fault being fixed. Both load paths now filter on whether our own token was cancelled.

Article links now prefer the `alternate` relationship over the first link, so Enter on a podcast episode opens the episode page rather than the MP3.

### Priority 3.2 — high contrast and text scaling

Hardcoded brushes are gone: folder names, headline dates, the status bar and the splitter all take their colours from Windows now, so a high contrast theme works. Folders are distinguished by weight alone — colour conveyed nothing to a screen reader or a colour-blind user and was actively wrong in high contrast.

The Windows Accessibility text scale ("Make text bigger") is read at startup and applied to the window font size. WPF does not honour it on its own — unlike display scaling, which the manifest's per-monitor DPI awareness covers.

`ThemeTests` asserts all of this against the live visual tree, and every test there was checked to fail against a reintroduced hardcoded colour. Two earlier versions of those tests were silently vacuous, which is worth knowing if you write more: `ReadLocalValue` returns unset for content inside a `DataTemplate` (the value source is `ParentTemplate`, not `Local`), and indexing into a row's visual tree finds container chrome rather than the row's own text.

---

## Priority 2 — structure

### 2.1 `MainWindow.xaml.cs` is still ~940 lines

The models and the feed loading have moved out. What remains in one file is `MainViewModel`, `MainWindow`, `RelayCommand`, plus OPML parsing and all the focus management.

**Do:** finish the split along the seams that already exist:

```
Models/         FeedItem, ArticleItem          (done)
Services/       FeedLoader, FeedText           (done)
Services/       OpmlParser                     (still in the window)
ViewModels/     MainViewModel, RelayCommand    (still in the window)
```

`OpmlParser` is the valuable one: it is a pure function from a string to a `FeedItem` tree, and it is completely untested.

**Do also:** move the project into `src/`. It sits at the repository root, so its default `**/*.cs` glob swallows every C# file anywhere in the repo — `tests/**` and `installer/**` had to be excluded in `Directory.Build.props` to stop them being compiled into the app. That exclusion is a patch over the layout, and the next directory anyone adds will hit it again.

**Size:** half a day.

### 2.2 Test coverage gaps

54 tests now cover the tab ring, startup, theming, text scaling, title cleaning, and feed parsing including malformed and hostile input. Still uncovered:

- **OPML parsing**: nesting, missing `xmlUrl`, missing `text` with `title` present, an empty body, malformed XML. Needs 2.1 first.
- **Focus after a load**: that focus lands on the first headline, and that Tab away and back returns to the same one.
- The four network tests are opt-in behind `RSSQUICK_RUN_NETWORK_TESTS=1` because they reach third-party servers. A local HTTP stub would let the timeout, concurrency, and partial-failure paths run on every build.

### 2.3 Dead and oversized state

- `Summary`, `Content` and `Author` on `ArticleItem` are populated and never read — no binding touches them. `Content` holds the full article body, so a twenty-feed folder retains around a thousand article bodies for nothing. Either drop them or use them (see 3.1).
- `_feedCategories` is a `Dictionary<string, Dictionary<string, FeedItem>>` populated on every parse and read only to produce a total count.

`BoolToMarginConverter` and `BoolToForegroundConverter` are gone, removed alongside 3.2.

**Size:** under an hour.

---

## Priority 3 — accessibility and features

### 3.1 A reading pane, or at least a summary

Every article's summary is already fetched and thrown away. Opening the browser is the right default, but a keyboard-toggleable summary would let someone triage a long list without leaving it.

If you add it: a read-only multiline `TextBox`, not a `WebBrowser` or `WebView2`. The 3-panel layout was removed for good reasons recorded in `DEVELOPMENT-NOTES.md`, and an embedded browser brings all of them back.

### 3.2a Live theme and text-size changes

Done in the pass above, with one limitation worth recording. Colours are `DynamicResource` lookups and so follow a theme switch while the app is running, but the text scale is read once at startup, so changing "Make text bigger" needs a restart to take effect. Watching `HKCU\Software\Microsoft\Accessibility` for changes would close that, if it turns out to matter.

Neither has been checked by eye in an actual high contrast theme yet — the assertions are structural. Worth one manual pass.

### 3.3 Feed management in the app

Adding or removing a feed means editing `RSS.opml` in a text editor. Add, rename, remove, and reorder in the tree, writing back to OPML. The biggest functional gap against what people expect from a reader.

### 3.4 Search and filter across headlines

Type-ahead in the headlines list, and a filter box. QuickMail has a hand-rolled type-ahead accumulator (`TypeAheadPrefixTracker`) worth borrowing, along with its note on why WPF's built-in `TextSearch` is not enough for a `TreeView`.

### 3.5 Remembering things between runs

No settings are stored. Worth keeping: window size and position, the last feed loaded, and which folders were expanded. A portable build should write beside the executable and an installed build to `%APPDATA%`; `FindDefaultOpml` already establishes that pattern.

### 3.6 Marking headlines read

There was a `Foreground` binding to `IsRead` until 1.1.0 — the intent was there, the property never was. Read state is genuinely useful in a headline reader, and it needs 3.5 to survive a restart.

### 3.7 Conditional GET

Feeds are refetched in full every time. Sending `If-Modified-Since` and `If-None-Match` and honouring a 304 would make F5 close to instant on an unchanged feed and is polite to publishers. Small, now that there is one place to put it.

---

## Suggested order

1. **2.1** finish the split, extract `OpmlParser`, move to `src/`
2. **2.2** OPML tests and a local HTTP stub, once 2.1 makes them cheap
3. **2.3** dead state
4. **3.7** conditional GET
5. **3.1, 3.3, 3.4, 3.5, 3.6** as appetite allows

Nothing left is urgent. The application can now be used daily without hitting the things that used to make it unusable, and the remaining work is about keeping it easy to change rather than about fixing it.
