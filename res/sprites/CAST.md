# Player, guests and staff

SPDX-License-Identifier: CC-BY-NC-SA-4.0

Crown & Card by David Kendig. Generated with the built-in image_gen tool on 2026-09-27, following GAME_DESIGN.md sections 2.3 and 5.

- `player.png`: anonymous initiate; five world views for eight-direction display. The body is available in the F2 sprite preview; mirrors and avatar customization are not yet implemented.
- `player_hands.png`: first-person gloved hand, signet ring and coupe, replacing the procedural HUD hand.
- `female_guest.png`: masked guest in teal/gold evening attire, used in the Rotunda and Card Room.
- `male_staff.png`: blue uniformed steward, used for Quill and Pemberton.
- `female_staff.png`: blue uniformed steward/dealer, used at the cloakroom and blackjack table.

Character PNGs contain five source views, imported to 48x112 pixels per frame. Runtime source-cell partitioning supports widths not divisible by five. These are idle directional sheets, not walk/reaction animations. They retain their authored colors: the old automatic NAVY-to-DARK_WOOD/RED/OLIVE/PURPLE swaps were removed from scene spawns. The palette shade LUT still handles lighting.

Click the bottom-left **F2: Sprites** control or press F2 to preview the player and cast. Click **Next**, **Rotate**, and **Close**, or use C, R and F2. The preview is full-bright; world sprites receive normal sector and distance shading.

## Exact generation prompts

### player

Use case: stylized-concept. Production transparent PNG sprite sheet for Crown & Card. Original Ion Maiden / Ion Fury detailed crisp pixel art in a Victorian gothic manor with 1920s Art Deco masked casino guests. Exactly FIVE equal-width cells in ONE horizontal row, identical character in front, front three-quarter facing viewer-right, right profile, back three-quarter, back order. All full-body at equal scale with aligned feet, adult realistic proportions, relaxed symmetrical idle stance, no held objects. Each silhouette completely inside its own cell, ample empty transparent margins, no overlap, no floor or cast shadow. Actual transparent alpha background, no text, no grid, no border. Strong deliberate pixel clusters, no smooth painterly shading, warm ivory/gold highlights, cool blue-violet shadows. A 3:1 wide canvas, intended for five 48x112 frames. Half mask covers eyes only, eyebrows and mouth visible. Anonymous young adult initiate, androgynous slim silhouette, short dark hair, crisp saturated royal NAVY BLUE fitted evening suit and trousers, ivory shirt, silver-blue half-mask with restrained gold trim, white gloves, gold signet ring, black shoes. Distinct from the elderly guest and uniformed staff. No tails, no weapons.

### female_guest

Use case: stylized-concept. Production transparent PNG sprite sheet for Crown & Card. Original Ion Maiden / Ion Fury detailed crisp pixel art in a Victorian gothic manor with 1920s Art Deco masked casino guests. Exactly FIVE equal-width cells in ONE horizontal row, identical character in front, front three-quarter facing viewer-right, right profile, back three-quarter, back order. All full-body at equal scale with aligned feet, adult realistic proportions, relaxed symmetrical idle stance, no held objects. Each silhouette completely inside its own cell, ample empty transparent margins, no overlap, no floor or cast shadow. Actual transparent alpha background, no text, no grid, no border. Strong deliberate pixel clusters, no smooth painterly shading, warm ivory/gold highlights, cool blue-violet shadows. A 3:1 wide canvas, intended for five 48x112 frames. Half mask covers eyes only, eyebrows and mouth visible. Elegant adult woman guest, dark finger-wave bob hair, emerald teal ankle-length 1920s evening dress with tasteful gold Deco trim, ivory opera gloves, gold half mask, small pearl necklace, black low heels. Dignified social party attire, strong slender silhouette.

### male_staff

Use case: stylized-concept. Production transparent PNG sprite sheet for Crown & Card. Original Ion Maiden / Ion Fury detailed crisp pixel art in a Victorian gothic manor with 1920s Art Deco masked casino guests. Exactly FIVE equal-width cells in ONE horizontal row, identical character in front, front three-quarter facing viewer-right, right profile, back three-quarter, back order. All full-body at equal scale with aligned feet, adult realistic proportions, relaxed symmetrical idle stance, no held objects. Each silhouette completely inside its own cell, ample empty transparent margins, no overlap, no floor or cast shadow. Actual transparent alpha background, no text, no grid, no border. Strong deliberate pixel clusters, no smooth painterly shading, warm ivory/gold highlights, cool blue-violet shadows. A 3:1 wide canvas, intended for five 48x112 frames. Half mask covers eyes only, eyebrows and mouth visible. Adult male manor steward and card dealer, neat silver hair and small moustache, clearly BLUE navy tailcoat, navy trousers, ivory shirt and waistcoat, gold buttons, ivory gloves, gold half mask, small symmetrical crown lapel insignia. Impeccably formal, visibly a uniformed staff member.

### female_staff

Use case: stylized-concept. Production transparent PNG sprite sheet for Crown & Card. Original Ion Maiden / Ion Fury detailed crisp pixel art in a Victorian gothic manor with 1920s Art Deco masked casino guests. Exactly FIVE equal-width cells in ONE horizontal row, identical character in front, front three-quarter facing viewer-right, right profile, back three-quarter, back order. All full-body at equal scale with aligned feet, adult realistic proportions, relaxed symmetrical idle stance, no held objects. Each silhouette completely inside its own cell, ample empty transparent margins, no overlap, no floor or cast shadow. Actual transparent alpha background, no text, no grid, no border. Strong deliberate pixel clusters, no smooth painterly shading, warm ivory/gold highlights, cool blue-violet shadows. A 3:1 wide canvas, intended for five 48x112 frames. Half mask covers eyes only, eyebrows and mouth visible. Adult female manor steward and card dealer, neat dark hair bun, clearly BLUE navy tailored uniform jacket with gold piping, ivory shirt, navy ankle-length straight skirt, ivory gloves, small symmetrical crown lapel insignia, gold half mask, black low heels. Professional formal uniform, distinct from an evening dress.

### player_hands

Use case: stylized-concept. Production transparent PNG first-person PLAYER HAND sprite for Crown & Card, a 1920s Art Deco secret society manor game with Ion Maiden / Ion Fury crisp pixel-art rendering. One right hand seen from the wearer's first-person viewpoint, ivory glove with small gold signet ring, clearly royal NAVY BLUE suit sleeve and ivory cuff entering from bottom right, holding a shallow elegant coupe glass by the stem. Glass contains a small amber drink, bowl in upper left, gloved fingers and wrist lower right. No other limbs or objects. Strong pixel clusters, 1990s Build engine HUD sprite with modern detail, limited palette, no smooth gradients, no blur, no text. Actual transparent alpha background throughout empty area including around glass, no scene or shadows. Entire glass and fingers visible, sleeve continues naturally off bottom right edge. Landscape composition intended for 150x112 game pixels. Sympathetic to Victorian gothic / Deco manor atmosphere, no weapon.
