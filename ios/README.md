# RSS Quick for iOS

A SwiftUI version of RSS Quick for iPhone and iPad. It is deliberately small: the feed list with
folders that expand and collapse, OPML import, and headlines that open the article when activated.

## What it shares, and what it doesn't

The feed and OPML parsing is **not** reimplemented. `project.yml` compiles
`macos/Sources/RSSQuickCore` straight into the app, so iOS and macOS share one parser, one
title cleaner (`FeedText.cleanTitle`, the braille whitespace fix), one date reader and one folder
loader with its per-feed failure reporting. Those are tested by `macos/Tests` (`cd macos &&
./build.sh test`). Only the UI lives here:

| File | Is |
|---|---|
| `RSSQuick/FeedStore.swift` | The feed tree, OPML import, and the one thing kept between runs |
| `RSSQuick/FeedListView.swift` | The tree: `DisclosureGroup` folders, feeds as navigation links |
| `RSSQuick/HeadlinesView.swift` | Headlines for a feed or a whole folder, and the in-app Safari view |
| `RSSQuick/Accessibility.swift` | Row identity, the navigation route, and VoiceOver announcements |

## Decisions that differ from the desktop versions

- **The default feed list commands are in the ••• menu**, dimmed when they have nothing to do,
  as the desktop versions dim theirs. Importing shows a list without saving it; Make This My
  Default Feed List saves a copy, which is the only way a list survives on iOS, where a file picked
  in Files is only lent to the app for that moment. The copy lives at
  Application Support/Imported.opml — a name kept from the first TestFlight build, which saved on
  every import, so a list saved by that build still opens. Never feed content.
- **Articles open in Safari inside the app** (`SFSafariViewController`), not in the Safari app.
  On a phone, switching apps means finding the way back. Done returns to the same headline,
  and Safari Reader and content blockers still work.
- **Tapping a folder expands it.** That is what a disclosure row does everywhere on iOS. Loading
  every feed in a folder, which Enter does on Windows, is the **Show all headlines** VoiceOver
  action (swipe up or down on the folder) or a long press.
- **Announcements** go through `AccessibilityNotification.Announcement`, and only when a load
  finishes: "45 headlines", or the count plus how many feeds failed. The message is delayed
  slightly, because an announcement made during a screen change is dropped.
- **The feed is named on a headline only in a folder's merged list**, as on macOS.
- **Plain http feeds are allowed** (`NSAllowsArbitraryLoads`). Feeds come from whatever list the
  reader imports, and the bundled list has one http feed.

## Build and run

```bash
cd ios
xcodegen                # only after editing project.yml; the .xcodeproj is committed
open RSSQuick.xcodeproj
```

Or from the command line, for the simulator:

```bash
xcodebuild -project ios/RSSQuick.xcodeproj -scheme RSSQuick -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Releasing to TestFlight

The team is `P887QF74N8`, the bundle ID `com.kellylford.rssquick` (the same ID the macOS app
uses), and signing is automatic, as in Scores and FastWeather. The version comes from `VERSION`
at the repository root.

### Once, in the Apple portals

1. **Register the App ID**: developer.apple.com → Certificates, Identifiers & Profiles →
   Identifiers → + → App IDs → App. Choose Explicit, bundle ID `com.kellylford.rssquick`,
   description "RSS Quick". No capabilities are needed.
2. **Create the app record**: App Store Connect → Apps → + → New App. Choose iOS, name
   "RSS Quick" (App Store names must be unique; if that one is taken, the home-screen name stays
   "RSS Quick" whatever you enter here), primary language English (U.S.), bundle ID
   `com.kellylford.rssquick`, SKU `rssquick-ios-001`, and Full access.
3. **Create the internal group**: in the app → TestFlight → Internal Testing → + → name it
   "Internal" → add **kelly@kellford.com**. Internal testers must already be App Store Connect
   users on the team. If that address isn't one yet, add it under Users and Access first.
   Turn on automatic distribution so every new build reaches the group without extra clicks.

### Each release

```bash
ios/scripts/release-testflight.sh 2
```

The argument is the build number. Each release needs a number App Store Connect hasn't seen for
this version, including builds it rejected. The script archives the app, signs it, and uploads it
with the Apple ID signed in to Xcode. App Store Connect takes 5 to 15 minutes to process a build,
then TestFlight emails the Internal group. `--export-only` writes an `.ipa` without uploading.

Local uploads from this Mac are fine for TestFlight even though it runs a beta macOS. As the
FastWeather notes record, an **App Store** submission built on a beta OS is rejected. When it's
time for that, copy Scores' `.github/workflows/ios-release.yml` and point it at
`ios/RSSQuick.xcodeproj`.

`ENABLE_PREVIEWS` and `ENABLE_DEBUG_DYLIB` are off in `project.yml`. Both must stay off: either
one bundles a dylib that crashes the app at launch on iOS 27 (found in Scores).
