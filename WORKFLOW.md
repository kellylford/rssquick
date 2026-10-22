# Release process

## Cutting a release

```bash
powershell -File build/prepare-release.ps1 1.1.0
```

For a fix that ships on some platforms only, name them: `build/prepare-release.ps1 1.4.1 -Platforms windows` (see [Versioning](#versioning)).

That writes `VERSION`, which is the single source of truth — `Directory.Build.props` reads it into the executable's file version, and `build/publish.ps1` reads it for the artefact filenames. Nothing else needs the number changing. It also writes `RELEASE-PLATFORMS`, the platforms the release ships on, which each release workflow reads.

Then:

1. **Write the changelog.** Add a `[1.1.0]` section to `CHANGELOG.md`; for a fix on some platforms only, say which in its heading, as in `## [1.4.1] - 2026-10-22 - Windows only`. Describe what changed for someone using the app, not what changed in the code.
2. **Run the tests.** `build.cmd test` on Windows, and `./build.sh test` in `macos/`.
3. **Build the packages.** `package.cmd` on Windows. On a Mac, `./build.sh dist` in `macos/` — see [Cutting the macOS half](#cutting-the-macos-half) below.
4. **Try them.** Install the installer, run the portable ZIP, and check the things that are easy to break: Tab and Shift+Tab through all four stops, load a feed, load a folder, open an article. Do this with a screen reader running. Then the same on the Mac with VoiceOver, from the disk image rather than the build directory. Before the first release of a new installer or updater change, also try an update end to end — HOW-TO-BUILD.md's *Trying an update without publishing one* does it against a local folder.
5. **Commit and tag.**
   ```bash
   git commit -am "Release v1.1.0"
   ```
   ```bash
   git tag -a v1.1.0 -m "Release v1.1.0"
   ```
   ```bash
   git push origin main --follow-tags
   ```

Pushing the tag runs three workflows, each for the platforms `RELEASE-PLATFORMS` lists; a workflow for a platform it leaves out stops at its first job and builds nothing. `.github/workflows/release.yml` checks the tag against `VERSION`, runs the tests, rebuilds all four Windows artefacts on a clean runner, and opens a **draft** GitHub release with them attached. `.github/workflows/macos-release.yml` does the same for the disk image on a macOS runner and attaches it to that same draft. `.github/workflows/ios-release.yml` builds the iPhone and iPad version at the same version, uploads it to TestFlight, and submits it to the External TestFlight group (the external testers, with the public link) for Beta App Review; unlike the draft, that goes to testers as soon as Apple approves it. See ios/README.md.

`release.yml`'s first job creates the draft on every tag, whichever platforms it is for, and opens its notes with a line such as **"RSS Quick 1.4.1 is a Windows-only release. The Mac, iPhone and iPad versions have not changed, so there is nothing new to install there."** (`build/release-platforms.sh` writes it; a release on all three has no such line). The platform jobs then attach their files to it. The macOS job spends most of its time waiting on Apple's notary service, so by the time it uploads, the draft exists. The draft is made only once: re-running the job, or re-tagging, leaves notes you have edited alone. A fix for iPhone and iPad alone makes no GitHub release, because there would be nothing on it to download; the changelog records it.

When you publish a release that has no Windows files, untick **Set as the latest release**. The Releases page, which the README sends Windows and Mac readers to, shows the latest release first, and a Mac-only release there tells a Windows reader there is nothing for them. It also keeps installed Windows copies on track whichever way Velopack picks its release; the portable Windows copy and the Mac look through recent releases for one with their own download, so they are not affected either way.

6. **Review the draft**, edit the generated notes, and publish it.

The release is a draft rather than published on purpose: the artefacts deserve a manual check before anyone downloads them, and auto-generated notes deserve reading before they go out.

Publishing it is also what ships the update. Installed Windows copies read the update feed from the latest published release, so within a few seconds of their next start they download the new version and install it when they close; portable and Mac copies say a new version is available. Nothing is offered while the release is a draft — and once it is published, it is on its way to every installed copy, so check the draft first. The feed files attached to it (`*.nupkg`, `releases.*.json`, `assets.*.json`, `RELEASES*`) are for the updater: leave them on the release.

## Cutting the macOS half

The disk image has to be signed with a Developer ID certificate and notarised by Apple, or macOS
tells the reader the app cannot be opened safely and sends them to System Settings. Talking a
VoiceOver user through a Gatekeeper override is not an acceptable first run, so an unsigned or
unnotarised image is not a releasable artefact — it is a build you keep to yourself.

That needs two credentials, neither of which lives in the repository:

- A **Developer ID Application** certificate in the keychain.
- An **App Store Connect API key** — a `.p8`, a Key ID and an Issuer ID — exported as
  `NOTARY_KEY_PATH`, `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID`.

With both in place, `./build.sh dist` in `macos/` runs the tests, builds the universal app, signs
it, notarises and staples it, builds the image, signs and notarises that, and verifies the
result. It fails closed. Most of the 5–30 minutes is Apple's: two submissions, each two to
fifteen.

The same scripts run in CI, which needs those credentials as five repository secrets.
[macos/README.md](macos/README.md) has the full list and how to produce each one.

If you have no Mac to hand, tag and let `macos-release.yml` do it — that is the whole point of it
existing. What you cannot do without a Mac is step 4, opening the finished image with VoiceOver,
and that step is not optional.

## What CI does

| Workflow | Runs on | Does |
|---|---|---|
| `ci.yml` | Every push to `main` and every PR | Build and test |
| `codeql.yml` | Push, PR, and weekly | Security and quality analysis |
| `release.yml` | A pushed `v*` tag, or on demand | Test, build all four Windows packages, open a draft release |
| `macos-release.yml` | A pushed `v*` tag, or on demand | Test, build, sign, notarise and staple the disk image, attach it to the draft |

`release.yml` can also be run from the Actions tab without a tag, which builds the packages as run artefacts without creating a release. That is the way to get a testable build before you are ready to tag.

Dependabot proposes NuGet and Actions updates weekly, with the test packages grouped into one PR.

## Between releases

- Work on a branch and open a PR; `main` should stay releasable.
- Anything touching focus, tab order, announcements, or headline text wants a test in `tests/RSSQuick.Tests` and a manual check with a screen reader. See [CONTRIBUTING.md](CONTRIBUTING.md).
- Keep `CHANGELOG.md` current as you go, rather than reconstructing it at release time.

## Versioning

### One product, three platforms

**MAJOR.MINOR is the product; PATCH is a fix, and ships only where something changed.**

- **A feature release (x.y.0) ships on Windows, Mac, iPhone and iPad together**, with the same features: "1.4" means one feature set everywhere. `prepare-release.ps1` refuses an x.y.0 for fewer than all three.
- **A fix release (x.y.z) ships only on the platforms it fixes.** A Windows-only fix must not send iPhone testers a new build with nothing in it, or put a Mac user through an update for nothing. The other platforms stay where they are, on the same feature version.
- **The patch counter is shared.** Every number is one release, with one changelog entry and one GitHub release: a Windows fix is 1.4.1, a later Mac fix is 1.4.2, and the Mac never has a 1.4.1. A platform's own versions may skip numbers, and that is expected.
- The next feature release brings all three level again.
- `VERSION` holds the newest number used on any platform, so a Mac built from main after a Windows-only 1.4.1 calls itself 1.4.1. The iOS project's marketing version moves only when iOS ships.
- Copies that check GitHub for a newer version (the portable Windows copy and the Mac) look through recent releases for the newest one carrying their own download, so a later release for another platform never hides one meant for them. `ReleaseCheck` on both sides, with matching tests.

Semantic versioning:

- **Patch** (1.1.1) — bug fixes only.
- **Minor** (1.2.0) — new features, or fixes that change behaviour people may have adapted to.
- **Major** (2.0.0) — a change that breaks how existing users work, such as dropping OPML support or changing where the feed list lives.

A change to how the keyboard or a screen reader behaves is a minor release, not a patch: people build muscle memory around these, and the change is worth being visible in the notes. A fix for something plainly broken, that nobody could have adapted to, is still a patch: a feed tree that read every row as "RSSReaderWPF.FeedItem" (1.4.1) is a bug fix, not a behaviour change.
