// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import world.GridMap.Prop;

/**
	One room type: every cell painted with its key belongs to it (§13.6). Its
	heights are measured from the elevation of the floor it's painted on, so
	the same room type can be used on any floor.
**/
typedef SectorDef = {
	/** A single character, anything but `#` (solid wall) and `.` (open to the floor below). **/
	var key:String;

	var name:String;
	var floorZ:Float;
	var ceilZ:Float;
	var floorTex:String;
	var ceilTex:String;
	var wallTex:String;
	var upperTex:String;

	/** 0 brightest .. 31 black. **/
	var shade:Float;
}

/** A built set piece placed by its anchor point (see Fixtures for the catalog). **/
typedef FixtureDef = {
	var type:String;
	var x:Float;
	var y:Float;

	/** The floor it stands on (see FloorDef.level); absent on the ground floor. **/
	@:optional var floor:Int;
}

typedef GuestDef = {
	var name:String;
	var x:Float;
	var y:Float;

	/** Degrees, 0 = east, counter-clockwise (90 = north). **/
	var facing:Float;

	/** A character sheet from art.SpriteArt. **/
	var art:String;

	/** Turns to face the player. Without this or `spins`, holds `facing`. **/
	@:optional var turns:Bool;

	/** Turns slowly in place. **/
	@:optional var spins:Bool;

	@:optional var walkTo:{x:Float, y:Float};

	/** The floor it stands on; absent on the ground floor. **/
	@:optional var floor:Int;
}

typedef LightDef = {
	var x:Float;
	var y:Float;

	/** Height above its floor's elevation. **/
	var z:Float;

	var radius:Float;
	var power:Float;

	/** The floor it hangs on; absent on the ground floor. **/
	@:optional var floor:Int;
}

/** A candle chandelier sprite (its width in meters; height is three quarters of it). **/
typedef ChandelierDef = {
	var x:Float;
	var y:Float;

	/** Height above its floor's elevation. **/
	var z:Float;

	var width:Float;

	/** The floor it hangs on; absent on the ground floor. **/
	@:optional var floor:Int;
}

/**
	A storey other than the ground floor: 1, 2, 3... above it, -1, -2...
	below it, as many as a map needs. Every floor covers the same grid as the
	ground floor, so a cell is the same place on each.
**/
typedef FloorDef = {
	/** Its storey number: counts up from 1 above the ground floor, down from -1 below it. **/
	var level:Int;

	var name:String;

	/**
		Where the floor starts, in meters above the ground floor (below it for
		basements). The heights of its rooms, and of everything placed on it,
		are measured from here.
	**/
	var elevation:Float;

	/** Its plan, like MapFile.rows. `.` cells are open to the floor below (stairwells, galleries, atriums). **/
	var rows:Array<String>;
}

typedef MapFile = {
	var format:String;
	var version:Int;
	var name:String;

	/**
		The ground floor's plan, one character per 1 m cell; the first row is the
		north edge. `#` is solid; `.` is open to the floor below.
	**/
	var rows:Array<String>;

	/** The other floors, above and below the ground floor (none in a one-floor map). **/
	var floors:Array<FloorDef>;

	var sectors:Array<SectorDef>;
	var props:Array<Prop>;
	var fixtures:Array<FixtureDef>;
	var start:{x:Float, y:Float, facing:Float, ?floor:Int};
	var guests:Array<GuestDef>;
	var lights:Array<LightDef>;
	var chandeliers:Array<ChandelierDef>;
}

typedef Problem = {
	var error:Bool;
	var message:String;
	@:optional var x:Float;
	@:optional var y:Float;

	/** The floor the place is on, when it isn't the ground floor. **/
	@:optional var floor:Int;
}

/**
	The map file format shared by the game and the Haxen editor (§13.6):
	versioned JSON. The manor itself ships as res/maps/manor.json; custom maps
	use the same format. Version 2 added floors above and below the ground
	floor; a map without them is still written as version 1.
**/
class MapData {
	public static inline var FORMAT = "crown-and-card-map";
	public static inline var VERSION = 2;
	public static inline var MAX_SIZE = 128;

	/** Solid cells. **/
	public static inline var WALL = "#";

	/** Cells with no floor of their own: open to the floor below. **/
	public static inline var OPEN = ".";

	/** The usual height of one storey, and how far a new floor sits above or below the last. **/
	public static inline var STOREY = 3.6;

