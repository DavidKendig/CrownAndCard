// SPDX-License-Identifier: AGPL-3.0-or-later
import art.SpriteArt;
import render.Palette;

/** CPU-only validation of the shipped PNGs and their palette import. */
class VerifySprites {
	static function main() {
		hxd.Res.initEmbed();
		var palette = new Palette();
		for (name in SpriteArt.CHARACTERS) {
			var guest = SpriteArt.characterSheet(name, palette);
			var w = SpriteArt.frameWidth(name), h = SpriteArt.frameHeight(name), rows = SpriteArt.animationRows(name);
			if (guest.width != w * 5 || guest.height != h * rows) throw 'Wrong dimensions: $name';
			for (row in 0...rows) for (frame in 0...5) {
				var opaque = 0, navy = 0, changed = 0;
				for (y in 0...h) for (x in 0...w) {
					var i = guest.get(frame * w + x, row * h + y);
					if (i != 0) opaque++;
					if (Palette.rampOf(i) == Palette.NAVY) navy++;
					if ((x == 0 || x == w - 1 || y == 0 || y == h - 1) && i != 0) throw 'Missing gutter: $name';
					if (row > 0 && i != guest.get(frame * w + x, (row - 1) * h + y)) changed++;
				}
				if (opaque < 500) throw 'Unusable $name frame $frame row $row';
				if (!StringTools.startsWith(name, "female_guest") && navy < 100) throw 'Blue outfit lost in $name frame $frame';
				if (row > 0 && changed < 50) throw 'Repeated animation in $name frame $frame row $row';
			}
		}
		var map = world.Greybox.map();
		for (spawn in world.Greybox.GUESTS) {
			if (SpriteArt.CHARACTERS.indexOf(spawn.art) < 0) throw 'Missing art for ${spawn.name}';
			if (spawn.walkTo == null) continue;
			var walk = new world.GuestWalkPath(spawn.x, spawn.y, spawn.walkTo.x, spawn.walkTo.y);
			var phases = new Map<Int, Bool>();
			var turned = false;
			for (_ in 0...180) {
				walk.update(0.1, map);
				if (map.blocked(walk.x, walk.y, 0.25)) throw "Walker entered a wall or table";
				if (walk.y < Math.min(spawn.y, spawn.walkTo.y) || walk.y > Math.max(spawn.y, spawn.walkTo.y)) throw "Walker left route";
				phases.set(walk.phase, true);
				if (Math.sin(walk.facing) < 0) turned = true;
			}
			if (!turned || [for (_ in phases.keys()) 1].length != 4) throw "Walk did not turn and animate";
		}
		if (world.Greybox.GUESTS[0].art != "male_staff") throw "Front desk must use blue staff art";
		var hands = SpriteArt.playerHands(palette);
		if (hands.width != 150 || hands.height != 112) throw "Wrong player HUD size";
		// Blue remains cool through the actual LUT, not just in the preview.
		var lut = palette.buildShadeLut();
		for (shade in 0...Palette.SHADES) for (step in 0...Palette.RAMP_STEPS) {
			var c = lut.getPixel(Palette.index(Palette.NAVY, step), shade);
			if ((c & 255) < ((c >> 16) & 255)) throw 'Navy turned brown at shade $shade';
		}
		var chandelier = SpriteArt.chandelier(palette);
		if (chandelier.width != 96 || chandelier.height != 72) throw "Wrong prop dimensions";
		// Opaque darkest pixels must never become transparent palette index zero.
		var px = hxd.Pixels.alloc(2, 2, RGBA);
		px.clear(0);
		px.setPixel(0, 0, 0xFF0E0D12);
		var imported = SpriteArt.importSheet(px, palette, 1, 4, 4);
		if (imported.get(1, 1) == 0 || imported.get(0, 0) != 0) throw "Alpha/index-zero regression";
		trace("All character poses: angles, animation rows, walk routes, blue outfits, HUD, shade LUT, gutters and alpha PASS");
		// Heaps' resource runtime owns a timer; this headless verifier is done.
		js.Syntax.code("process.exit(0)");
	}
}
