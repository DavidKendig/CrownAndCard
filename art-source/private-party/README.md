# Private Party

Generated with the built-in image_gen tool; exact prompts and source locations are in `prompts.json`. Runtime PNGs are saved in `res/sprites/` (`security_black`, `security_white`, `party_chair`) and `res/materials/` (`party-floor`, `party-wall`, `party-ceiling`). The table's cloth, `res/materials/private-table-top.png` and `private-table-drape.png`, was supplied by the project owner; see `res/materials/README.md`. Asset license: CC BY-NC-SA-4.0.

Guards have five drawn angles across and two pose rows: clasped hands, then earpiece check. The importer mirrors the side views for eight-way rendering and palette-snaps at 64 texels per meter. Each guard turns toward the player and makes a staggered 2.5-second radio check every 13 seconds. The empty chair has five angles and no animation.

The room is north of the conservatory, connected to the main hall through a guarded west passage. Four seated guests surround a long table; the empty chair is centered between the two south-side guests. It is decorative seating, with no new sitting interaction. The existing seated guest sheets are reused.

Development cameras: `?foyerView=party` (guards) and `?foyerView=partyinside` (seating). Browser verification completed; screenshots are `entrance-in-game.png` and `room-in-game.png`. Room textures use architectural-scale repeats; conservatory rain sheets are clipped above surrounding roofs so they cannot fall inside this room or its entrance. Map connectivity, roof clearance, and sprite import are checked independently.

`import-preview.png` shows the actual palette-snapped sprite import (the generated sheets' low-alpha halos are discarded). Rebuild with `haxe -cp src -cp tools -lib heaps -main PreviewPrivateParty -js bin/private-party-preview.js`, then `node bin/private-party-preview.js` with Sharp available.
