<#
.SYNOPSIS
    Sets the version for a release and prints the remaining steps.

.DESCRIPTION
    VERSION is the single source of truth: Directory.Build.props reads it into the executable's
    file version, and build/publish.ps1 reads it for the artefact filenames. Setting it here is
    the only place it needs changing.

.EXAMPLE
    pwsh build/prepare-release.ps1 1.1.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $Version
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
Set-Content -Path (Join-Path $repo 'VERSION') -Value $Version -NoNewline -Encoding UTF8

Write-Host "VERSION set to $Version."
Write-Host ''
Write-Host 'Remaining steps:'
Write-Host "  1. Add a [$Version] section to CHANGELOG.md."
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
Write-Host 'The macOS half cannot be built or checked from here. It needs a Mac for step 4 —'
Write-Host 'opening the finished image with VoiceOver — and that step is not optional. See the'
Write-Host 'macOS section of WORKFLOW.md.'
