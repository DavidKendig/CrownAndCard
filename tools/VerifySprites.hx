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
				if (!StringTools.startsWith(name, "female_guest") && !StringTools.startsWith(name, "security_") && name != "party_chair" && navy < 100) throw 'Blue outfit lost in $name frame $frame';
				if (row > 0 && changed < 50) throw 'Repeated animation in $name frame $frame row $row';
			}
		}
		// The manor as the game loads it (res/maps/manor.json).
		var level = new world.Level(world.MapData.parse(hxd.Res.load("maps/manor.json").toText()));
		var map = level.map;
		for (spawn in level.data.guests) {
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
		if (level.data.guests[0].art != "hooded_keeper") throw "Front desk must use the hooded keeper";
		var start=level.data.start;
		if(map.blocked(start.x,start.y,.25) || !level.atDesk(start.x,start.y,level.startYaw)) throw "Invalid foyer spawn";
		// Both side aisles must reach the original playable rooms without crossing ropes.
		for (x in [7.5,18.5]) {
			var p={x:start.x,y:start.y};
			p=map.slide(p.x,p.y,x-p.x,0,.25);
			p=map.slide(p.x,p.y,0,24-p.y,.25);
			if(Math.abs(p.x-x)>.01 || Math.abs(p.y-24)>.01) throw "Foyer aisle is blocked";
		}
		for (asset in ["fountain.png","welcome-desk.png","grand-doors.png"]) {
			var pixels=hxd.Res.load('foyer/$asset').toImage().getPixels();
			if(pixels.width<256 || pixels.height<256) throw 'Missing foyer source: $asset';
		}
		var codes=new Map<String,Bool>();
		for(i in 0...52) {
			var card=cards.Card.fromIndex(i), path=art.CardArt.path(card);
			var face=hxd.Res.load(path).toImage().getPixels();
			if(face.width!=200 || face.height!=280) throw 'Wrong card proportions: $path';
			if(codes.exists(card.code)) throw "Duplicate card face";
			codes.set(card.code,true);
		}
		var back=hxd.Res.load("cards/back.png").toImage().getPixels();
		if(back.width*7!=back.height*5) throw "Wrong card back proportions";
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
