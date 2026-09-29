// SPDX-License-Identifier: AGPL-3.0-or-later

import art.ProcArt;
import art.SpriteArt;
import art.FoyerArt;
import ui.ButtonGlyph.InputMode;
import core.LaunchOptions;
import core.Settings;
import core.Telemetry;
import core.Version;
import render.BuildShader;
import render.BuildSprite;
import render.LowResView;
import render.Palette;
import render.Resolution;
import world.Level;
import world.MapData.MapFile;
import world.PlayerController;
import world.WorldBuilder;

/**
	Phase 0 render spike (§14.2): walk the manor (or a custom Haxen map) in
	the HD pixel / Build look. Proves the 360p pixel grid, palette shade
	tables, 8-angle face sprites, y-shearing and the first-person hands.
**/
class Main extends hxd.App {
	/** Shade levels added per meter of distance. **/
	static inline var VISIBILITY = 0.55;

	var view:LowResView;
	var player:PlayerController;
	final sprites:Array<BuildSprite> = [];
	final spinners:Array<BuildSprite> = [];
	/** Guests that turn to face the player (a map guest's "turns"). **/
	final turners:Array<BuildSprite> = [];
	final walkers:Array<{sprite:BuildSprite, path:world.GuestWalkPath}> = [];
	final securityGuards:Array<BuildSprite> = [];
	var hands:h2d.Bitmap;
	var crosshair:h2d.Bitmap;
	var info:h2d.Text;
	var time = 0.0;
	var spritePreview:art.SpritePreview;
	var map:world.GridMap;

	/** The map being played, with its fixtures' interactions (§13.6). Null until it has loaded. **/
	var level:Null<Level>;

	var entrance:ui.EntranceUI;
	var register:core.GuestRegister;

	/** The Card Room table's game menu and seated games (§4.3). **/
	var table:ui.CardTableUI;
	/** The Private Party table, where multiplayer starts (§13.13). **/
	var privateTable:ui.PrivateTableUI;

	/**
		The controller as the launcher reads it (XInput, web build only), and the
		platform's own when it has one: the browser's Gamepad API on the web
		build, SDL's game controllers in the native window.
	**/
	var bridge:core.PadBridge;
	var browserPad:hxd.Pad = hxd.Pad.createDummy();
	var browserPadActivity = -1.0;
	final connectedPads:Array<hxd.Pad> = [];

	/** Logs the window, controllers and hitches (GameLog). **/
	var windowWatch:core.WindowWatch;

	#if hl
	/** Frame pacing for the native window, rechecked now and then in case it moves to another display. **/
	var pacer:core.FramePacer;
	var refreshCheckedAt = 0.0;

	/**
		The native window, set up before anything loads so it's already
		fullscreen (the default) while the manor is built.
	**/
	function setUpWindow():Void {
		var window = hxd.Window.getInstance();
		window.title = "Crown & Card";
		// The game paces itself at the display's refresh rate instead of the driver's vsync (see FramePacer).
		window.vsync = false;
		pacer = new core.FramePacer(displayRefreshRate());
		core.GameLog.info("window", 'Pacing frames at ${pacer.targetFps} fps (the display\'s refresh rate)');
		window.resize(settings.windowWidth, settings.windowHeight);
		window.displayMode = settings.fullscreen ? Borderless : Windowed;
		window.onClose = () -> {
			// The window's close button; the launcher learns the visit ended on purpose.
			core.GameLog.flush();
			core.GameLog.info("window", "Closed by the player");
			telemetry.event("quit", "Closed the game window");
			true;
		};
	}

	/** The refresh rate of the display the window is on, or 0 if SDL can't say. **/
	static function displayRefreshRate():Int {
		return try sdl.Sdl.getFramerate(@:privateAccess hxd.Window.getInstance().window.win) catch (_:Dynamic) 0;
	}
	#end

	/** The purse, saved with each check-in (§10.1). **/
	final wallet = new core.Wallet();
	var visited:Array<String> = [];
	var doorArmed = true;
	var fountainWater:Array<BuildShader> = [];
	var fountainAnimations:Array<Float->Void> = [];
	var waterTime=0.0;
	var storm:world.FoyerStorm;
	#if devtools
	var showDebug = false;
	#end

	/** Graphics and audio options passed in by the launcher. **/
	var settings:Settings;

	/** Heartbeats and error reports to the launcher (§13.12). **/
	var telemetry:Telemetry;

	static function main() {
		new Main();
	}

	override function init() {
		var options = LaunchOptions.read();
		core.GameLog.init(options.get("telemetry") != null);
		// Every play at the tables, the player's and the house players', goes into the log (§13.12).
		games.PlayLog.sink = (table, text) -> core.GameLog.info("play", '$table · $text');
		settings = Settings.fromOptions(options);
		// Before any art is made: the frame and all art that follows are drawn at this resolution.
		Resolution.set(settings.renderHeight);
		telemetry = new Telemetry(options.get("telemetry"));
		#if hl
		setUpWindow();
		#end

		hxd.Res.initEmbed();
		core.MapSource.load(options.get("map"), options.get("telemetry"), (data, notice) -> {
			buildWorld(options, data);
			if (notice != null) {
				telemetry.event("map", notice);
				entrance.notify(notice, 10);
			}
		});
	}

