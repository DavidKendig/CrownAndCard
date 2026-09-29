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
	final walkers:Array<{sprite:BuildSprite, path:world.GuestWalkPath}> = [];
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

	/** The controller as the launcher reads it (XInput), and the browser's own when it has one. **/
	var bridge:core.PadBridge;
	var browserPad:hxd.Pad = hxd.Pad.createDummy();
	var browserPadActivity = -1.0;

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
		settings = Settings.fromOptions(options);
		telemetry = new Telemetry(options.get("telemetry"));

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
			"marble" => FoyerArt.surface("materials/manor-floor.png",palette,128,128).toIndexTexture(false,true),
			"parquet" => ProcArt.parquet().toIndexTexture(false, true),
			"carpet" => ProcArt.carpet().toIndexTexture(false, true),
			"coffer" => FoyerArt.surface("materials/ceiling-coffer.png",palette,256,256).toIndexTexture(false,true),
			"dome" => ProcArt.ceilingDome().toIndexTexture(false, true),
			"damask" => FoyerArt.surface("materials/manor-wall.png",palette,128,192).toIndexTexture(false,true),
			"damaskUpper" => FoyerArt.surface("materials/manor-wall.png",palette,128,128,.06,.59).toIndexTexture(false,true),
			"deco" => ProcArt.wallDeco().toIndexTexture(false, true),
			"decoUpper" => ProcArt.upperDeco().toIndexTexture(false, true),
			"green" => ProcArt.wallGreen().toIndexTexture(false, true),
			"greenUpper" => ProcArt.upperGreen().toIndexTexture(false, true),
			"felt" => ProcArt.felt().toIndexTexture(false, true),
			"tableWood" => ProcArt.tableWood().toIndexTexture(false, true),
			"stone" => FoyerArt.surface("materials/ivory-marble.png",palette,128,128).toIndexTexture(false,true),
			"ivory" => FoyerArt.surface("materials/ivory-marble.png",palette,128,128).toIndexTexture(false,true),
			"pillarMarble" => FoyerArt.surface("materials/pillar-marble.png",palette,256,256).toIndexTexture(false,true),
			"stairMarble" => FoyerArt.surface("materials/stair-marble.png",palette,256,256).toIndexTexture(false,true),
			"banisterWood" => FoyerArt.surface("materials/banister-wood.png",palette,256,256).toIndexTexture(false,true),
			"ropeBraid" => FoyerArt.surface("materials/braided-rope.png",palette,256,256).toIndexTexture(false,true),
			"grateMetal" => FoyerArt.surface("materials/grate-steel.png",palette,256,256).toIndexTexture(false,true),
			"planterCeramic" => FoyerArt.surface("materials/planter-ceramic.png",palette,256,256).toIndexTexture(false,true),
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
			FoyerArt.surface("sprites/conservatory-"+name+".png",palette,192,name=="palm"?288:192,0,1,true).toIndexTexture(true,false)];
		for(p in map.plants) {
			var plant=new BuildSprite(plantTextures[p.palm?0:1],shadeLut,1,p.palm?2.4:1.65,p.palm?3.6:1.65,s3d);
			plant.setPosition(p.x,p.y,p.z); sprites.push(plant);
		}

		// Cache by character identity; keep authored colors (no implicit brown swap).
		var characterSheets = [for (name in SpriteArt.CHARACTERS) name => SpriteArt.characterSheet(name, palette)];
		var texturesByCharacter = new Map<String, h3d.mat.Texture>();
		for (g in data.guests) {
			if (SpriteArt.CHARACTERS.indexOf(g.art) < 0) continue;
			if (!texturesByCharacter.exists(g.art))
				texturesByCharacter.set(g.art, characterSheets.get(g.art).toIndexTexture(true, false));
			var s = new BuildSprite(texturesByCharacter.get(g.art), shadeLut, BuildSprite.DRAWN_ANGLES,
				SpriteArt.frameWidth(g.art) / SpriteArt.density(g.art), SpriteArt.frameHeight(g.art) / SpriteArt.density(g.art),
				s3d, SpriteArt.animationRows(g.art));
			s.setPosition(g.x, g.y, 0);
			s.facing = g.facing * Math.PI / 180;
			s.shader.shadeOffset = sectorShade(map, g.x, g.y);
			sprites.push(s);
			if (g.spins == true)
				spinners.push(s);
			if (g.walkTo != null)
				walkers.push({sprite: s, path: new world.GuestWalkPath(g.x, g.y, g.walkTo.x, g.walkTo.y)});
		}

		var chandelierTex = SpriteArt.chandelier(palette).toIndexTexture(true, false);
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
			default:
		}
		player.feetZ=map.floorAt(player.x,player.y);
		#end

		#if hl
		var window = hxd.Window.getInstance();
		window.resize(settings.windowWidth, settings.windowHeight);
		window.displayMode = settings.fullscreen ? Borderless : Windowed;
		#end

		view = new LowResView(s2d);
		view.integerScaling = settings.scaling == Integer;
		view.resize(s2d.width, s2d.height);
		hands = new h2d.Bitmap(SpriteArt.playerHands(palette).toColorTile(palette), view.hud);
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
			browserPad = p;
			InputMode.usingPad = true;
			p.onDisconnect = () -> if (browserPad == p) browserPad = hxd.Pad.createDummy();
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
		Mouse look: drag with the left button, or press M to capture the mouse
		(pointer lock) where the platform allows it. Esc releases it.
	**/
	function updateMouseLook():Void {
		var window = hxd.Window.getInstance();
		if (hxd.Key.isPressed(hxd.Key.M))
			window.mouseMode = window.mouseMode == Absolute ? Relative(e -> { if (!entrance.open) player.look(e.relX, e.relY); }, true) : Absolute;
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
		The launcher's XInput stream or the browser's gamepad, whichever was used
		last (they're usually the same controller); a dummy when there's neither.
	**/
	function choosePad():Void {
		bridge.update();
		if (core.PadBridge.active(browserPad)) browserPadActivity = haxe.Timer.stamp();
		var useBridge = bridge.pad.connected && (!browserPad.connected || bridge.lastActivity >= browserPadActivity);
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
		var window = hxd.Window.getInstance();
		if (toggle) window.displayMode = window.displayMode == Windowed ? Borderless : Windowed;
		var full = window.displayMode != Windowed;
		#end
		if (full != view.fillScreen) {
			view.fillScreen = full;
			view.resize(s2d.width, s2d.height);
		}
	}

	var lastMouseX = 0.0;
	var lastMouseY = 0.0;
	var firstDragFrame = true;

	function checkIn():Void {
		if(entrance.open || !level.atDesk(player.x,player.y,player.yaw) || register.busy) return;
		entrance.notify("Signing the Guest Register...");
		register.checkIn(visited,wallet,error -> entrance.notify(error==null?'Check-in saved with ${wallet.sovereigns} Sovereigns. Fortune favors the bold.':error,6));
	}

	/** E / A (or a click on the prompt): whatever the player is standing at. **/
	function interact():Void {
		if (entrance.open || table.open) return;
		if (level.atDesk(player.x,player.y,player.yaw)) checkIn();
		else if (level.atTable(player.x,player.y,player.yaw)) {
			hxd.Window.getInstance().mouseMode=Absolute;
			table.show();
		}
	}

	function quitGame():Void {
		if(storm!=null) storm.stop();
		hxd.Window.getInstance().mouseMode=Absolute;
		telemetry.event("quit","Left through the manor's front doors");
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
		return {
			map: level.data.name,
			room: sector == null ? "outside the map" : sector.name,
			x: Math.round(player.x * 100) / 100,
			y: Math.round(player.y * 100) / 100,
			yawDeg: ((Math.round(player.yaw * 180 / Math.PI) % 360) + 360) % 360,
			pitchDeg: Math.round(player.pitch * 180 / Math.PI),
			fps: Math.round(hxd.Timer.fps()),
			view: '${view.width}x${LowResView.HEIGHT} at ${Math.round(view.scale * 100) / 100}x',
			table: table == null ? "" : table.status,
			sovereigns: wallet.sovereigns,
		};
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
		updateFullscreen();
		dt=Math.min(dt,.1);
		if (entrance.departed) { entrance.update(view.width,dt,player.pad,""); return; }
		time += dt;
		telemetry.update(dt);
		choosePad();
		InputMode.update(player.pad);
		var seated = table.open;
		if (seated) table.update(view.width,dt,player.pad);
		if (!entrance.open && !seated) {
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
		if(storm!=null) storm.update(dt,player.x,player.y);
		if(!entrance.open) {
			waterTime+=dt;
			for(sh in fountainWater) {
				sh.waterTime=waterTime;
				if(sh.waterSurface) sh.uvOffset.set(waterTime*.012,-waterTime*.008);
			}
			for(animate in fountainAnimations) animate(waterTime);
		}
		if(!entrance.open) for (s in spinners)
			s.facing = time * 0.7;
		if(!entrance.open) for (walker in walkers) {
			walker.path.update(dt, map);
			walker.sprite.setPosition(walker.path.x, walker.path.y, 0);
			walker.sprite.facing = walker.path.facing;
			walker.sprite.animationFrame = walker.path.phase;
			walker.sprite.shader.shadeOffset = sectorShade(map, walker.path.x, walker.path.y);
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
		info.text = 'CROWN & CARD  ${Version.CURRENT}  render spike  ${view.width}x${LowResView.HEIGHT}\n'
			+ (player.pad.connected
				? 'Controller: left stick move  |  right stick look  |  LB run  |  R3 re-center\n'
				: 'WASD move  |  arrows turn  |  drag or M to look  |  PgUp/PgDn look up/down  |  Shift run\n')
			+ (settings.showFps ? 'FPS ${Math.round(hxd.Timer.fps())}  |  ' : '') + 'F2 sprite preview'
			+ (spinner != null ? '   spinning guest angle: ${angleNames[spinner.angleIndex]}' : '');
		#if devtools
		if(hxd.Key.isPressed(hxd.Key.F3)) showDebug=!showDebug;
		if(!showDebug)
		#end
		{
			var here=map.sectorAtWorld(player.x,player.y);
			info.text=level.data.name.toUpperCase()+"\n"+(here==null?"":here.name);
		}
		spritePreview.hideToggle(table.open);
		if(!entrance.open && !table.open) spritePreview.update(view.width, dt);
		crosshair.visible=hands.visible=info.visible=!entrance.open && !table.open;
		var atDesk=level.atDesk(player.x,player.y,player.yaw), atTable=level.atTable(player.x,player.y,player.yaw);
		var prompt=table.open ? ""
			: atDesk ? (register.busy?"Signing the Guest Register...":"Check in with Mr. Quill - save your visit")
			: atTable ? "Sit down at the card table"
			: level.belowStairs(player.x,player.y) ? "The upper floor is closed. Please use the side aisles." : "";
		entrance.update(view.width,dt,player.pad,prompt,!table.open && ((atDesk && !register.busy) || atTable));
	}

	override function render(e:h3d.Engine) {
		if (level == null) {
			e.clear(0xFF020308, 1);
			return;
		}
		if(!entrance.departed) view.renderWorld(e, s3d);
		s2d.render(e);
	}
}
