// SPDX-License-Identifier: AGPL-3.0-or-later
package art;

import render.IndexCanvas;
import render.Palette;

/**
	Procedural placeholder art in the master palette, at 64 texels per meter
	(§5.2). It only has to prove the pipeline and the look; real art will be
	drawn in Aseprite and imported into the same indexed form.

	Uses its own hash noise, not the game RNG: art generation isn't gameplay.
**/
class ProcArt {
	// --- Floors and ceilings (64 × 64 = 1 m²) -------------------------------

	public static function marble():IndexCanvas {
		var c = new IndexCanvas(64, 64);
		for (y in 0...64)
			for (x in 0...64) {
				var light = ((x >> 5) + (y >> 5)) % 2 == 0;
				var ramp = light ? Palette.IVORY : Palette.STONE;
				var step = light ? 11 : 6;
				var n = noise(x, y, 1);
				if (n < 0.12) step--;
				if (n > 0.93) step++;
				if (Math.abs(Math.sin((x * 0.7 + y * 0.45) * 0.35 + Math.sin(y * 0.2 + x * 0.05) * 2.0)) < 0.07)
					step -= 2;
				if (x % 32 == 0 || y % 32 == 0) {
					ramp = Palette.STONE;
					step = 3;
				}
				c.set(x, y, I(ramp, step));
			}
		return c;
	}

	public static function parquet():IndexCanvas {
		var c = new IndexCanvas(64, 64);
		for (y in 0...64) {
			var row = y >> 3;
			var offset = hash(row, 0, 7) % 32;
			var tone = hash(row, 1, 7) % 3;
			for (x in 0...64) {
				var seam = ((x + offset) % 32) == 0 || (y & 7) == 7;
				var step = 6 + tone + ((y & 7) == 0 ? 1 : 0) + (noise(x >> 1, y, 3) > 0.82 ? -1 : 0);
				c.set(x, y, seam ? I(Palette.DARK_WOOD, 3) : I(Palette.WOOD, step));
			}
		}
		return c;
	}

	public static function carpet():IndexCanvas {
		var c = new IndexCanvas(64, 64);
		for (y in 0...64)
			for (x in 0...64) {
				var d1 = (x + y) % 32, d2 = (x - y + 64) % 32;
				var cx = (x % 32) - 16, cy = (y % 32) - 16;
				var rosette = cx * cx + cy * cy < 10;
				var index = if (d1 == 0 || d2 == 0) I(Palette.GOLD, 7) else if (rosette) I(Palette.GOLD, 9) else
					I(Palette.RED, 5 + (noise(x, y, 4) > 0.85 ? 1 : 0) - (noise(x, y, 5) > 0.9 ? 1 : 0));
				c.set(x, y, index);
			}
		return c;
	}

	public static function ceilingCoffer():IndexCanvas {
		var c = new IndexCanvas(64, 64);
		c.fillRect(0, 0, 64, 64, I(Palette.DARK_WOOD, 4));
		c.fillRect(6, 6, 52, 52, I(Palette.DARK_WOOD, 6));
		c.fillRect(8, 8, 48, 48, I(Palette.DARK_WOOD, 2));
		c.fillRect(6, 6, 52, 1, I(Palette.DARK_WOOD, 8));
		c.fillRect(6, 6, 1, 52, I(Palette.DARK_WOOD, 7));
		c.fillRect(30, 30, 4, 4, I(Palette.GOLD, 8));
		return c;
	}

	/** Night-blue dome with gold stars, for the Rotunda's high ceiling. **/
	public static function ceilingDome():IndexCanvas {
		var c = new IndexCanvas(64, 64);
		for (y in 0...64)
			for (x in 0...64)
				c.set(x, y, I(Palette.NIGHT, 3 + (noise(x >> 2, y >> 2, 9) > 0.7 ? 1 : 0)));
		for (i in 0...5) {
			var sx = hash(i, 0, 11) % 64, sy = hash(i, 1, 11) % 64;
			c.set(sx, sy, I(Palette.GOLD, 13));
			if (i % 2 == 0) {
				c.set(sx + 1, sy, I(Palette.GOLD, 9));
				c.set(sx - 1, sy, I(Palette.GOLD, 9));
				c.set(sx, sy + 1, I(Palette.GOLD, 9));
				c.set(sx, sy - 1, I(Palette.GOLD, 9));
			}
		}
		return c;
	}

