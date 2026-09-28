# Launcher artwork

SPDX-License-Identifier: CC-BY-NC-SA-4.0

`manor-launcher.png` was generated using the built-in image_gen tool for Crown & Card by David Kendig. It follows the GDD's Victorian gothic / Art Deco manor, navy and teal masquerade guests, burgundy damask and brass lighting. It is embedded as `CrownAndCard.Manor.png` by `launcher/build.ps1`; ManorPanel draws it with nearest-neighbor sampling and renders real UI text separately. No network or asset extraction is required at runtime.

## Exact generation prompt

Use case: stylized-concept. Asset type: static portrait PNG background artwork for the Crown & Card Windows game launcher. Original high-detail crisp pixel art in the Ion Fury / Blood Build-engine visual tradition. An opulent Victorian gothic manor hosting a 1920s Art Deco secret society card night: imposing symmetrical archway into a candlelit rotunda, tall burgundy damask walls and dark carved mahogany, brass geometric trim, grand golden chandelier, black and ivory marble floor with a subtle crown-and-four-suits mosaic. In lower middle distance two small elegant half-masked guests, silver-haired man in navy evening suit and dark-bob-haired woman in teal-and-gold evening dress, viewed from behind entering the room. Grandiose aristocratic conspiracy, warm candle pools against deep navy shadows, regal, secretive, inviting. Architectural environment is the hero, guests secondary. Deliberate visible pixel clusters, limited navy burgundy brass ivory and teal palette, no blurry painting, no photography, no weapons, no modern technology. Portrait 2:3 composition for narrow launcher sidebar. Keep bottom quarter very dark and visually quiet for a separately rendered title. NO text, no lettering, no logos, no UI, no watermarks. Full opaque background.


## Launcher branding

`launcher-icon.png` and `launcher-logo.png` are transparent PNG masters generated with the built-in image_gen tool. The header embeds both masters and draws their visible bounds with nearest-neighbor sampling. `launcher.ico` packages the emblem at 16, 20, 24, 32, 40, 48, 64, 96, 128 and 256 pixels for the executable, taskbar and installer. Rebuild it with `python tools/make_launcher_icon.py` (Pillow required); this performs only format conversion and resizing, preserving alpha. The tagline is live text: **Fortune favors the bold.**

### Exact icon prompt

Use case: logo-brand. Asset type: square transparent PNG master for a Windows game launcher ICO. Create the Crown & Card secret society emblem in deliberate crisp 1990s Build-engine pixel art: a bold antique brass royal crown sits above one upright midnight-navy playing card with thick stepped brass border and a single large ivory spade centered on the card, small burgundy jewel in the crown. Grandiose Victorian gothic meets 1920s Art Deco. Warm candlelit gold edge highlights, dark bronze pixel shadows, restrained ivory. Strong clean silhouette, centered, fills 88 percent of square, highly recognizable at 32 pixels. Coarse intentional pixel clusters, no fine filigree. Isolated emblem on genuinely transparent background. No letters, no words, no scenery, no glow outside silhouette, no drop shadow, no watermark.

### Exact wordmark prompt

Use case: logo-brand. Asset type: transparent PNG title wordmark for upper left of Crown & Card game launcher. Wide horizontal layout, 3:1 canvas. ONLY text exactly 'CROWN & CARD', all on ONE line, large readable chiseled gold serif capitals, broad compact lettering. Deliberate crisp pixel art matching a 1990s gothic Build-engine game, aged brass highlights, dark bronze beveled shadows, restrained ivory glints and subtle burgundy accents. Grandiose Victorian gothic secret society meets Art Deco. Centered narrow decorative brass horizontal rules immediately above and below the lettering with very small spade and diamond ornaments at their centers; text is the hero filling almost full width, minimal padding. No separate large crest, no crown emblem, no additional words, no tagline, no background panel, no scenery, no glow, no watermark. Truly transparent background around the lettering and delicate rules. Designed to read at 380 pixels wide on a midnight navy header.

