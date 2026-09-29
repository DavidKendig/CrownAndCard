// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

enum abstract GlyphAction(Int) {
	/** E on the keyboard, the green A button on a controller. **/
	var Confirm = 0;

	/** Esc on the keyboard, the red B button on a controller. **/
	var Back = 1;

	/** Space on the keyboard, the blue X button on a controller: a game's second action (slap, auto). **/
	var Alt = 2;
}

/**
	Button prompts drawn on the pixel grid: a keycap while the player uses the
	keyboard, the Xbox-style colored face button while they use a controller.
	They're hand-drawn in grid pixels, so a finer render resolution draws each
	one as a whole-number block (render.Resolution.pixelScale).
**/
class ButtonGlyph {
	public static inline var HEIGHT = 13;

	static final cache = new Map<String, h2d.Tile>();

	public static function tile(action:GlyphAction, pad:Bool):h2d.Tile {
		var scale = render.Resolution.pixelScale();
		var key = '${(cast action : Int)}/$pad/$scale';
		var t = cache.get(key);
		if (t == null) {
			var px = switch [action, pad] {
				case [Confirm, false]: keycap("E");
				case [Back, false]: keycap("Esc");
				case [Confirm, true]: faceButton("A", 0xFF4FA83D, 0xFF1F5518);
				case [Back, true]: faceButton("B", 0xFFD2413A, 0xFF6A1612);
				case [Alt, false]: keycap("Space");
				case [Alt, true]: faceButton("X", 0xFF2F6FD0, 0xFF12305E);
				case _: keycap("?");
			}
			var tex = h3d.mat.Texture.fromPixels(blocks(px, scale));
			tex.filter = Nearest;
			t = h2d.Tile.fromTexture(tex);
			t.scaleToSize(px.width, px.height);
			cache.set(key, t);
		}
		return t;
	}

	/** `px` with every pixel a `scale` × `scale` block. **/
	static function blocks(px:hxd.Pixels, scale:Int):hxd.Pixels {
		if (scale == 1) return px;
		var out = hxd.Pixels.alloc(px.width * scale, px.height * scale, hxd.PixelFormat.RGBA);
		for (y in 0...out.height) for (x in 0...out.width) out.setPixel(x, y, px.getPixel(Std.int(x / scale), Std.int(y / scale)));
		return out;
	}

	static function keycap(label:String):hxd.Pixels {
		var w = PixelGlyphs.width(label) + 6, h = HEIGHT;
		var px = hxd.Pixels.alloc(w, h, hxd.PixelFormat.RGBA);
		var ink = 0xFF1A1622, face = 0xFFEDE4CC, side = 0xFFA89C80;
		for (y in 0...h) for (x in 0...w) {
			var corner = (x == 0 || x == w - 1) && (y == 0 || y == h - 1);
			if (corner) continue;
			var edge = x == 0 || y == 0 || x == w - 1 || y == h - 1;
			px.setPixel(x, y, edge ? ink : y >= h - 3 ? side : face);
		}
		PixelGlyphs.drawText(px, label, 3, 2, ink);
		return px;
	}

	static function faceButton(label:String, fill:Int, ring:Int):hxd.Pixels {
		var px = hxd.Pixels.alloc(HEIGHT, HEIGHT, hxd.PixelFormat.RGBA);
		var c = HEIGHT / 2;
		for (y in 0...HEIGHT) for (x in 0...HEIGHT) {
			var dx = x + .5 - c, dy = y + .5 - c;
			var d = Math.sqrt(dx * dx + dy * dy);
			if (d > c) continue;
			px.setPixel(x, y, d > c - 1.2 ? ring : fill);
		}
		PixelGlyphs.drawText(px, label, 4, 3, 0xFFFFFFFF);
		return px;
	}
}

/** Tracks whether the player is on the keyboard or a controller, for the prompts. **/
class InputMode {
	public static var usingPad = false;

	/** haxe.Timer.stamp() of the last controller input. **/
	public static var lastPadInput = -100.0;

