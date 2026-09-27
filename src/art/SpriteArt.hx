// SPDX-License-Identifier: AGPL-3.0-or-later
package art;

import render.IndexCanvas;
import render.Palette;

/** PNG source art imported onto the game's 64 texels/m palette grid. */
class SpriteArt {
	public static inline var GUEST_W = 48;
	public static inline var GUEST_H = 112;

	public static function guestSheet(palette:Palette):IndexCanvas {
		return characterSheet("masked_guest", palette);
	}

	public static final CHARACTERS = ["player", "masked_guest", "female_guest", "male_staff", "female_staff",
		"male_guest_seated", "female_guest_seated", "male_guest_walk", "female_guest_walk"];

	public static function frameWidth(name:String):Int {
		return StringTools.endsWith(name, "_seated") ? 128 : StringTools.endsWith(name, "_walk") ? 64 : GUEST_W;
	}

	public static function frameHeight(name:String):Int {
		return StringTools.endsWith(name, "_seated") ? 168 : GUEST_H;
	}

	public static function density(name:String):Int {
		return StringTools.endsWith(name, "_seated") ? 128 : 64;
	}

	public static function animationRows(name:String):Int {
		return StringTools.endsWith(name, "_walk") ? 4 : 1;
	}

	public static function characterSheet(name:String, palette:Palette):IndexCanvas {
		if (CHARACTERS.indexOf(name) < 0) throw 'Unknown character sheet: $name';
		// Generated walk rows have explicit transparent separators, not equal heights.
		var cuts = switch (name) {
			case "male_guest_walk": [0, 402, 776, 1136, 1448];
			case "female_guest_walk": [0, 345, 661, 986, 1292];
			default: null;
		};
		var sourceName = cuts == null ? name : name + "_v2";
		var sheet = importSheet(hxd.Res.load('sprites/$sourceName.png').toImage().getPixels(), palette, 5,
			frameWidth(name), frameHeight(name), animationRows(name), cuts);
		// The female source's rear three-quarter is drawn from the opposite side.
		if (name == "female_guest_seated" || name == "female_guest_walk") {
			var original = sheet.copy(), w = frameWidth(name);
			for (y in 0...sheet.height) for (x in 0...w)
				sheet.set(3 * w + x, y, original.get(4 * w - 1 - x, y));
		}
		return sheet;
	}

	public static function playerHands(palette:Palette):IndexCanvas {
		return importSheet(hxd.Res.load("sprites/player_hands.png").toImage().getPixels(), palette, 1, 150, 112);
	}

	public static function chandelier(palette:Palette):IndexCanvas {
		return importSheet(hxd.Res.sprites.brass_chandelier.getPixels(), palette, 1, 96, 72);
	}

	/**
		Equal source cells, centered silhouettes, common scale and grounded feet.
		Nearest sampling and binary alpha avoid soft fringes in the shade LUT.
		The same importer accepts replacement PNGs without a separate asset tool.
	**/
	public static function importSheet(source:hxd.Pixels, palette:Palette, columns:Int, frameW:Int, frameH:Int, rows:Int = 1, ?rowCuts:Array<Int>):IndexCanvas {
		if (columns < 1 || rows < 1 || frameW < 3 || frameH < 3 || source.width < columns || source.height < rows)
			throw "Invalid sprite sheet dimensions";
		if (rowCuts != null) {
			if (rowCuts.length != rows + 1 || rowCuts[0] != 0 || rowCuts[rows] != source.height) throw "Invalid row cuts";
			for (r in 0...rows) if (rowCuts[r + 1] <= rowCuts[r]) throw "Unordered row cuts";
		}
		var bounds = [];
		var scale = Math.POSITIVE_INFINITY;
		for (frame in 0...columns * rows) {
			// PNG generators may round canvas width; partition without losing pixels.
			var col = frame % columns, row = Std.int(frame / columns);
			var cellX = Std.int(col * source.width / columns);
			var cellW = Std.int((col + 1) * source.width / columns) - cellX;
			var cellY = rowCuts == null ? Std.int(row * source.height / rows) : rowCuts[row];
			var cellH = (rowCuts == null ? Std.int((row + 1) * source.height / rows) : rowCuts[row + 1]) - cellY;
			var left = cellW, right = -1, top = cellH, bottom = -1;
			for (y in 0...cellH)
				for (x in 0...cellW)
					if ((source.getPixel(cellX + x, cellY + y) >>> 24) >= 128) {
						left = Std.int(Math.min(left, x));
						right = Std.int(Math.max(right, x));
						top = Std.int(Math.min(top, y));
						bottom = Std.int(Math.max(bottom, y));
					}
			if (right < left) throw 'Empty sprite frame $frame';
			var w = right - left + 1, h = bottom - top + 1;
			bounds.push({x: cellX + left, y: cellY + top, w: w, h: h});
			scale = Math.min(scale, Math.min((frameW - 2) / w, (frameH - 2) / h));
		}
		var out = new IndexCanvas(columns * frameW, rows * frameH);
		var colors = new Map<Int, Int>();
		for (frame in 0...columns * rows) {
			var b = bounds[frame];
			// Normalize walk cel height so source scale drift does not shrink actors mid-step.
			var frameScale = rowCuts == null ? scale : Math.min((frameW - 2) / b.w, (frameH - 2) / b.h);
			var w = Std.int(Math.max(1, Math.round(b.w * frameScale)));
			var h = Std.int(Math.max(1, Math.round(b.h * frameScale)));
			var dx = (frame % columns) * frameW + Std.int((frameW - w) / 2);
			var dy = Std.int(frame / columns) * frameH + frameH - 1 - h;
			for (y in 0...h)
				for (x in 0...w) {
					var c = source.getPixel(b.x + Std.int((x + 0.5) * b.w / w), b.y + Std.int((y + 0.5) * b.h / h));
					if ((c >>> 24) < 128) continue;
					var rgb = c & 0xFFFFFF;
					if (!colors.exists(rgb))
						colors.set(rgb, palette.nearest((c >> 16) & 255, (c >> 8) & 255, c & 255, 1));
					out.set(dx + x, dy + y, colors.get(rgb));
				}
		}
		return out;
	}
}
