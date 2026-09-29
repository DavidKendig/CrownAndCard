# Sovereign casino chips

SPDX-License-Identifier: CC-BY-NC-SA-4.0

Seven transparent 128 × 128 PNG chips: 1 ivory, 5 red, 10 blue, 25 green, 50 purple, 100 black, 250 gold. Denominations represent the player's existing Sovereigns, not a separate balance. `manifest.json` maps denominations to files.

Generated with the built-in image_gen tool. Original atlas, roulette felt master and exact prompts are in `art-source/roulette/`. `node tools/build_roulette_art.cjs` (Node.js + Sharp) slices the atlas, adds exact denomination numerals, and exports these chips plus `res/tabletops/roulette.png` at 640 × 360. The runtime uses palette-snapped 32px chips in the tray and small stacks on the mat.

Roulette interaction: click denominations repeatedly to build the amount in hand, then click a number, boundary, corner, street/six-line dot, zero basket or outside space. Hover identifies the bet, payout and total placed there. Undo removes one chip from the hand first, otherwise the last placement. Clear returns all reservations. Chips are reserved until Spin, cannot exceed the purse, and cannot be edited while the wheel runs. Unplaced chips must be placed or undone before spinning.

For keyboard/controller use, Space/X cycles chip tray → betting mat → actions; arrows/D-pad navigate; E/A confirms; Escape/B leaves when the wheel is stopped. Table artwork and hit-testing share the same `BettingLayout` geometry so the painted numbers and wager coverage agree.
