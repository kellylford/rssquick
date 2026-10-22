<#
.SYNOPSIS
    Sets the version for a release and prints the remaining steps.

.DESCRIPTION
    VERSION is the single source of truth: Directory.Build.props reads it into the executable's
    file version, and build/publish.ps1 reads it for the artefact filenames. Setting it here is
    the only place it needs changing.

.PARAMETER Platforms
    Where this release ships: windows, macos, ios, or any of them. All three by default. A
    feature release (x.y.0) always ships on all three; a fix (x.y.z) ships only where something
    changed, so nobody is sent a new version with nothing in it. The version counter is shared:
    a Windows fix is 1.4.1, a later Mac fix 1.4.2, and the Mac never has a 1.4.1. Written to
    RELEASE-PLATFORMS, which each release workflow reads; build/release-platforms.sh, and
    WORKFLOW.md for the rule.

.EXAMPLE
    pwsh build/prepare-release.ps1 1.1.0

.EXAMPLE
    pwsh build/prepare-release.ps1 1.4.1 -Platforms windows
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $Version,

    [ValidateSet('windows', 'macos', 'ios')]
    [string[]] $Platforms = @('windows', 'macos', 'ios')
)

$ErrorActionPreference = 'Stop'

$all = 'windows', 'macos', 'ios'
$Platforms = @($all | Where-Object { $Platforms -contains $_ })
if ($Version.EndsWith('.0') -and $Platforms.Count -ne $all.Count) {
    throw "$Version is a feature release, and a feature release ships on all three platforms. Only a fix (x.y.z, z above 0) can ship on some of them."
}

$repo = Split-Path -Parent $PSScriptRoot
# No byte-order mark. Windows PowerShell 5.1's Set-Content -Encoding UTF8 always writes one,
# and while .NET skips it, the macOS build reads VERSION with `tr` in bash: the mark survives
# into the bundle's version string and makes the release workflow's tag check fail.
[System.IO.File]::WriteAllText((Join-Path $repo 'VERSION'), $Version, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "VERSION set to $Version."

# The iOS marketing version, so local Xcode and CI builds report the same version. Release builds
# take it from the tag anyway; this only stops it drifting in between. Both files, because the
# committed .xcodeproj is what Xcode reads and project.yml is what regenerates it.
if ($Platforms -contains 'ios') {
    foreach ($file in 'ios\project.yml', 'ios\RSSQuick.xcodeproj\project.pbxproj') {
        $path = Join-Path $repo $file
        $text = [System.IO.File]::ReadAllText($path)
        $text = [regex]::Replace($text, '(MARKETING_VERSION ?[:=] ?)\d+\.\d+\.\d+', "`${1}$Version")
        [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
    }
    Write-Host "iOS MARKETING_VERSION set to $Version."
} else {
    Write-Host 'iOS MARKETING_VERSION left as it is: this release does not ship on iPhone and iPad.'
}

# No byte-order mark, for the same reason as VERSION: build/release-platforms.sh reads it in bash.
[System.IO.File]::WriteAllText((Join-Path $repo 'RELEASE-PLATFORMS'), ($Platforms -join ' '), (New-Object System.Text.UTF8Encoding($false)))
$names = @{ windows = 'Windows'; macos = 'Mac'; ios = 'iPhone and iPad' }
if ($Platforms.Count -eq $all.Count) {
    Write-Host 'RELEASE-PLATFORMS: all three platforms.'
} else {
    Write-Host "RELEASE-PLATFORMS: $(($Platforms | ForEach-Object { $names[$_] }) -join ', ') only. The other workflows will skip this tag,"
    Write-Host 'and the release notes will open by saying which platforms it is for.'
}

Write-Host ''
Write-Host 'Remaining steps:'
if ($Platforms.Count -eq $all.Count) {
    Write-Host "  1. Add a [$Version] section to CHANGELOG.md."
} else {
    Write-Host "  1. Add a [$Version] section to CHANGELOG.md, headed with the platforms, such as"
    Write-Host "     ## [$Version] - <date> - $(($Platforms | ForEach-Object { $names[$_] }) -join ', ') only"
}
Write-Host '  2. Run the tests:            build.cmd test'
Write-Host '  3. Build the artefacts:      package.cmd'
Write-Host '  4. Try the installer and the portable ZIP by hand, with a screen reader running.'
Write-Host "  5. git commit -am `"Release v$Version`""
Write-Host "  6. git tag -a v$Version -m `"Release v$Version`""
Write-Host "  7. git push origin main --follow-tags"
Write-Host ''
Write-Host 'Pushing the tag runs two workflows. release.yml rebuilds the Windows artefacts on a'
Write-Host 'clean runner; macos-release.yml builds, signs and notarises the macOS disk image. Both'
Write-Host 'attach to the same draft GitHub release for you to review and publish.'
Write-Host ''
Write-Host 'Publishing that draft is what ships the update. Installed Windows copies download it'
Write-Host 'within a few seconds of their next start and install it when they close; portable and'
Write-Host 'macOS copies say a new version is available. Nothing is offered while it is a draft.'
Write-Host ''
Write-Host 'The macOS half cannot be built or checked from here. It needs a Mac for step 4 —'
Write-Host 'opening the finished image with VoiceOver — and that step is not optional. See the'
Write-Host 'macOS section of WORKFLOW.md.'
