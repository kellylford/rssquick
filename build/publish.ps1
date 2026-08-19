<#
.SYNOPSIS
    Builds the release artefacts: a portable ZIP and an installer, per architecture.

.DESCRIPTION
    Both artefacts are self-contained, so neither one asks the user to install .NET first.
    That is deliberate: "app won't start, missing .NET Runtime" was the single most common
    support problem with the framework-dependent packages this replaces, and the people
    RSS Quick is built for should not have to diagnose a runtime dialog.

.PARAMETER Architecture
    x64, arm64, or both (the default).

.PARAMETER SkipInstaller
    Produce only the portable ZIP. Useful when Inno Setup is not installed.

.EXAMPLE
    pwsh build/publish.ps1 -Architecture x64
#>
[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64', 'both')]
    [string] $Architecture = 'both',

    [switch] $SkipInstaller
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo      = Split-Path -Parent $PSScriptRoot
$project   = Join-Path $repo 'RSSReaderWPF.csproj'
$artifacts = Join-Path $repo 'artifacts'
$staging   = Join-Path $artifacts 'staging'
$version   = (Get-Content (Join-Path $repo 'VERSION') -Raw).Trim()

if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "VERSION should hold a three-part version such as 1.1.0, but holds '$version'."
}

if ($Architecture -eq 'both') { $targets = @('x64', 'arm64') } else { $targets = @($Architecture) }

# Find the Inno Setup compiler. Present on GitHub's windows runners; installed from
# https://jrsoftware.org/isdl.php locally.
function Get-InnoCompiler {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }

    $onPath = Get-Command 'iscc.exe' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    return $null
}

Write-Host "RSS Quick $version"
Write-Host "Building: $($targets -join ', ')"
Write-Host ''

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Path $artifacts -Force | Out-Null

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

Unzip anywhere and run RSSQuick.exe. Nothing is installed, and nothing is written
outside this folder. A USB stick works fine.

.NET does not need to be installed - this build carries its own copy.

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
        $iscc = Get-InnoCompiler
        if (-not $iscc) {
            Write-Warning "[$rid] Inno Setup not found; skipping the installer. Install it from https://jrsoftware.org/isdl.php, or pass -SkipInstaller to stop asking."
        }
        else {
            # The installer payload is the portable tree minus its portable-only readme.
            $installerSource = Join-Path $staging "installer-$rid"
            New-Item -ItemType Directory -Path $installerSource -Force | Out-Null
            Get-ChildItem $outDir -Exclude 'README-PORTABLE.txt' | Copy-Item -Destination $installerSource -Recurse -Force

            & $iscc `
                "/DAppVersion=$version" `
                "/DArch=$arch" `
                "/DSourceDir=$installerSource" `
                "/DOutputDir=$artifacts" `
                (Join-Path $repo 'installer\rssquick.iss')

            if ($LASTEXITCODE -ne 0) { throw "[$rid] installer build failed." }

            $setup = Join-Path $artifacts "RSSQuick-$version-setup-$rid.exe"
            $built += $setup
            Write-Host "[$rid] installer -> $(Split-Path -Leaf $setup)"
        }
    }

    Write-Host ''
}

Write-Host 'Done. Artefacts:'
foreach ($f in $built) {
    $sizeMb = [math]::Round((Get-Item $f).Length / 1MB, 1)
    Write-Host ("  {0,-45} {1} MB" -f (Split-Path -Leaf $f), $sizeMb)
}
