# CrownAndCard

A first-person, HD pixel-art game night inside a secret society's manor, written in Haxe with Heaps. See [GAME_DESIGN.md](GAME_DESIGN.md) for the full design.

## Building

Requirements: [Haxe](https://haxe.org) 4.3+, Python 3 (tools), Node.js (JS test run). HashLink is needed later for native builds.

Install the libraries into a project-local repo (`.haxelib/`, git-ignored):

```bash
haxelib newrepo
haxelib install heaps 2.1.0
haxelib install utest 1.13.2
```

| Task | Command |
|---|---|
| Unit tests (interpreter) | `haxe tests.hxml` |
| Unit tests (JavaScript / Node, cross-target check) | `haxe tests-js.hxml` |
| PNG sprite import checks (JavaScript / Node) | `haxe tests-sprites.hxml` |
| RNG lint (no `Std.random` / `Math.random`) | `python tools/lint_rng.py` |
| Regenerate RNG reference vectors | `python tools/rng_reference.py` |
| Web build | `haxe build-js.hxml`, then serve `web/` (for example `python -m http.server 8080 --directory web`) and open http://localhost:8080 |

**Render spike controls:** WASD move, arrows turn, drag with the mouse (or press M to capture it) to look, PgUp/PgDn look up/down, End re-centers, Shift runs. **Controller:** left stick (or d-pad) moves, right stick looks, LB or clicking the left stick runs, clicking the right stick (or Y) re-centers.

**Sprite preview:** click **F2: Sprites** at the bottom left (or press F2). Use **Next / C** to cycle the player, male/female guests and male/female staff, and **Rotate / R** to inspect eight directions. The player body is previewed here pending mirror support; the new first-person hand is visible while walking.

The render spike uses generated PNG guest angles and a brass chandelier from `res/sprites/`. See [sprite sources and prompts](res/sprites/README.md) for the art provenance and import specification. The web build embeds these PNGs and converts them to the master palette at startup.

## Launcher

`launcher/` holds the Windows game launcher, `CrownAndCardLauncher.exe`. It's C# on the .NET Framework 4.8 that ships with Windows 10 and 11, so the exe runs without installing anything.

- **News:** the latest posts from [davidkendig.info](https://davidkendig.info), from every category, cached for offline use.
- **Settings:** graphics and audio options, passed to the game as `--key=value` arguments (native builds) or URL parameters (web build).
- **Error tracking:** the game reports its state every 5 seconds, plus any errors, to the launcher, which records each session under `%LOCALAPPDATA%\CrownAndCard\sessions\`. Reports stay on the computer; nothing is uploaded.
- **Play:** starts the native build if there is one, otherwise the web build, served locally and opened as an Edge or Chrome app window in guest mode.
- **Updates:** on start it checks the latest [GitHub release](https://github.com/DavidKendig/CrownAndCard/releases). If it's newer, the launcher downloads `CrownAndCard-<version>-win64.zip`, checks its SHA-256, installs it with a rollback copy, and restarts. A copy inside a git checkout is never overwritten; it only reports the new version.
- **Controller:** A or Start plays, LB/RB switch tabs, Y toggles the music.
- **Menu music:** plays the menu loop (`res/audio/music/menu-loop-dark.ogg`, embedded in the exe) on repeat. It follows the Master and Music sliders, fades out while the game runs, and has an on/off switch in the header. It's decoded by [stb_vorbis](launcher/native/README.md) (MIT or public domain).

| Task | Command |
|---|---|
| Build the exe (needs Visual Studio Build Tools with the C# and C++ build tools) | `powershell -File launcher\build.ps1` |
| Show or bump the version (0.YY.BBB: year, then build number) | `python tools/version.py` / `python tools/version.py bump` |
| Build, package and publish a GitHub release (needs `gh`) | `powershell -File tools\release.ps1 -Bump -Notes "What changed"` |
| Check the menu music decodes and the audio device opens (result in `%LOCALAPPDATA%\CrownAndCard\launcher.log`) | `launcher\bin\CrownAndCardLauncher.exe --check-audio` |
| Build and package with the web build into `dist\CrownAndCard\` | `haxe build-js.hxml`, then `powershell -File launcher\build.ps1 -Package` |
| Regenerate the launcher icon | `python tools/make_launcher_icon.py` |

## License

Copyright (C) 2026 David Kendig

This project uses two licenses: one for code, one for everything else.

| What | License | File |
|---|---|---|
| **Code:** Haxe source (`src/`), tests (`tests/`), tools (`tools/`), build files (`*.hxml`), shaders | [GNU AGPL-3.0](https://www.gnu.org/licenses/agpl-3.0.html) | [LICENSE](LICENSE) |
| **Assets:** art, sprites, textures, palettes, music, sound (`res/`), game data and writing (`data/`), levels (`levels/`), documentation (`docs/`, `GAME_DESIGN.md`) | [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) | [LICENSE-ASSETS](LICENSE-ASSETS) |

- **Code (AGPL-3.0):** you may use, modify and share the code, but if you distribute it or let people use a modified version over a network, you must release your source code under the same license.
- **Assets (CC BY-NC-SA 4.0):** you may share and adapt the assets for **non-commercial** purposes only, with credit ("Crown & Card by David Kendig"), and you must share your adaptations under the same license.
- **Third-party files** (fonts, libraries and anything else not made for this project) keep their own licenses, noted alongside them. Currently that's `launcher/native/stb_vorbis.c` (MIT or public domain).

If a file doesn't fit either category, ask before assuming. For commercial licensing, contact the author.
