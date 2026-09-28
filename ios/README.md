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
- **No check for a newer version.** The desktop versions ask GitHub at launch; on iOS TestFlight
  and the App Store deliver updates, and an app that told you about its own would only be
  repeating them. `ReleaseCheck.swift` is in `RSSQuickCore`, which this app compiles, but nothing
  here calls it.
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

### Each release: from GitHub

Pushing a `v*` tag releases all three platforms at the same version. `.github/workflows/ios-release.yml`
runs beside the Windows and macOS release workflows, on a GitHub-hosted Mac:

1. It builds with the version from `VERSION`.
2. It asks App Store Connect for the highest build number it has ever seen, and uses one more.
   Build numbers only go up, whichever route uploaded the last build.
3. It uploads the build and waits for Apple to process it.
4. It sets "What to Test" from that version's `CHANGELOG.md` section.
5. It adds the build to the external **Public Testers** group. If there is no such group, it
   creates one with a public link.
6. It submits the build for Beta App Review.

To upload the version on a branch without tagging, run it by hand from the Actions tab.

`ios-testflight-status.yml`, run by hand, is read-only. For every build it lists the version,
processing state and Beta App Review state; it also lists the App Store versions and each
TestFlight group with its public link. Run it from the Actions tab, or with
`gh workflow run ios-testflight-status.yml`, then read the log.

Both workflows are built on GitHub rather than on this Mac on purpose. The Mac runs a beta
macOS, and Apple rejects App Store builds made on one. Both are driven by
`ios/scripts/asc.py`, which also runs by hand on a Mac with `ASC_KEY_ID`, `ASC_ISSUER_ID` and
`ASC_KEY_PATH` set.

**Repository secrets.**
- **App Store Connect API key:** the workflows use the one the macOS release already uses
  (`NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_P8`). That key needs the **App Manager**
  or **Admin** role to manage groups and submit builds. With the Developer role, the status
  workflow works but distributing fails with a 403.
- **Apple Distribution certificate:** not the Developer ID certificate the Mac build uses. Set
  it once, from this Mac:

```bash
# Keychain Access -> login -> My Certificates -> "Apple Distribution: Kelly Ford (P887QF74N8)"
# (it must have a private key under it) -> Export -> dist.p12, with a password.
base64 -i dist.p12 | gh secret set IOS_DIST_CERT_P12 -R kellylford/rssquick
gh secret set IOS_DIST_CERT_PASSWORD -R kellylford/rssquick   # paste the export password
rm dist.p12
```

These are the same certificate and key Scores' `ios-release.yml` uses. GitHub secrets are
per-repository, so they have to be set here too.

### Each release: from this Mac

```bash
ios/scripts/release-testflight.sh 2
```

This still works for a quick internal build. The argument is the build number, which must be
higher than any App Store Connect has seen; `ios-testflight-status.yml` shows the current
highest. The script archives the app, signs it, and uploads it with the Apple ID signed in to
Xcode. TestFlight emails the Internal group 5 to 15 minutes later. `--export-only` writes an
`.ipa` without uploading.

`ENABLE_PREVIEWS` and `ENABLE_DEBUG_DYLIB` are off in `project.yml`. Both must stay off: either
one bundles a dylib that crashes the app at launch on iOS 27 (found in Scores).
