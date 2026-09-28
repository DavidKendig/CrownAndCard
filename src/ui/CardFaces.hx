// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import cards.Card;
import render.Palette;

/**
	Seated-view cards (§5.7): 40×56, drawn 1:1 on the 360p grid. The index and
	pips are pixel glyphs so they stay readable; aces and court portraits are
	reduced from the authored 200×280 faces (res/cards/). Colors snap to the
	master palette.
**/
class CardFaces {
	public static inline var W = 40;
	public static inline var H = 56;

	static inline var INK_DARK = 0x14202C;
	static inline var INK_RED = 0x972637;
	static inline var CREAM = 0xF4EAD5;
	static inline var EDGE = 0xB89B63;

	final palette:Palette;
	final faces = new Map<Int, h2d.Tile>();
	final snapped = new Map<Int, Int>();
	var backTile:Null<h2d.Tile>;

	public function new(palette:Palette) {
		this.palette = palette;
	}

	public function face(card:Card):h2d.Tile {
		var t = faces.get(card.index);
		if (t == null) {
			t = toTile(drawFace(card));
			faces.set(card.index, t);
		}
		return t;
	}

	public function back():h2d.Tile {
		if (backTile == null) {
			var px = blank();
			var src = hxd.Res.load("cards/back.png").toImage().getPixels();
			for (y in 1...H - 1) for (x in 1...W - 1)
				if (inside(x, y)) {
					var c = average(src, x * src.width / W, y * src.height / H, (x + 1) * src.width / W, (y + 1) * src.height / H);
					if ((c >>> 24) > 128) px.setPixel(x, y, snap(c));
				}
			backTile = toTile(px);
		}
		return backTile;
	}

	function drawFace(card:Card):hxd.Pixels {
		var px = blank();
		var ink = snap(card.suit.isRed ? INK_RED : INK_DARK);
		var rank = card.rank;
		var label = rank == 10 ? "|0" : "23456789TJQKA".charAt(rank - 2);
		if (rank >= Card.JACK && rank <= Card.KING) court(px, card);
		else if (rank == Card.ACE) ace(px, card, ink);
		else for (p in pips(rank)) {
			var x = Std.int(Math.round(11 + p.x * 13)), y = Std.int(Math.round(5 + p.y * 39));
			PixelGlyphs.drawSuit(px, card.suit, x, y, ink, p.y > .5);
		}
		// Indices last, over the corners of the court frames.
		PixelGlyphs.drawText(px, label, rank == 10 ? 2 : 3, 3, ink);
		PixelGlyphs.drawSuit(px, card.suit, 2, 12, ink);
		PixelGlyphs.drawSuit(px, card.suit, W - 9, H - 9, ink, true);
		return px;
	}

	/** Pip positions in the 13×39 pip field: x 0/.5/1 = left/center/right columns. **/
	static function pips(rank:Int):Array<{x:Float, y:Float}> {
		function p(x:Float, y:Float) return {x: x, y: y};
		var corners = [p(0, 0), p(1, 0), p(0, 1), p(1, 1)];
		var six = corners.concat([p(0, .5), p(1, .5)]);
		var eightSides = [for (row in 0...4) for (col in 0...2) p(col, row / 3)];
		return switch rank {
			case 2: [p(.5, 0), p(.5, 1)];
			case 3: [p(.5, 0), p(.5, .5), p(.5, 1)];
			case 4: corners;
			case 5: corners.concat([p(.5, .5)]);
			case 6: six;
			case 7: six.concat([p(.5, .25)]);
			case 8: six.concat([p(.5, .25), p(.5, .75)]);
			case 9: eightSides.concat([p(.5, .5)]);
			default: eightSides.concat([p(.5, 1 / 6), p(.5, 5 / 6)]);
		}
	}

	/** The court frame (both portraits) from the authored face, reduced into the pip field. **/
	function court(px:hxd.Pixels, card:Card):Void {
		var src = hxd.Res.load(art.CardArt.path(card)).toImage().getPixels();
		// Frame rectangle in the 200×280 face (tools/build_cards.cjs).
		var fx = 47 * src.width / 200, fy = 34 * src.height / 280, fw = 106 * src.width / 200, fh = 212 * src.height / 280;
		var ox = 10, oy = 5, ow = 22, oh = 44;
		for (y in 0...oh) for (x in 0...ow) {
			var c = average(src, fx + x * fw / ow, fy + y * fh / oh, fx + (x + 1) * fw / ow, fy + (y + 1) * fh / oh);
			px.setPixel(ox + x, oy + y, snap(c));
		}
	}