	public static function felt():IndexCanvas {
		var c = new IndexCanvas(64, 64);
		for (y in 0...64)
			for (x in 0...64)
				c.set(x, y, I(Palette.FELT, 6 + (noise(x, y, 12) > 0.8 ? 1 : 0) - (noise(x, y, 13) > 0.9 ? 1 : 0)));
		return c;
	}

	public static function tableWood():IndexCanvas {
		var c = new IndexCanvas(64, 64);
		for (y in 0...64)
			for (x in 0...64) {
				var grain = Math.sin(x * 0.9 + Math.sin(y * 0.15) * 2) > 0.7 ? -1 : 0;
				c.set(x, y, I(Palette.DARK_WOOD, 5 + grain));
			}
		c.fillRect(0, 0, 64, 3, I(Palette.GOLD, 8));
		c.fillRect(0, 3, 64, 1, I(Palette.GOLD, 4));
		return c;
	}

	// --- Walls (64 × 192 = 1 m × 3 m, v = 0 at the top) ---------------------

	public static function wallDamask():IndexCanvas {
		var c = new IndexCanvas(64, 192);
		crownMolding(c, Palette.GOLD);
		damask(c, 8, 124, Palette.RED, 4, 7);
		chairRail(c, 124);
		wainscot(c, 132);
		return c;
	}

	public static function wallGreen():IndexCanvas {
		var c = new IndexCanvas(64, 192);
		crownMolding(c, Palette.DARK_WOOD);
		stripes(c, 8, 124);
		chairRail(c, 124);
		wainscot(c, 132);
		return c;
	}

	public static function wallDeco():IndexCanvas {
		var c = new IndexCanvas(64, 192);
		crownMolding(c, Palette.GOLD);
		deco(c, 8, 124);
		chairRail(c, 124);
		wainscot(c, 132);
		return c;
	}

	/** Tiling 1 m wall pieces for walls above 3 m. **/
	public static function upperDamask():IndexCanvas {
		var c = new IndexCanvas(64, 64);
		damask(c, 0, 64, Palette.RED, 4, 7);
		return c;
	}

	public static function upperDeco():IndexCanvas {
		var c = new IndexCanvas(64, 64);
		deco(c, 0, 64);
		return c;
	}

	public static function upperGreen():IndexCanvas {
		var c = new IndexCanvas(64, 64);
		stripes(c, 0, 64);
		return c;
	}

	static function crownMolding(c:IndexCanvas, ramp:Int) {
		var steps = [3, 9, 12, 8, 5, 9, 4, 2];
		for (i in 0...8)
			c.fillRect(0, i, 64, 1, I(ramp, steps[i]));
	}

	static function chairRail(c:IndexCanvas, y:Int) {
		var steps = [3, 7, 10, 8, 6, 4, 3, 2];
		for (i in 0...8)
			c.fillRect(0, y + i, 64, 1, I(Palette.DARK_WOOD, steps[i]));
		c.fillRect(0, y + 2, 64, 1, I(Palette.GOLD, 9));
	}

