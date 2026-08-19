# Building and packaging RSS Quick

## What you need

- **Windows 10 or 11.** WPF is Windows-only; there is no way to build this elsewhere.
- **[.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)** — the SDK, not just the runtime. Check with `dotnet --version`.
- **[Inno Setup 6](https://jrsoftware.org/isdl.php)**, only if you want to build the installer. Without it you still get the portable ZIP.

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
RSSQuick-1.1.0-setup-win-x64.exe        installer, Intel/AMD
RSSQuick-1.1.0-portable-win-x64.zip     portable, Intel/AMD
RSSQuick-1.1.0-setup-win-arm64.exe      installer, ARM
RSSQuick-1.1.0-portable-win-arm64.zip   portable, ARM
```

Pass an architecture to build just one: `package.cmd x64`.

Each is about 55 MB, and each takes a minute or two to compile and compress.

Under the hood `package.cmd` runs `build/publish.ps1`, which you can call directly for more control:

```bash
powershell -File build/publish.ps1 -Architecture x64 -SkipInstaller
```

## Why the packages are built this way

**Both packages are self-contained**, meaning each one carries its own copy of the .NET runtime. That is why they are ~55 MB rather than ~400 KB.

This is a deliberate trade. The framework-dependent packages this replaces were tiny, but "the app won't start" — because .NET was missing, or because the user had installed the runtime for the wrong architecture — was by a wide margin the most common support problem. RSS Quick is aimed at people who should be able to download it and read the news, not diagnose a runtime dialog. Bandwidth is cheaper than that.

**The installer is per-user by default.** `PrivilegesRequired=lowest` means the common case never raises a UAC prompt; nothing here needs administrator rights. An administrator can still choose an all-users install on the first wizard page.

**The installer will not overwrite an edited feed list.** `RSS.opml` is installed with Inno's `onlyifdoesntexist` flag, so upgrading keeps whatever you have edited in place.

**The portable build writes nothing outside its own folder.** It reads `RSS.opml` from the working directory first and falls back to the folder holding the executable, so a copy on a USB stick uses the feed list that travels with it.

## Building the installer by hand

`build/publish.ps1` does this for you, but if you need to run the compiler directly:

```bash
ISCC.exe /DAppVersion=1.1.0 /DArch=x64 /DSourceDir=<published files> /DOutputDir=artifacts installer\rssquick.iss
```

Every value the script needs comes in through `/D`. `installer/rssquick.iss` documents what each one is for.

## Troubleshooting

**"SDK not found"** — install the .NET 10 SDK, then restart your terminal or editor so it picks up the new PATH.

**Package restore fails** — `dotnet restore`, then build again.

**`package.cmd` warns that Inno Setup was not found** — install it from [jrsoftware.org](https://jrsoftware.org/isdl.php), or pass `-SkipInstaller` if you only want the portable ZIP.

**ARM64 build fails on an Intel machine** — it should not; the ARM64 build is cross-compiled and needs no ARM hardware. If it does, build the architectures separately with `package.cmd x64` and `package.cmd arm64` to see which step is failing.
