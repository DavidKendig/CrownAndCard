# Crown & Card deck

SPDX-License-Identifier: CC-BY-NC-SA-4.0

52 individual PNG faces in `faces/`, one `back.png`, all **200 × 280 pixels (5:7)**. `manifest.json` maps game index, rank, suit and filename. Codes match `cards.Card.code`: ranks 2–9, T, J, Q, K, A; suits c, d, h, s. No jokers.

The back and 12 court portraits were generated with built-in image_gen. `tools/build_cards.cjs` authors exact vector rank labels, suit shapes and pip layouts, places the court atlas cells in traditional double-ended layouts, then exports all PNGs with Sharp. It checks all pip counts, unique codes and dimensions. Run `node tools/build_cards.cjs` with `sharp` installed. Masters remain in `source/`. `deck-preview.png` is a full-deck contact sheet. `CardArt` loads faces by canonical card code; sample cards and the back are already rendered on the blackjack table.

## Exact source prompts (built-in imagegen)

### source/back-master.png

Use case: logo-brand. Asset: single playing-card BACK PNG for Crown & Card, full-bleed flat orthographic rectangle, standard poker-card aspect ratio 5:7 portrait. Elegant mysterious Victorian Art Deco secret society pattern in midnight navy, burgundy and antique brass gold. Narrow ivory outer border with delicately stepped rounded corners, double thin brass rules, intricate but readable geometric damask, two opposing mirrored royal crowns and spade medallions. Strict 180-degree rotational symmetry so it has no identifiable upside. Crisp high-detail pixel art harmonizing with a Blood / Ion Fury era grand manor, gold highlights not neon. No lettering, no ranks, no numbers, no perspective, no shadow, no surrounding surface, no hand. The card fills the entire canvas. Opaque background.

### source/courts.png

Use case: stylized-concept. Asset: playing-card COURT ILLUSTRATION sprite atlas for Crown & Card. EXACTLY 12 isolated waist-up royal character illustrations arranged in a strict 3-column by 4-row grid, all equal cells, ample transparent gutters. Columns left to right: JACK (young male courtier), QUEEN (regal woman), KING (bearded crowned ruler). Rows top to bottom: SPADES midnight navy robes with spade emblems, HEARTS burgundy robes with heart emblems, CLUBS deep teal robes with club emblems, DIAMONDS crimson-gold robes with diamond emblems. Victorian gothic secret society aristocrats in luxurious antique-gold embroidered robes, half-masks with mouths visible, each holding a ceremonial scepter or flower, dignified and mysterious. Crisp detailed pixel-art illustrations for traditional double-ended playing cards. Each figure upright, front or slight three-quarter, contained wholly within its own cell with same baseline, no overlap. No card borders, no letters, no rank text, no numbers, no scenery, no shadows, no weapons. Transparent background between and around all figures. Entire grid visible. Symmetrical compact silhouettes readable at 80 pixels high.