	/** Builds the world from the loaded map, then everything that plays in it. **/
	function buildWorld(options:Map<String, String>, data:MapFile):Void {
		level = new Level(data);
		var palette = new Palette();
		var shadeLut = h3d.mat.Texture.fromPixels(palette.buildShadeLut());
		shadeLut.filter = Nearest;
		shadeLut.wrap = Clamp;

		map = level.map;
		var textures = [
			"kitchenTile" => FoyerArt.surface("materials/kitchen-floor-tile.png",palette,128,128).toIndexTexture(false,true),
			"bathroomTile" => FoyerArt.surface("materials/bathroom-floor-tile.png",palette,128,128).toIndexTexture(false,true),
			"clubPurple" => FoyerArt.material(Palette.PURPLE,13).toIndexTexture(false,true),
			"clubTeal" => FoyerArt.material(Palette.TEAL,13).toIndexTexture(false,true),
			"partyFloor" => FoyerArt.texture(false,true,"materials/party-floor.png",palette,256,256),
			"partyWall" => FoyerArt.texture(false,true,"materials/party-wall.png",palette,128,192),
			"partyCeiling" => FoyerArt.texture(false,true,"materials/party-ceiling.png",palette,256,256),
			"marble" => FoyerArt.texture(false,true,"materials/manor-floor.png",palette,128,128),
			"parquet" => ProcArt.parquet().toIndexTexture(false, true),
			"carpet" => ProcArt.carpet().toIndexTexture(false, true),
			"coffer" => FoyerArt.texture(false,true,"materials/ceiling-coffer.png",palette,256,256),
			"dome" => ProcArt.ceilingDome().toIndexTexture(false, true),
			"damask" => FoyerArt.texture(false,true,"materials/manor-wall.png",palette,128,192),
			"damaskUpper" => FoyerArt.texture(false,true,"materials/manor-wall.png",palette,128,128,.06,.59),
			"deco" => ProcArt.wallDeco().toIndexTexture(false, true),
			"decoUpper" => ProcArt.upperDeco().toIndexTexture(false, true),
			"green" => ProcArt.wallGreen().toIndexTexture(false, true),
			"greenUpper" => ProcArt.upperGreen().toIndexTexture(false, true),
			"felt" => ProcArt.felt().toIndexTexture(false, true),
			"tableWood" => ProcArt.tableWood().toIndexTexture(false, true),
			"stone" => FoyerArt.texture(false,true,"materials/ivory-marble.png",palette,128,128),
			"ivory" => FoyerArt.texture(false,true,"materials/ivory-marble.png",palette,128,128),
			"pillarMarble" => FoyerArt.texture(false,true,"materials/pillar-marble.png",palette,256,256),
			"stairMarble" => FoyerArt.texture(false,true,"materials/stair-marble.png",palette,256,256),
			"banisterWood" => FoyerArt.texture(false,true,"materials/banister-wood.png",palette,256,256),
			"ropeBraid" => FoyerArt.texture(false,true,"materials/braided-rope.png",palette,256,256),
			"grateMetal" => FoyerArt.texture(false,true,"materials/grate-steel.png",palette,256,256),
			"planterCeramic" => FoyerArt.texture(false,true,"materials/planter-ceramic.png",palette,256,256),
			"glass" => FoyerArt.material(Palette.NAVY,9).toIndexTexture(false,true),
			"soil" => FoyerArt.material(Palette.NIGHT,3).toIndexTexture(false,true),
			"brass" => FoyerArt.material(Palette.GOLD,10).toIndexTexture(false,true),
			"velvet" => FoyerArt.material(Palette.RED,6).toIndexTexture(false,true),
			"flame" => FoyerArt.material(Palette.IVORY,15).toIndexTexture(false,true),
		];
		var shaders = WorldBuilder.build(map, textures, shadeLut, s3d);
		var fixtureArt = world.FixtureArt.build(level, palette, shadeLut, s3d);
		shaders = shaders.concat(fixtureArt.shaders);
		fountainWater = fixtureArt.water;
		fountainAnimations = fixtureArt.animations;

		var plantTextures=[for(name in ["palm","fern"])
			FoyerArt.texture(true,false,"sprites/conservatory-"+name+".png",palette,192,name=="palm"?288:192,0,1,true)];
		for(p in map.plants) {
			var plant=new BuildSprite(plantTextures[p.palm?0:1],shadeLut,1,p.palm?2.4:1.65,p.palm?3.6:1.65,s3d);
			plant.setPosition(p.x,p.y,p.z); sprites.push(plant);
		}

		for (fixture in world.BathroomArt.build(map, palette, shadeLut, s3d)) sprites.push(fixture);

		// Cache by character identity; keep authored colors (no implicit brown swap).
		var characterSheets = [for (name in SpriteArt.CHARACTERS) name => SpriteArt.characterSheet(name, palette)];
		var texturesByCharacter = new Map<String, h3d.mat.Texture>();
		for (g in data.guests) {
			if (SpriteArt.CHARACTERS.indexOf(g.art) < 0) continue;
			if (!texturesByCharacter.exists(g.art))
			{
				// Imported again at twice the size when the render resolution calls for finer textures.
				var sheet = characterSheets.get(g.art), art = g.art;
				texturesByCharacter.set(art, Resolution.texture(sheet.width, sheet.height, false,
					(pw, ph) -> (pw == sheet.width ? sheet : SpriteArt.characterSheet(art, palette, Std.int(pw / sheet.width))).toIndexPixels(true)));
			}
			var s = new BuildSprite(texturesByCharacter.get(g.art), shadeLut, BuildSprite.DRAWN_ANGLES,
				SpriteArt.frameWidth(g.art) / SpriteArt.density(g.art), SpriteArt.frameHeight(g.art) / SpriteArt.density(g.art),
				s3d, SpriteArt.animationRows(g.art));
			s.setPosition(g.x, g.y, 0);
			s.facing = g.facing * Math.PI / 180;
			s.shader.shadeOffset = sectorShade(map, g.x, g.y);
			sprites.push(s);
			if (StringTools.startsWith(g.art, "security_")) securityGuards.push(s);
			if (g.turns == true && g.walkTo == null)
				turners.push(s);
			if (g.spins == true)
				spinners.push(s);
			if (g.walkTo != null)
				walkers.push({sprite: s, path: new world.GuestWalkPath(g.x, g.y, g.walkTo.x, g.walkTo.y)});
		}

		var chandelierTex = Resolution.texture(96, 72, false, (pw, ph) -> SpriteArt.chandelier(palette, Std.int(pw / 96)).toIndexPixels(true));
		for (ch in data.chandeliers) {
			var chandelier = new BuildSprite(chandelierTex, shadeLut, 1, ch.width, ch.width * .75, s3d);
			chandelier.setPosition(ch.x, ch.y, ch.z);
			chandelier.shader.shadeOffset = -8; // candlelit: nearly full bright
			sprites.push(chandelier);
		}

		for (s in sprites)
			shaders.push(s.shader);
		if(map.windows.length>0) {
			storm=new world.FoyerStorm(map,textures,shadeLut,s3d,shaders,settings,palette);
			for(sh in storm.frames) shaders.push(sh);
		}
		for (sh in shaders) {
			sh.visibility = VISIBILITY;
			sh.setLights(data.lights);
		}

		var cam = s3d.camera;
		// World is right-handed with Z up: facing north (+Y), east (+X) is on the right.
		cam.rightHanded = true;
		cam.fovY = settings.verticalFov(); // horizontal FOV measured at 16:9 (§5.5)
		cam.zNear = 0.05;
		cam.zFar = 120;

		player = new PlayerController(map, data.start.x, data.start.y, level.startYaw);
		player.bobAmount = settings.headBob / 100;
		player.mouseScale = settings.mouseSensitivity / 100;
		player.perspectiveLook = settings.lookStyle == Perspective;
		#if devtools
		// Named inspection views for repeatable visual checks; absent in release builds.
		switch(options.get("foyerView")) {
			case "conservatory": player.x=34; player.y=8; player.yaw=.8; player.pitch=.15;
			case "gallery": player.x=34; player.y=17; player.yaw=-Math.PI/2; player.pitch=-.3;
			case "glassroof": player.x=36; player.y=10; player.yaw=.3; player.pitch=1.1;
			case "doors": player.x=13; player.y=2.1; player.yaw=-Math.PI/2;
			case "windows": player.x=13; player.y=9; player.yaw=-Math.PI/2; player.pitch=.2;
			case "fountain": player.x=10; player.y=7.9; player.yaw=.80; player.pitch=-.10;
			case "pillars": player.x=7; player.y=6; player.yaw=2.5; player.pitch=.35;
			case "ceiling": player.x=9; player.y=10; player.yaw=.4; player.pitch=.95;
			case "courtyard": player.x=9; player.y=2.6; player.yaw=-Math.PI/2; player.pitch=.1;
			case "stairs": player.x=13; player.y=13.25; player.yaw=Math.PI/2;
			case "aisle": player.x=7.5; player.y=11.5; player.yaw=.35;
			case "rotunda": player.x=13; player.y=24; player.yaw=Math.PI/2;
			case "blackjack": player.x=13; player.y=34.8; player.yaw=Math.PI/2; player.pitch=-.38;
			case "roulette": player.x=10; player.y=34.65; player.yaw=Math.PI/2; player.pitch=-.38;
			case "party": player.x=26; player.y=20.5; player.yaw=0; player.pitch=-.05;
			case "partyinside": player.x=36; player.y=21.5; player.yaw=Math.PI/2; player.pitch=.06;
			case "partytable": player.x=32; player.y=23; player.yaw=.65; player.pitch=-.25;
			default:
		}
		player.feetZ=map.floorAt(player.x,player.y);
		#end

		windowWatch = new core.WindowWatch();

		view = new LowResView(s2d);
		view.integerScaling = settings.scaling == Integer;
		view.resize(s2d.width, s2d.height);
		hands = new h2d.Bitmap(Resolution.tile(150, 112, (pw, ph) -> SpriteArt.playerHands(palette, pw, ph).toColorPixels(palette)), view.hud);
		crosshair = new h2d.Bitmap(h2d.Tile.fromColor(0xE8E0C8, 2, 2), view.hud);
		info = new h2d.Text(hxd.res.DefaultFont.get(), view.hud);
		info.textColor = 0xE8D8A8;
		info.dropShadow = {dx: 1, dy: 1, color: 0x000000, alpha: 1};
		info.x = 6;
		info.y = 4;
		spritePreview = new art.SpritePreview(characterSheets, palette, view.hud);
		entrance = new ui.EntranceUI(view.hud);
		entrance.onLeave = quitGame;
		entrance.onPrompt = interact;
		entrance.onStay = () -> { firstDragFrame=true; };
		register = new core.GuestRegister(options.get("telemetry"));
		// Outcome streams fork from one master key per visit (§7.3). Saving it in the register comes later.
		table = new ui.CardTableUI(view.hud, palette, wallet, rng.ChaChaRng.fromEntropy());
		// Multiplayer starts at the Private Party table (§13.13).
		privateTable = new ui.PrivateTableUI(view.hud, palette, options.get("telemetry"));
		pauseMenu = new ui.PauseMenu(view.hud, settings);
		pauseMenu.onChange = applySetting;
		pauseMenu.onSave = () -> core.GameLog.info("settings", core.SettingsSync.save(options.get("telemetry"), settings)
			? "Sent to the launcher to keep for next time" : "Changed for this visit (no launcher to keep them)");
		pauseMenu.onQuit = () -> {
			quitReason = "Quit from the game menu";
			pauseMenu.close();
			entrance.depart();
		};
		lookMode = Relative(e -> if (!entrance.open && !table.open && !privateTable.open && !pauseMenu.open) player.look(e.relX, e.relY), true);
		hxd.Window.getInstance().addEventTarget(e -> if (e.kind == EPush && e.button == 0) clickFrame = hxd.Key.getFrame());
		register.load(error -> {
			if(error!=null) entrance.notify(error,8);
			else {
				var saved = register.wallet();
				wallet.sovereigns = saved.sovereigns;
				wallet.marker = saved.marker;
				for(room in register.checkpoint.rooms) if(visited.indexOf(room)<0) visited.push(room);
				if (data.name != "Dodriec Manor") entrance.notify('Welcome to ${data.name}.');
				else entrance.notify(register.checkpoint.checkIns>0?"Welcome back. Your Guest Register page has been restored.":"Welcome to Dodriec Manor. Check in with the hooded keeper.");
			}
		});

		// Controllers: use the first one to connect; fall back to keyboard and mouse if it goes away.
		InputMode.listen();
		bridge = new core.PadBridge(options.get("telemetry"));
		hxd.Pad.wait(p -> {
			core.WindowWatch.padConnected(p);
			connectedPads.push(p);
			browserPad = p;
			InputMode.usingPad = true;
			p.onDisconnect = () -> {
				core.WindowWatch.padDisconnected(p);
				connectedPads.remove(p);
				// Carry on with another controller that's still plugged in, if there is one.
				if (browserPad == p) browserPad = connectedPads.length > 0 ? connectedPads[connectedPads.length - 1] : hxd.Pad.createDummy();
			};
		});

		telemetry.stateProvider = gameState;
		telemetry.start(settings);

		#if (js && devtools)
		// Dev-only console hooks: crownDebug.teleport(x, y, yawDegrees, pitchDegrees), crownDebug.state()
		js.Syntax.code("window.crownDebug = {0}", {
			teleport: (x:Float, y:Float, yawDeg:Float, pitchDeg:Float) -> {
				player.x = x;
				player.y = y;
				player.feetZ = map.floorAt(x,y);
				player.yaw = yawDeg * Math.PI / 180;
				player.pitch = pitchDeg * Math.PI / 180;
			},
			state: () -> {x: player.x, y: player.y, yawDeg: player.yaw * 180 / Math.PI, pitchDeg: player.pitch * 180 / Math.PI,
				pad: {connected: player.pad.connected, x: player.pad.xAxis, y: player.pad.yAxis, bridge: bridge.pad.connected}},
			padPrompts: (on:Bool) -> InputMode.forcePad = on,
		});
		#end
	}

