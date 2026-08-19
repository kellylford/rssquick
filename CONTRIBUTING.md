# Contributing to RSS Quick

Issues and pull requests are welcome. This is a small project with one maintainer, so the most useful thing you can do before writing code is open an issue and check the direction first.

## What this project is for

RSS Quick exists to make browsing headlines fast for people using a screen reader or a braille display. That goal outranks features. A change that adds something useful but makes the tab order less predictable, the announcements noisier, or the headline text less clean is not a good trade here.

## Getting set up

You need **Windows 10 or 11** and the **.NET 10 SDK**. WPF is Windows-only, so there is no way to build this on macOS or Linux.

```bash
dotnet --version
```

Then:

| Command | What it does |
|---|---|
| `run.cmd` | Build and run — the everyday loop |
| `build.cmd test` | Run the tests |
| `build.cmd clean` | Delete build output and artefacts |
| `package.cmd` | Build the installer and portable ZIP into `artifacts/` |

`package.cmd` needs [Inno Setup 6](https://jrsoftware.org/isdl.php) for the installer half; without it you still get the portable ZIP.

## Accessibility is the test suite's main job

Most of what can break here is invisible in a screenshot, so it is measured instead:

- **Tab order** is asserted in `tests/RSSQuick.Tests/TabOrderTests.cs` by walking focus the same way Tab and Shift+Tab do. If you add, remove, or reorder a focusable control, that file should change with it.
- **Headline text** goes through `CleanTitleText`, which strips zero-width and exotic-space characters that render as confusing blank cells on a braille display. Text that reaches a headline must go through it.

If you change anything touching focus, tab order, status-bar announcements, or headline text, please also try it with a screen reader before opening the PR, and say in the PR which one you used.

Two details that have caused real bugs and are easy to reintroduce:

- **A list or tree container should not be its own tab stop.** `IsTabStop="True"` on an items control puts a stop on the container as well as the item — a stop that reports no name, value or state. That was the Shift+Tab bug fixed in 1.1.0. The comments in `MainWindow.xaml` explain the arrangement that replaced it.
- **There are two feed-loading paths.** `LoadFeedAsync` handles one feed, `LoadAllFeedsInCategoryAsync` handles a folder, and they build `ArticleItem`s independently. A change to how article fields are produced has to be made in both, or the two diverge in ways that only show up on a braille display.

## Pull requests

- Branch from `main`.
- Keep the change focused; separate refactoring from behaviour changes where you can.
- Match the surrounding style — the `.editorconfig` covers the mechanical parts.
- Run `build.cmd test` before pushing.
- Fill in the PR template, including how you checked it.

## Reporting bugs

Use the [issue templates](https://github.com/kellylford/rssquick/issues/new/choose). There is a dedicated accessibility template; please use it for anything involving a screen reader, braille display, magnifier, or keyboard-only use. Those are treated as bugs rather than enhancements, and you do not need to work out the cause — describing what you heard or could not reach is the useful part.

Security issues go through [SECURITY.md](SECURITY.md) instead, not the public tracker.
