# Audio

All audio ships as **Ogg Vorbis** (`.ogg`): an open, royalty-free format that Heaps plays natively on the web and HashLink builds.

| File | What it is | Source | License |
|---|---|---|---|
| `music/menu-loop-dark.ogg` | Crown & Card menu loop. Plays in the launcher (§13.12). | Encoded from `C&C Menu Loop Dark.wav` (48 kHz stereo) with libvorbis at quality 6 (~192 kbps) | CC BY-NC-SA 4.0 (project asset license) |

## Loops

The encode keeps the exact sample count of the source (9,964,800 frames, 207.600 s), so the loop point is seamless. To re-encode after editing the master:

```bash
ffmpeg -i "C&C Menu Loop Dark.wav" -map_metadata -1 -c:a libvorbis -q:a 6 -metadata title="C&C Menu Loop Dark" -metadata album="Crown & Card" res/audio/music/menu-loop-dark.ogg
```

Then run `CrownAndCardLauncher.exe --check-audio` (a dev copy reads the loop from `res/audio/music/`; release packages copy it to `music\` next to the exe) to confirm it decodes to the same length (the result goes to `%LOCALAPPDATA%\CrownAndCard\launcher.log`).
