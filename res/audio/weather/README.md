# Courtyard weather

SPDX-License-Identifier: CC-BY-NC-SA-4.0

Original procedural audio for Crown & Card by David Kendig. No recorded or third-party samples.

- `rain.wav`: seamless 7.5-second filtered rainfall loop.
- `thunder.wav`: seven-second low rumble with a short initial crack and fading tail.

Regenerate both 22,050 Hz mono PCM assets with `python tools/build_weather.py`. The fixed offline seed makes regeneration reproducible. Runtime lightning timing uses the game's separate cosmetic RNG. Thunder starts 1.3–4 seconds after lightning, with strikes 17–41 seconds apart after the initial strike.