	#if devtools
	/** Dev-only: show controller prompts without a controller (crownDebug.padPrompts). **/
	public static var forcePad = false;
	#end

	/**
		True just after the controller was used. Mouse input then is most likely
		the controller itself (Steam's desktop layout turns sticks and triggers
		into mouse moves and clicks), so mouse look and prompt switching ignore it.
	**/
	public static var padRecent(get, never):Bool;

	static function get_padRecent():Bool return haxe.Timer.stamp() - lastPadInput < 0.75;

	/** Call once at startup: any key, or a mouse press that isn't the controller's, switches the prompts to the keyboard. **/
	public static function listen():Void {
		hxd.Window.getInstance().addEventTarget(e -> switch e.kind {
			case EKeyDown: usingPad = false;
			case EPush: if (!padRecent) usingPad = false;
			default:
		});
	}

	/** Call every frame: any button or a pushed stick switches the prompts to the controller. **/
	public static function update(pad:hxd.Pad):Void {
		#if devtools
		if (forcePad) {
			usingPad = true;
			return;
		}
		#end
		if (!pad.connected) {
			usingPad = false;
			return;
		}
		var touched = false;
		for (b in pad.buttons) if (b) touched = true;
		if (Math.abs(pad.xAxis) > .5 || Math.abs(pad.yAxis) > .5 || Math.abs(pad.rxAxis) > .5 || Math.abs(pad.ryAxis) > .5) touched = true;
		if (touched) {
			usingPad = true;
			lastPadInput = haxe.Timer.stamp();
		}
	}
}

/** Edge-triggered menu input from the keyboard and the controller (d-pad or left stick). **/
class MenuInput {
	public var up(default, null) = false;
	public var down(default, null) = false;
	public var left(default, null) = false;
	public var right(default, null) = false;
	public var confirm(default, null) = false;
	public var back(default, null) = false;

	/** Space / the X button: a game's second action. **/
	public var alt(default, null) = false;

	var stickX = 0;
	var stickY = 0;

	public function new() {}

	public function update(pad:hxd.Pad):Void {
		var K = hxd.Key;
		var sx = 0, sy = 0;
		if (pad.connected) {
			sx = pad.xAxis > .6 ? 1 : pad.xAxis < -.6 ? -1 : (Math.abs(pad.xAxis) < .3 ? 0 : stickX);
			// Stick Y is negative when pushed up.
			sy = pad.yAxis > .6 ? 1 : pad.yAxis < -.6 ? -1 : (Math.abs(pad.yAxis) < .3 ? 0 : stickY);
		}
		var p = pad.connected;
		up = K.isPressed(K.UP) || K.isPressed(K.W) || (p && pad.isPressed(pad.config.dpadUp)) || (sy == -1 && stickY != -1);
		down = K.isPressed(K.DOWN) || K.isPressed(K.S) || (p && pad.isPressed(pad.config.dpadDown)) || (sy == 1 && stickY != 1);
		left = K.isPressed(K.LEFT) || K.isPressed(K.A) || (p && pad.isPressed(pad.config.dpadLeft)) || (sx == -1 && stickX != -1);
		right = K.isPressed(K.RIGHT) || K.isPressed(K.D) || (p && pad.isPressed(pad.config.dpadRight)) || (sx == 1 && stickX != 1);
		// Alt+Enter is the fullscreen toggle, not a menu choice.
		confirm = K.isPressed(K.E) || (K.isPressed(K.ENTER) && !K.isDown(K.ALT)) || (p && pad.isPressed(pad.config.A));
		alt = K.isPressed(K.SPACE) || (p && pad.isPressed(pad.config.X));
		back = K.isPressed(K.ESCAPE) || K.isPressed(K.BACKSPACE) || (p && pad.isPressed(pad.config.B));
		stickX = sx;
		stickY = sy;
	}

	/** Swallows this frame's input (for example the press that opened a menu). **/
	public function clear():Void {
		up = down = left = right = confirm = back = alt = false;
	}
}