	/** Raised dark-wood panels with a baseboard, from `y` to the bottom. **/
	static function wainscot(c:IndexCanvas, y:Int) {
		var h = c.height - y;
		c.fillRect(0, y, 64, h, I(Palette.DARK_WOOD, 4));
		for (px in [0, 32]) {
			c.fillRect(px + 4, y + 6, 24, h - 18, I(Palette.DARK_WOOD, 6));
			c.fillRect(px + 4, y + 6, 24, 1, I(Palette.DARK_WOOD, 9));
			c.fillRect(px + 4, y + 6, 1, h - 18, I(Palette.DARK_WOOD, 8));
			c.fillRect(px + 4, y + h - 13, 24, 1, I(Palette.DARK_WOOD, 2));
			c.fillRect(px + 27, y + 6, 1, h - 18, I(Palette.DARK_WOOD, 2));
		}
		c.fillRect(0, c.height - 6, 64, 6, I(Palette.DARK_WOOD, 2));
		c.fillRect(0, c.height - 6, 64, 1, I(Palette.DARK_WOOD, 6));
	}

	/** Repeating fleur motif on a 32 × 32 grid, alternate rows offset. **/
	static function damask(c:IndexCanvas, y0:Int, y1:Int, ramp:Int, baseStep:Int, motifStep:Int) {
		for (y in y0...y1)
			for (x in 0...64) {
				var ly = (y - y0) % 32;
				var lx = ((((y - y0) >> 5) & 1) == 1) ? (x + 16) % 32 : x % 32;
				var dy = ly - 16, dx = Math.abs(lx - 16);
				var w = dy >= -13 && dy <= 13 ? 7 * Math.sin(Math.PI * (dy + 13) / 26) : -1;
				var onMotif = (w > 0 && dx <= w && dx >= w - 1.6) || (lx == 16 && Math.abs(dy) < 10);
				var step = onMotif ? motifStep : baseStep - (noise(x, y, 21) > 0.9 ? 1 : 0);
				c.set(x, y, I(ramp, step));
			}
	}

	static function stripes(c:IndexCanvas, y0:Int, y1:Int) {
		for (y in y0...y1)
			for (x in 0...64) {
				var band = (x >> 3) & 1;
				var index = (x & 15) == 0 ? I(Palette.GOLD, 7) : I(Palette.OLIVE, band == 0 ? 5 : 4);
				c.set(x, y, index);
			}
	}

	/** Art Deco chevrons, navy and gold. **/
	static function deco(c:IndexCanvas, y0:Int, y1:Int) {
		for (y in y0...y1)
			for (x in 0...64) {
				var lx = x % 32, ly = (y - y0) % 16;
				var onChevron = Math.abs(lx - 16) == 15 - ly || Math.abs(lx - 16) == 11 - ly;
				c.set(x, y, onChevron ? I(Palette.GOLD, 9) : I(Palette.NAVY, 4 + ((x >> 4) & 1)));
			}
	}

	// --- Sprites ----------------------------------------------------------

	public static inline var GUEST_W = 48;
	public static inline var GUEST_H = 112;

	/**
		A masked guest in evening wear, drawn from the 5 Build angles side by
		side: front, front-¾, side (facing screen-left), back-¾, back.
		Palette-swap the NAVY ramp for other outfits (§5.3).
	**/
	public static function guestSheet():IndexCanvas {
		var sheet = new IndexCanvas(GUEST_W * 5, GUEST_H);
		for (angle in 0...5)
			sheet.blit(guestFrame(angle), angle * GUEST_W, 0);
		return sheet;
	}

