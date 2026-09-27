# SPDX-License-Identifier: AGPL-3.0-or-later
<#
.SYNOPSIS
  Builds everything and publishes a GitHub release that installed launchers
  pick up as an update (GAME_DESIGN.md §13.12).

.DESCRIPTION
  1. Optionally bumps the build number (-Bump): 0.YY.BBB -> 0.YY.BBB+1.
  2. Builds the web game and the launcher, and packages
     dist\CrownAndCard-<version>-win64.zip (+ .sha256).
  3. Creates GitHub release v<version> on DavidKendig/CrownAndCard with the zip
     and checksum attached (needs the GitHub CLI, `gh auth login`).

  Commit and push the version bump before publishing, so the tag points at
  the code that built the release.

.EXAMPLE
  powershell -File tools\release.ps1 -Bump -Notes "Controller support"
#>
param(
    [switch]$Bump,
    [string]$Notes = "",
    [switch]$Draft
)
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
Push-Location $repo
try {
    if ($Bump) { python tools\version.py bump | Out-Host }
    $version = (Get-Content version.json -Raw | ConvertFrom-Json).version

    haxe build-js.hxml
    if ($LASTEXITCODE -ne 0) { throw "Game build failed." }
    & powershell -NoProfile -ExecutionPolicy Bypass -File launcher\build.ps1 -Package
    if ($LASTEXITCODE -ne 0) { throw "Launcher build failed." }

    $zip = "dist\CrownAndCard-$version-win64.zip"
    $args = @("release", "create", "v$version", $zip, "$zip.sha256",
        "--repo", "DavidKendig/CrownAndCard",
        "--title", "Crown & Card $version",
        "--notes", $(if ($Notes) { $Notes } else { "Crown & Card $version" }))
    if ($Draft) { $args += "--draft" }
    gh @args
    if ($LASTEXITCODE -ne 0) { throw "gh release create failed." }
    Write-Host "Published v$version"
}
finally {
    Pop-Location
}
