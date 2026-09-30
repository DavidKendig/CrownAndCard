# West-wing bedrooms

SPDX-License-Identifier: CC-BY-NC-SA-4.0

Eight 6 x 6 m bedrooms open onto the three-metre-wide West Bedroom Corridor,
reached through the left wall of the Entrance Hall near the front of the manor.
Each has a king-size four-poster bed, marble-topped bedside cabinets, a chandelier,
and clear space on both sides and behind the headboard. The existing manor has
been translated 20 m east to make room for the new wing, including every prop,
fixture, guest, walking destination, light and player start.

The `fourPosterBed` fixture is also available in Haxen. Its anchor is the center,
with its headboard to the north. Its 1.93 x 2.03 m mattress sits inside a
2.44 x 2.56 m footprint; the finials reach 2.94 m. `FourPosterBed.hx` builds the
frame, separate mattress and coverlet, raised pillows, headboard, footboard,
four turned octagonal posts, corner drapes, gilt ties and solid canopy in 3D.
The four-post and upper tester construction follows the user's
[four-poster reference](https://en.wikipedia.org/wiki/Four-poster_bed).

## PNG artwork

Generated with the built-in `image_gen` tool. The exact prompts are preserved in
[prompts.json](prompts.json). The final game assets are:

- [Surface atlas](../../res/materials/bed-surface-atlas.png): sixteen full-bleed
  tiles in a 4 x 4 grid, sampled once per face with inset UVs.
- [Coverlet top](../../res/materials/bed-coverlet-top.png): an embroidered burgundy
  and gold quilt, mapped once across the top of the bedspread.
- [Bedroom carpet](../../res/materials/bedroom-carpet.png): a seamless custom
  oxblood Axminster-style weave with ivory quatrefoils, old-gold vines and
  midnight-navy accents. It repeats every three metres in the eight bedrooms;
  the corridor retains its existing floor so the room thresholds stay distinct.

Atlas rows, left to right:

| Row | First | Second | Third | Fourth |
| --- | --- | --- | --- | --- |
| 1 | Burgundy damask | Mattress ticking | Ivory pillow silk | Pleated velvet |
| 2 | Headboard | Footboard | Carved side rail | Mahogany grain |
| 3 | Fluted post | Brass | Canopy top | Canopy underside |
| 4 | Canopy fascia | Wood end grain | Embroidered hem | Cloth backing |

Every face has PNG artwork, including mattress sides, wood edges, finials,
post bases, curtain ends and the undersides of the canopy, frame and bedding.
Both assets go through the game's palette import and resolution scaling.
All eight beds share two meshes and two textures. The rooms and corridor also
use existing PNG floor, wall and coffered-ceiling materials.

The map tests walk from the player start into all eight bedrooms, around each
bed, and check collision at the bed and four posts. The sprite verifier checks
that all sixteen atlas regions contain opaque artwork after palette conversion.

For an in-game art review, build the web version and open
`bedrooms-preview.html` on the local web server. Its buttons use the existing
development-only teleport hooks to inspect the front, sides, rear, corridor
and foyer entrance without changing the actual player start.

## Basement stair and lower room

The bedroom corridor now continues through an iron-framed opening into nineteen
real stone treads that descend 3.6 m. The old basement beyond has a low ceiling,
damp block walls, cracked flagstones, oxidized machinery, storage shelves,
crates, overhead pipes, a central drain and an authored boiler face. It is dimly
lit but fully walkable, including both directions on the stairs.

The generated basement assets are:

- [Stair surfaces](../../res/materials/basement-stairs.png): worn charcoal stone
  treads and risers with tarnished brass nosing.
- [Basement materials](../../res/materials/basement-materials.png): a four-band
  atlas for damp walls, flagstone floor, cracked low ceiling and corroded metal.
- [Boiler face](../../res/materials/basement-boiler.png): riveted iron boiler,
  gauges, furnace hatch, valves, copper pipes and hanging chain.

The exact built-in `image_gen` prompts are recorded in `prompts.json`.
