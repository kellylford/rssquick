# RSS Quick — code review and improvement plan

Written 19 August 2026, against the code as it stands after the 1.1.0 fixes.

The application works, and the accessibility instincts behind it are sound — the status bar as a polite live region, headline text cleaning for braille, select-does-not-fetch. What follows is what is holding it back, in the order worth doing.

Line references are to `MainWindow.xaml.cs` unless noted.

---

## Already done in 1.1.0

Fixed and covered by tests or by hand: the Shift+Tab trap, F6/Ctrl+Tab only moving one way, F5 refreshing the wrong feed, the status bar naming the wrong feed, the installed build starting with an empty tree, and a handful of dead handlers and bindings. See `CHANGELOG.md`.

The rest of this document is what is left.

---

## Priority 1 — problems users hit today

### 1.1 A slow feed freezes the app for up to 100 seconds

`XmlReader.Create(feed.Url)` (lines 523 and 629) fetches over the network synchronously, using the default `WebRequest` timeout of 100 seconds. There is no timeout of our own and no cancellation.

It is worse for a folder. `LoadAllFeedsInCategoryAsync` loops over the feeds **one at a time** (line 510), awaiting each. A folder of twenty feeds where three servers are unresponsive takes five minutes before it finishes, with a status bar that says "Loading feed: …" the whole time and no way to stop it. The Sports folder in the shipped `RSS.opml` has enough feeds to make this reachable in normal use.

**Do:** replace `XmlReader.Create(url)` with a single shared `HttpClient` (10–15 second timeout, a real `User-Agent` — some feeds reject the default), fetch into a stream, and parse with `XmlReader.Create(stream, settings)` where `settings.DtdProcessing = DtdProcessing.Prohibit`. Fetch a folder's feeds concurrently with a small cap, say six at a time. Announce progress as "Loaded 4 of 20 feeds".

**Size:** half a day. This is the single biggest improvement available.

### 1.2 Loading a second feed while the first is still loading corrupts the list

There is no cancellation anywhere. `_isLoadingFeed` is a bool that suppresses selection side effects; it does not stop an in-flight load. Press Enter on one feed, then Enter on another before the first returns, and both completions call `_viewModel.Headlines.Add(...)` — the list ends up holding both feeds' headlines interleaved, with a status bar reporting whichever finished last.

This is easy to hit with a slow feed, which is exactly when a user is most likely to give up and try a different one.

**Do:** hold a `CancellationTokenSource` for the current load, cancel it at the top of every load, and drop results whose token has been cancelled. Escape during a load should cancel too, and say so.

**Size:** a few hours, and it wants doing together with 1.1.

### 1.3 Feed failures inside a folder are invisible

A feed that fails inside `LoadAllFeedsInCategoryAsync` is swallowed to `Console.WriteLine` (line 545). RSS Quick is a `WinExe` and has no console, so that output goes nowhere. The user sees a smaller list than expected with nothing to say why.

Single-feed failures have the opposite problem: a modal `MessageBox` (lines 580, 694) that has to be dismissed before anything else can happen.

**Do:** collect failures and report them in the status bar — "Loaded 380 headlines from 17 of 20 feeds; 3 could not be reached". Keep the modal box for actions the user explicitly asked for that produced nothing (a single feed failing, an OPML import failing), and drop it for partial success.

**Size:** a few hours, on top of 1.1.

### 1.4 Dates are formatted, then parsed back, to sort

`Published` is a string. `LoadFeedAsync` writes `"yyyy-MM-dd HH:mm"`, `LoadAllFeedsInCategoryAsync` writes `"MMM dd, yyyy HH:mm"`, and the folder path then sorts by running `DateTime.TryParse` over its own output (lines 551–556). When the parse fails the article sorts to `DateTime.MinValue` and lands at the bottom regardless of its real date.

Both calls also use the current culture (`CA1305`, two build warnings), so the format the sort depends on changes with the user's regional settings.

A feed with no `pubDate` yields `DateTimeOffset.MinValue`, which is shown to the user as `0001-01-01 00:00`.

**Do:** keep `DateTimeOffset?` on the model, sort on it, and format only for display. Show something honest when a feed gives no date. Pick one format and use it on both paths.

**Size:** an hour or two.

### 1.5 The two feed-loading paths keep drifting apart

This is the fault that produced the original braille whitespace bug, recorded in `DEVELOPMENT-NOTES.md`, and it has recurred. `LoadFeedAsync` and `LoadAllFeedsInCategoryAsync` each build `ArticleItem`s by hand, and they currently differ in the date format (1.4), in whether `Summary` and `Author` are populated at all, and in what they use for missing content.

The cause is structural: there is no one place where a syndication item becomes an `ArticleItem`.

**Do:** extract a single `ArticleItem FromSyndicationItem(SyndicationItem, string feedTitle)` and have both paths call it. Test it directly. This is a small change that permanently closes a category of bug this project has already been bitten by twice.

**Size:** an hour. Do it before or alongside 1.1.

---

## Priority 2 — structure that makes the rest cheap

### 2.1 One 1063-line file holds everything

`MainWindow.xaml.cs` contains `FeedItem` (28), `ArticleItem` (71), `MainViewModel` (133), `MainWindow` (170) and `RelayCommand` (1043). Network fetching, XML parsing, text cleaning, focus management, and status text all live in the window class, which is why almost none of it can be tested without standing up a window.

