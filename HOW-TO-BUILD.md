# Building and packaging RSS Quick

## What you need

- **Windows 10 or 11.** WPF is Windows-only; there is no way to build this elsewhere.
- **[.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)** — the SDK, not just the runtime. Check with `dotnet --version`.

The installer is built by [Velopack](https://velopack.io)'s `vpk`, a .NET tool pinned in `.config/dotnet-tools.json`. `package.cmd` restores it, so there is nothing else to install.

## Everyday development

Double-click any of these, or run them from a terminal.

| Script | Does |
|---|---|
| `run.cmd` | Build and run in Release. The normal loop. |
| `build.cmd` | Build and run in Debug |
| `build.cmd release` | Build and run in Release |
| `build.cmd test` | Run the test suite |
| `build.cmd clean` | Delete `bin`, `obj`, and `artifacts` |

Or use `dotnet` directly: `dotnet build`, `dotnet run`, `dotnet test`.

## Building the release packages

```bash
package.cmd
```

That builds both architectures and puts four files in `artifacts/`:

```
RSSQuick-1.2.0-setup-win-x64.exe        installer, Intel/AMD
RSSQuick-1.2.0-portable-win-x64.zip     portable, Intel/AMD
RSSQuick-1.2.0-setup-win-arm64.exe      installer, ARM
RSSQuick-1.2.0-portable-win-arm64.zip   portable, ARM
```

and the update feed in `artifacts/releases/`: a `.nupkg` package per architecture, and the
`releases.win.json`, `releases.win-arm64.json`, `assets.*.json` and `RELEASES*` files an installed
copy reads to find it. Every one of those goes on the GitHub release; `release.yml` uploads them.
x64 is Velopack's default `win` channel and ARM64 is `win-arm64`. An installed copy only ever
looks at its own channel, and the x64 one must never be renamed, or every installed x64 copy
stops seeing updates.

Pass an architecture to build just one: `package.cmd x64`.

Each is about 55 MB, and each takes a minute or two to compile and compress.

Under the hood `package.cmd` runs `build/publish.ps1`, which you can call directly for more control:

```bash
powershell -File build/publish.ps1 -Architecture x64 -SkipInstaller
```

`-KeepReleaseFeed` leaves `artifacts/releases/` as it is rather than emptying it first. The release
workflow runs `vpk download github` into it beforehand, so vpk can build a delta package against
the previous version, and installed copies download the difference rather than 55 MB.

### Signing

Local builds are not signed. Releases are: on a `v*` tag, `release.yml` signs through Azure
Artifact Signing, the same account QuickMail uses, with no certificate stored anywhere. It runs
`publish.ps1` in two steps, `-Step Publish` and then `-Step Package`, and signs `RSSQuick.exe`
between them, so the portable ZIP carries a signed program as well as the installer. See the
comments in `release.yml` and the *Packaging* section of CLAUDE.md for what the Azure side
needs.

## The Microsoft Store package

```bash
package.cmd store
```

That builds `artifacts/RSSQuick-<version>.msixbundle`, one MSIX package for each architecture
bundled together, which is what Partner Center takes. It is unsigned: the Store signs what it
publishes. The first run downloads Microsoft's SDK build tools (for `makeappx`) into
`artifacts/tools`, so the Windows SDK does not need to be installed.

To try the packaged app before submitting it, turn on Developer Mode in Windows Settings, then:

```bash
package.cmd store -Install
```

RSSQuick (dev) then appears in the Start menu, running as a Store copy would: Help, Check for
Updates says the Store keeps it up to date. It runs from `artifacts\store-installed`, under its
own identity, so it never replaces a real Store install and ordinary builds leave it alone;
`-Install` again replaces it (close it first). The script prints the command that removes it.

`build/store/identity.json` holds the package identity from Partner Center (*Product identity*).
With its placeholders a package still installs locally with `-Install`; a release tag skips the
Store bundle, with a warning, until the real values are there. `docs/STORE-PLAN.md` has the whole plan.

## Why the packages are built this way

**Both packages are self-contained**, meaning each one carries its own copy of the .NET runtime. That is why they are ~55 MB rather than ~400 KB.

This is a deliberate trade. The framework-dependent packages this replaces were tiny, but "the app won't start" — because .NET was missing, or because the user had installed the runtime for the wrong architecture — was by a wide margin the most common support problem. RSS Quick is aimed at people who should be able to download it and read the news, not diagnose a runtime dialog. Bandwidth is cheaper than that.

**The installer is per-user.** Velopack installs into `%LocalAppData%\RSSQuick`, so there is never a UAC prompt, and the installed copy can replace itself without one. There is no wizard: Setup installs, adds a Start Menu shortcut and starts RSS Quick, which is fewer pages for a screen reader to get through than the Inno Setup installer it replaced.

**Updates replace the shipped `RSS.opml`.** Velopack swaps the whole program folder, so a list edited in place there would be lost. That is why the reader's own list lives in `%APPDATA%\RSSQuick\Default.opml` (Make This My Default), which no update touches. The first start after moving from the old installer copies an edited `RSS.opml` there before removing the old copy; see `src/RSSQuick/Services/PreviousInstall.cs`.

**The portable build writes nothing outside its own folder.** It reads `RSS.opml` from the working directory first and falls back to the folder holding the executable, so a copy on a USB stick uses the feed list that travels with it.

## Trying an update without publishing one

An installed copy reads its updates from GitHub, but `RSSQUICK_UPDATE_FEED` points it at a folder
instead, so the whole download-and-install cycle can be tried before a release exists.

1. `package.cmd x64`, and install `artifacts\RSSQuick-<version>-setup-win-x64.exe`.
2. Put a higher version in `VERSION`, then build again without emptying the feed:
   `powershell -File build/publish.ps1 -Architecture x64 -KeepReleaseFeed`.
   `artifacts\releases` now holds both versions, and a delta between them.
3. Start the installed copy with the variable set, from a Command Prompt in the repository:

   ```bash
   set RSSQUICK_UPDATE_FEED=%CD%\artifacts\releases && "%LocalAppData%\RSSQuick\current\RSSQuick.exe"
   ```

   About five seconds after it opens, the status bar says the new version has downloaded, and
   Restart and Update appears.
4. Put `VERSION` back, and uninstall from Installed Apps when you are done.

## Troubleshooting

**"SDK not found"** — install the .NET 10 SDK, then restart your terminal or editor so it picks up the new PATH.

**Package restore fails** — `dotnet restore`, then build again.

**`vpk pack` says the version already exists** — `artifacts/releases` still holds this version from an earlier run with `-KeepReleaseFeed`. Run without it, which empties the folder first.

**ARM64 build fails on an Intel machine** — it should not; the ARM64 build is cross-compiled and needs no ARM hardware. If it does, build the architectures separately with `package.cmd x64` and `package.cmd arm64` to see which step is failing.
