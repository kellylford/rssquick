# Microsoft Store — Plan

**Date:** 2026-09-30
**Status:** the code, the packaging and the privacy policy are done (Part 5 has the detail).
What remains is trying the package with a screen reader, and Partner Center. The name **RSSQuick** is reserved in
Partner Center. No release goes out until the Store package has been tried end to end, so the
first Store submission and the next GitHub release are the same version.

QuickMail's `docs/planning/microsoft-store-msix-plan.md` is the house reference for this, and
most of what made it hard there does not apply here: RSS Quick has no saved passwords, no
WebView2 and no database. What it keeps between runs is one file.

## Why the Store

A Store package is re-signed by Microsoft, so installing it never meets the SmartScreen
"isn't commonly downloaded" prompt that a signed download from GitHub still gets — that prompt
is keyed to each file's download count, and signing cannot clear it. Windows then keeps the
Store copy up to date by itself. Registration and hosting are free.

The Store also accepts a plain installer (our Velopack `Setup.exe`) as an "unpackaged" listing,
but Microsoft does not re-sign those, so the prompt stays. That route is not worth the
submission. This plan packages the existing app as **MSIX**.

## What does not change

- The GitHub installer, the portable ZIP, the Velopack update feed and code signing. They stay
  primary, and every copy installed from them keeps updating itself.
- The app's code paths for reading feeds, focus, keyboard and the tab ring. The Store copy is
  the same program; a package only changes where it is installed from and who updates it.
- macOS and iOS. This is Windows packaging, not a feature, so it has no counterpart there. (The
  Mac is distributed as a notarised disk image; the Mac App Store would be its own decision.)

## Part 1 — What the app does differently in a package

One question decides all of it: *is this copy running from a package?* Windows answers it
through `GetCurrentPackageFullName`, which fails with `APPMODEL_ERROR_NO_PACKAGE` for anything
that is not. `Services/PackageIdentity.IsPackaged` asks once.

1. **No update check.** `App.OfferUpdateAsync` treats any copy Velopack did not install as
   portable and asks GitHub about a newer version. A Store copy would fall into that path and
   offer a GitHub download, which the Store does not allow and which would leave the reader with
   two copies. When packaged, App skips the check, so the Update button never appears.
2. **Help, Check for Updates still answers.** Menu items are never disabled or hidden here (a
   reader arrowing through a menu should meet everything in it), so the item stays and says:
   "Windows keeps this copy of RSS Quick up to date through the Microsoft Store. This is
   version 1.3.0".
3. **About says where it came from**: "Installed from the Microsoft Store."
4. **No retiring the old Inno Setup install.** `PreviousInstall.Retire` only runs for a copy
   Velopack installed, which a packaged copy is not, but the check is made explicit so it can
   never start: a Store app uninstalling other software would be wrong in itself.

Nothing else needs to change. The starter `RSS.opml` is read from beside the program, which in
a package is a read-only folder, but nothing ever writes there. Opening articles, file dialogs,
and the text-scale setting all work the same in a package.

## Part 2 — Where saved data goes, now and later

Today the one saved thing is `%APPDATA%\RSSQuick\Default.opml`.

A packaged desktop app keeps `%APPDATA%` as its path, but Windows redirects **new** files written
there into the package's private folder
(`%LOCALAPPDATA%\Packages\<package family>\LocalCache\Roaming`) and shows the app a merged view.
A file that already existed in the real `%APPDATA%` is readable; changing it writes a private copy.
In practice:

- **A new Store user** saves their default list into the package's folder, and it works.
- **Someone moving from the GitHub copy** finds their saved list on the first run, because the
  file already exists and reads fall through (measured; see Q1). Once they save a new default from the Store
  copy, the two copies no longer share it. This is what the first test package has to confirm
  (Part 5, step 3). If reads do not fall through, File, Export and Import move the list across,
  and that is a sentence in the README.
- **Uninstalling the Store copy deletes its saved data.** That is Windows' rule for packages and
  not something the app can change.

### If RSS Quick starts saving more

**That is fine, and nothing about the Store makes it harder**, as long as three rules hold. They
are the same rules that keep the GitHub copy tidy, so they are worth following regardless:

1. **Everything saved lives in `%APPDATA%\RSSQuick`, found through one helper.** Settings, read
   state, window size: files in that folder. Windows redirects the whole folder consistently, so
   the app never needs to know whether it is packaged. Where it goes wrong is data scattered
   across several places, each redirected, or not, in its own way.
2. **Nothing is ever written beside the program.** In a package that folder is read-only, and a
   write fails. (The portable copy's "keep everything in my folder" appeal does not change this:
   it already saves its default list to the profile.)
3. **Files rather than the registry.** A package's writes to `HKEY_CURRENT_USER` are virtualised
   as well, and are harder to inspect or move than a file a reader can see, back up or copy.

What *does* get harder with more data is the move between a GitHub copy and a Store copy: each
new thing saved is one more thing the two copies stop sharing once either changes it. If that
matters later, the answer is an explicit File, Export Settings, not trying to make the two
copies share a folder. Two copies writing one set of files, with nothing stopping both running
at once, is the trap QuickMail's plan identified.

