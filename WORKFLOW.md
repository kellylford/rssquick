# Release process

## Cutting a release

```bash
powershell -File build/prepare-release.ps1 1.1.0
```

That writes `VERSION`, which is the single source of truth — `Directory.Build.props` reads it into the executable's file version, and `build/publish.ps1` reads it for the artefact filenames. Nothing else needs the number changing.

Then:

1. **Write the changelog.** Add a `[1.1.0]` section to `CHANGELOG.md`. Describe what changed for someone using the app, not what changed in the code.
2. **Run the tests.** `build.cmd test` on Windows, and `./build.sh test` in `macos/`.
3. **Build the packages.** `package.cmd` on Windows. On a Mac, `./build.sh dist` in `macos/` — see [Cutting the macOS half](#cutting-the-macos-half) below.
4. **Try them.** Install the installer, run the portable ZIP, and check the things that are easy to break: Tab and Shift+Tab through all four stops, load a feed, load a folder, open an article. Do this with a screen reader running. Then the same on the Mac with VoiceOver, from the disk image rather than the build directory.
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

Pushing the tag runs two workflows. `.github/workflows/release.yml` checks the tag against `VERSION`, runs the tests, rebuilds all four Windows artefacts on a clean runner, and opens a **draft** GitHub release with them attached. `.github/workflows/macos-release.yml` does the same for the disk image on a macOS runner and attaches it to that same draft.

The Windows job finishes first and is the one that creates the draft: the macOS job spends most of its time waiting on Apple's notary service, so by the time it uploads, the draft exists. If the Windows job fails, the macOS job creates the draft instead.

6. **Review the draft**, edit the generated notes, and publish it.

The release is a draft rather than published on purpose: the artefacts deserve a manual check before anyone downloads them, and auto-generated notes deserve reading before they go out.

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

Semantic versioning:

- **Patch** (1.1.1) — bug fixes only.
- **Minor** (1.2.0) — new features, or fixes that change behaviour people may have adapted to.
- **Major** (2.0.0) — a change that breaks how existing users work, such as dropping OPML support or changing where the feed list lives.

A fix to a keyboard or screen reader behaviour is a minor release, not a patch: people build muscle memory around these, and the change is worth being visible in the notes.
