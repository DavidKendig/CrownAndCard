# Crown & Card

A first-person, HD pixel-art game night inside a secret society's manor, written in Haxe with Heaps. See [GAME_DESIGN.md](GAME_DESIGN.md) for the full design.

## Building

Requirements: [Haxe](https://haxe.org) 4.3+, Python 3 (tools), Node.js (JS test run). The native build runs on [HashLink](https://hashlink.haxe.org) 1.16, which `tools/fetch_hashlink.ps1` puts in `native/`.

Install the libraries into a project-local repo (`.haxelib/`, git-ignored):

```bash
haxelib newrepo
haxelib install heaps 2.1.0
haxelib install hlsdl 1.16.0
haxelib install hlopenal 1.16.0
haxelib install utest 1.13.2
```

`hlsdl` and `hlopenal` are for the native build and must match the HashLink runtime's version.

| Task | Command |
|---|---|
| Unit tests (interpreter) | `haxe tests.hxml` |
| Unit tests (JavaScript / Node, cross-target check) | `haxe tests-js.hxml` |
| PNG sprite import checks (JavaScript / Node) | `haxe tests-sprites.hxml` |
| Regenerate the card faces and back in `res/cards/` (needs `npm install --no-save sharp`) | `node tools/build_cards.cjs` |
| RNG lint (no `Std.random` / `Math.random`) | `python tools/lint_rng.py` |
| Regenerate RNG reference vectors | `python tools/rng_reference.py` |
| Native build (its own window; what the launcher plays) | `haxe build-hl.hxml` (writes `native/game.hl`), and once, `powershell -File toolsetch_hashlink.ps1` for the runtime. Run it with `native\hl.exe native\game.hl`, or press PLAY in the launcher |
| Web build | `haxe build-js.hxml`, then serve `web/` (for example `python -m http.server 8080 --directory web`) and open http://localhost:8080 |
| Haxen, the map editor | `haxe haxen.hxml`, then serve `web/` and open http://localhost:8080/haxen.html (or use the launcher's HAXEN button) |

**Render spike controls:** WASD move, the mouse looks around, Left/Right turn, Up/Down (or PgUp/PgDn) look up and down (up to 75° either way), End re-centers, Shift runs. The mouse is captured for looking while you walk; M frees it, and a click takes it back. Menus and tables free it on their own.

**Game menu:** Esc in fullscreen (or Start on a controller) pauses the game and opens a menu: Resume, Settings, or Quit the game. In a window, Esc first frees the mouse and a second Esc opens the menu. Settings (display, pixel scaling, render resolution, field of view, head bob, looking style, mouse sensitivity, frame rate, volumes) take effect at once, and the launcher keeps them for next time. **Render resolution** is 480 lines by default, or 720. Everything is drawn into one frame that tall and then scaled to the screen: the world, sprites, the hands, the HUD, menus, card tables, cards, tiles and text. Layout stays on the 360-line design grid, so nothing moves when you switch, it only gets finer: art from high-resolution sources (materials, sprites, cards, tiles, the casino art) is redrawn at the new size, while the hand-drawn pixel glyphs and the font grow in whole steps (1× at 480, 2× at 720). Switching redraws all the art, which takes a few seconds. Arrows or WASD choose and change, Enter picks, Esc goes back; the mouse can click the < > arrows. In devtools builds F12 saves a screenshot to `%LOCALAPPDATA%\CrownAndCard\screenshots\` (Windows' own capture can come out black for the native window). In the browser build, click the game once to start mouse look (browsers only lock the pointer on a click); while the mouse is free, dragging with it still looks. **Controller:** left stick (or d-pad) moves, right stick looks, LB or clicking the left stick runs, clicking the right stick (or Y) re-centers. The native window reads controllers itself through SDL (Xbox, PlayStation, Switch and other pads). In the browser build the launcher reads the controller through XInput and streams it to the game, so it works even when the browser can't see it. If Steam is running, its desktop controller layout also moves the mouse: turn it off in Steam (Settings > Controller) for clean input.

**Window and fullscreen:** the game starts fullscreen, filling the whole screen at any aspect ratio. Alt+Enter or F11 switches to a window (or set Display to Windowed in the launcher's Settings), where it shows a 16:9 widescreen frame, letterboxed or pillarboxed to fit. The native window paces its frames at the display's refresh rate itself: OpenGL vsync paced some drivers far below it.

**Sprite preview:** click **F2: Sprites** at the bottom left (or press F2). Use **Next / C** to cycle the player, male/female guests and male/female staff, and **Rotate / R** to inspect eight directions. The player body is previewed here pending mirror support; the new first-person hand is visible while walking.

The render spike uses generated PNG guest angles and a brass chandelier from `res/sprites/`. See [sprite sources and prompts](res/sprites/README.md) for the art provenance and import specification. The web build embeds these PNGs and converts them to the master palette at startup.

## Games

Walk into the Card Room, step up to the card table and face it. The prompt shows **E** (keyboard) or the green **A** (controller). Press it to open the game menu and choose a game.

| Game | Players | Stakes | Rules reference |
|---|---|---|---|
| Blackjack | You vs the dealer | Bets of 2–50 Sovereigns | [Bicycle Cards: Blackjack](https://bicyclecards.com/how-to-play/blackjack). There's no governing body; each casino sets its own table rules, and ours are in [GAME_DESIGN.md §6.4](GAME_DESIGN.md) |
| Roulette | You vs the house | Straight up 35 to 1, down to even money | Single-zero European wheel with French La Partage. No governing body; house rules are in [GAME_DESIGN.md §6.4](GAME_DESIGN.md) |
| Craps | You vs the house | Pass/Don't Pass, Come/Don't Come, Field, Place, Hardways, props | No governing body; house rules are in [GAME_DESIGN.md §6.4](GAME_DESIGN.md) |
| Slots | Solo | Bets of 1–10 Sovereigns | One authored three-reel machine; house rules are in [GAME_DESIGN.md §6.4](GAME_DESIGN.md) |
| Texas Hold'em | You and 3 NPCs | 100-Sovereign buy-in, blinds 1/2, no-limit | [Pagat: Texas Hold'em](https://www.pagat.com/poker/variants/texasholdem.html). For tournament play, the rules authority is the [Poker TDA](https://www.pokertda.com/view-poker-tda-rules/) |
| Five-card draw | You and 3 NPCs | 100-Sovereign buy-in, ante 1, no-limit | [Pagat: Draw Poker](https://www.pagat.com/poker/variants/5draw.html) |
| Spades | You and a partner vs 2 NPCs | Points (game to 500) | [Bicycle Cards: Spades](https://bicyclecards.com/how-to-play/spades) |
| Go Fish | You and 3 NPCs | Books | [Bicycle Cards: Go Fish](https://bicyclecards.com/how-to-play/go-fish) |
| Slapjack | You and 3 NPCs | Every card | [Bicycle Cards: Slapjack](https://bicyclecards.com/how-to-play/slapjack) |
| War | You vs 1 NPC | Every card | [Bicycle Cards: War](https://bicyclecards.com/how-to-play/war) |
| Solitaire (Klondike) | Solo | None | [Bicycle Cards: Solitaire](https://bicyclecards.com/how-to-play/solitaire) |
| Classic Mahjong | You and 3 NPCs | Points (one East round) | [Pagat: Mah Jong](https://www.pagat.com/rummy/mahjong.html). Hong Kong-style play with flowers; the faan table is a house table (GAME_DESIGN.md §6.4) |
| Riichi Mahjong | You and 3 NPCs | Points (25,000 start, one East round) | [World Riichi Championship rules](https://www.worldriichi.org/wrc-rules), the rules authority for Riichi |
| Euchre | You and a partner vs 2 NPCs | Points (game to 10) | [Pagat: Euchre](https://www.pagat.com/euchre/euchre.html) |
| Hearts | You and 3 NPCs | Points (game ends at 100, low score wins) | [Pagat: Hearts](https://www.pagat.com/reverse/hearts.html) |
| Gin Rummy | You vs 1 NPC | Points (game to 100) | [Pagat: Gin Rummy](https://www.pagat.com/rummy/ginrummy.html) |
| Canasta | You and a partner vs 1 NPC | Points | [Pagat: Canasta](https://www.pagat.com/rummy/canasta.html). Simplified: no jokers (the card model can't represent them), no red/black threes or freeze pile; house rules are in [GAME_DESIGN.md §6.4](GAME_DESIGN.md) |
| Bridge | You and a partner vs 2 NPCs | Points (game to 700) | [Pagat: Bridge](https://www.pagat.com/auctionwhist/bridge.html). Simplified: no doubling, redoubling, conventions or vulnerability; house rules are in [GAME_DESIGN.md §6.4](GAME_DESIGN.md) |
| Egyptian Rat Screw | You and 3 NPCs | Every card | [Bicycle Cards: Egyptian Rat Screw](https://bicyclecards.com/how-to-play/egyptian-rat-screw) |
| Durak | You vs 1 NPC | Last one holding cards loses | [Pagat: Durak](https://www.pagat.com/beating/durak.html) |

Poker (the Poker Tournament Directors Association, for tournaments) and Riichi Mahjong (the World Riichi Championship) have recognized rules authorities. For the other games, the links point to the standard published rules from the US Playing Card Company (Bicycle) or to [Pagat](https://www.pagat.com/), the reference card-game rules site. Where those rules leave something open, the game's house rule is written in the rules engine (`src/games/`) and in GAME_DESIGN.md §6.4.

**Controls at the table:**

- **Menus:** arrow keys, WASD, the d-pad or the left stick move the highlight. E, Enter or A chooses; Esc or B goes back (or offers to leave the table). The mouse works too.
- **Second action:** Space on the keyboard, the blue X on a controller. It slaps in Slapjack, marks cards to exchange in five-card draw, sends a card to a foundation (or finishes the game) in Solitaire, and toggles auto-play in War.
- **Blackjack:** up/down sets the bet (even amounts, so 3:2 always pays whole Sovereigns). Hit, Stand, Double, Split and Surrender appear when they're allowed.
- **Roulette:** pick Straight number, Outside bet, or Spin from the menu. A straight bet moves a cursor around the 0-36 layout with the arrows; up/down sets the amount before every bet is confirmed. Bets sit on the layout until you spin.
- **Craps:** the menu walks you through each bet family (line, odds, Come/Don't Come, Field, Place, Hardway, props); up/down sets the amount. Roll the dice from the same menu once your bets are down.
- **Slots:** up/down sets the bet, then pull the lever.
- **Poker:** Fold, Check or Call, Bet or Raise, and All in; up/down changes the bet size. Leaving mid-hand folds, and your stack goes back to your purse.
- **Spades:** left/right picks a card (only legal cards light up) or sets your bid.
- **Go Fish:** left/right picks the rank to ask for, up/down picks the player.
- **Solitaire:** move the cursor with left/right, and up/down to switch rows or reach deeper into a pile. E picks cards up and puts them down.
- **Euchre:** order it up, pass, or name trump from the menu; discard and play a card with left/right and E.
- **Hearts:** select three cards to pass (E toggles a card, Space commits your three), then play with left/right and E.
- **Gin Rummy:** draw from the stock or the discard, then play (or knock) a card with left/right and E.
- **Canasta:** menu-driven: draw, meld a rank, lay off, or discard, all chosen from the menu.
- **Bridge:** bid a level then a strain from the menu, or pass; play your hand (and the dummy's, once it's revealed) with left/right and E.
- **Egyptian Rat Screw:** E turns over your top card; Space slaps the pile for doubles, sandwiches, top-bottom or a marriage.
- **Durak:** attack or defend with left/right and E; take the table with the second action when you can't beat it.
- **Saving:** the purse is saved when you check in with Mr. Quill.

## Haxen: the map editor

**Haxen** opens the game's floor plan and lets you make your own maps. Open it from the launcher's **HAXEN** button: maps save to `%LOCALAPPDATA%\CrownAndCard\maps`, and **Play test** starts the game on the map you're editing. Opened straight from a web server, Haxen saves maps in that browser instead, and Play test opens the game in a new tab.

- **Open:** start from a copy of Dodriec Manor (`res/maps/manor.json`), a blank room, or one of your saved maps. **Import** and **Export** move maps as `.json` files, for example to share one.
- **Rooms:** pick a room (or Wall) on the right, then paint cells with the **Brush** (B), **Rect** (R) or **Fill** (F) tools. Each room sets its floor and ceiling heights, its floor, ceiling and wall textures, and how dark it is.
- **Things to place:**
  - **Props** (P): boxes such as tables, pillars and counters. Set their height, textures, and whether they're solid, walkable on top or invisible.
  - **Guests** (G): characters with art, facing and an optional walk route.
  - **Lights** (L) and **chandeliers** (C).
  - **Fixtures** (X): the front doors (leave the game), the front desk (check in and save), the fountain, the grand stairs and the card table (the game menu).
  - **The player start** (S).
- **Select** (V): click to pick, drag to move, and drag a prop's corners to resize. Delete removes, Ctrl+D duplicates, and the arrow keys nudge (Shift for bigger steps).
- **View:** scroll to zoom, right-drag or Space-drag to pan, Home to fit. Ctrl+Z / Ctrl+Y undo and redo, and Ctrl+S saves.
- **Problems:** the panel runs the game's own checks. Click a problem to find it on the plan. A map with errors saves, but can't be played until they're fixed.
- **Playing a custom map:** use the launcher's **MAP** button to choose what PLAY starts. The web build also takes `?map=<name>`. If a map is missing or broken, the game plays Dodriec Manor and says why.

The file format is described in [res/maps/README.md](res/maps/README.md).

## Launcher

`launcher/` holds the Windows game launcher's source; building it (see below) compiles `CrownAndCardLauncher.exe` to the repo root, next to `web/`, so it finds the dev build the same way a packaged release finds its own files. It's C# on the .NET Framework 4.8 that ships with Windows 10 and 11, so the exe runs without installing anything.

The launcher follows the manor's navy, burgundy, brass and ivory palette. Its news page pairs a framed pixel-art masquerade scene with the Manor Gazette; settings and reports retain full-width layouts. The static PNG is embedded in the executable. Art provenance and the generation prompt are in [launcher/assets/README.md](launcher/assets/README.md).

- **News:** the latest posts from [davidkendig.info](https://davidkendig.info), from every category, cached for offline use.
- **Settings:** graphics and audio options, passed to the game as `--key=value` arguments (native builds) or URL parameters (web build).
- **Error tracking:** the game reports its state every 5 seconds, plus any errors, to the launcher, which records each session under `%LOCALAPPDATA%\CrownAndCard\sessions\`. Reports stay on the computer; nothing is uploaded.
- **Game log:** the native window has no browser console, so the game logs what it's doing (window size and focus, the graphics driver and frame pacing, controllers connecting, slow frames, uncaught errors with their stack, and every play at the tables, yours and the house players': cards played, bids, bets, draws, rolls and who won) and the launcher shows it live in the game log window beside the game, with the game's reported events and the launcher's own notes. Plays only record what the table can see (a card drawn from the stock stays hidden until it's played). Filter by level or source (**Plays at the tables** shows just the moves), search (Ctrl+F), copy lines, or follow along. It opens with the game (Settings > Launcher), from the **LOG** button, or from **Open log** in Reports for a past session; each session keeps it as `session.log`. Run on its own, the game writes `%LOCALAPPDATA%\CrownAndCard\logs\game.log`. In devtools builds F10 throws a test error to check the whole path.
- **Play:** starts the native build (its own window, reading controllers through SDL) if there is one; Settings > Graphics > **Run the game in** can choose the browser instead. Otherwise it plays the web build, served locally and opened as an app window in guest mode: in Chrome if it's installed, otherwise in Edge. In Edge, a controller starts out moving a pointer; right-click the game and choose **Use game controls** to play with it.
- **Multiplayer:** in the game, take the empty chair at the Private Party table to host or join a Texas Hold'em table with friends on the same version (up to six players; the host can fill seats with house players). The host's lobby shows a 16-character join code, and friends type or paste it at their own Private Party table. On the same network it just works; over the internet the host forwards TCP port 47724 to their PC and chooses **Host over the internet** with their public address, so the code points there. The launcher carries the connection (it has no multiplayer controls of its own), and your name at the table is in its Settings. Everyone sits down with 1,000 chips that never touch your purse or save. Each hand is shuffled from a seed every player adds to, and every guest's game replays the hand afterwards to check the host dealt it fairly ([GAME_DESIGN.md §13.13](GAME_DESIGN.md)).
- **Install:** `CrownAndCard-Setup-<version>.exe` (Inno Setup) installs for the current user into `%LOCALAPPDATA%\Programs\CrownAndCard` with no admin prompt. It adds a Start menu entry (and an optional desktop icon) and a normal uninstaller in Windows' installed apps. The zip is a portable alternative.
- **Updates:** on start it checks the latest [GitHub release](https://github.com/DavidKendig/CrownAndCard/releases) and offers anything newer. When you click Install, it downloads that release's Setup exe, checks its SHA-256 against GitHub's digest, runs it and closes; the installer replaces the files. A copy inside a git checkout only reports the new version.
- **Controller:** A or Start plays, LB/RB switch tabs, Y toggles the music.
- **Menu music:** plays the menu loop (`music\menu-loop-dark.ogg` next to the exe, from `res/audio/music/`) on repeat. It follows the Master and Music sliders, fades out while the game runs, and has an on/off switch in the header. It's decoded by [stb_vorbis](launcher/native/README.md) (MIT or public domain).

| Task | Command |
|---|---|
| After a `git pull`, rebuild the game, Haxen and the exe (the built files aren't in git) | `rebuild.bat` |
| Build the exe (needs Visual Studio Build Tools with the C# and C++ build tools) | `powershell -File launcher\build.ps1` |
| Build the exe and check the Guest Register save store and the local save API | `powershell -File launcher\build.ps1 -Verify` |
| Build the release: `dist\CrownAndCard\`, the portable zip and the Setup exe (run `haxe build-hl.hxml`, `tools\fetch_hashlink.ps1` and `haxe build-js.hxml` first; also needs [Inno Setup 6](https://jrsoftware.org/isinfo.php): `winget install JRSoftware.InnoSetup`) | `powershell -File launcher\build.ps1 -Package` |
| Show or bump the version (0.YY.BBB: year, then build number) | `python tools/version.py` / `python tools/version.py bump` |
| Build, package and publish a GitHub release (needs `gh`) | `powershell -File tools\release.ps1 -Bump -Notes "What changed"` |
| Check the menu music decodes and the audio device opens (result in `%LOCALAPPDATA%\CrownAndCard\launcher.log`) | `CrownAndCardLauncher.exe --check-audio` |
| Regenerate the launcher icon | `python tools/make_launcher_icon.py` |

## License

Copyright (C) 2026 David Kendig

This project uses two licenses: one for code, one for everything else.

| What | License | File |
|---|---|---|
| **Code:** Haxe source (`src/`), tests (`tests/`), tools (`tools/`), build files (`*.hxml`), shaders | [GNU AGPL-3.0](https://www.gnu.org/licenses/agpl-3.0.html) | [LICENSE](LICENSE) |
| **Assets:** art, sprites, textures, palettes, music, sound (`res/`), game data and writing (`data/`), maps (`res/maps/`, including maps made with Haxen), documentation (`docs/`, `GAME_DESIGN.md`) | [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) | [LICENSE-ASSETS](LICENSE-ASSETS) |

- **Code (AGPL-3.0):** you may use, modify and share the code, but if you distribute it or let people use a modified version over a network, you must release your source code under the same license.
- **Assets (CC BY-NC-SA 4.0):** you may share and adapt the assets for **non-commercial** purposes only, with credit ("Crown & Card by David Kendig"), and you must share your adaptations under the same license.
- **Third-party files** (fonts, libraries and anything else not made for this project) keep their own licenses, noted alongside them. Currently that's `launcher/native/stb_vorbis.c` (MIT or public domain).

If a file doesn't fit either category, ask before assuming. For commercial licensing, contact the author.