## Part 3 — The package

- **Identity.** Three values from Partner Center, under *Product management → Product identity*:
  `Package/Identity/Name`, `Package/Identity/Publisher` (a `CN=` followed by a GUID), and
  `Package/Properties/PublisherDisplayName`. They go in `build/store/identity.json`. They are not
  secret; every package carries them.
- **Manifest.** `build/store/AppxManifest.xml` is a template: a full-trust desktop app
  (`runFullTrust`), `internetClient`, Windows 10 1809 or later, display name "RSS Quick".
- **Version.** MSIX needs four parts with the last one 0, so `VERSION` 1.3.0 becomes `1.3.0.0`.
  The packaging script adds it; `VERSION` stays the only place a version is written. Every
  submission must carry a higher version than the last, which the one-version rule gives us.
- **Logos.** Made at build time from the iOS app icon
  (`ios/RSSQuick/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`), so all three platforms
  show the same mark and there is one source image to change.
- **Loose files, not single-file.** The GitHub builds are one self-contained executable because
  that makes a tidy portable ZIP. The Store build is the same self-contained app published as
  ordinary files: the Store's differential updates compare blocks, and one compressed executable
  changes almost everywhere between versions, so every update would be a full download.
- **Both architectures**, x64 and ARM64, bundled into one `.msixbundle`. Partner Center takes the
  bundle and each device installs the part it needs.
- **Unsigned.** The Store signs what it publishes. Our Azure certificate is not used for this.
- **Tools.** `makeappx` comes from Microsoft's `Microsoft.Windows.SDK.BuildTools` NuGet package,
  downloaded by the script at a pinned version, so neither the dev machine nor CI needs the
  Windows SDK installed.

`build/package-store.ps1` does all of this, and `package.cmd store` runs it. With `-Install` it
also registers the x64 layout on this machine (Developer Mode, which is on), so the packaged app
can be run and checked with a screen reader before anything goes to Microsoft.

## Part 4 — CI

`release.yml` builds the bundle on every `v*` tag, alongside the other packages, and uploads it
as a workflow artifact. It is **not** attached to the GitHub release: an unsigned MSIX will not
install for anyone, and it would only confuse. On a tag the script requires real identity
values, so a release cannot quietly produce a bundle Partner Center would reject.

The first submission is by hand, to read the certification report. Automating submission through
the Store submission API can come after, if uploading by hand becomes a chore.

## Part 5 — Order of work

1. **Code** — done: `PackageIdentity`, the Store behaviour in App and the window,
   `StoreCopyTests`.
2. **Packaging** — done: the manifest template, logos, `package-store.ps1`, `package.cmd store`,
   and the bundle step in `release.yml`. Both architectures build; the ARM64 package registers
   and runs on the dev machine, and Check for Updates there gives the Store answer.
3. **Try it on this machine** — partly done (see Q1): `package.cmd store -Install`, then with a screen reader:
   the app starts; the starter list or the saved default opens; Check for Updates and About say
   Store; Make This My Default saves and survives a restart; Export and Import work; an article
   opens in the browser. Also record where `Default.opml` was read from and written to (Part 2).
4. **Kelly, in Partner Center**: copy the three identity values into `build/store/identity.json`;
   publish `docs/privacy.html` to theideaplace.net and give Partner Center its URL; set up the
   listing from `docs/store/LISTING.md`; age rating
   questionnaire; screenshots.
5. **Release**: `prepare-release.ps1 1.3.0`, tag, publish the GitHub draft, upload
   `RSSQuick-1.3.0.msixbundle` to Partner Center, submit.
6. **After it is live**: a Store link in the README and on the projects page.

## Part 6 — The listing (Kelly's part)

`docs/store/LISTING.md` has draft text for each field: description, features, keywords, what's
new, and suggested answers for the age-rating questionnaire.

- **Privacy policy URL.** Required:
  `https://theideaplace.net/projects/rssquick/privacy.html`. Its source is `docs/privacy.html`
  here, one policy for all three platforms. It says the app collects nothing and names every host
  the app connects to, so any change to what RSS Quick fetches or keeps has to update that page,
  and its effective date, in the same pull request.
- **Screenshots.** At least one, 1366×768 or larger. The window with a folder open and headlines
  loaded is the one that explains the app.
- **Accessibility.** Partner Center lets a listing declare that the product has been tested
  against accessibility guidelines. RSS Quick has.
- **Category:** News & weather.

## Open questions

1. **Q1 — reads answered, 2026-09-30.** A package registered on the dev machine (Windows 11,
   ARM64) opened the existing `%APPDATA%\RSSQuick\Default.opml` saved by the GitHub copy: its
   tree showed the saved list, not the starter. Still to see: where Make This My Default writes
   from the Store copy, and that the GitHub copy then keeps its own list.
2. **Q2.** Should the Store copy open `.opml` files from File Explorer (a file-type association in
   the manifest)? The GitHub copy does not today, so this would be a feature for both and belongs
   in its own change.
3. **Q3.** Package size and whether differential updates earn their keep, from the first two
   Store versions. If they do not, the Store build can go back to single-file.