	/** Wall and surface textures the renderer provides. **/
	public static final TEXTURES = [
		"partyFloor", "bedroomCarpet", "basementFloor", "basementWall", "basementCeiling", "basementMetal", "basementStair",
		"partyWall", "partyCeiling", "clubPurple", "clubTeal", "kitchenTile", "bathroomTile",
		"marble", "parquet", "carpet", "coffer", "dome", "damask", "damaskUpper", "deco", "decoUpper", "green", "greenUpper", "felt",
		"tableWood", "stone", "ivory", "pillarMarble", "stairMarble", "brass", "velvet", "flame", "glass", "banisterWood", "ropeBraid", "grateMetal", "planterCeramic", "soil"
	];

	/** Character sheets a guest can use (art.SpriteArt.CHARACTERS). **/
	public static final ARTS = [
		"security_black", "security_white", "party_chair", "chef", "bartender", "salon-singer",
		"masked_guest", "female_guest", "male_staff", "female_staff", "male_guest_seated", "female_guest_seated", "male_guest_walk",
		"female_guest_walk", "hooded_keeper", "player"
	];

	/** Legal map names: also the file name, so letters, digits, spaces, dashes and underscores. **/
	public static function validName(name:String):Bool {
		return name != null && name.length >= 1 && name.length <= 40 && ~/^[A-Za-z0-9 _-]+$/.match(name) && StringTools.trim(name) == name;
	}

	/** Parses a map file, filling defaults for optional lists. Throws with a readable message on bad input. **/
	public static function parse(text:String):MapFile {
		var raw:Dynamic;
		try raw = haxe.Json.parse(text) catch (e:Dynamic) throw 'Not valid JSON: $e';
		if (raw == null || Reflect.field(raw, "format") != FORMAT) throw 'Not a Crown & Card map file';
		var version:Dynamic = Reflect.field(raw, "version");
		if (!Std.isOfType(version, Int) || version > VERSION) throw 'Map format version $version is newer than this game understands';
		var map:MapFile = {
			format: FORMAT,
			version: VERSION,
			name: str(raw, "name", "Untitled"),
			rows: [for (r in list(raw, "rows")) Std.string(r)],
			floors: [for (f in list(raw, "floors")) {
				level: Std.int(num(f, "level", 0)),
				name: str(f, "name", "Floor"),
				elevation: num(f, "elevation", 0),
				rows: [for (r in list(f, "rows")) Std.string(r)],
			}],
			sectors: [for (s in list(raw, "sectors")) {
				key: str(s, "key", "?"),
				name: str(s, "name", "Room"),
				floorZ: num(s, "floorZ", 0),
				ceilZ: num(s, "ceilZ", 3),
				floorTex: str(s, "floorTex", "parquet"),
				ceilTex: str(s, "ceilTex", "coffer"),
				wallTex: str(s, "wallTex", "damask"),
				upperTex: str(s, "upperTex", "damaskUpper"),
				shade: num(s, "shade", 8),
			}],
			props: [for (p in list(raw, "props")) prop(p)],
			fixtures: [for (f in list(raw, "fixtures")) onFloor(f, {type: str(f, "type", ""), x: num(f, "x", 0), y: num(f, "y", 0)})],
			start: onFloor(Reflect.field(raw, "start"), {
				x: num(Reflect.field(raw, "start"), "x", 1.5),
				y: num(Reflect.field(raw, "start"), "y", 1.5),
				facing: num(Reflect.field(raw, "start"), "facing", 90)
			}),
			guests: [for (g in list(raw, "guests")) guest(g)],
			lights: [for (l in list(raw, "lights")) onFloor(l, {
				x: num(l, "x", 0),
				y: num(l, "y", 0),
				z: num(l, "z", 3),
				radius: num(l, "radius", 6),
				power: num(l, "power", 8)
			})],
			chandeliers: [for (c in list(raw, "chandeliers")) onFloor(c, {x: num(c, "x", 0), y: num(c, "y", 0), z: num(c, "z", 3), width: num(c, "width", 1.5)})],
		};
		return map;
	}

	/** Copies a `floor` field from the file, keeping it only off the ground floor. **/
	static function onFloor<T>(from:Dynamic, to:T):T {
		var f = from == null ? 0 : Std.int(num(from, "floor", 0));
		if (f != 0) Reflect.setField(to, "floor", f);
		return to;
	}

	public static function stringify(map:MapFile):String {
		// A map on one floor stays version 1, which games before floors can still open.
		var out:Dynamic = Reflect.copy(map);
		if (map.floors == null || map.floors.length == 0) {
			Reflect.deleteField(out, "floors");
			out.version = 1;
		} else out.version = VERSION;
		return haxe.Json.stringify(out, null, "\t");
	}

