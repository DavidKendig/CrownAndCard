# Midnight Salon

SPDX-License-Identifier: CC-BY-NC-SA-4.0

The nightclub-style cocktail salon opens off the kitchen's north side. The kitchen prep counter and shelves leave an entry at x=4.6. A clear east aisle leads past three round brass pedestal tables and burgundy booths to the bar, bartender, and stocked back-bar shelves. Purple wall accents and teal ceiling strips frame the dark Art Deco room.

Generated with the built-in image_gen tool on 2026-09-29. Exact prompts: [prompts.json](prompts.json).

- [Bartender PNG](../../res/sprites/bartender.png): five transparent directional views, imported through SpriteArt at 48x112 per frame, with the existing directional mirroring and palette conversion.
- [Round tabletop PNG](../../res/tabletops/salon-round.png): transparent circular overhead cocktail-table art, imported at 256x256. SalonArt places the surface over a round brass rim and pedestal; hidden collision props use a circular radius rather than square corners.

These are decorative lounge furnishings. The bartender turns toward the player; drink-ordering interactions are not implemented.

- [Singer and vintage microphone](../../res/sprites/salon-singer.png): five transparent directional views of a burgundy-gowned jazz singer at a classic chrome microphone stand. Generated with the built-in image_gen tool; [exact prompt](singer-prompt.json). Imported at 64x128 per frame, including the complete stand and its base. The singer faces the audience from the salon's south performance area with a velvet backdrop and a dedicated light. This is a visual sprite, without singing audio or animation.
