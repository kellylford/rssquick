<#
.SYNOPSIS
    Builds the release artefacts: a portable ZIP and an installer, per architecture, and the
    update feed installed copies read.

.DESCRIPTION
    Both artefacts are self-contained, so neither one asks the user to install .NET first.
    That is deliberate: "app won't start, missing .NET Runtime" was the single most common
    support problem with the framework-dependent packages this replaces, and the people
    RSS Quick is built for should not have to diagnose a runtime dialog.

    The installer is Velopack's Setup.exe, built by `vpk pack`, which also writes the update
    feed into artifacts\releases: the packages and the releases.<channel>.json files an
    installed copy reads to update itself. Every file in that folder is uploaded to the GitHub
    release. x64 is Velopack's default `win` channel and ARM64 is `win-arm64`, the same split
    QuickMail uses; an installed copy only ever looks at the channel it came from.

    vpk is a local .NET tool pinned in .config/dotnet-tools.json, restored here, so there is
    nothing to install first.

.PARAMETER Architecture
    x64, arm64, or both (the default).

.PARAMETER SkipInstaller
    Produce only the portable ZIP.

.PARAMETER KeepReleaseFeed
    Leave artifacts\releases as it is instead of emptying it first. The release workflow runs
    `vpk download github` into it beforehand, so the previous version is there for vpk to build
    a delta package against - a few hundred kilobytes to download instead of the whole 55 MB.

.EXAMPLE
    pwsh build/publish.ps1 -Architecture x64
#>
[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64', 'both')]
    [string] $Architecture = 'both',

    [switch] $SkipInstaller,

    [switch] $KeepReleaseFeed
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo      = Split-Path -Parent $PSScriptRoot
$project   = Join-Path $repo 'src\RSSQuick\RSSQuick.csproj'
$artifacts = Join-Path $repo 'artifacts'
$staging   = Join-Path $artifacts 'staging'
$releases  = Join-Path $artifacts 'releases'
$version   = (Get-Content (Join-Path $repo 'VERSION') -Raw).Trim()

if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "VERSION should hold a three-part version such as 1.1.0, but holds '$version'."
}

# dotnet finds the vpk tool manifest by looking up from the current directory, so work from
# the repository whichever folder the script was started in.
Push-Location $repo

if ($Architecture -eq 'both') { $targets = @('x64', 'arm64') } else { $targets = @($Architecture) }

Write-Host "RSS Quick $version"
Write-Host "Building: $($targets -join ', ')"
Write-Host ''

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Path $artifacts -Force | Out-Null

if (-not $SkipInstaller) {
    # Emptied unless asked not to: vpk refuses to pack a version the feed already holds, so a
    # second local run would otherwise fail on the first run's output.
    if ((Test-Path $releases) -and -not $KeepReleaseFeed) { Remove-Item $releases -Recurse -Force }
    New-Item -ItemType Directory -Path $releases -Force | Out-Null

    & dotnet tool restore
    if ($LASTEXITCODE -ne 0) { throw 'dotnet tool restore failed; vpk is needed to build the installer.' }
}

$built = @()

