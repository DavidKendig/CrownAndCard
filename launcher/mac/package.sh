#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Builds the Mac release: dist/CrownAndCard-<version>-mac-arm64.dmg (+ .sha256),
# a disk image holding "Crown & Card.app" with the whole game inside it.
#
#   sh launcher/mac/package.sh
#
# 1. The native game (tools/build_mac.sh), the web build and Haxen.
# 2. The launcher app (launcher/mac/build.sh), with the game in
#    Contents/Resources/game (native/mac and web, where the launcher looks).
# 3. The game's Homebrew libraries (SDL3, OpenAL, libpng, libjpeg-turbo,
#    libvorbis, libogg, libuv) copied next to it and relinked to load from
#    there, so the app runs on a Mac without Homebrew.
# 4. Everything signed ad hoc, then a compressed disk image with a link to
#    Applications for dragging the app across.
#
# The app isn't notarized: the first time, open it with right-click > Open (or
# System Settings > Privacy & Security > Open Anyway).
set -e
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
cd "$repo"
version="$(sed -n 's/.*"version"[^"]*"\([0-9.]*\)".*/\1/p' version.json)"
[ -n "$version" ] || { echo "Couldn't read the version from version.json" >&2; exit 1; }

sh tools/build_mac.sh
haxe build-js.hxml
haxe haxen.hxml
sh "$here/build.sh"

app="$repo/Crown & Card.app"
game="$app/Contents/Resources/game"
mkdir -p "$game/native/mac" "$game/web"
cp native/mac/game native/mac/libhl.dylib native/mac/*.hdll "$game/native/mac/"
cp web/index.html web/game.js web/haxen.html web/haxen.js "$game/web/"
cp LICENSE LICENSE-ASSETS version.json "$app/Contents/Resources/"

# Copy every library the game loads from Homebrew beside it and point the
# references at the copies (@loader_path), repeating until nothing is left.
dir="$game/native/mac"
while :; do
	changed=0
	for f in "$dir"/*; do
		file "$f" | grep -q "Mach-O" || continue
		for dep in $(otool -L "$f" | tail -n +2 | awk '{print $1}' | grep -E '^/(opt/homebrew|usr/local)/'); do
			name="$(basename "$dep")"
			if [ ! -f "$dir/$name" ]; then
				cp "$(realpath "$dep")" "$dir/$name"
				chmod u+w "$dir/$name"
				install_name_tool -id "@loader_path/$name" "$dir/$name" 2>/dev/null
				changed=1
			fi
			install_name_tool -change "$dep" "@loader_path/$name" "$f" 2>/dev/null
			changed=1
		done
	done
	[ $changed = 0 ] && break
done
if otool -L "$dir"/* 2>/dev/null | grep -E '^\s*/(opt/homebrew|usr/local)/'; then
	echo "Some libraries still load from Homebrew (above)" >&2
	exit 1
fi
# Sign and pack a clean copy outside the checkout: in a synced folder (like
# ~/Documents) macOS keeps putting back the Finder metadata codesign refuses.
staging="$(mktemp -d)"
ditto --norsrc --noextattr --noqtn "$app" "$staging/Crown & Card.app"
signed="$staging/Crown & Card.app"
for f in "$signed/Contents/Resources/game/native/mac"/*; do codesign --force --sign - "$f" >/dev/null; done
codesign --force --deep --sign - "$signed"
codesign --verify --deep --strict "$signed"
ln -s /Applications "$staging/Applications"

mkdir -p dist
dmg="dist/CrownAndCard-$version-mac-arm64.dmg"
rm -f "$dmg"
hdiutil create -volname "Crown & Card $version" -srcfolder "$staging" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$dmg" >/dev/null
rm -rf "$staging"
(cd dist && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
echo "Built $dmg ($version)"