	/**
		Mouse look (§11.4): while the player walks the manor the mouse is
		captured and turns the camera, like any first-person game. Esc (or M)
		frees it to reach other windows; a click takes it back. Menus and
		tables free it on their own and it comes back when they close.

		The native window captures it straight away and again whenever it
		regains focus. A browser only grants pointer lock on a click (and ends
		it itself on Esc), so there it starts on the first click. While the
		mouse is free, dragging with the left button still looks.
	**/
	function updateMouseLook():Void {
		var window = hxd.Window.getInstance();
		var captured = window.mouseMode != Absolute;
		// Key.isPressed misses a click that's pressed and released within one frame; the push event doesn't.
		var click = clickFrame >= hxd.Key.getFrame() - 1;
		if (captured && (hxd.Key.isPressed(hxd.Key.ESCAPE) || hxd.Key.isPressed(hxd.Key.M))) mouseFree = true;
		else if (!captured && (click || hxd.Key.isPressed(hxd.Key.M))) mouseFree = false;
		#if js
		var want = !mouseFree && (click || hxd.Key.isPressed(hxd.Key.M));
		if (!captured && want) window.mouseMode = lookMode;
		else if (captured && mouseFree) window.mouseMode = Absolute;
		#else
		var want = !mouseFree && window.isFocused;
		if (want != captured) window.mouseMode = want ? lookMode : Absolute;
		#end
		var nowCaptured = window.mouseMode != Absolute;
		if (nowCaptured != captured)
			core.GameLog.info("input", nowCaptured ? "Mouse captured for looking" : mouseFree ? "Mouse freed (click the game to look again)" : "Mouse released");
		if (window.mouseMode == Absolute) {
			var mx = window.mouseX, my = window.mouseY;
			// Right after controller input, mouse drags are the controller in disguise (Steam's desktop layout).
			if (hxd.Key.isDown(hxd.Key.MOUSE_LEFT) && !firstDragFrame && !InputMode.padRecent)
				player.look(mx - lastMouseX, my - lastMouseY);
			firstDragFrame = !hxd.Key.isDown(hxd.Key.MOUSE_LEFT);
			lastMouseX = mx;
			lastMouseY = my;
		}
	}

