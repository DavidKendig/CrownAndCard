# Manor art and implementation

SPDX-License-Identifier: CC-BY-NC-SA-4.0

Generated with the built-in image_gen tool for Crown & Card. Sources are saved in this project; no live image service is used by the game.

The foyer has a desk-facing spawn, a hooded Mr. Quill, explicit Guest Register saves, a three-tier **3D** fountain, and a 20-tread staircase with separate removable velvet rope barriers. The fountain uses `world/Fountain.hx` revolved geometry with dedicated marble/water PNG materials, translucent rippling pools, gravity-shaped streams and ballistic splash droplets. See `../materials/README.md` for the new fountain and pillar art. `foyer/fountain.png` is the original visual reference, no longer rendered as a billboard. Doors and desk are fixed planes on solid geometry. Save data currently records check-ins and explored rooms; campaign systems are not yet implemented.

Controls: E / controller A or click the desk prompt to save. Approach the south doors for the translucent Stay/Leave menu. Escape / B cancels; arrows or d-pad select, Enter / A activates. Stay is the default. Web builds attempt to close their tab and otherwise stop at a departure screen. Loading restores the saved page and spawns at the desk.

Launcher saves: `%LOCALAPPDATA%/CrownAndCard/saves/guest-register.json`, token-protected local API with atomic replacement and a `.bak` page. Standalone web preview uses localStorage. Native builds use the same data directory on Windows. No auto-save on departure.

## Entrance windows and nighttime courtyard

The front facade has four true wall openings with transparent glass, deep ivory marble reveals, mahogany borders, brass mullions and diamond transoms. `world/FoyerWindows.hx` places them around a south-boundary front-door fixture; unsuitable custom-map walls are left intact. The collision grid remains solid at the panes.

`world/FoyerStorm.hx` builds a real 3D courtyard with wet slate paths, hedges, iron railings and layered evergreen trees. All surfaces use the game's indexed palette and nearest sampling. Rain falls in depth layers outside, with occasional lightning illuminating the courtyard and nearby foyer, followed by delayed thunder. Weather uses an independent cosmetic RNG, leaving game outcomes untouched. Rain and thunder follow Master/Effects volume, distance and background muting, and stop on departure. Original generated audio and its source are documented in `../audio/weather/README.md`.

The development view `?foyerView=windows` faces the front windows for visual inspection.

## Source prompts (built-in imagegen)

### ../sprites/hooded_keeper.png

Use case: stylized-concept. Game sprite sheet PNG for Crown & Card, Victorian gothic secret society manor, Ion Fury / Blood era crisp textured pixel art, limited midnight navy, charcoal, antique brass, burgundy, ivory palette. FIVE full body views of the SAME male hooded front desk keeper in one horizontal row of FIVE equal width cells: front, front three-quarter facing viewer's left, left profile, rear three-quarter, back. Long heavy midnight blue ceremonial robe, deep hood shadows face but visible pale chin, antique gold piping and crown medallion, burgundy inner lining, hands calmly clasped at waist, dignified welcoming secret society archivist, no weapon. Same height, grounded feet aligned, orthographic game camera at chest height, no perspective foreshortening, discrete pixels, readable silhouette. Each figure fully isolated with generous transparent gutters, no overlap, no text, no furniture, no floor, no shadows. Genuinely transparent background.

### fountain.png

Use case: stylized-concept. Asset: transparent PNG world prop sprite for Crown & Card gothic grand manor foyer, crisp detailed 1990s Build-engine / Ion Fury pixel art. One grand symmetrical three-tier indoor water fountain, front elevation orthographic camera at human chest height. Wide low circular ivory marble basin with dark navy water and antique brass molding, slender carved stone central pedestal, two progressively smaller scalloped bowls, a small brass crown finial at the top. Clearly visible pale turquoise and silver streams falling from each bowl, small bright sparkling droplets, luxurious Victorian / Art Deco detailing. Whole object visible from finial to base, basin wider than top, near-square silhouette. Readable at 192x192 game pixels. Navy shadows, cream marble, muted antique gold, teal water. Transparent outside silhouette including between falling streams. No setting, no people, no lettering, no base shadow, no background. Genuinely transparent background.

### welcome-desk.png

Use case: stylized-concept. Asset: seamless-edge rectangular front-panel texture for a grand Victorian gothic manor welcome desk in Crown & Card game. Straight orthographic elevation, no perspective, no furniture legs, no countertop or background. Full-bleed 3:1 wide horizontal panel. Dark mahogany carved wood, thick antique brass border, three inset panels, central embossed brass royal crown above four small suit symbols (spade heart club diamond), subtle burgundy velvet insets in side panels, symmetric Art Deco moldings. Crisp 1990s Build engine / Ion Fury textured pixel art with deliberate visible pixel clusters, navy brown shadows, warm antique gold highlights, restrained detail legible at 256x80 pixels. No text, no writing, no people. Opaque texture fills entire canvas edge to edge.

### grand-doors.png

Use case: stylized-concept. Asset: opaque wall-mounted grand front double-door texture, Crown & Card Victorian gothic secret society manor. Straight-on orthographic front elevation no perspective, complete tall rectangular door frame fills canvas, 2:3 portrait. Two imposing CLOSED carved dark mahogany doors, antique brass geometric inlay and crown crest, paired brass handles at middle height, burgundy inset panels, thick ivory stone architrave and gilded gothic arch overhead inside the rectangle, fanlight of dark midnight blue stained glass above doors. Rich candlelit pixel art like Blood / Ion Fury 1990s Build-engine, visible crisp pixel clusters, midnight navy dark wood ivory muted gold burgundy palette, readable at 192x288 texels. No scenery beyond frame, no people, no text, no floor. Full opaque rectangle edge to edge.