	/** The floors top to bottom, the ground floor (level 0) among them. **/
	public static function storeys(map:MapFile):Array<{level:Int, name:String, elevation:Float, rows:Array<String>}> {
		var all = [{level: 0, name: "Ground floor", elevation: 0.0, rows: map.rows}];
		for (f in map.floors) all.push({level: f.level, name: f.name, elevation: f.elevation, rows: f.rows});
		all.sort((a, b) -> b.level - a.level);
		return all;
	}

	/** A floor's elevation: 0 for the ground floor (and for a floor the map doesn't have). **/
	public static function elevation(map:MapFile, ?level:Int):Float {
		if (level == null || level == 0) return 0;
		for (f in map.floors) if (f.level == level) return f.elevation;
		return 0;
	}

	/** A floor's plan (the ground floor's for 0), or null if the map has no such floor. **/
	public static function floorRows(map:MapFile, level:Int):Null<Array<String>> {
		if (level == 0) return map.rows;
		for (f in map.floors) if (f.level == level) return f.rows;
		return null;
	}

	/** A floor's name. **/
	public static function floorName(map:MapFile, ?level:Int):String {
		if (level == null || level == 0) return "the ground floor";
		for (f in map.floors) if (f.level == level) return f.name;
		return 'floor $level';
	}

	/** A fresh map: one 10 × 8 m room inside a wall border, with a start point and a light. **/
	public static function blank(name:String, width = 16, height = 12):MapFile {
		var rows = [];
		for (y in 0...height) {
			var line = "";
			for (x in 0...width) line += (x == 0 || y == 0 || x == width - 1 || y == height - 1) ? "#" : "a";
			rows.push(line);
		}
		return {
			format: FORMAT,
			version: VERSION,
			name: name,
			rows: rows,
			floors: [],
			sectors: [{key: "a", name: "Parlour", floorZ: 0, ceilZ: 3.5, floorTex: "parquet", ceilTex: "coffer", wallTex: "damask", upperTex: "damaskUpper", shade: 7}],
			props: [],
			fixtures: [],
			start: {x: width / 2, y: 2, facing: 90},
			guests: [],
			lights: [{x: width / 2, y: height / 2, z: 3, radius: 8, power: 9}],
			chandeliers: [],
		};
	}

