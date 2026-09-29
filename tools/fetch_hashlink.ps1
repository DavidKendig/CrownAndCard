# SPDX-License-Identifier: AGPL-3.0-or-later
<#
.SYNOPSIS
  Puts the HashLink runtime in native\, beside the native build (native\game.hl).

.DESCRIPTION
  Downloads the official Windows release of HashLink from the HaxeFoundation's
  GitHub, checks it against the SHA-256 pinned below (the digest GitHub
  publishes for the release asset), and copies the runtime into native\:
  hl.exe, libhl.dll, the .hdll libraries (sdl, openal, fmt, ui, ...) and the
  DLLs they need (SDL2, OpenAL). The launcher then finds native\hl.exe +
  native\game.hl and runs the game in its own window.

  The version must match the hlsdl and hlopenal haxelibs the game compiles
  against (README: Building). To move to a new HashLink, update all three and
  the digest together.
#>
param([string]$Destination = (Join-Path (Split-Path $PSScriptRoot -Parent) "native"))
$ErrorActionPreference = "Stop"

$version = "1.16"
$asset = "hashlink-1.16.0-win.zip"
$sha256 = "ec80b5bfbe93ae497ff43cd72d5bb4d906de3c6398839ba692fa28c47b54aa0f"
$url = "https://github.com/HaxeFoundation/hashlink/releases/download/$version/$asset"

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("hashlink-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $work | Out-Null
try {
    $zip = Join-Path $work $asset
    Write-Host "Downloading $url"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    $actual = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLowerInvariant()
    if ($actual -ne $sha256) { throw "$asset has SHA-256 $actual; expected $sha256. Not installing it." }

    Expand-Archive -Path $zip -DestinationPath (Join-Path $work "x") -Force
    $hl = Get-ChildItem (Join-Path $work "x") -Recurse -Filter hl.exe | Select-Object -First 1
    if (-not $hl) { throw "$asset has no hl.exe." }

    New-Item -ItemType Directory -Force $Destination | Out-Null
    $runtime = Get-ChildItem $hl.DirectoryName -File | Where-Object { $_.Extension -in ".exe", ".dll", ".hdll" }
    foreach ($f in $runtime) { Copy-Item $f.FullName $Destination -Force }
    foreach ($license in Get-ChildItem $hl.DirectoryName -File | Where-Object { $_.Name -match '^(LICENSE|COPYING)' }) {
        Copy-Item $license.FullName (Join-Path $Destination ("HASHLINK-" + $license.Name)) -Force
    }
    Write-Host "HashLink $version runtime ($($runtime.Count) files) is in $Destination"
}
finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