	static function guestFrame(angle:Int):IndexCanvas {
		var c = new IndexCanvas(GUEST_W, GUEST_H);
		switch (angle) {
			case 0: // front
				c.shadedRect(16, 62, 7, 44, Palette.NAVY, 3, 6);
				c.shadedRect(25, 62, 7, 44, Palette.NAVY, 2, 5);
				shoes(c, 15, 24);
				c.shadedRect(6, 27, 6, 34, Palette.NAVY, 3, 6);
				c.shadedRect(36, 27, 6, 34, Palette.NAVY, 2, 5);
				c.shadedRect(11, 25, 26, 40, Palette.NAVY, 3, 7);
				shirtV(c, 24, 6);
				c.fillRect(20, 26, 8, 3, I(Palette.RED, 8));
				c.set(24, 27, I(Palette.RED, 5));
				c.set(24, 50, I(Palette.GOLD, 10));
				c.set(24, 56, I(Palette.GOLD, 10));
				c.shadedEllipse(9, 63, 3, 3.5, Palette.SKIN, 6, 10);
				c.shadedEllipse(39, 63, 3, 3.5, Palette.SKIN, 5, 9);
				c.fillRect(21, 21, 6, 5, I(Palette.SKIN, 7));
				c.shadedEllipse(24, 11, 8.5, 9.5, Palette.HAIR, 3, 6);
				c.shadedEllipse(24, 15, 7, 8, Palette.SKIN, 6, 11);
				mask(c, 16, 16, [19, 26]);
				c.fillRect(22, 19, 4, 1, I(Palette.RED, 5));
			case 1: // front three-quarter, turned toward screen-left
				c.shadedRect(15, 62, 7, 44, Palette.NAVY, 3, 6);
				c.shadedRect(24, 62, 7, 44, Palette.NAVY, 2, 5);
				shoes(c, 13, 23);
				c.shadedRect(35, 27, 6, 34, Palette.NAVY, 2, 5);
				c.shadedRect(13, 25, 23, 40, Palette.NAVY, 3, 7);
				c.shadedRect(9, 27, 5, 34, Palette.NAVY, 4, 6);
				shirtV(c, 20, 5);
				c.fillRect(17, 26, 7, 3, I(Palette.RED, 8));
				c.set(24, 50, I(Palette.GOLD, 10));
				c.shadedEllipse(11, 63, 3, 3.5, Palette.SKIN, 6, 10);
				c.shadedEllipse(38, 63, 3, 3.5, Palette.SKIN, 5, 9);
				c.fillRect(20, 21, 6, 5, I(Palette.SKIN, 7));
				c.shadedEllipse(26, 11, 8, 10, Palette.HAIR, 3, 6);
				c.shadedEllipse(22, 15, 7, 8, Palette.SKIN, 6, 11);
				mask(c, 15, 14, [17, 23]);
				c.fillRect(16, 14, 1, 2, I(Palette.SKIN, 9));
				c.fillRect(19, 19, 3, 1, I(Palette.RED, 5));
			case 2: // side, facing screen-left
				c.shadedRect(22, 62, 7, 44, Palette.NAVY, 2, 4);
				c.shadedRect(19, 62, 7, 44, Palette.NAVY, 3, 6);
				c.fillRect(13, 104, 15, 6, I(Palette.HAIR, 2));
				c.fillRect(13, 104, 15, 1, I(Palette.HAIR, 4));
				c.shadedRect(16, 25, 17, 40, Palette.NAVY, 3, 7);
				c.fillRect(16, 26, 3, 18, I(Palette.IVORY, 12));
				c.fillRect(13, 26, 4, 3, I(Palette.RED, 8));
				c.shadedRect(21, 27, 7, 34, Palette.NAVY, 2, 6);
				c.shadedEllipse(24, 63, 3, 3.5, Palette.SKIN, 6, 10);
				c.fillRect(21, 21, 6, 5, I(Palette.SKIN, 7));
				c.shadedEllipse(26, 12, 7, 9.5, Palette.HAIR, 3, 6);
				c.shadedEllipse(21, 15, 6, 8, Palette.SKIN, 6, 11);
				c.fillRect(14, 13, 2, 3, I(Palette.SKIN, 9));
				mask(c, 15, 10, [17]);
				c.fillRect(25, 12, 6, 2, I(Palette.GOLD, 7));
				c.fillRect(26, 15, 2, 3, I(Palette.SKIN, 8));
				c.fillRect(16, 19, 2, 1, I(Palette.RED, 5));
			case 3: // back three-quarter
				c.shadedRect(17, 62, 7, 44, Palette.NAVY, 3, 5);
				c.shadedRect(25, 62, 7, 44, Palette.NAVY, 2, 4);
				shoes(c, 16, 25);
				c.shadedRect(8, 27, 6, 34, Palette.NAVY, 3, 6);
				c.shadedRect(13, 25, 23, 40, Palette.NAVY, 3, 6);
				c.shadedRect(35, 27, 5, 34, Palette.NAVY, 2, 4);
				c.fillRect(26, 40, 1, 25, I(Palette.NAVY, 2));
				c.shadedEllipse(10, 63, 3, 3.5, Palette.SKIN, 5, 9);
				c.fillRect(21, 21, 6, 5, I(Palette.SKIN, 6));
				c.fillRect(17, 25, 10, 2, I(Palette.IVORY, 10));
				c.shadedEllipse(19, 15, 3, 6, Palette.SKIN, 6, 9);
				c.shadedEllipse(25, 12, 8, 10, Palette.HAIR, 3, 6);
				c.fillRect(15, 12, 5, 3, I(Palette.GOLD, 9));
			default: // back
				c.shadedRect(16, 62, 7, 44, Palette.NAVY, 3, 5);
				c.shadedRect(25, 62, 7, 44, Palette.NAVY, 2, 4);
				shoes(c, 15, 24);
				c.shadedRect(6, 27, 6, 34, Palette.NAVY, 3, 6);
				c.shadedRect(36, 27, 6, 34, Palette.NAVY, 2, 5);
				c.shadedRect(11, 25, 26, 40, Palette.NAVY, 3, 6);
				c.fillRect(24, 40, 1, 25, I(Palette.NAVY, 2));
				c.shadedEllipse(9, 63, 3, 3.5, Palette.SKIN, 5, 9);
				c.shadedEllipse(39, 63, 3, 3.5, Palette.SKIN, 5, 9);
				c.fillRect(21, 21, 6, 5, I(Palette.SKIN, 6));
				c.fillRect(19, 25, 10, 2, I(Palette.IVORY, 10));
				c.shadedEllipse(24, 12, 8, 10, Palette.HAIR, 3, 6);
				c.fillRect(21, 12, 6, 2, I(Palette.GOLD, 8));
				c.fillRect(22, 14, 1, 4, I(Palette.GOLD, 7));
				c.fillRect(25, 14, 1, 4, I(Palette.GOLD, 7));
		}
		c.outline();
		return c;
	}