	/** Everything that would stop the map loading (errors) or leave it lacking (warnings). **/
	public static function check(map:MapFile):Array<Problem> {
		var out:Array<Problem> = [];
		function add(bad:Bool, m:String, ?x:Float, ?y:Float, ?floor:Int) {
			var p:Problem = {error: bad, message: m, x: x, y: y};
			if (floor != null && floor != 0) p.floor = floor;
			out.push(p);
		}
		function error(m:String, ?x:Float, ?y:Float, ?floor:Int) add(true, m, x, y, floor);
		function warn(m:String, ?x:Float, ?y:Float, ?floor:Int) add(false, m, x, y, floor);
		if (!validName(map.name)) error('The map name must be 1-40 letters, digits, spaces, dashes or underscores.');
		else if (map.name.toLowerCase() == "manor") error('"manor" is reserved for the built-in map; choose another name.');
		if (map.rows.length == 0 || map.rows[0].length == 0) {
			error("The map has no cells.");
			return out;
		}
		var w = map.rows[0].length, h = map.rows.length;
		if (w > MAX_SIZE || h > MAX_SIZE) error('The map is ${w} × ${h}; the most is $MAX_SIZE × $MAX_SIZE.');
		var keys = new Map<String, Bool>();
		for (s in map.sectors) {
			if (s.key.length != 1 || s.key == WALL || s.key == OPEN) error('Room "${s.name}" needs a single-character key other than # and ".".');
			else if (keys.exists(s.key)) error('Two rooms use the key "${s.key}".');
			keys.set(s.key, true);
			if (s.ceilZ <= s.floorZ + 1.8) error('Room "${s.name}": the ceiling must be at least 1.8 m above the floor.');
			for (t in [s.floorTex, s.ceilTex, s.wallTex, s.upperTex])
				if (TEXTURES.indexOf(t) < 0) error('Room "${s.name}" uses an unknown texture "$t".');
		}
		// Floors: any number above and below, each over the same grid, each above the one below it.
		var levels = new Map<Int, Bool>();
		for (f in map.floors) {
			if (f.level == 0) error('Floor "${f.name}" is level 0, which is the ground floor.');
			else if (levels.exists(f.level)) error('Two floors are level ${f.level}.');
			levels.set(f.level, true);
			if (Math.isNaN(f.elevation) || !Math.isFinite(f.elevation)) error('Floor "${f.name}" needs an elevation in meters.');
		}
		var ordered = storeys(map);
		for (i in 1...ordered.length) if (ordered[i - 1].elevation <= ordered[i].elevation)
			error('${cap(ordered[i - 1].name)} must be higher than ${ordered[i].name}, the floor below it.');
		var unknown = new Map<String, Bool>();
		for (st in ordered) {
			var on = st.level == 0 ? "" : ' on ${st.name}';
			if (st.rows.length != h) error('${cap(st.name)} is ${st.rows.length} cells from north to south; the ground floor is $h.');
			for (row in 0...st.rows.length) {
				if (st.rows[row].length != w) error('Row ${row + 1}$on is ${st.rows[row].length} cells wide; the ground floor is $w.');
				for (i in 0...st.rows[row].length) {
					var c = st.rows[row].charAt(i);
					if (c != WALL && c != OPEN && !keys.exists(c) && !unknown.exists(c)) {
						unknown.set(c, true);
						error('Cells$on use "$c", which isn\'t any room\'s key.', i + .5, h - row - .5, st.level);
					}
				}
			}
		}
		if (out.length > 0) return out;
		// Build the level to check positions against the real collision.
		var level = new Level(map);
		function exists(f:Null<Int>, what:String, x:Float, y:Float):Bool {
			if (f == null || f == 0 || levels.exists(f)) return true;
			error('$what is on floor $f, which this map doesn\'t have.', x, y);
			return false;
		}
		inline function floorOf(f:Null<Int>):Int return f == null ? 0 : f;
		var s = map.start;
		if (exists(s.floor, "The player start", s.x, s.y)) {
			if (level.map.sectorOn(floorOf(s.floor), s.x, s.y) == null) error("The player starts inside a wall or outside the map.", s.x, s.y, s.floor);
			else if (level.map.blocked(s.x, s.y, 0.25, floorOf(s.floor) == 0 ? null : level.startFeetZ()))
				error("The player starts inside a prop or fixture.", s.x, s.y, s.floor);
		}
		for (f in map.fixtures) {
			var kind = Fixtures.get(f.type);
			if (kind == null) error('Unknown fixture "${f.type}".', f.x, f.y, f.floor);
			else if (exists(f.floor, kind.label, f.x, f.y) && level.map.sectorOn(floorOf(f.floor), f.x, f.y) == null)
				warn('${kind.label} sits in a wall.', f.x, f.y, f.floor);
		}
		for (g in map.guests) {
			if (ARTS.indexOf(g.art) < 0) error('${g.name} uses unknown art "${g.art}".', g.x, g.y, g.floor);
			if (exists(g.floor, g.name, g.x, g.y) && level.map.sectorOn(floorOf(g.floor), g.x, g.y) == null)
				warn('${g.name} stands in a wall.', g.x, g.y, g.floor);
		}
		for (l in map.lights) exists(l.floor, "A light", l.x, l.y);
		for (c in map.chandeliers) exists(c.floor, "A chandelier", c.x, c.y);
		for (p in map.props) exists(p.floor, "A prop", p.x0, p.y0);
		for (p in map.props) if (p.x1 <= p.x0 || p.y1 <= p.y0 || p.height <= (p.baseZ == null ? 0 : p.baseZ))
			error("A prop has no size (its far corner must be beyond its near corner, and its top above its base).", p.x0, p.y0, p.floor);
		for (p in map.props) for (t in [p.topTex, p.sideTex]) if (TEXTURES.indexOf(t) < 0) {
			error('A prop uses an unknown texture "$t".', p.x0, p.y0, p.floor);
			break;
		}
		checkStacking(map, level.map, error, warn);
		if (!level.has("frontDesk")) warn("No front desk: nobody can check in (save) on this map.");
		if (map.lights.length == 0) warn("No lights: rooms will be lit only by their shade.");
		return out;
	}

