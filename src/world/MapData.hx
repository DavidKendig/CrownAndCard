// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import world.GridMap.Prop;

/** One room type: every cell painted with its key belongs to it (§13.6). **/
typedef SectorDef = {
	/** A single character, anything but `#` (solid wall). **/
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
}

typedef LightDef = {
	var x:Float;
	var y:Float;
	var z:Float;
	var radius:Float;
	var power:Float;
}

/** A candle chandelier sprite (its width in meters; height is three quarters of it). **/
typedef ChandelierDef = {
	var x:Float;
	var y:Float;
	var z:Float;
	var width:Float;
}

typedef MapFile = {
	var format:String;
	var version:Int;
	var name:String;

	/** Floor plan, one character per 1 m cell; the first row is the north edge. `#` is solid. **/
	var rows:Array<String>;

	var sectors:Array<SectorDef>;
	var props:Array<Prop>;
	var fixtures:Array<FixtureDef>;
	var start:{x:Float, y:Float, facing:Float};
	var guests:Array<GuestDef>;
	var lights:Array<LightDef>;
	var chandeliers:Array<ChandelierDef>;
}

typedef Problem = {
	var error:Bool;
	var message:String;
	@:optional var x:Float;
	@:optional var y:Float;
}

/**
	The map file format shared by the game and the Haxen editor (§13.6):
	versioned JSON. The manor itself ships as res/maps/manor.json; custom maps
	use the same format.
**/
class MapData {
	public static inline var FORMAT = "crown-and-card-map";
	public static inline var VERSION = 1;
	public static inline var MAX_SIZE = 128;

	/** Wall and surface textures the renderer provides. **/
	public static final TEXTURES = [
		"partyFloor", "partyWall", "partyCeiling", "clubPurple", "clubTeal", "kitchenTile", "bathroomTile",
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
			fixtures: [for (f in list(raw, "fixtures")) {type: str(f, "type", ""), x: num(f, "x", 0), y: num(f, "y", 0)}],
			start: {
				x: num(Reflect.field(raw, "start"), "x", 1.5),
				y: num(Reflect.field(raw, "start"), "y", 1.5),
				facing: num(Reflect.field(raw, "start"), "facing", 90)
			},
			guests: [for (g in list(raw, "guests")) guest(g)],
			lights: [for (l in list(raw, "lights")) {
				x: num(l, "x", 0),
				y: num(l, "y", 0),
				z: num(l, "z", 3),
				radius: num(l, "radius", 6),
				power: num(l, "power", 8)
			}],
			chandeliers: [for (c in list(raw, "chandeliers")) {x: num(c, "x", 0), y: num(c, "y", 0), z: num(c, "z", 3), width: num(c, "width", 1.5)}],
		};
		return map;
	}

	public static function stringify(map:MapFile):String {
		return haxe.Json.stringify(map, null, "\t");
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
		function error(m:String, ?x:Float, ?y:Float) out.push({error: true, message: m, x: x, y: y});
		function warn(m:String, ?x:Float, ?y:Float) out.push({error: false, message: m, x: x, y: y});
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
			if (s.key.length != 1 || s.key == "#") error('Room "${s.name}" needs a single-character key other than #.');
			else if (keys.exists(s.key)) error('Two rooms use the key "${s.key}".');
			keys.set(s.key, true);
			if (s.ceilZ <= s.floorZ + 1.8) error('Room "${s.name}": the ceiling must be at least 1.8 m above the floor.');
			for (t in [s.floorTex, s.ceilTex, s.wallTex, s.upperTex])
				if (TEXTURES.indexOf(t) < 0) error('Room "${s.name}" uses an unknown texture "$t".');
		}
		var unknown = new Map<String, Bool>();
		for (row in 0...h) {
			if (map.rows[row].length != w) error('Row ${row + 1} is ${map.rows[row].length} cells wide; the first row is $w.');
			for (i in 0...map.rows[row].length) {
				var c = map.rows[row].charAt(i);
				if (c != "#" && !keys.exists(c) && !unknown.exists(c)) {
					unknown.set(c, true);
					error('Cells use "$c", which isn\'t any room\'s key.', i + .5, h - row - .5);
				}
			}
		}
		if (out.length > 0) return out;
		// Build the level to check positions against the real collision.
		var level = new Level(map);
		var s = map.start;
		if (level.map.sectorAtWorld(s.x, s.y) == null) error("The player starts inside a wall or outside the map.", s.x, s.y);
		else if (level.map.blocked(s.x, s.y, 0.25)) error("The player starts inside a prop or fixture.", s.x, s.y);
		for (f in map.fixtures) {
			var kind = Fixtures.get(f.type);
			if (kind == null) error('Unknown fixture "${f.type}".', f.x, f.y);
			else if (level.map.sectorAtWorld(f.x, f.y) == null) warn('${kind.label} sits in a wall.', f.x, f.y);
		}
		for (g in map.guests) {
			if (ARTS.indexOf(g.art) < 0) error('${g.name} uses unknown art "${g.art}".', g.x, g.y);
			if (level.map.sectorAtWorld(g.x, g.y) == null) warn('${g.name} stands in a wall.', g.x, g.y);
		}
		for (p in map.props) if (p.x1 <= p.x0 || p.y1 <= p.y0 || p.height <= (p.baseZ == null ? 0 : p.baseZ))
			error("A prop has no size (its far corner must be beyond its near corner, and its top above its base).", p.x0, p.y0);
		for (p in map.props) for (t in [p.topTex, p.sideTex]) if (TEXTURES.indexOf(t) < 0) {
			error('A prop uses an unknown texture "$t".', p.x0, p.y0);
			break;
		}
		if (!level.has("frontDesk")) warn("No front desk: nobody can check in (save) on this map.");
		if (map.lights.length == 0) warn("No lights: rooms will be lit only by their shade.");
		return out;
	}

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
		return out;
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
		return out;
	}
}
