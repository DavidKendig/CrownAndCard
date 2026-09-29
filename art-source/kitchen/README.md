# Kitchen PNG art

SPDX-License-Identifier: CC-BY-NC-SA-4.0

Created with the built-in image_gen tool on 2026-09-29. Exact prompts are saved in [prompts.json](prompts.json).

- [Kitchen range](../../res/materials/kitchen-range.png): opaque front elevation of a navy cast-iron range with brass hardware. `FixtureArt` places it once across the east face of the `kitchenRange` prop. The importer samples above the source's bottom margin and converts it to the game palette at 256 by 128 pixels.
- [Cook sheet](../../res/sprites/chef.png): five full-body directional views with original transparent alpha, ivory jacket and toque, apron and navy trousers. `SpriteArt` imports each frame at 48 by 122 pixels using its existing silhouette normalization and directional mirroring. Both kitchen cooks use this PNG instead of the earlier recolored staff placeholder.

The existing range body, hood, burners and pots remain 3D geometry; the PNG front panel replaces the box oven fronts and handles.

## Counter, sink, pantry and freezer

Four additional PNGs were generated with the built-in image_gen tool on 2026-09-29; see [expansion-prompts.json](expansion-prompts.json) for the exact prompts.

- [Food countertop](../../res/materials/kitchen-counter-food.png): bread, cheese, vegetables, fruit and pastries on marble; mapped across the north prep counter.
- [Sink](../../res/materials/kitchen-sink.png): porcelain basin, brass tap, draining board, plates and towel; mapped across the south sink counter, facing the approaching staff.
- [Stocked shelves](../../res/materials/kitchen-shelves.png): jars, crocks, bread, cheese and produce; mounted above the north counter.
- [Freezer](../../res/materials/kitchen-freezer.png): ivory insulated doors, brass latches, frost, thermometer and ventilation grille; placed beside the range facing east.

`KitchenArt` maps each image once across its tagged prop's bounds with nearest filtering and the master palette. Worktops are sampled at 384 by 128, shelves at 384 by 256 and the freezer at 128 by 192. The freezer has solid box collision; wall shelves stay above the counter. These are decorative set pieces, without food pickup or freezer-door interactions.
