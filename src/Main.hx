// SPDX-License-Identifier: AGPL-3.0-or-later

import art.ProcArt;
import art.SpriteArt;
import core.LaunchOptions;
import core.Settings;
import core.Telemetry;
import core.Version;
import render.BuildShader;
import render.BuildSprite;
import render.LowResView;
import render.Palette;
import world.Greybox;
import world.PlayerController;
import world.WorldBuilder;

/**
	Phase 0 render spike (§14.2): walk the greybox manor in the HD pixel /
	Build look. Proves the 360p pixel grid, palette shade tables, 8-angle face
	sprites, y-shearing and the first-person hands.
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
		var palette = new Palette();
		var shadeLut = h3d.mat.Texture.fromPixels(palette.buildShadeLut());
		shadeLut.filter = Nearest;
		shadeLut.wrap = Clamp;

		map = Greybox.map();
		var textures = [
			"marble" => ProcArt.marble().toIndexTexture(false, true),
			"parquet" => ProcArt.parquet().toIndexTexture(false, true),
			"carpet" => ProcArt.carpet().toIndexTexture(false, true),
			"coffer" => ProcArt.ceilingCoffer().toIndexTexture(false, true),
			"dome" => ProcArt.ceilingDome().toIndexTexture(false, true),
			"damask" => ProcArt.wallDamask().toIndexTexture(false, true),
			"damaskUpper" => ProcArt.upperDamask().toIndexTexture(false, true),
			"deco" => ProcArt.wallDeco().toIndexTexture(false, true),
			"decoUpper" => ProcArt.upperDeco().toIndexTexture(false, true),
			"green" => ProcArt.wallGreen().toIndexTexture(false, true),
			"greenUpper" => ProcArt.upperGreen().toIndexTexture(false, true),
			"felt" => ProcArt.felt().toIndexTexture(false, true),
			"tableWood" => ProcArt.tableWood().toIndexTexture(false, true),
		];
		var shaders = WorldBuilder.build(map, textures, shadeLut, s3d);

		// Cache by character identity; keep authored colors (no implicit brown swap).
		var characterSheets = [for (name in SpriteArt.CHARACTERS) name => SpriteArt.characterSheet(name, palette)];
		var texturesByCharacter = new Map<String, h3d.mat.Texture>();
		for (g in Greybox.GUESTS) {
			if (!texturesByCharacter.exists(g.art))
				texturesByCharacter.set(g.art, characterSheets.get(g.art).toIndexTexture(true, false));
			var s = new BuildSprite(texturesByCharacter.get(g.art), shadeLut, BuildSprite.DRAWN_ANGLES,
				SpriteArt.frameWidth(g.art) / SpriteArt.density(g.art), SpriteArt.frameHeight(g.art) / SpriteArt.density(g.art),
				s3d, SpriteArt.animationRows(g.art));
			s.setPosition(g.x, g.y, 0);
			s.facing = g.facing;
			s.shader.shadeOffset = sectorShade(map, g.x, g.y);
			sprites.push(s);
			if (g.spins)
				spinners.push(s);
			if (g.walkTo != null)
				walkers.push({sprite: s, path: new world.GuestWalkPath(g.x, g.y, g.walkTo.x, g.walkTo.y)});
		}

		var ch = Greybox.CHANDELIER;
		var chandelier = new BuildSprite(SpriteArt.chandelier(palette).toIndexTexture(true, false), shadeLut, 1, 96 / 64, 72 / 64, s3d);
		chandelier.setPosition(ch.x, ch.y, ch.z);
		chandelier.shader.shadeOffset = -8; // candlelit: nearly full bright
		sprites.push(chandelier);

		for (s in sprites)
			shaders.push(s.shader);
		for (sh in shaders) {
			sh.visibility = VISIBILITY;
			sh.setLights(Greybox.LIGHTS);
		}

		var cam = s3d.camera;
		// World is right-handed with Z up: facing north (+Y), east (+X) is on the right.
		cam.rightHanded = true;
		cam.fovY = settings.verticalFov(); // horizontal FOV measured at 16:9 (§5.5)
		cam.zNear = 0.05;
		cam.zFar = 120;

		var start = Greybox.PLAYER_START;
		player = new PlayerController(map, start.x, start.y, start.yaw);
		player.bobAmount = settings.headBob / 100;
		player.perspectiveLook = settings.lookStyle == Perspective;

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

		// Controllers: use the first one to connect; fall back to keyboard and mouse if it goes away.
		hxd.Pad.wait(p -> {
			player.pad = p;
			p.onDisconnect = () -> if (player.pad == p) player.pad = hxd.Pad.createDummy();
		});

		telemetry.stateProvider = gameState;
		telemetry.start(settings);

		#if (js && devtools)
		// Dev-only console hooks: crownDebug.teleport(x, y, yawDegrees, pitchDegrees), crownDebug.state()
		js.Syntax.code("window.crownDebug = {0}", {
			teleport: (x:Float, y:Float, yawDeg:Float, pitchDeg:Float) -> {
				player.x = x;
				player.y = y;
				player.yaw = yawDeg * Math.PI / 180;
				player.pitch = pitchDeg * Math.PI / 180;
			},
			state: () -> {x: player.x, y: player.y, yawDeg: player.yaw * 180 / Math.PI, pitchDeg: player.pitch * 180 / Math.PI},
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
			window.mouseMode = window.mouseMode == Absolute ? Relative(e -> player.look(e.relX, e.relY), true) : Absolute;
		if (window.mouseMode == Absolute) {
			var mx = window.mouseX, my = window.mouseY;
			if (hxd.Key.isDown(hxd.Key.MOUSE_LEFT) && !firstDragFrame)
				player.look(mx - lastMouseX, my - lastMouseY);
			firstDragFrame = !hxd.Key.isDown(hxd.Key.MOUSE_LEFT);
			lastMouseX = mx;
			lastMouseY = my;
		}
	}

	var lastMouseX = 0.0;
	var lastMouseY = 0.0;
	var firstDragFrame = true;

	/** What the launcher records with every heartbeat and error report. **/
	function gameState():Dynamic {
		var sector = map.sectorAtWorld(player.x, player.y);
		return {
			room: sector == null ? "outside the map" : sector.name,
			x: Math.round(player.x * 100) / 100,
			y: Math.round(player.y * 100) / 100,
			yawDeg: ((Math.round(player.yaw * 180 / Math.PI) % 360) + 360) % 360,
			pitchDeg: Math.round(player.pitch * 180 / Math.PI),
			fps: Math.round(hxd.Timer.fps()),
			view: '${view.width}x${LowResView.HEIGHT} at ${Math.round(view.scale * 100) / 100}x',
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
		time += dt;
		telemetry.update(dt);
		updateMouseLook();
		player.update(dt);
		player.applyTo(s3d.camera);
		for (s in spinners)
			s.facing = time * 0.7;
		for (walker in walkers) {
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
		spritePreview.update(view.width, dt);
	}

	override function render(e:h3d.Engine) {
		view.renderWorld(e, s3d);
		s2d.render(e);
	}
}
