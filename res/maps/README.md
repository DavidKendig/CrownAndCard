# Maps

SPDX-License-Identifier: CC-BY-NC-SA-4.0

`manor.json` is Dodriec Manor, the game's built-in map. Custom maps made in Haxen (see the main README) use the same format and live in `%LOCALAPPDATA%\CrownAndCard\maps\<name>.json`.

The Entrance Hall's back-left corner contains the kitchen: a range with copper pots and hood, prep counters, a sink and a serving pass. Two cooks use the `chef` directional sheet (a generated PNG with a white uniform and toque), accompanied by a steward and server. The south entrance and the original west aisle remain open.

A map is versioned JSON (`world.MapData` in `src/world/MapData.hx` reads and checks it):

The **Library** opens from the north side of the Private Party room. Its ten solid bookcases use a PNG of books across their fronts, including both faces of the freestanding shelves. See [library artwork and layout](../../art-source/library/README.md).

The kitchen's north exit leads to the **Midnight Salon**, with a bartender, round cocktail tables, velvet booths, colored accents, and a singer at a vintage microphone. The rear-foyer passage also leads north into the **Security Room**, with decorative CRT surveillance screens, a VHS deck, tape shelves, and an operator. Asset details and prompts: [salon](../../art-source/salon/README.md), [security room](../../art-source/security/README.md).

| Field | What it holds |
|---|---|
| `format`, `version` | Always `"crown-and-card-map"`, and `1` |
| `name` | The map's name, which is also its file name: 1-40 letters, digits, spaces, dashes or underscores. `manor` is reserved. |
| `rows` | The floor plan, one character per 1 m cell, **north row first**. `#` is solid wall; any other character is a room key. |
| `sectors` | The rooms: `key`, `name`, `floorZ`, `ceilZ` (meters), `floorTex`, `ceilTex`, `wallTex`, `upperTex` (walls above 3 m), and `shade` (0 brightest to 31 black) |
| `props` | Boxes: `x0 y0 x1 y1` (meters, +x east, +y north), `baseZ`, `height` (top), `topTex`, `sideTex`, and optional `solid`, `walkable` (stand on top), `hidden` (collision only) |
| `fixtures` | Set pieces by `type` and anchor `x y`: `frontDoors`, `frontDesk`, `fountain`, `grandStairs`, `cardTable` (see `src/world/Fixtures.hx` for footprints) |
| `start` | The player start: `x`, `y`, `facing` (degrees: 0 east, 90 north) |
| `guests` | Characters: `name`, `x`, `y`, `facing`, `art` (a sprite sheet name), and optional `turns` (turns to face the player), `spins` (turns slowly in place) and `walkTo {x, y}`. With neither `turns` nor `spins`, a guest always faces `facing` |
| `lights` | Point lights: `x`, `y`, `z`, `radius`, `power` |
| `chandeliers` | Candle chandelier sprites: `x`, `y`, `z`, `width` |

Textures: `marble`, `parquet`, `carpet`, `coffer`, `dome`, `damask`, `damaskUpper`, `deco`, `decoUpper`, `green`, `greenUpper`, `felt`, `tableWood`, `stone`, `ivory`, `pillarMarble`, `stairMarble`, `brass`, `velvet`, `flame`.
