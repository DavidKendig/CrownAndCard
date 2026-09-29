# Maps

SPDX-License-Identifier: CC-BY-NC-SA-4.0

`manor.json` is Dodriec Manor, the game's built-in map. Custom maps made in Haxen (see the main README) use the same format and live in `%LOCALAPPDATA%\CrownAndCard\maps\<name>.json`.

A map is versioned JSON (`world.MapData` in `src/world/MapData.hx` reads and checks it):

| Field | What it holds |
|---|---|
| `format`, `version` | Always `"crown-and-card-map"`, and `1` |
| `name` | The map's name, which is also its file name: 1-40 letters, digits, spaces, dashes or underscores. `manor` is reserved. |
| `rows` | The floor plan, one character per 1 m cell, **north row first**. `#` is solid wall; any other character is a room key. |
| `sectors` | The rooms: `key`, `name`, `floorZ`, `ceilZ` (meters), `floorTex`, `ceilTex`, `wallTex`, `upperTex` (walls above 3 m), and `shade` (0 brightest to 31 black) |
| `props` | Boxes: `x0 y0 x1 y1` (meters, +x east, +y north), `baseZ`, `height` (top), `topTex`, `sideTex`, and optional `solid`, `walkable` (stand on top), `hidden` (collision only) |
| `fixtures` | Set pieces by `type` and anchor `x y`: `frontDoors`, `frontDesk`, `fountain`, `grandStairs`, `cardTable` (see `src/world/Fixtures.hx` for footprints) |
| `start` | The player start: `x`, `y`, `facing` (degrees: 0 east, 90 north) |
| `guests` | Characters: `name`, `x`, `y`, `facing`, `art` (a sprite sheet name), and optional `spins` and `walkTo {x, y}` |
| `lights` | Point lights: `x`, `y`, `z`, `radius`, `power` |
| `chandeliers` | Candle chandelier sprites: `x`, `y`, `z`, `width` |

Textures: `marble`, `parquet`, `carpet`, `coffer`, `dome`, `damask`, `damaskUpper`, `deco`, `decoUpper`, `green`, `greenUpper`, `felt`, `tableWood`, `stone`, `ivory`, `pillarMarble`, `stairMarble`, `brass`, `velvet`, `flame`.
