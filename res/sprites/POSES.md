# Guest poses

SPDX-License-Identifier: CC-BY-NC-SA-4.0

Generated with the built-in image_gen tool using the existing male and female guest PNGs as identity references.

Standing guests retain `masked_guest.png` and `female_guest.png`. Seated poses use `male_guest_seated.png` and `female_guest_seated.png`: five directions with chairs, imported to 128x168 per frame at 128 texels/m. Walking poses use `male_guest_walk_v2.png` and `female_guest_walk_v2.png`: five directions by four stride phases, imported to 64x112 per frame at 64 texels/m. The renderer mirrors five views into eight and selects animation rows independently.

Walk source rows have measured boundaries recorded in SpriteArt; their silhouette heights are normalized to prevent size drift between cels. The female rear three-quarter frames are mirrored into the canonical direction on import. Alpha cutout and the original navy/teal palette are preserved. These are initial four-frame stroll cycles, not the full eight-frame walk/reaction budget from the GDD.

The Card Room has one seated man and woman. The Rotunda retains standing guests and adds one walking man and woman on short collision-checked routes. This is a render demonstration, not the full NPC schedule. F2 / the Sprites button previews every pose, and walking previews animate automatically.

Validation: `haxe tests-sprites.hxml` checks every imported cel, transparency gutters, animation variation, blue lighting, references and walking-route bounds/collision/reversal.

## Prompts

See the generation history in this task.

### Walk refinement

Refine to four alternating contact/passing stride phases with transparent row gutters and consistent character identity.