	/**
		The launcher's XInput stream whenever it's there; the browser's gamepad
		without the launcher, or while it's the only one being touched (a pad
		XInput can't see). They're usually the same controller. A browser pad
		that always looks touched (a stuck axis on Steam's virtual device) mustn't
		outvote the launcher's, so the stream only yields while it sits idle.
		A dummy when there's neither.
	**/
	function choosePad():Void {
		bridge.update();
		var now = haxe.Timer.stamp();
		if (core.PadBridge.active(browserPad)) browserPadActivity = now;
		var bridgeIdle = bridge.lastActivity < 0 || now - bridge.lastActivity > 1;
		var browserBusy = browserPadActivity >= 0 && now - browserPadActivity < .25;
		var useBridge = bridge.pad.connected && !(browserPad.connected && browserBusy && bridgeIdle);
		var pad = useBridge ? bridge.pad : browserPad;
		if (pad != player.pad) player.pad = pad;
	}

	/**
		Windowed play shows a 16:9 frame; fullscreen fills the screen (§5.2).
		Alt+Enter toggles fullscreen; F11 (the browser's own) and the launcher's
		Fullscreen setting are detected too.
	**/
	function updateFullscreen():Void {
		var toggle = hxd.Key.isDown(hxd.Key.ALT) && hxd.Key.isPressed(hxd.Key.ENTER);
		#if js
		var doc:Dynamic = js.Browser.document;
		var win = js.Browser.window;
		if (toggle) {
			if (doc.fullscreenElement != null) doc.exitFullscreen();
			else if (doc.documentElement.requestFullscreen != null) doc.documentElement.requestFullscreen();
		}
		var full = doc.fullscreenElement != null || (win.innerWidth >= win.screen.width - 2 && win.innerHeight >= win.screen.height - 2);
		#else
		// No browser to handle F11 in the native window; it toggles like Alt+Enter.
		if (hxd.Key.isPressed(hxd.Key.F11)) toggle = true;
		var window = hxd.Window.getInstance();
		if (toggle) window.displayMode = window.displayMode == Windowed ? Borderless : Windowed;
		var full = window.displayMode != Windowed;
		#end
		// The game menu shows (and saves) what's really on screen: a browser can refuse or delay leaving fullscreen.
		settings.fullscreen = full;
		if (full != view.fillScreen) {
			view.fillScreen = full;
			view.resize(s2d.width, s2d.height);
		}
	}

