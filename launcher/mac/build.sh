#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Builds "Crown & Card.app", the launcher for macOS (Apple Silicon), at the repo root.
#
#   sh launcher/mac/build.sh
#
# 1. Publishes the launcher (CrownAndCardLauncher.Mac.csproj: the shared
#    launcher code in ../src plus the Avalonia UI) as a self-contained osx-arm64
#    app, with the menu-music decoder (libcc_vorbis.dylib) beside it.
# 2. Wraps it in an app bundle: Contents/MacOS (the launcher), Contents/Resources
#    (the icon and the menu loop), Info.plist with the version from version.json.
# 3. Signs it ad hoc, so macOS runs it on this Mac.
#
# The bundle finds the game in the repo (native/mac/game from tools/build_mac.sh,
# and web/ from `haxe build-js.hxml`), like the Windows launcher at the repo root.
#
# Needs the .NET 10 SDK (dotnet) and Xcode's command line tools (clang, iconutil).
set -e
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
app="$repo/Crown & Card.app"
version="$(sed -n 's/.*"version"[^"]*"\([0-9.]*\)".*/\1/p' "$repo/version.json")"
[ -n "$version" ] || { echo "Couldn't read the version from version.json" >&2; exit 1; }

command -v dotnet >/dev/null 2>&1 || { [ -x "$HOME/.dotnet/dotnet" ] && export PATH="$HOME/.dotnet:$PATH" DOTNET_ROOT="$HOME/.dotnet"; }
command -v dotnet >/dev/null 2>&1 || { echo "The .NET SDK wasn't found (https://dot.net, or dotnet-install.sh into ~/.dotnet)." >&2; exit 1; }
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

publish="$here/bin/publish"
rm -rf "$publish"
dotnet publish "$here/CrownAndCardLauncher.Mac.csproj" -c Release -r osx-arm64 --self-contained -o "$publish"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/music"
cp -R "$publish/" "$app/Contents/MacOS/"
rm -f "$app/Contents/MacOS/"*.pdb
cp "$repo/res/audio/music/menu-loop-dark.ogg" "$app/Contents/Resources/music/"

# The icon, from the same art as the Windows launcher.ico.
iconset="$here/bin/AppIcon.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
	sips -z $size $size "$here/../assets/launcher-icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
	double=$((size * 2))
	sips -z $double $double "$here/../assets/launcher-icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Crown &amp; Card</string>
	<key>CFBundleDisplayName</key>
	<string>Crown &amp; Card</string>
	<key>CFBundleIdentifier</key>
	<string>info.davidkendig.crownandcard.launcher</string>
	<key>CFBundleExecutable</key>
	<string>CrownAndCardLauncher</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$version</string>
	<key>CFBundleVersion</key>
	<string>$version</string>
	<key>LSMinimumSystemVersion</key>
	<string>12.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.games</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright (C) 2026 David Kendig. AGPL-3.0-or-later.</string>
</dict>
</plist>
EOF

xattr -cr "$app"
codesign --force --deep --sign - "$app" >/dev/null 2>&1 || echo "warning: ad hoc signing failed; macOS may refuse to open the app" >&2
echo "Built $app ($version)"