	/** The ace's large pip, found by its ink and reduced to fit 22×22. **/
	function ace(px:hxd.Pixels, card:Card, ink:Int):Void {
		var src = hxd.Res.load(art.CardArt.path(card)).toImage().getPixels();
		inline function isInk(c:Int):Bool {
			var r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
			return (c >>> 24) > 128 && r + g + b < 420;
		}
		var x0 = src.width, y0 = src.height, x1 = -1, y1 = -1;
		for (y in Std.int(src.height * .2)...Std.int(src.height * .8))
			for (x in Std.int(src.width * .2)...Std.int(src.width * .8))
				if (isInk(src.getPixel(x, y))) {
					if (x < x0) x0 = x;
					if (y < y0) y0 = y;
					if (x > x1) x1 = x;
					if (y > y1) y1 = y;
				}
		if (x1 < 0) return;
		var bw = x1 - x0 + 1, bh = y1 - y0 + 1;
		var size = 22, scale = Math.max(bw, bh) / size;
		var ow = Math.round(bw / scale), oh = Math.round(bh / scale);
		var ox = Std.int(20 - ow / 2), oy = Std.int(28 - oh / 2);
		for (y in 0...oh) for (x in 0...ow) {
			var inkCount = 0, total = 0;
			for (sy in Std.int(y0 + y * scale)...Std.int(y0 + (y + 1) * scale))
				for (sx in Std.int(x0 + x * scale)...Std.int(x0 + (x + 1) * scale)) {
					total++;
					if (isInk(src.getPixel(sx, sy))) inkCount++;
				}
			if (total > 0 && inkCount * 2 >= total) px.setPixel(ox + x, oy + y, ink);
		}
	}

	/** Cream card with a tan edge and cut corners. **/
	function blank():hxd.Pixels {
		var px = hxd.Pixels.alloc(W, H, hxd.PixelFormat.RGBA);
		var face = snap(CREAM), edge = snap(EDGE);
		for (y in 0...H) for (x in 0...W) {
			if (!inside(x, y)) continue;
			var border = x == 0 || y == 0 || x == W - 1 || y == H - 1 || !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1);
			px.setPixel(x, y, border ? edge : face);
		}
		return px;
	}

	static inline function inside(x:Int, y:Int):Bool {
		if (x < 0 || y < 0 || x >= W || y >= H) return false;
		var cx = x < 2 ? 2 - x : x > W - 3 ? x - (W - 3) : 0;
		var cy = y < 2 ? 2 - y : y > H - 3 ? y - (H - 3) : 0;
		return cx + cy < 3;
	}

	/** Alpha-weighted average color over a source rectangle. **/
	static function average(src:hxd.Pixels, x0:Float, y0:Float, x1:Float, y1:Float):Int {
		var r = 0.0, g = 0.0, b = 0.0, a = 0.0, n = 0;
		for (y in Std.int(y0)...Std.int(Math.max(y0 + 1, y1)))
			for (x in Std.int(x0)...Std.int(Math.max(x0 + 1, x1))) {
				if (x >= src.width || y >= src.height) continue;
				var c = src.getPixel(x, y);
				var ca = (c >>> 24) / 255;
				r += ((c >> 16) & 255) * ca;
				g += ((c >> 8) & 255) * ca;
				b += (c & 255) * ca;
				a += ca;
				n++;
			}
		if (n == 0 || a == 0) return 0;
		return (Std.int(a / n * 255) << 24) | (Std.int(r / a) << 16) | (Std.int(g / a) << 8) | Std.int(b / a);
	}

	/** Nearest master-palette color, opaque. **/
	function snap(rgb:Int):Int {
		var key = rgb & 0xFCFCFC;
		var c = snapped.get(key);
		if (c == null) {
			c = 0xFF000000 | palette.colors[palette.nearest((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255, 1)];
			snapped.set(key, c);
		}
		return c;
	}

	static function toTile(px:hxd.Pixels):h2d.Tile {
		var tex = h3d.mat.Texture.fromPixels(px);
		tex.filter = Nearest;
		return h2d.Tile.fromTexture(tex);
	}
}