	static function shoes(c:IndexCanvas, leftX:Int, rightX:Int) {
		c.fillRect(leftX, 104, 9, 6, I(Palette.HAIR, 2));
		c.fillRect(rightX, 104, 9, 6, I(Palette.HAIR, 1));
		c.fillRect(leftX, 104, 9, 1, I(Palette.HAIR, 4));
	}

	/** White shirt front narrowing to a point below the bow tie. **/
	static function shirtV(c:IndexCanvas, centerX:Int, halfWidth:Int) {
		for (y in 25...46) {
			var half = Math.round(halfWidth * (1 - (y - 25) / 21));
			if (half > 0)
				c.fillRect(centerX - half, y, half * 2, 1, I(Palette.IVORY, 12));
		}
	}

	/** Gold half-mask across the eyes, with dark eye holes. **/
	static function mask(c:IndexCanvas, x:Int, w:Int, eyes:Array<Int>) {
		c.fillRect(x, 11, w, 5, I(Palette.GOLD, 10));
		c.fillRect(x, 11, w, 1, I(Palette.GOLD, 13));
		c.fillRect(x, 15, w, 1, I(Palette.GOLD, 6));
		for (e in eyes)
			c.fillRect(e, 13, 3, 2, I(Palette.NAVY, 1));
	}

