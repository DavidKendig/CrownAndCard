# Conservatory artwork and gallery

Six PNG assets were generated with the built-in image generation tool. Exact prompts and final project paths are recorded in `prompts.json`. Original generated alpha is preserved for both plant sprites; the game reduces their colors and resolution to match the existing manor art.

- `res/materials/banister-wood.png`: carved mahogany for foyer banisters, newels, and gallery handrails.
- `res/materials/braided-rope.png`: burgundy braided material for existing rope barriers.
- `res/materials/grate-steel.png`: forged metal surface on physical grate bars and balusters.
- `res/materials/planter-ceramic.png`: teal and brass patterned planter sides.
- `res/sprites/conservatory-palm.png`: transparent tall palm.
- `res/sprites/conservatory-fern.png`: transparent fern.

The conservatory has clear brass-framed exterior walls and roof, with rainy nighttime scenery beyond them. Its authored upper walkway becomes a grate with real openings and continuous collision support. Four enclosing railings protect every edge. No stairs, ladder, or gameplay access to the gallery have been added; access is reserved for later work. Ground-floor movement passes beneath the gallery independently of its upper walking surface.

Developer inspection views: `?foyerView=conservatory`, `?foyerView=gallery`, and `?foyerView=glassroof`. These are available only in development builds.
