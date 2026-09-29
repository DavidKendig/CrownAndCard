// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import world.GridMap.Prop;

/** What Haxen needs to draw and describe a fixture type. **/
typedef FixtureKind = {
	var type:String;
	var label:String;
	var description:String;

	/** Footprint relative to the anchor, in meters (+Y north). **/
	var x0:Float;

	var y0:Float;
	var x1:Float;
	var y1:Float;

	/** Round footprint (the fountain). **/
	var round:Bool;
}

/**
	Built set pieces placed by an anchor point (§13.6). Each adds its
	collision and walkable geometry to the grid map here; the 3D art for the
	ones that need it is in world.FixtureArt. Interactions (checking in,
	leaving, sitting at the table) follow the fixture wherever it's placed.

	Fixtures keep the orientation they have in the manor: the desk, stairs
	and card table face south (toward a player coming from the south), and
	the doors are in a south wall.
**/
class Fixtures {
	public static final KINDS:Array<FixtureKind> = [
		{
			type: "privateTable", label: "Private party table", round: false,
			description: "A 6 x 1.4 m table with a draped teal cloth and a spread of tabletop games. Standing 1.7 m south of its center and facing it (put an empty chair there) opens the multiplayer tables: host or join friends. Anchor: its center.",
			x0: -3, y0: -.7, x1: 3, y1: .7
		},
		{
			type: "rouletteTable", label: "Roulette table", round: false,
			description: "A 2.4 x 1.35 m roulette table with a complete betting mat and resting wheel. Facing it from the guests' side opens the game menu. Anchor: its center.",
			x0: -1.2, y0: -0.675, x1: 1.2, y1: 0.675
		},
		{
			type: "frontDoors", label: "Front doors", round: false,
			description: "The grand doors in a south wall. Walking up to them asks whether to leave the manor. Anchor: the middle of the wall line.",
			x0: -2.6, y0: -0.2, x1: 2.6, y1: 1.2
		},
		{
			type: "frontDesk", label: "Front desk", round: false,
			description: "Mr. Quill's welcome desk with the Guest Register. Standing south of it and facing north checks in (saves). Place a guest with the hooded_keeper art just north of it.",
			x0: -2.35, y0: -0.7, x1: 2.35, y1: 1.45
		},
		{
			type: "fountain", label: "Fountain", round: true,
			description: "The three-tier marble fountain with running water. Anchor: its center.",
			x0: -1.72, y0: -1.72, x1: 1.72, y1: 1.72
		},
		{
			type: "grandStairs", label: "Grand stairs", round: false,
			description: "Twenty real treads up to a 3.6 m landing, closed with velvet ropes, and the upper doorway. Anchor: the middle of the bottom step.",
			x0: -4.4, y0: -0.6, x1: 4.4, y1: 6.5
		},
		{
			type: "cardTable", label: "Card table", round: false,
			description: "The 2.4 × 1.2 m card table. Facing it from the south, east or west opens the game menu. Anchor: its center.",
			x0: -1.2, y0: -0.6, x1: 1.2, y1: 0.6
		},
	];

	public static function get(type:String):Null<FixtureKind> {
		for (k in KINDS) if (k.type == type) return k;
		return null;
	}

	/** Adds a fixture's collision and walkable geometry to the grid map. **/
	public static function furnish(map:GridMap, type:String, ax:Float, ay:Float):Void {
		function box(x0:Float, y0:Float, x1:Float, y1:Float, top:Float, tex:String, base:Float = 0, solid:Bool = true) {
			map.props.push({x0: ax + x0, y0: ay + y0, x1: ax + x1, y1: ay + y1, height: top, baseZ: base, topTex: tex, sideTex: tex, solid: solid});
		}
		switch type {
			case "privateTable":
				map.props.push({x0:ax-3,y0:ay-.7,x1:ax+3,y1:ay+.7,height:.82,topTex:"tableWood",sideTex:"tableWood",hidden:true});
				box(-3,-.7,3,.7,.82,"tableWood",.77,false);
				for(dx in [-2.5,2.5]) for(dy in [-.43,.43]) box(dx-.09,dy-.09,dx+.09,dy+.09,.78,"tableWood");
			case "frontDesk":
				// Broad desk, overhanging marble counter, brass plinth, and the Guest Register.
				box(-2.2, -.6, 2.2, .6, 1.08, "tableWood");
				box(-2.35, -.7, 2.35, .7, 1.16, "stone", 1.08);
				box(-2.25, -.65, 2.25, .65, .10, "brass");
				box(-.35, -.25, .35, .2, 1.20, "ivory", 1.16, false);
				box(-.03, -.26, .03, .21, 1.205, "brass", 1.2, false);
				for (dx in [-1.8, 1.8]) {
					box(dx - .10, -.1, dx + .10, .1, 1.22, "brass", 1.16, false);
					box(dx - .03, -.03, dx + .03, .03, 1.57, "ivory", 1.22, false);
					box(dx - .025, -.03, dx + .025, .03, 1.65, "flame", 1.57, false);
				}
				// The keeper behind the desk has a solid footprint.
				map.props.push({x0: ax - .35, y0: ay + .75, x1: ax + .35, y1: ay + 1.45, height: 2, topTex: "stone", sideTex: "stone", hidden: true});
			case "fountain":
				// Circular collision follows the 3D rim.
				map.props.push({x0: ax - 1.6, y0: ay - 1.6, x1: ax + 1.6, y1: ay + 1.6, height: .5, topTex: "stone", sideTex: "stone", hidden: true,
					collisionRadius: 1.72});
			case "grandStairs":
				// Twenty true treads rise to a 3.6 m landing. Future access only needs rope removal.
				for (i in 0...20) {
					var y = i * .3, z = (i + 1) * .18;
					map.props.push({x0: ax - 4, y0: ay + y, x1: ax + 4, y1: ay + y + .3, height: z, topTex: "stairMarble", sideTex: "stairMarble", walkable: true, kind: "stair"});
					box(-1.75, y, 1.75, y + .3, z + .008, "carpet", z, false);
					// Brass nosings make the individual risers legible from below.
					box(-3.95, y - .012, 3.95, y + .035, z + .012, "brass", z - .025, false);
					for (dx in [-3.88, 3.88]) {
						box(dx - .07, y + .10, dx + .07, y + .20, z + .9, "banisterWood", z, false);
						box(dx - .11, y, dx + .11, y + .3, z + 1, "banisterWood", z + .92, false);
					}
				}
				map.props.push({x0: ax - 4, y0: ay + 6, x1: ax + 4, y1: ay + 6.5, height: 3.6, topTex: "stairMarble", sideTex: "stairMarble", walkable: true, kind: "landing"});
				box(-1.75, 6, 1.75, 6.48, 3.608, "carpet", 3.6, false);
				for (dx in [-3.9, 3.9]) box(dx - .25, -.2, dx + .25, .3, 1.25, "banisterWood");
				rope(map, ax - 4.4, ay - .6, ax + 4.4, ay - .6);
				rope(map, ax - 4.4, ay - .6, ax - 4.4, ay + 6.3);
				rope(map, ax + 4.4, ay - .6, ax + 4.4, ay + 6.3);
			case "cardTable":
				map.props.push({x0: ax - 1.2, y0: ay - .6, x1: ax + 1.2, y1: ay + .6, height: 0.9, topTex: "felt", sideTex: "tableWood"});
			case "rouletteTable":
				map.props.push({x0: ax - 1.2, y0: ay - .675, x1: ax + 1.2, y1: ay + .675, height: 0.9, topTex: "felt", sideTex: "tableWood"});
			default:
		}
	}

