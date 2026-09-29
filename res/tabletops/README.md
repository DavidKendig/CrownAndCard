# Seated tabletop art

SPDX-License-Identifier: CC-BY-NC-SA-4.0

Eight 640 × 360 PNG surfaces, generated with the built-in image_gen tool and reduced for the game's internal pixel grid. Original masters and exact prompts are in `art-source/tabletops/`. Rebuild with `node tools/build_tabletops.cjs` (requires Sharp).

| File | Use |
| --- | --- |
| holdem.png | Texas Hold'em: green felt, four suits |
| draw.png | Five-card draw: wine felt, Art Deco corners |
| spades.png | Spades: navy felt, brass spades |
| go-fish.png | Go Fish: teal felt, engraved fish |
| slapjack.png | Slapjack: oxblood felt, lightning corners |
| war.png | War: plum felt, opposed crowns |
| solitaire.png | Klondike: forest felt, ivy |
| mahjong.png | Future Mahjong table: jade felt, bamboo inlay |
| roulette.png | Single-zero betting grid, outside bets, and a stationary wheel; shared with world tables |

Roulette's complete 640 × 360 PNG is built from the generated felt and wheel art in `art-source/roulette/` and `res/roulette/`. Export the game's exact geometry with `haxe -cp src -cp tools -main ExportRouletteArt --interp`, then run `node tools/build_roulette_art.cjs` (Sharp required). The seated UI places the animated wheel, chips, and feedback above this artwork, with one shared transform for the texture and hit regions. The `rouletteTable` world/Haxen fixture uses the same PNG at 2.4 × 1.35 m; the manor includes one beside the card table.

The seven implemented games consume these through `ui.TableSurface`, which imports RGBA, snaps to the master palette once, caches textures, and uses nearest-neighbor sampling. The art sits below cards, pile outlines, labels and controls. The current variable-width 360p view fits each surface to its viewport. Blackjack retains its existing authored layout in `res/materials/blackjack-table.png`. Mahjong is an asset kit only; it is not added as a playable menu entry.
