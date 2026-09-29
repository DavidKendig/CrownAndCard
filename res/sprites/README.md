# Generated sprite sources

See [POSES.md](POSES.md) for standing, seated and animated walking male/female guests.

SPDX-License-Identifier: CC-BY-NC-SA-4.0

Crown & Card by David Kendig. Created with the built-in image_gen tool on 2026-09-27. Original art guided by GAME_DESIGN.md sections 5.1–5.4 and 5.8–5.9.

- `masked_guest.png`: five horizontal views (front, front three-quarter, right profile, back three-quarter, back). Used for male guests in its original navy colors. This is one shared crowd body, not individual final character designs or a walk animation.
- `brass_chandelier.png`: transparent brass candle chandelier, used in the Rotunda.

## Tall courtyard trees

- [`tall-cedar.png`](tall-cedar.png): mature layered cedar, transparent around its silhouette and between branches.
- [`tall-cypress.png`](tall-cypress.png): narrow irregular cypress with a visible trunk and root flare, transparent background.

Generated with the built-in image_gen tool on 2026-09-28. Exact prompts are in [`art-source/estate-materials/prompts.json`](../../art-source/estate-materials/prompts.json). Source PNG alpha is preserved; `FoyerArt.surface` samples them at 256×512 with alpha testing, then uses the normal indexed palette and nearest filtering. `FoyerStorm` places 36 upright face sprites in three staggered rows, at 12–19 metres tall, replacing the old cone trees. They remain grounded, turn around the vertical axis toward the camera, have parallax between rows, and brighten during lightning. They are scenery outside the playable boundary.

## Character sprites

See [CAST.md](CAST.md) for the new player, female guest, male/female staff, first-person hands and their exact generation prompts. Press F2 in-game to inspect the cast; C cycles characters and R rotates them.

`art.SpriteArt` trims each equal-width source cell, uses a common scale, centers and grounds each silhouette, samples with nearest-neighbor to 48x112 per guest / 96x72 per prop, and maps RGB to the master palette while reserving zero for transparency. Alpha below 128 is discarded. The original PNG alpha is preserved on disk. Textures use the existing eight-angle billboard, shade LUT and nearest filtering. PNGs are embedded by the web build; no separate resource server is required.

Run `haxe tests-sprites.hxml` to validate the assets and importer.

## Exact generation prompts

### Guest sheet

Use case: stylized-concept. Asset type: production PNG directional sprite sheet for Crown & Card, a first-person Build-engine-style game. Create original Ion Maiden / Ion Fury quality detailed crisp pixel art adapted to Blood-like Victorian gothic manor and 1920s Art Deco masked casino party. ONE horizontal sheet with exactly FIVE equally spaced cells, same male guest in each, full body, identical scale and feet baseline: front, front three-quarter facing viewer-right, right profile, back three-quarter, back. Slim distinguished silver-haired gentleman, navy blue tailcoat and trousers, ivory waistcoat and shirt, brass buttons, small gold domino HALF mask, mouth visible, black shoes, relaxed arms. No hat, no weapon. Anatomically natural adult proportions. Hard pixel clusters, controlled highlights, deep blue violet shadows, ivory gold skin and navy palette, no smooth painting. Orthographic views, no perspective foreshortening of height. Each cell has comfortable transparent margins, all five figures wholly isolated, no overlaps. Transparent alpha background, no ground, no shadows outside silhouette, no text, no cell borders. Wide 3:1 canvas. Intended to sample down to five 48x112 frames, so strong readable silhouette and economical detail.

### Chandelier

Use case: stylized-concept. Asset type: transparent PNG prop sprite for Crown & Card, a first person Build-style Victorian gothic manor casino. Original Ion Maiden / Ion Fury detailed hard pixel art: one ornate symmetrical antique brass chandelier, five ivory candles with small amber flames, scrolling curved arms, central finial, short hanging chain, warm gold highlights and dark bronze shadows. Straight front elevation suitable for upright billboard in a 2.5D game. Strong readable silhouette and deliberate pixel clusters, no smooth gradients or blur. Isolated fully visible with generous transparent alpha margins, absolutely no background, floor, cast shadow, text or border. Designed for a 96x72 pixel game sprite. Landscape 4:3 composition.
