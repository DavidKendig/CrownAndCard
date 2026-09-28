# Mahjong art kit

SPDX-License-Identifier: CC-BY-NC-SA-4.0

42 individual 144 × 192 transparent PNG faces, plus a matching back and blank enamel tile. Jade thickness edges, ivory enamel, brass trim, navy and red ink match the manor. Suggested seated display is 36 × 48 pixels. `preview.png` shows every unique face.

`manifest.json` contains stable IDs, names, groups, relative PNG paths, copy counts, and ready-to-use tile-ID lists for a 136-tile standard set or 144 tiles including bonuses. Three suits contain ranks 1–9; honors are four winds and three dragons. Four flowers and four seasons are optional single-copy bonuses. Composition follows the [Mahjong International League-hosted guide, pages 7–8](https://mahjong-mil.org/wp-content/uploads/2024/08/A_GUIDE_TO_MAHJONG.pdf). No jokers or red-five variants are included.

The built-in image_gen tool generated the blank enamel, ornamental back and nine botanical/bird motifs. Masters and exact prompts are saved in `art-source/mahjong/`. `tools/build_mahjong.cjs` places exact counted pips, bamboo marks, Chinese numerals/honors and readable corner indices over the generated art, then exports and validates the set. Rebuild with Node.js, Sharp and the SimSun font available on Windows. The PNGs need no fonts at runtime.

The matching table is `res/tabletops/mahjong.png`. Gameplay is not implemented yet; these are prepared assets, not a new playable game.
