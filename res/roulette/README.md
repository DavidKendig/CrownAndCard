# Roulette art

Generated in the built-in image tool, with exact prompts in `art-source/roulette/prompts.json`:

- `roulette-bowl.png`: stationary carved mahogany and brass bowl with recessed ball track.
- `roulette-rotor.png`: separate mahogany center and brass spindle, rotated with the numbered pockets.
- `roulette-ball.png`: separate transparent ivory ball sprite.

The game preserves the generated alpha, imports these into its existing palette, and downsamples with nearest-neighbor rendering. Pocket colors, dividers, and numbers are drawn by the game so all 37 pockets match the single-zero European sequence exactly.

Each eight-second spin animates the rotor clockwise and the ball counterclockwise, followed by deceleration, inward bounces, pocket capture, and a final shared stop. Motion is cosmetic choreography toward the existing outcome engine's selected pocket; it does not consume outcome randomness or change payouts. Betting and leaving are locked during the spin, and the result is revealed only after the ball settles.