	var lastMouseX = 0.0;
	var lastMouseY = 0.0;
	var firstDragFrame = true;

	/**
		The game menu: Esc in fullscreen opens it. In a window Esc first frees
		the mouse (updateMouseLook) and opens the menu once it's free. Start on
		a controller opens it either way. Returns true when it opened.
	**/
	function openMenuIfAsked():Bool {
		var window = hxd.Window.getInstance();
		var esc = hxd.Key.isPressed(hxd.Key.ESCAPE) && (view.fillScreen || window.mouseMode == Absolute);
		var start = player.pad.connected && player.pad.isPressed(player.pad.config.start);
		if (!esc && !start) return false;
		pauseMenu.show(player.pad);
		window.mouseMode = Absolute;
		core.GameLog.info("menu", "Opened the game menu");
		return true;
	}

	/** Applies a setting changed in the game menu. Frame rate and volumes are read every frame, so they need nothing. **/
	function applySetting(key:String):Void {
		switch (key) {
			case "fullscreen": setFullscreen(settings.fullscreen);
			case "scaling":
				view.integerScaling = settings.scaling == Integer;
				view.resize(s2d.width, s2d.height);
			case "renderHeight":
				// Redrawing every piece of art takes a few seconds: say so first, and change over once that's on screen.
				pendingLines = settings.renderHeight;
				pendingFrames = 2;
				pauseMenu.notice = 'Redrawing everything at ${settings.renderHeight} lines...';
			case "fov": s3d.camera.fovY = settings.verticalFov();
			case "headBob": player.bobAmount = settings.headBob / 100;
			case "lookStyle": player.perspectiveLook = settings.lookStyle == Perspective;
			case "mouseSensitivity": player.mouseScale = settings.mouseSensitivity / 100;
			default:
		}
		core.GameLog.info("settings", '$key = ${settings.toOptions().get(key)}');
	}

