# Manor surface textures

SPDX-License-Identifier: CC-BY-NC-SA-4.0

Generated with the built-in image_gen tool. `FoyerArt.surface` samples PNGs into the game's indexed palette using nearest-neighbor filtering. Walls use a 3 m horizontal repeat, floor tiles a 1 m repeat. Upper wallpaper samples the fabric portion of the wall master. The original ivory marble remains on stairs and counters; the fountain and pillar shafts use their dedicated materials below. Blackjack art is mapped once across the tabletop, with dealer at the north edge. The world table displays example cards; seated blackjack is playable, and the other seated games use the surfaces in `res/tabletops/`.

## Fountain and pillar materials

New original PNGs generated with the built-in image_gen tool; exact prompts are saved in [`art-source/foyer-materials/prompts.json`](../../art-source/foyer-materials/prompts.json).

- `fountain-marble.png`: warm ivory marble with branching smoky veins, mapped over the 3D bowls, pedestal and submerged basin beds.
- `pillar-marble.png`: long grey and gold mineral veins, used by `pillarMarble` on all eight entrance-hall pillar shafts. A stretched vertical texture repeat preserves the long vein structure; other ivory details retain their original material.
- `fountain-water.png`: blue-teal ripple and caustic artwork for translucent pool surfaces and falling water.

All three are sampled at 256×256 into the master palette at runtime. Pool UVs are planar; bowl UVs follow profile distance to avoid the old pinching. Water includes small surface displacement, local impact ripples and foam, view-dependent opacity, accelerating six-sided streams that narrow with speed, and batched ballistic splash droplets. Motion uses analytic gravity (9.81 m/s²), not a full fluid solver; it does not affect gameplay collision or random outcomes. Development views: `?foyerView=fountain` and `?foyerView=pillars`.

## Stair, ceiling and courtyard materials

Generated with the built-in image_gen tool. Exact prompts and the stair revision are in [`art-source/estate-materials/prompts.json`](../../art-source/estate-materials/prompts.json).

- `stair-marble.png`: pale ivory marble with restrained grey veins, applied to the grand staircase's treads, risers and landing as `stairMarble`.
- `ceiling-coffer.png`: carved mahogany coffer with brass inlay and an ivory rosette, replacing the procedural `coffer` ceiling.
- `courtyard-slate.png`: wet blue-grey flagstones for the exterior paths.
- `courtyard-gravel.png`: rain-dark gravel for the courtyard ground.
- `courtyard-hedge.png`: dense clipped foliage for the hedge surfaces.
- `courtyard-iron.png`: weathered blackened iron for fence bars, rails and posts.

Materials are sampled at 256×256 through the existing palette renderer. Surface imports intentionally ignore source alpha; the tree sprites preserve it. Courtyard materials remain on solid 3D geometry and respond to lightning. The two tall tree sprites are documented in `../sprites/README.md`. Development inspection views: `?foyerView=stairs`, `?foyerView=ceiling`, and `?foyerView=courtyard`.

## Original material prompts

### manor-wall.png

Use case: stylized-concept. Asset: opaque tiling wall texture for a 1990s Build-engine style Victorian gothic manor interior, Crown & Card. Flat straight orthographic elevation, absolutely no perspective. Burgundy damask wallpaper in upper two thirds, deep carved mahogany wainscoting in lower third, antique brass dado rail and very thin crown molding at top. One elegant narrow wall bay, dark navy shadows, warm muted brass, rich red wine fabric, realistic textured pixel clusters as in Blood / Ion Fury. Tile seamlessly left-to-right, left and right edges identical phase; no corners, lighting gradients, floor or ceiling. No doors, text, furniture or people. Portrait 2:3 texture, entire image filled with wall surface. Rich precise high-detail pixel art, not smooth illustration.

### manor-floor.png

Use case: stylized-concept. Asset: seamless square top-down floor texture for Crown & Card, a grand Victorian / Art Deco manor in 1990s Blood / Ion Fury pixel art. A luxurious symmetric checker of FOUR large polished marble squares (2 by 2), ivory cream and midnight navy black alternating, subtle sparse natural veining, fine antique brass grout lines and tiny brass diamond joins. Flat orthographic surface with no perspective and no lighting gradient. Seamless tiling on all edges: continuous grid spacing. Rich but restrained textured pixel art, clearly defined pixel clusters at 128x128 game scale. No reflections of objects, no cast shadows, no furniture, no letters, no logos, no ornament in tile centers. Full bleed opaque square.

### ivory-marble.png

Use case: stylized-concept. Asset: seamless square ivory marble surface texture for a 3D grand manor fountain and staircase in Crown & Card. Flat evenly lit orthographic material, warm cream marble with sparse elegant muted gray-gold natural veins, subtle patina, restrained high-detail 1990s Build-engine pixel art texture, visible crisp pixel clusters. Seamless on all four edges, no border, no geometric tiles, no grout, no objects, no baked highlights or cast shadows, no text. Surface fills opaque image edge to edge. Light antique ivory dominant, not gray concrete.

### blackjack-table.png

Use case: stylized-concept. Asset: full-bleed opaque top-down rectangular blackjack tabletop felt texture for Crown & Card, grand Victorian / Art Deco secret society card room. 2:1 wide horizontal composition, no perspective, no table legs or background. Deep bottle green teal felt, elegant antique gold and ivory screen-printed layout. Dealer area along TOP edge, five empty clearly outlined oval betting spots in a broad shallow arc across LOWER half. Center exact legible text 'BLACKJACK PAYS 3 TO 2', smaller line 'DEALER MUST STAND ON 17', curved line below 'INSURANCE PAYS 2 TO 1'. Small crown and four suit symbols above main title. Thin rectangular gold ornamental border safely inset from edges, dark burgundy padded rail framing entire rectangle. Crisp detailed 1990s Build-engine pixel art, no gradients obscuring text, no cards, no chips, no people, no watermark. Accurate readable lettering; whole tabletop visible.

