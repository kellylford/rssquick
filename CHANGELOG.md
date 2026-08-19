# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-08-19

### Fixed
- **Shift+Tab did nothing in either panel.** The feed tree and the headlines list were each a tab stop in their own right, on top of the item inside them, so Shift+Tab moved focus to the bare container — an element with no name, value or state to announce — and the focus handler pushed it straight back in. Tab order is now Import → feed → headline → Open in Browser, and walks the same stops in reverse. Measured by a test rather than assumed.
- **F6 and Ctrl+Tab only ever went one way.** Both checked whether the container held focus, which it never does, so every press landed on the feed tree. They now move between the two panels properly.
- **F5 refreshed the wrong thing.** It reloaded whatever was selected in the tree rather than what was on screen, and did nothing at all after loading a whole folder. It now reloads what you are actually reading.
- **The status bar named the wrong feed.** After loading a folder, or after arrowing around the tree, the position announcement named the tree selection instead of the feed the headline came from. It now names the article's own feed, which also makes merged folder views readable.
- The installed build opened with an empty feed tree, because it looked for `RSS.opml` only in the working directory and a Start Menu shortcut does not reliably set one. It now falls back to the folder holding the executable.
- Removed a headline colour binding to a property that does not exist, and a click handler for a button that is not in the window.

### Added
- **An installer.** Per-user by default, so no administrator prompt, with Start Menu and optional desktop shortcuts and a proper Add/Remove Programs entry. An upgrade replaces the previous install and leaves an edited `RSS.opml` alone.
- **A portable package.** Unzip and run; nothing is installed and nothing is written outside the folder.
- Neither package needs .NET installed — both carry their own copy.
- A test suite (`build.cmd test`), currently covering the tab ring.
- Continuous integration, CodeQL scanning, and Dependabot.
- `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, a `LICENSE` file, and issue templates including one for accessibility reports.

### Changed
- Now built on .NET 10, which is supported into 2028. .NET 8 support ends in November 2026.
- The build scripts are now `run.cmd`, `build.cmd` and `package.cmd`. The `distribute*` scripts they replace were empty files that three documents described as working.

## [1.0.0] - 2025-08-29
### Added
- Initial public release
- Accessible, fast, and simple RSS reader for Windows
- Multi-platform: x64 and ARM64 builds
- No installation required: just unzip and run
- Loads any `rss.opml` in the launch folder (default file included)
- Optimized for screen readers and keyboard navigation
- OPML import, clean 2-panel interface, external browser support