foreach ($arch in $targets) {
    $rid     = "win-$arch"
    $outDir  = Join-Path $staging $rid

    Write-Host "[$rid] publishing..."

    # Self-contained single file. Native libraries are extracted rather than left loose so the
    # portable ZIP really is one executable plus the feed list.
    & dotnet publish $project `
        --configuration Release `
        --runtime $rid `
        --self-contained true `
        --output $outDir `
        -p:PublishSingleFile=true `
        -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:EnableCompressionInSingleFile=true `
        -p:DebugType=none `
        --nologo

    if ($LASTEXITCODE -ne 0) { throw "[$rid] publish failed." }

    Copy-Item (Join-Path $repo 'README.md')  $outDir -Force
    Copy-Item (Join-Path $repo 'LICENSE')    $outDir -Force

    # A portable copy keeps everything in its own folder, so say so where someone will see it.
    @"
RSS Quick $version - portable
=============================

Unzip anywhere and run RSSQuick.exe. Nothing is installed, and a USB stick works fine.
The one thing written outside this folder is a feed list you save with Make This My
Default, which is kept in your Windows profile on this computer.

.NET does not need to be installed - this build carries its own copy.

This copy does not update itself. When a newer version is published, RSS Quick says so
in its status bar and offers the download page.

RSS.opml in this folder is the feed list loaded at startup. Replace it with your own,
or use the "Import OPML File" button to load a different one.

Source and issues: https://github.com/kellylford/rssquick
"@ | Set-Content -Path (Join-Path $outDir 'README-PORTABLE.txt') -Encoding UTF8

    $zip = Join-Path $artifacts "RSSQuick-$version-portable-$rid.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zip
    $built += $zip
    Write-Host "[$rid] portable  -> $(Split-Path -Leaf $zip)"

    if (-not $SkipInstaller) {
        # The installer payload is the portable tree minus its portable-only readme.
        $installerSource = Join-Path $staging "installer-$rid"
        New-Item -ItemType Directory -Path $installerSource -Force | Out-Null
        Get-ChildItem $outDir -Exclude 'README-PORTABLE.txt' | Copy-Item -Destination $installerSource -Recurse -Force

        # x64 stays on the default channel. Every installed x64 copy polls releases.win.json, so
        # naming its channel now would strand them; ARM64 gets its own.
        if ($arch -eq 'arm64') {
            $channelArgs = @('--runtime', 'win-arm64', '--channel', 'win-arm64')
            $channel = 'win-arm64'
        }
        else {
            $channelArgs = @()
            $channel = 'win'
        }

        # Per-user, like the Inno Setup installer it replaces, so there is no administrator
        # prompt. One Start Menu shortcut and no desktop one, which is what Inno did by default.
        & dotnet tool run vpk pack `
            --packId RSSQuick `
            --packVersion $version `
            --packDir $installerSource `
            --mainExe RSSQuick.exe `
            --packTitle 'RSS Quick' `
            --packAuthors 'Kelly Ford' `
            --shortcuts StartMenuRoot `
            --instLocation PerUser `
            --outputDir $releases `
            @channelArgs

        if ($LASTEXITCODE -ne 0) { throw "[$rid] vpk pack failed." }

        # vpk names Setup after the channel with no version in it. Renamed to the same pattern the
        # Inno Setup installer used, so links to it keep their shape. Named exactly rather than
        # globbed, so a change in vpk's naming fails here instead of shipping nothing.
        $vpkSetup = Join-Path $releases "RSSQuick-$channel-Setup.exe"
        if (-not (Test-Path $vpkSetup)) {
            $found = (Get-ChildItem $releases -Filter '*Setup.exe' | Select-Object -ExpandProperty Name) -join ', '
            throw "[$rid] expected $(Split-Path -Leaf $vpkSetup) from vpk, found: $found"
        }
        $setup = Join-Path $artifacts "RSSQuick-$version-setup-$rid.exe"
        Move-Item $vpkSetup $setup -Force

        # vpk's own portable ZIP. The one built above is the portable download: it carries the
        # feed list and the readme, and it does not try to update itself in place.
        Remove-Item (Join-Path $releases "RSSQuick-$channel-Portable.zip") -ErrorAction SilentlyContinue

        $built += $setup
        Write-Host "[$rid] installer -> $(Split-Path -Leaf $setup)"
    }

    Write-Host ''
}

Write-Host 'Done. Artefacts:'
foreach ($f in $built) {
    $sizeMb = [math]::Round((Get-Item $f).Length / 1MB, 1)
    Write-Host ("  {0,-45} {1} MB" -f (Split-Path -Leaf $f), $sizeMb)
}

if (-not $SkipInstaller) {
    Write-Host ''
    Write-Host 'Update feed (artifacts\releases, every file goes on the release):'
    Get-ChildItem $releases | ForEach-Object { Write-Host "  $($_.Name)" }
}

Pop-Location