	function setFullscreen(on:Bool):Void {
		#if js
		var doc:Dynamic = js.Browser.document;
		if (on && doc.fullscreenElement == null && doc.documentElement.requestFullscreen != null) doc.documentElement.requestFullscreen();
		else if (!on && doc.fullscreenElement != null) doc.exitFullscreen();
		#else
		hxd.Window.getInstance().displayMode = on ? Borderless : Windowed;
		#end
	}

	/** Set by Esc or M: the player freed the mouse; a click captures it again. **/
	var mouseFree = false;

	/** The game menu (Esc in fullscreen, Start on a controller). **/
	var pauseMenu:ui.PauseMenu;

	/** A render resolution chosen in the game menu, applied a couple of frames later (after its notice shows), or 0. **/
	var pendingLines = 0;
	var pendingFrames = 0;

	/** Redraws every piece of art for a new render resolution, then the frame (render.Resolution). **/
	function applyResolution():Void {
		var redrew = Resolution.set(pendingLines);
		view.resize(s2d.width, s2d.height);
		core.GameLog.info("settings", 'Render resolution now ${Resolution.lines} lines (${view.renderWidth}x${view.renderHeight}); redrew $redrew');
		pendingLines = 0;
		pauseMenu.notice = "";
	}

	/** What the launcher is told when the game quits. **/
	var quitReason = "Left through the manor's front doors";

	/** hxd.Key's frame of the last left click in the window. **/
	var clickFrame = -10;

	/**
		The captured mode, made once: Heaps compares modes by value, so a new
		closure every frame would count as a change and reset the capture.
	**/
	var lookMode:Null<hxd.impl.MouseMode>;

	function checkIn():Void {
		if(entrance.open || !level.atDesk(player.x,player.y,player.yaw) || register.busy) return;
		entrance.notify("Signing the Guest Register...");
		register.checkIn(visited,wallet,error -> entrance.notify(error==null?'Check-in saved with ${wallet.sovereigns} Sovereigns. Fortune favors the bold.':error,6));
	}

	/** E / A (or a click on the prompt): whatever the player is standing at. **/
	function interact():Void {
		if (entrance.open || table.open || privateTable.open || pauseMenu.open) return;
		if (level.atDesk(player.x,player.y,player.yaw)) checkIn();
		else if (level.atTable(player.x,player.y,player.yaw)) {
			hxd.Window.getInstance().mouseMode=Absolute;
			table.show();
		} else if (level.atPrivateTable(player.x,player.y,player.yaw)) {
			hxd.Window.getInstance().mouseMode=Absolute;
			games.PlayLog.sitAt("Private Party Hold'em", []);
			privateTable.show();
		}
	}

	function quitGame():Void {
		if(storm!=null) storm.stop();
		hxd.Window.getInstance().mouseMode=Absolute;
		core.GameLog.flush();
		telemetry.event("quit",quitReason);
		hands.visible=crosshair.visible=info.visible=false;
		#if js
		js.Browser.document.title="Crown & Card — Visit ended";
		js.Browser.window.close();
		#elseif sys
		Sys.exit(0);
		#end
	}