	/**
		Where floors meet: rooms on different floors mustn't fill the same space,
		a room rising into the floor above needs open cells there, and open cells
		need a room below that reaches up to them. Each problem is reported once.
	**/
	static function checkStacking(map:MapFile, grid:GridMap, error:(String, ?Float, ?Float, ?Int) -> Void, warn:(String, ?Float, ?Float, ?Int) -> Void):Void {
		var layers = grid.layers;
		if (layers.length < 2 && grid.layers[0].open.indexOf(true) < 0) return;
		var seen = new Map<String, Bool>();
		function once(key:String):Bool {
			if (seen.exists(key)) return false;
			seen.set(key, true);
			return true;
		}
		function name(l:GridMap.Layer):String return floorName(map, l.level);
		var hanging = [for (_ in layers) 0];
		var hangingAt:Array<Null<{x:Float, y:Float}>> = [for (_ in layers) null];
		for (cy in 0...grid.height) for (cx in 0...grid.width) {
			var i = cy * grid.width + cx, x = cx + .5, y = cy + .5;
			for (a in 0...layers.length) {
				var la = layers[a], s = la.cells[i];
				if (s != null) {
					for (b in a + 1...layers.length) {
						var lb = layers[b], t = lb.cells[i];
						// Rooms on two floors overlapping in height.
						if (t != null && t.floorZ < s.ceilZ - 1e-6 && s.floorZ < t.ceilZ - 1e-6) {
							if (once('overlap ${s.name} ${la.level} ${t.name} ${lb.level}'))
								error('${s.name} (${name(la)}) and ${t.name} (${name(lb)}) fill the same space. Lower the ceiling below, raise the floor above, or make these cells open to the floor below on ${name(lb)}.', x, y, lb.level);
						} else if (t == null && !lb.open[i] && s.ceilZ > lb.elevation + 1e-6) {
							// A tall room rising into a floor that has walls over it.
							if (once('rises ${s.name} ${la.level} ${lb.level}'))
								warn('${s.name} (${name(la)}) rises into ${name(lb)}, where its cells are walls. Make them open to the floor below there, or lower the ceiling.', x, y, lb.level);
						}
					}
				} else if (la.open[i]) {
					// Open cells look down into a room below that reaches up to this floor.
					var below = false;
					var b = a;
					while (b-- > 0) {
						var t = layers[b].cells[i];
						if (t != null) {
							below = t.ceilZ > la.elevation - 1e-6;
							break;
						}
						if (!layers[b].open[i]) break;
					}
					if (!below) {
						hanging[a]++;
						if (hangingAt[a] == null) hangingAt[a] = {x: x, y: y};
					}
				}
			}
		}
		for (a in 0...layers.length) if (hanging[a] > 0)
			warn('${hanging[a]} cell${hanging[a] == 1 ? " is" : "s are"} open to the floor below on ${name(layers[a])}, but no room below reaches up to ${hanging[a] == 1 ? "it" : "them"}; they act as walls.',
				hangingAt[a].x, hangingAt[a].y, layers[a].level);
	}

	static function cap(s:String):String return s.charAt(0).toUpperCase() + s.substr(1);

	public static function hasErrors(problems:Array<Problem>):Bool {
		for (p in problems) if (p.error) return true;
		return false;
	}

	/** A deep copy (maps are edited in place by Haxen). **/
	public static function copy(map:MapFile):MapFile return parse(stringify(map));

	static function list(o:Dynamic, field:String):Array<Dynamic> {
		var v:Dynamic = o == null ? null : Reflect.field(o, field);
		return Std.isOfType(v, Array) ? v : [];
	}

	static function str(o:Dynamic, field:String, fallback:String):String {
		var v:Dynamic = o == null ? null : Reflect.field(o, field);
		return v == null ? fallback : Std.string(v);
	}

	static function num(o:Dynamic, field:String, fallback:Float):Float {
		var v:Dynamic = o == null ? null : Reflect.field(o, field);
		return Std.isOfType(v, Float) || Std.isOfType(v, Int) ? v : fallback;
	}

	static function prop(p:Dynamic):Prop {
		var out:Prop = {
			x0: num(p, "x0", 0),
			y0: num(p, "y0", 0),
			x1: num(p, "x1", 1),
			y1: num(p, "y1", 1),
			height: num(p, "height", 1),
			topTex: str(p, "topTex", "tableWood"),
			sideTex: str(p, "sideTex", "tableWood"),
		};
		for (f in ["baseZ", "collisionRadius"]) if (Reflect.hasField(p, f)) Reflect.setField(out, f, num(p, f, 0));
		for (f in ["solid", "walkable", "hidden"]) if (Reflect.hasField(p, f)) Reflect.setField(out, f, Reflect.field(p, f) == true);
		if (Reflect.hasField(p, "kind")) out.kind = str(p, "kind", "");
		return onFloor(p, out);
	}

	static function guest(g:Dynamic):GuestDef {
		var out:GuestDef = {
			name: str(g, "name", "Guest"),
			x: num(g, "x", 0),
			y: num(g, "y", 0),
			facing: num(g, "facing", 0),
			art: str(g, "art", "masked_guest"),
		};
		if (Reflect.field(g, "turns") == true) out.turns = true;
		else if (Reflect.field(g, "spins") == true) out.spins = true;
		var w:Dynamic = Reflect.field(g, "walkTo");
		if (w != null) out.walkTo = {x: num(w, "x", out.x), y: num(w, "y", out.y)};
		return onFloor(g, out);
	}
}