	/** A gilded chandelier with five candles (a single-angle face sprite). **/
	public static function chandelier():IndexCanvas {
		var c = new IndexCanvas(96, 72);
		c.fillRect(47, 0, 2, 26, I(Palette.GOLD, 6));
		c.fillRect(12, 38, 72, 3, I(Palette.GOLD, 8));
		c.fillRect(12, 38, 72, 1, I(Palette.GOLD, 12));
		for (dx in [-36, -18, 0, 18, 36]) {
			var x = 48 + dx;
			c.fillRect(x - 2, 30, 4, 9, I(Palette.GOLD, 9));
			c.fillRect(x - 1, 18, 3, 12, I(Palette.IVORY, 13));
			c.shadedEllipse(x + 0.5, 13, 2.2, 4.5, Palette.FLAME, 11, 15);
		}
		c.shadedEllipse(48, 44, 13, 9, Palette.GOLD, 5, 12);
		for (dx in [-9, -5, -1, 3, 7])
			c.fillRect(48 + dx, 53, 1, 6 + (dx & 3), I(Palette.TEAL, 13));
		c.fillRect(46, 55, 4, 10, I(Palette.GOLD, 7));
		c.outline(2);
		return c;
	}

	/** First-person gloved hand holding a coupe of champagne (HUD sprite, §5.6). **/
	public static function handWithGlass():IndexCanvas {
		var c = new IndexCanvas(128, 104);
		// Forearm in a dark sleeve, coming in from the bottom right, with a shirt cuff.
		for (y in 62...104) {
			var x0 = 66 + Std.int((y - 62) * 0.7);
			c.shadedRect(x0, y, 128 - x0, 1, Palette.NAVY, 2, 6);
			c.fillRect(x0 - 5, y, 5, 1, I(Palette.IVORY, y < 66 ? 14 : 12));
		}
		// Coupe glass: rim, champagne, stem and foot.
		for (y in 18...36) {
			var t = (y - 18) / 18;
			var half = Math.round(21 * Math.sqrt(Math.max(0, 1 - t * t)));
			c.fillRect(48 - half, y, half * 2, 1, I(Palette.GOLD, y < 21 ? 13 : 11 - Std.int(t * 4)));
		}
		c.fillRect(27, 18, 42, 1, I(Palette.IVORY, 15));
		c.fillRect(30, 21, 3, 2, I(Palette.IVORY, 15)); // glint
		c.fillRect(47, 36, 3, 40, I(Palette.IVORY, 12));
		c.fillRect(48, 36, 1, 40, I(Palette.IVORY, 14));
		c.fillRect(36, 74, 25, 3, I(Palette.IVORY, 13));
		// White glove: back of the hand, fingers curled round the stem, thumb across it.
		c.shadedEllipse(60, 58, 13, 11, Palette.IVORY, 8, 14);
		for (i in 0...4)
			c.shadedEllipse(47, 50 + i * 5.5, 5, 3, Palette.IVORY, 7, 13);
		for (t in 0...10)
			c.fillRect(57 - t, 48 - Std.int(t * 0.4), 5, 3, I(Palette.IVORY, 13));
		c.fillRect(62, 52, 1, 12, I(Palette.IVORY, 9));
		c.fillRect(66, 54, 1, 10, I(Palette.IVORY, 9));
		c.outline();
		return c;
	}

	// --- Noise ------------------------------------------------------------

	static inline function I(ramp:Int, step:Int):Int {
		return Palette.index(ramp, step < 1 ? 1 : (step > 15 ? 15 : step));
	}

	static function hash(x:Int, y:Int, seed:Int):Int {
		var h = (imul(x, 374761393) + imul(y, 668265263) + imul(seed, 1442695041)) | 0;
		h = imul(h ^ (h >>> 13), 1274126177);
		return (h ^ (h >>> 16)) & 0x7FFFFFFF;
	}

	static inline function noise(x:Int, y:Int, seed:Int):Float {
		return hash(x, y, seed) / 2147483647.0;
	}

	static inline function imul(a:Int, b:Int):Int {
		#if js
		return js.Syntax.code("Math.imul({0}, {1})", a, b);
		#else
		return a * b;
		#end
	}
}