	/** What the launcher records with every heartbeat and error report. **/
	function gameState():Dynamic {
		if (level == null) return {room: "loading the map"};
		var sector = map.sectorAtWorld(player.x, player.y);
		// Heaps reports a huge rate until a few frames have been timed; leave it out until then.
		var fps = hxd.Timer.fps();
		return {
			map: level.data.name,
			room: sector == null ? "outside the map" : sector.name,
			x: Math.round(player.x * 100) / 100,
			y: Math.round(player.y * 100) / 100,
			yawDeg: ((Math.round(player.yaw * 180 / Math.PI) % 360) + 360) % 360,
			pitchDeg: Math.round(player.pitch * 180 / Math.PI),
			fps: fps > 1000 ? null : Math.round(fps),
			view: '${view.renderWidth}x${view.renderHeight} at ${Math.round(view.scale * 100) / 100}x',
			table: privateTable != null && privateTable.open ? privateTable.status : table == null ? "" : table.status,
			sovereigns: wallet.sovereigns,
			controller: controllerState(),
		};
	}

	/** Which controller drives the player and what its left stick reads, for the launcher's session records. **/
	function controllerState():String {
		if (bridge == null) return "starting";
		var p = player.pad;
		var own = #if js "browser" #else "SDL" #end;
		var source = !p.connected ? "none" : p == bridge.pad ? "launcher" : '$own (${browserPad.name})';
		var others = [];
		if (bridge.pad.connected && p != bridge.pad) others.push("launcher");
		if (browserPad.connected && p != browserPad) others.push('$own (${browserPad.name})');
		var stick = p.connected ? ' stick ${Math.round(p.xAxis * 100) / 100},${Math.round(p.yAxis * 100) / 100}' : "";
		return source + stick + (others.length > 0 ? '; also ${others.join(", ")}' : "");
	}

	static function sectorShade(map:world.GridMap, x:Float, y:Float):Float {
		var s = map.sectorAtWorld(x, y);
		return s == null ? 8 : s.shade;
	}

	override function onResize() {
		if (view != null)
			view.resize(s2d.width, s2d.height);
	}

