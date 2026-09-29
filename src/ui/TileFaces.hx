// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import games.mahjong.Tiles;
import render.Palette;

/**
	Mahjong tiles for the seated view (§5.7), reduced from the 144 × 192 art
	kit in res/mahjong/ to 30 × 40 (your hand) and 21 × 28 (discards, melds,
	dora) grid units, drawn at the render resolution (render.Resolution),
	with an area filter and snapped to the master palette.
**/
class TileFaces {
	public static inline var W = 30;
	public static inline var H = 40;
	public static inline var SW = 21;
	public static inline var SH = 28;

	final palette:Palette;
	final cache = new Map<String, h2d.Tile>();
	final snapped = new Map<Int, Int>();

	public function new(palette:Palette) {
		this.palette = palette;
	}

	public function face(kind:Int, small = false):h2d.Tile return load('faces/${Tiles.art(kind)}.png', small);

	public function back(small = false):h2d.Tile return load("back.png", small);

	function load(file:String, small:Bool):h2d.Tile {
		var key = file + (small ? "@s" : "") + "@" + render.Resolution.lines;
		var t = cache.get(key);
		if (t != null) return t;
		var gw = small ? SW : W, gh = small ? SH : H;
		var w = render.Resolution.px(gw), h = render.Resolution.px(gh);
		var src = hxd.Res.load('mahjong/$file').toImage().getPixels(hxd.PixelFormat.RGBA);
		var px = hxd.Pixels.alloc(w, h, hxd.PixelFormat.RGBA);
		var sx = src.width / w, sy = src.height / h;
		for (y in 0...h) for (x in 0...w) {
			var r = 0.0, g = 0.0, b = 0.0, a = 0.0, n = 0;
			for (yy in Std.int(y * sy)...Std.int((y + 1) * sy)) for (xx in Std.int(x * sx)...Std.int((x + 1) * sx)) {
				var c = src.getPixel(xx, yy);
				var ca = (c >>> 24) / 255;
				r += ((c >> 16) & 255) * ca;
				g += ((c >> 8) & 255) * ca;
				b += (c & 255) * ca;
				a += ca;
				n++;
			}
			if (n == 0 || a / n < .5) continue;
			px.setPixel(x, y, snap((Std.int(r / a) << 16) | (Std.int(g / a) << 8) | Std.int(b / a)));
		}
		var tex = h3d.mat.Texture.fromPixels(px);
		tex.filter = Nearest;
		t = h2d.Tile.fromTexture(tex);
		t.scaleToSize(gw, gh);
		cache.set(key, t);
		return t;
	}

	function snap(rgb:Int):Int {
		var key = rgb & 0xFCFCFC;
		var c = snapped.get(key);
		if (c == null) {
			c = 0xFF000000 | palette.colors[palette.nearest((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255, 1)];
			snapped.set(key, c);
		}
		return c;
	}
}
