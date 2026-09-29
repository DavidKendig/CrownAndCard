// SPDX-License-Identifier: AGPL-3.0-or-later
package render;

/**
	The render resolution (§5.2): how many lines the whole frame is drawn at,
	480 by default or 720 (a graphics setting). Everything goes through it:
	the 3D world, the HUD, menus, card tables, cards and tiles, and text are
	drawn into one frame that tall (LowResView), which is then scaled to the
	screen.

	Layout stays on the 360-line design grid (`GRID`): positions and sizes in
	the code are grid units, and the frame draws them `density` times larger,
	so nothing moves when the resolution changes; it only gets finer.

	Art made from high-resolution sources is rasterized for the frame, not the
	grid: `tile` (2D) and `texture` (world) take a drawing function, call it
	with the pixel size for the current resolution, and call it again when the
	resolution changes. The tile or texture object stays the same (its texture
	is resized and refilled in place), so whatever holds it needs no update.
	Art drawn in grid pixels by hand (the button glyphs, card indices and the
	font) can only grow by whole steps: `pixelScale`.
**/
class Resolution {
	/** Lines in the layout grid every screen is designed on. **/
	public static inline var GRID = 360;

	/** The resolutions the player can choose. **/
	public static final CHOICES = [480, 720];

	public static var lines(default, null) = 480;

	/** Frame pixels per grid unit: 4/3 at 480 lines, 2 at 720. **/
	public static var density(get, never):Float;

	/** Bumped at every change, for caches keyed by resolution. **/
	public static var version(default, null) = 0;

	static final tiles:Array<{tile:h2d.Tile, w:Float, h:Float, draw:(Int, Int) -> hxd.Pixels}> = [];
	static final textures:Array<{texture:h3d.mat.Texture, w:Int, h:Int, draw:(Int, Int) -> hxd.Pixels}> = [];

	static inline function get_density():Float return lines / GRID;

	/** Snaps a setting to a supported resolution (the old 360 becomes 480). **/
	public static function supported(n:Int):Int return n >= 720 ? 720 : 480;

	/** Frame pixels for `v` grid units. **/
	public static inline function px(v:Float):Int return Std.int(Math.max(1, Math.round(v * density)));

	/** Whole-number scale for art drawn in grid pixels: 1 at 480 lines, 2 at 720. **/
	public static function pixelScale():Int return Std.int(Math.max(1, Math.round(density)));

	/**
		Texel scale for world textures: a power of two so repeating textures stay
		power-of-two sized (1 at 480 lines, 2 at 720).
	**/
	public static function textureScale():Int return density >= 1.75 ? 2 : 1;

	/** Changes the resolution and redraws every registered tile and texture for it. Returns what it redrew, for the log. **/
	public static function set(n:Int):String {
		n = supported(n);
		if (n == lines) return "nothing to redraw";
		lines = n;
		version++;
		var t0 = haxe.Timer.stamp();
		for (t in tiles) fill(t.tile.getTexture(), t.draw(px(t.w), px(t.h)));
		var t1 = haxe.Timer.stamp(), redrawn = 0;
		for (t in textures) {
			var s = textureScale();
			if (t.texture.width != t.w * s || t.texture.height != t.h * s) {
				fill(t.texture, t.draw(t.w * s, t.h * s));
				redrawn++;
			}
		}
		var t2 = haxe.Timer.stamp();
		return '${tiles.length} tiles in ${Math.round((t1 - t0) * 1000)} ms, $redrawn of ${textures.length} world textures in ${Math.round((t2 - t1) * 1000)} ms';
	}

	/**
		A 2D tile `w` × `h` grid units in size whose image `draw(pixelWidth,
		pixelHeight)` paints at the render resolution. Redrawn when it changes.
	**/
	public static function tile(w:Float, h:Float, draw:(Int, Int) -> hxd.Pixels):h2d.Tile {
		var texture = h3d.mat.Texture.fromPixels(draw(px(w), px(h)));
		texture.filter = Nearest;
		var t = h2d.Tile.fromTexture(texture);
		t.scaleToSize(w, h);
		tiles.push({tile: t, w: w, h: h, draw: draw});
		return t;
	}

	/**
		A world texture of `w` × `h` texels at 480 lines, painted by `draw` at
		`textureScale()` times that. Redrawn when the scale changes.
	**/
	public static function texture(w:Int, h:Int, repeat:Bool, draw:(Int, Int) -> hxd.Pixels):h3d.mat.Texture {
		var s = textureScale();
		var texture = h3d.mat.Texture.fromPixels(draw(w * s, h * s));
		texture.filter = Nearest;
		texture.wrap = repeat ? Repeat : Clamp;
		textures.push({texture: texture, w: w, h: h, draw: draw});
		return texture;
	}

	static function fill(texture:h3d.mat.Texture, pixels:hxd.Pixels):Void {
		if (texture.width != pixels.width || texture.height != pixels.height) texture.resize(pixels.width, pixels.height);
		texture.uploadPixels(pixels);
	}
}