**Do:** split along the seams that already exist, without redesigning anything:

```
Models/         FeedItem, ArticleItem
ViewModels/     MainViewModel, RelayCommand
Services/       OpmlParser, FeedLoader, TitleCleaner
```

`OpmlParser` and `TitleCleaner` are pure functions over strings and can be tested outright. `FeedLoader` behind a small interface can be tested against saved feed XML — including the malformed and hostile shapes that are currently untested.

**Do also:** move the project into `src/`. It currently sits at the repository root, so its default `**/*.cs` glob swallows every C# file anywhere in the repo — the test project had to be explicitly excluded in `Directory.Build.props` to stop it being compiled into the app. That exclusion is a patch over the layout, and the next directory anyone adds will hit it again.

**Size:** a day, mostly mechanical. Worth doing before the P1 work if you would rather not do that work twice.

### 2.2 The test suite covers one thing

`tests/RSSQuick.Tests` currently asserts the tab ring and nothing else. That was the point of adding it, but the coverage worth having next is:

- `CleanTitleText` against real problem strings — the zero-width and exotic-space cases it was written for. This is the project's most important invariant and nothing checks it.
- OPML parsing: nesting, missing `xmlUrl`, missing `text` with `title` present, an empty body, malformed XML.
- Feed parsing against saved RSS and Atom fixtures, including missing dates, missing links, and HTML in titles.
- Focus behaviour after a load: that focus lands on the first headline, and that Tab away and back returns to the same one.

Most of this needs 2.1 first, which is the argument for doing 2.1 early.

**Size:** ongoing; a day gets the important half.

### 2.3 Dead and oversized state

- `Summary`, `Content` and `Author` on `ArticleItem` are written and never read anywhere — no binding in `MainWindow.xaml` touches them. `Content` holds the full article body, so loading a twenty-feed folder retains roughly a thousand article bodies in memory for nothing. Either drop them, or use them (see 3.1).
- `BoolToMarginConverter` in `Converters.cs` is referenced by nothing.
- `_feedCategories` (line 173) is a `Dictionary<string, Dictionary<string, FeedItem>>` that is populated on every parse and then read only to produce a total count.

**Size:** an hour, and it makes 2.1 smaller.

---

## Priority 3 — accessibility and features worth having

### 3.1 A reading pane, or at least a summary

Every article's summary is already fetched and thrown away. Opening the browser is the right default, but a keyboard-toggleable summary in the window would let someone triage a long list without leaving it. This is the most commonly requested thing in readers of this shape.

If you add it: a read-only multiline `TextBox`, not a `WebBrowser` or `WebView2`. The 3-panel layout was removed for good reasons recorded in `DEVELOPMENT-NOTES.md`, and an embedded browser brings all of them back.

### 3.2 High contrast and text scaling are ignored

`Converters.cs` hardcodes `Brushes.DarkBlue` and `Brushes.Black` (line 58), and `MainWindow.xaml` hardcodes `Foreground="Gray"` and `FontSize="11"` on the date line (line 95). In a Windows high contrast theme the hardcoded foregrounds sit on a system-coloured background, which at best looks wrong and at worst is unreadable. The fixed 11pt ignores the Windows text size setting entirely.

**Do:** use `SystemColors.*Brush` dynamic resources instead of literal brushes, drop the fixed `FontSize` or scale it relative to the inherited size, and check the window in Windows high contrast and at 200% text scaling.

**Size:** a few hours, and it matters to low-vision users who are not screen reader users — a group this project currently does not serve well.

### 3.3 Feed management in the app

Adding or removing a feed means editing `RSS.opml` in a text editor. Add, rename, remove, and reorder in the tree, writing back to OPML. This is the biggest functional gap between RSS Quick and what people expect from a reader.

### 3.4 Search and filter across headlines

Type-ahead in the headlines list, and a filter box. QuickMail has a hand-rolled type-ahead accumulator (`TypeAheadPrefixTracker`) worth borrowing, along with its note on why WPF's built-in `TextSearch` is not enough for a `TreeView`.

### 3.5 Remembering things between runs

No settings are stored at all. Worth keeping: window size and position, the last feed loaded, and which folders were expanded. A portable build should write beside the executable and an installed build to `%APPDATA%`; the `FindDefaultOpml` helper already establishes that pattern.

### 3.6 Marking headlines read

There was a `Foreground` binding to `IsRead` in the XAML until 1.1.0 — the intent was there, the property never was. Read state is genuinely useful in a headline reader, and it needs 3.5 to survive a restart.

---

## Suggested order

1. **1.5** extract the shared article factory — an hour, stops the recurring divergence
2. **2.1** split the file and move to `src/` — makes everything after it testable
3. **1.1 + 1.2 + 1.3** the network rewrite as one piece of work — the biggest user-visible win
4. **1.4** dates
5. **2.2 + 2.3** tests and dead state, alongside the above
6. **3.2** high contrast and scaling — small, and it opens the app to a group it currently fails
7. **3.1, 3.3, 3.4, 3.5, 3.6** as appetite allows

Steps 1–4 are roughly a week and would leave the application genuinely solid. Everything in Priority 3 is optional.
