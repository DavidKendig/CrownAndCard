# SPDX-License-Identifier: AGPL-3.0-or-later
"""Generate original, deterministic rain and thunder PCM assets (no external samples)."""
import math
from pathlib import Path
import random
import struct
import wave

ROOT = Path(__file__).resolve().parent.parent / "res/audio/weather"
RATE = 22050


def write(name, seconds, thunder=False):
    rng = random.Random(9147 if thunder else 519)
    low = deep = 0.0
    samples = []
    for i in range(int(seconds * RATE)):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        low += .055 * (noise - low)
        deep += .009 * (noise - deep)
        if thunder:
            attack = min(1, t / .055)
            tail = max(0, 1 - t / seconds) ** 1.6
            swell = .65 + .22 * math.sin(t * 4.2) + .13 * math.sin(t * 9.7)
            value = (deep * 4.0 + low * 1.3 + noise * .035 * math.exp(-t * 5)) * attack * tail * swell
        else:
            # Steady filtered rainfall with a subtle periodic gust; crossfade makes the loop seamless.
            value = (noise * .26 + low * .55) * (.85 + .15 * math.sin(t * math.tau / seconds))
        samples.append(value)
    if not thunder:
        overlap = RATE // 2
        for i in range(overlap):
            a = i / overlap
            samples[i] = samples[-overlap+i] * (1-a) + samples[i] * a
        samples = samples[:-overlap]
    ROOT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(ROOT / name), "wb") as out:
        out.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        out.writeframes(b"".join(struct.pack("<h", round(max(-1, min(1, v)) * 32767)) for v in samples))


if __name__ == "__main__":
    write("rain.wav", 8)
    write("thunder.wav", 7, True)
