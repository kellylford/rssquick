# Release process

## Cutting a release

```bash
powershell -File build/prepare-release.ps1 1.1.0
```

That writes `VERSION`, which is the single source of truth — `Directory.Build.props` reads it into the executable's file version, and `build/publish.ps1` reads it for the artefact filenames. Nothing else needs the number changing.

Then:

1. **Write the changelog.** Add a `[1.1.0]` section to `CHANGELOG.md`. Describe what changed for someone using the app, not what changed in the code.
2. **Run the tests.** `build.cmd test`
3. **Build the packages.** `package.cmd`
4. **Try them.** Install the installer, run the portable ZIP, and check the things that are easy to break: Tab and Shift+Tab through all four stops, load a feed, load a folder, open an article. Do this with a screen reader running.
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

Pushing the tag runs `.github/workflows/release.yml`, which checks the tag against `VERSION`, runs the tests, rebuilds all four artefacts on a clean runner, and opens a **draft** GitHub release with them attached.

6. **Review the draft**, edit the generated notes, and publish it.

The release is a draft rather than published on purpose: the artefacts deserve a manual check before anyone downloads them, and auto-generated notes deserve reading before they go out.

## What CI does

| Workflow | Runs on | Does |
|---|---|---|
| `ci.yml` | Every push to `main` and every PR | Build and test |
| `codeql.yml` | Push, PR, and weekly | Security and quality analysis |
| `release.yml` | A pushed `v*` tag, or on demand | Test, build all four packages, open a draft release |

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