	static function rope(map:GridMap, x0:Float, y0:Float, x1:Float, y1:Float):Void {
		map.props.push({x0: x0 - .09, y0: y0 - .09, x1: x1 + .09, y1: y1 + .09, height: 1, topTex: "brass", sideTex: "brass", hidden: true, kind: "rope"});
		var length = Math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
		var spans = Std.int(Math.ceil(length / 2.2));
		for (i in 0...spans + 1) {
			var x = x0 + (x1 - x0) * i / spans, y = y0 + (y1 - y0) * i / spans;
			map.props.push({x0: x - .07, y0: y - .07, x1: x + .07, y1: y + .07, height: 1.05, topTex: "brass", sideTex: "brass", solid: false});
		}
		var pieces = spans * 12;
		for (i in 0...pieces) {
			var a = i / pieces, b = (i + 1) / pieces;
			var z = .92 - .23 * Math.sin(Math.PI * ((i % 12) + .5) / 12);
			map.props.push({x0: x0 + (x1 - x0) * a - .025, y0: y0 + (y1 - y0) * a - .025, x1: x0 + (x1 - x0) * b + .025, y1: y0 + (y1 - y0) * b + .025,
				height: z + .065, baseZ: z, topTex: "ropeBraid", sideTex: "ropeBraid", solid: false});
		}
	}

	// --- Interaction zones, relative to each fixture's anchor ---

	/** Standing south of the desk and facing it. **/
	public static function atDesk(ax:Float, ay:Float, x:Float, y:Float, yaw:Float):Bool {
		return x > ax - 2.2 && x < ax + 2.2 && y >= ay - 3.1 && y < ay - .7 && Math.sin(yaw) > 0.55;
	}

	/** At the doors, just inside the wall. **/
	public static function atDoor(ax:Float, ay:Float, x:Float, y:Float):Bool {
		return x > ax - 2 && x < ax + 2 && y < ay + 1.2 && y >= ay;
	}

	/** Far enough from the doors that walking back up to them asks again. **/
	public static function awayFromDoor(ax:Float, ay:Float, x:Float, y:Float):Bool {
		return y > ay + 1.9 || x < ax - 2.5 || x > ax + 2.5;
	}

	/** In front of the roped-off stairs. **/
	public static function belowStairs(ax:Float, ay:Float, x:Float, y:Float):Bool {
		return y > ay - 1.9 && y < ay && x > ax - 5 && x < ax + 5;
	}

	/**
		At the Private Party table's empty chair (1.7 m south of its center) and
		facing the table: the multiplayer seat (§13.13).
	**/
	public static function atPrivateSeat(ax:Float, ay:Float, x:Float, y:Float, yaw:Float):Bool {
		var sx = ax, sy = ay - 1.7;
		if ((x - sx) * (x - sx) + (y - sy) * (y - sy) > 0.9 * 0.9) return false;
		// Facing north, toward the table, within about 55 degrees.
		return Math.sin(yaw) > 0.57;
	}

	/** Standing at the table on the guests' side (the dealer works the north side) and facing it. **/
	public static function atTable(ax:Float, ay:Float, x:Float, y:Float, yaw:Float):Bool {
		var x0 = ax - 1.2, x1 = ax + 1.2, y0 = ay - .6, y1 = ay + .6;
		if (y > y1) return false;
		var dx = Math.max(x0 - x, Math.max(0, x - x1));
		var dy = Math.max(y0 - y, Math.max(0, y - y1));
		if (dx * dx + dy * dy > 1.0) return false;
		// Facing the table's center, within about 55 degrees.
		var tx = ax - x, ty = ay - y, len = Math.sqrt(tx * tx + ty * ty);
		if (len < 1e-6) return true;
		return (Math.cos(yaw) * tx + Math.sin(yaw) * ty) / len > 0.57;
	}
}
