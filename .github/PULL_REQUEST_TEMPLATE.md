## What this changes

<!-- One or two sentences. Link the issue it closes, if there is one. -->

## Why

<!-- What was wrong, or what this makes possible. -->

## How it was checked

- [ ] `build.cmd test` passes
- [ ] Ran the app and exercised the change by hand
- [ ] Keyboard-only: Tab and Shift+Tab still reach every control, in both directions
- [ ] Checked with a screen reader, if the change touches the UI

<!--
Anything touching focus, tab order, announcements, or headline text is an accessibility change
even when it does not look like one. Those are worth a test in tests/RSSQuick.Tests — the tab
ring is measured there rather than assumed.
-->
