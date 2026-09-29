// SPDX-License-Identifier: AGPL-3.0-or-later
package render;

/**
	The master 256-color palette (§5.4): 16 ramps of 16 steps, dark to light.
	A color's index is `ramp * 16 + step`. Index 0 doubles as "transparent"
	in sprite art, so art never paints it as an opaque color.
**/
class Palette {
	public static inline var SIZE = 256;
	public static inline var RAMP_STEPS = 16;

	/** Shade levels in the lookup table: 0 is full brightness, 31 is black. **/
	public static inline var SHADES = 32;

	public static inline var STONE = 0;
	public static inline var WOOD = 1;
	public static inline var DARK_WOOD = 2;
	public static inline var RED = 3;
	public static inline var GOLD = 4;
	public static inline var FELT = 5;
	public static inline var SKIN = 6;
	public static inline var NAVY = 7;
	public static inline var IVORY = 8;
	public static inline var PURPLE = 9;
	public static inline var TEAL = 10;
	public static inline var FLAME = 11;
	public static inline var ROSE = 12;
	public static inline var NIGHT = 13;
	public static inline var OLIVE = 14;
	public static inline var HAIR = 15;

	/** Dark, mid and light key colors for each ramp. **/
	static final RAMP_KEYS:Array<Array<Int>> = [
		[0x0e0d12, 0x6b6870, 0xe8e6ea], // stone
		[0x1a0c06, 0x8a4a22, 0xf0c080], // warm wood
		[0x0c0605, 0x4a2a1a, 0xb08060], // dark wood
		[0x1a0306, 0x8c1a22, 0xf08080], // deep red
		[0x1e1204, 0xa87a1c, 0xfff0a0], // gold
		[0x03140c, 0x1f6b3a, 0x9ee0a8], // felt green
		[0x2a140c, 0xb07a5a, 0xffe0c8], // skin
		[0x05060f, 0x1e2448, 0x8a96d0], // navy
		[0x2a2620, 0xb8b0a0, 0xfffcf0], // ivory
		[0x12061a, 0x5a2a78, 0xd8a8f0], // purple
		[0x031214, 0x1a6a70, 0x90f0e8], // teal
		[0x2a0a02, 0xe0701a, 0xfff4b0], // flame
		[0x1e0810, 0xa04a68, 0xffc0d8], // rose
		[0x02030a, 0x121c40, 0x5070c0], // night blue
		[0x0e1004, 0x5a6020, 0xd8e090], // olive
		[0x080605, 0x3a2418, 0xa0785a], // hair
	];

	/** 0xRRGGBB for each index. **/
	public final colors:Array<Int>;

	public function new() {
		colors = [for (r in 0...RAMP_KEYS.length) for (s in 0...RAMP_STEPS) rampColor(r, s)];
	}

	public static inline function index(ramp:Int, step:Int):Int {
		return ramp * RAMP_STEPS + step;
	}

	public static inline function rampOf(index:Int):Int {
		return index >> 4;
	}

	public static inline function stepOf(index:Int):Int {
		return index & 15;
	}

	/**
		The Build-style shade table (§5.4): for every palette index and shade
		level, the nearest palette color to that color darkened (and cooled
		slightly toward blue-violet). Keeping the result inside the palette is
		what gives the banded falloff.
	**/
	public function buildShadeLut():hxd.Pixels {
		var px = hxd.Pixels.alloc(SIZE, SHADES, hxd.PixelFormat.RGBA);
		for (s in 0...SHADES) {
			var f = 1 - s / (SHADES - 1);
			var cool = (1 - f) * 0.35;
			for (i in 0...SIZE) {
				var c = colors[i];
				var r = ((c >> 16) & 255) * f * (1 - cool) + 10 * cool;
				var g = ((c >> 8) & 255) * f * (1 - cool) + 8 * cool;
				var b = (c & 255) * f * (1 - cool) + 26 * cool;
				px.setPixel(i, s, 0xFF000000 | colors[nearest(r, g, b)]);
			}
		}
		return px;
	}

	/**
		`nearest` from index 1 for an RGB color, memoized on 6 bits a channel in
		one shared table: authored art has far too many distinct colors to
		search the palette for each (render.Resolution redraws it all at once).
	**/
	public function nearestRgb(rgb:Int):Int {
		if (lookup == null) {
			lookup = new haxe.ds.Vector<Int>(64 * 64 * 64);
			for (i in 0...lookup.length) lookup[i] = -1;
		}
		var r = (rgb >> 18) & 63, g = (rgb >> 10) & 63, b = (rgb >> 2) & 63;
		var key = (r << 12) | (g << 6) | b;
		var i = lookup[key];
		if (i < 0) {
			// The middle of the 4-level bucket, so every color in it snaps the same way.
			i = nearest(r * 4 + 1.5, g * 4 + 1.5, b * 4 + 1.5, 1);
			lookup[key] = i;
		}
		return i;
	}

	var lookup:Null<haxe.ds.Vector<Int>>;

	/** The palette index closest to an RGB color (weighted for perceived brightness). **/
	public function nearest(r:Float, g:Float, b:Float, firstIndex:Int = 0):Int {
		var best = firstIndex;
		var bestDist = Math.POSITIVE_INFINITY;
		for (i in firstIndex...SIZE) {
			var c = colors[i];
			var dr = ((c >> 16) & 255) - r;
			var dg = ((c >> 8) & 255) - g;
			var db = (c & 255) - b;
			var d = 2 * dr * dr + 4 * dg * dg + 3 * db * db;
			if (d < bestDist) {
				bestDist = d;
				best = i;
			}
		}
		return best;
	}

	static function rampColor(ramp:Int, step:Int):Int {
		var keys = RAMP_KEYS[ramp];
		var t = step / (RAMP_STEPS - 1);
		return t < 0.5 ? lerp(keys[0], keys[1], t * 2) : lerp(keys[1], keys[2], (t - 0.5) * 2);
	}

	static function lerp(a:Int, b:Int, t:Float):Int {
		inline function ch(shift:Int)
			return Math.round(((a >> shift) & 255) * (1 - t) + ((b >> shift) & 255) * t);
		return (ch(16) << 16) | (ch(8) << 8) | ch(0);
	}
}
