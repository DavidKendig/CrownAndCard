#!/bin/sh
# Native build for Apple Silicon Macs: Haxe -> C (HL/C) -> clang -> native/mac/game.
# Needs HashLink 1.16 built from source (libhl.dylib and the .hdll modules);
# set HASHLINK to its folder (default: ~/src/hashlink).
#   sh tools/build_mac.sh && native/mac/game
set -e
cd "$(dirname "$0")/.."
HL="${HASHLINK:-$HOME/src/hashlink}"
BREW="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"

haxe build-hlc-mac.hxml

OUT=native/mac
cp "$HL/libhl.dylib" "$HL"/fmt.hdll "$HL"/sdl.hdll "$HL"/openal.hdll "$HL"/ui.hdll "$HL"/uv.hdll "$OUT/"
clang -O2 -std=c11 -arch arm64 -w \
	-I "$OUT/c" -I "$HL/src" -I "$BREW/include" \
	"$OUT/c/game.c" \
	-L "$OUT" -lhl "$OUT/fmt.hdll" "$OUT/sdl.hdll" "$OUT/openal.hdll" "$OUT/ui.hdll" "$OUT/uv.hdll" -L "$BREW/lib" -luv \
	-Wl,-rpath,@executable_path \
	-o "$OUT/game"
echo "Built $OUT/game"