	override function update(dt:Float) {
		if (level == null) return;
		#if hl
		pacer.wait();
		if (time - refreshCheckedAt > 2) {
			refreshCheckedAt = time;
			var rate = displayRefreshRate();
			if (rate > 0 && rate != Math.round(pacer.targetFps)) {
				pacer.setTarget(rate);
				core.GameLog.info("window", 'Pacing frames at ${pacer.targetFps} fps (the display\'s refresh rate)');
			}
		}
		#end
		windowWatch.update();
		if (pendingLines != 0 && --pendingFrames <= 0) applyResolution();
		updateFullscreen();
		dt=Math.min(dt,.1);
		if (entrance.departed) { entrance.update(view.width,dt,player.pad,""); return; }
		time += dt;
		telemetry.update(dt);
		choosePad();
		InputMode.update(player.pad);
		// The game menu pauses the world. The frame it closes on isn't played, so its Esc can't reopen it.
		var paused = pauseMenu.open;
		if (paused) {
			pauseMenu.update(view.width,player.pad);
			if (!pauseMenu.open) mouseFree = false; // back to looking around
		}
		var seated = table.open || privateTable.open;
		if (table.open) table.update(view.width,dt,player.pad);
		if (privateTable.open) privateTable.update(view.width,dt,player.pad);
		if (!entrance.open && !seated && !paused && !openMenuIfAsked()) {
			updateMouseLook();
			player.update(dt);
			var room=map.sectorAtWorld(player.x,player.y);
			if(room!=null && visited.indexOf(room.name)<0) visited.push(room.name);
			if (!level.atDoor(player.x,player.y)) {
				if(level.awayFromDoors(player.x,player.y)) doorArmed=true;
			} else if(doorArmed) {
				doorArmed=false; entrance.show(); hxd.Window.getInstance().mouseMode=Absolute;
			}
			if(!entrance.open && (hxd.Key.isPressed(hxd.Key.E) || (player.pad.connected && player.pad.isPressed(player.pad.config.A))))
				interact();
		}
		player.applyTo(s3d.camera);
		var worldPaused = entrance.open || pauseMenu.open;
		if(storm!=null) storm.update(dt,player.x,player.y);
		if(!worldPaused) {
			waterTime+=dt;
			for(sh in fountainWater) {
				sh.waterTime=waterTime;
				if(sh.waterSurface) sh.uvOffset.set(waterTime*.012,-waterTime*.008);
			}
			for(animate in fountainAnimations) animate(waterTime);
		}
		if(!worldPaused) for (s in spinners)
			s.facing = time * 0.7;
		if(!worldPaused) for (s in turners) {
			// Swing round toward the player at up to 3 rad/s, the short way.
			var d = Math.atan2(player.y - s.mesh.y, player.x - s.mesh.x) - s.facing;
			d -= Math.PI * 2 * Math.round(d / (Math.PI * 2));
			var step = dt * 3;
			s.facing += d > step ? step : d < -step ? -step : d;
		}
		if(!worldPaused) for (walker in walkers) {
			walker.path.update(dt, map);
			walker.sprite.setPosition(walker.path.x, walker.path.y, 0);
			walker.sprite.facing = walker.path.facing;
			walker.sprite.animationFrame = walker.path.phase;
			walker.sprite.shader.shadeOffset = sectorShade(map, walker.path.x, walker.path.y);
		}
		if(!worldPaused) for (i in 0...securityGuards.length) {
			// Offset the radio checks so the sentries do not move in unison.
			securityGuards[i].animationFrame = (time + i * 5) % 13 >= 10.5 ? 1 : 0;
		}
		for (s in sprites)
			s.update(player.x, player.y);

		// Hands sway and bob with walking, Duke-style (§5.6).
		var sway = player.isMoving ? Math.sin(time * 6.2) : 0.0;
		var bob = player.isMoving ? Math.abs(Math.cos(time * 6.2)) : 0.0;
		// Overscan the sleeve so the alpha gutter never floats above the screen edge.
		hands.x = view.width - 150 + 10 + Math.round(sway * 5);
		hands.y = LowResView.HEIGHT - 112 + 4 + Math.round(bob * 4);
		crosshair.x = Std.int(view.width / 2) - 1;
		crosshair.y = Std.int(LowResView.HEIGHT / 2) - 1;

		var spinner = spinners.length > 0 ? spinners[0] : null;
		var angleNames = ["front", "front 3/4", "side", "back 3/4", "back", "back 3/4 (mirrored)", "side (mirrored)", "front 3/4 (mirrored)"];
		info.text = 'CROWN & CARD  ${Version.CURRENT}  render spike  ${view.renderWidth}x${view.renderHeight}\n'
			+ (player.pad.connected
				? 'Controller: left stick move  |  right stick look  |  LB run  |  R3 re-center\n'
				: 'WASD move  |  mouse or arrows look  |  Shift run  |  Esc game menu (in a window it frees the mouse first)\n')
			+ (settings.showFps ? 'FPS ${Math.round(hxd.Timer.fps())}  |  ' : '') + 'F2 sprite preview'
			+ (spinner != null ? '   spinning guest angle: ${angleNames[spinner.angleIndex]}' : '');
		#if devtools
		// F10 throws a test error, to check the game log and the launcher's error reports end to end.
		if(hxd.Key.isPressed(hxd.Key.F10)) throw "Test error (F10, devtools build)";
		#if sys
		if(hxd.Key.isPressed(hxd.Key.F12)) screenshotWanted = true;
		#end
		if(hxd.Key.isPressed(hxd.Key.F3)) showDebug=!showDebug;
		if(!showDebug)
		#end
		{
			var here=map.sectorAtWorld(player.x,player.y);
			info.text=level.data.name.toUpperCase()+"\n"+(here==null?"":here.name);
		}
		spritePreview.hideToggle(seated || pauseMenu.open);
		if(!worldPaused && !seated) spritePreview.update(view.width, dt);
		crosshair.visible=hands.visible=info.visible=!worldPaused && !seated;
		var atDesk=level.atDesk(player.x,player.y,player.yaw), atTable=level.atTable(player.x,player.y,player.yaw);
		var atPrivate=level.atPrivateTable(player.x,player.y,player.yaw);
		var prompt=seated || pauseMenu.open ? ""
			: atDesk ? (register.busy?"Signing the Guest Register...":"Check in with Mr. Quill - save your visit")
			: atTable ? "Sit down at the card table"
			: atPrivate ? "Take the empty chair - play with friends"
			: level.belowStairs(player.x,player.y) ? "The upper floor is closed. Please use the side aisles." : "";
		entrance.update(view.width,dt,player.pad,prompt,!seated && !pauseMenu.open && ((atDesk && !register.busy) || atTable || atPrivate));
	}

	override function render(e:h3d.Engine) {
		if (level == null) {
			e.clear(0xFF020308, 1);
			return;
		}
		// Everything is drawn into the frame at the render resolution; the screen only shows the frame.
		view.renderFrame(e, s3d, !entrance.departed);
		s2d.render(e);
		#if (devtools && sys)
		if (screenshotWanted) {
			screenshotWanted = false;
			saveScreenshot(e);
		}
		#end
	}

	#if (devtools && sys)
	var screenshotWanted = false;

	/**
		F12 (devtools builds): saves the frame, at the render resolution, to
		%LOCALAPPDATA%\CrownAndCard\screenshots. Windows' own screen capture
		can come out black for this OpenGL window without vsync.
	**/
	function saveScreenshot(e:h3d.Engine):Void {
		try {
			var px = view.capture();
			var root = Sys.getEnv("LOCALAPPDATA");
			var dir = haxe.io.Path.join([root == null ? "." : root, "CrownAndCard", "screenshots"]);
			sys.FileSystem.createDirectory(dir);
			var path = haxe.io.Path.join([dir, "crown-and-card-" + DateTools.format(Date.now(), "%Y-%m-%d_%H-%M-%S") + ".png"]);
			sys.io.File.saveBytes(path, px.toPNG());
			core.GameLog.info("screenshot", "Saved " + path);
		} catch (err:Dynamic) {
			core.GameLog.error("screenshot", "Couldn't save a screenshot: " + Std.string(err));
		}
	}
	#end
}
