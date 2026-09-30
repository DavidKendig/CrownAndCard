// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import world.GridMap.Prop;
import world.GridMap.Sector;
import world.MapData.ChandelierDef;
import world.MapData.FixtureDef;
import world.MapData.LightDef;
import world.MapData.MapFile;

/**
	A map file turned into something playable (§13.6): the collision grid with
	its props and fixture geometry, plus the interactions the fixtures bring.
	Pure logic, shared by the game, Haxen's checks and the tests.

	Everything here is in world heights: the rooms, props, fixtures, lights and
	chandeliers of a floor above or below the ground floor are raised or lowered
	by its elevation.
**/
class Level {
	public final data:MapFile;
	public final map:GridMap;

	/** The map's lights and chandeliers at world heights. **/
	public final lights:Array<LightDef>;

	public final chandeliers:Array<ChandelierDef>;

	public function new(data:MapFile) {
		this.data = data;
		map = new GridMap(data.rows, sectors(0, 0));
		for (f in data.floors) map.addFloor(f.level, f.elevation, f.rows, sectors(f.level, f.elevation));
		for (p in data.props) {
			var copy:Prop = Reflect.copy(p);
			raise(copy, elevation(p.floor));
			map.props.push(copy);
		}
		for (f in data.fixtures) {
			var first = map.props.length;
			Fixtures.furnish(map, f.type, f.x, f.y);
			var up = elevation(f.floor);
			if (up != 0) for (i in first...map.props.length) raise(map.props[i], up);
		}
		Conservatory.furnish(map);
		for (f in data.fixtures) if (f.type == "frontDoors" && onGround(f.floor))
			for (w in FoyerWindows.layout(map, f.x, f.y)) map.windows.push(w);
		lights = [for (l in data.lights) onGround(l.floor) ? l : {x: l.x, y: l.y, z: l.z + elevation(l.floor), radius: l.radius, power: l.power, floor: l.floor}];
		chandeliers = [for (c in data.chandeliers) onGround(c.floor) ? c : {x: c.x, y: c.y, z: c.z + elevation(c.floor), width: c.width, floor: c.floor}];
	}

	/** The map's room types as they stand on one floor: its elevation added to their heights. **/
	function sectors(level:Int, elevation:Float):Map<String, Sector> {
		var out = new Map<String, Sector>();
		for (s in data.sectors)
			out.set(s.key, {
				name: s.name,
				floorZ: s.floorZ + elevation,
				ceilZ: s.ceilZ + elevation,
				floorTex: s.floorTex,
				ceilTex: s.ceilTex,
				wallTex: s.wallTex,
				upperTex: s.upperTex,
				shade: s.shade,
				level: level,
			});
		return out;
	}

	static function raise(p:Prop, by:Float):Void {
		if (by == 0) return;
		p.baseZ = (p.baseZ == null ? 0 : p.baseZ) + by;
		p.height += by;
	}

	static inline function onGround(floor:Null<Int>):Bool return floor == null || floor == 0;

	/** A floor's elevation in meters (0 for the ground floor). **/
	public function elevation(?floor:Int):Float return MapData.elevation(data, floor);

	/** Where the player's feet start: the start floor's room, and any step or stage under the start point. **/
	public function startFeetZ():Float {
		var s = data.start;
		if (onGround(s.floor)) return map.floorAt(s.x, s.y);
		var room = map.sectorOn(s.floor, s.x, s.y);
		return map.floorAt(s.x, s.y, room == null ? elevation(s.floor) : room.floorZ);
	}

	/** The height a guest stands at: the floor of its room on its own floor. **/
	public function guestZ(g:MapData.GuestDef):Float {
		if (onGround(g.floor)) return 0;
		var room = map.sectorOn(g.floor, g.x, g.y);
		return room == null ? elevation(g.floor) : room.floorZ;
	}

	public function has(type:String):Bool {
		for (f in data.fixtures) if (f.type == type) return true;
		return false;
	}

	public function fixtures(type:String):Array<FixtureDef> return [for (f in data.fixtures) if (f.type == type) f];

	/**
		The fixtures of a type that someone at (x, y) with their feet at `z` can
		use: the ones on their floor. Without `z`, all of them.
	**/
	function reachable(type:String, x:Float, y:Float, ?z:Float):Array<FixtureDef> {
		if (z == null || data.floors.length == 0) return fixtures(type);
		var here = map.levelAt(x, y, z);
		return [for (f in data.fixtures) if (f.type == type && (f.floor == null ? 0 : f.floor) == here) f];
	}

	public function atDesk(x:Float, y:Float, yaw:Float, ?z:Float):Bool {
		for (f in reachable("frontDesk", x, y, z)) if (Fixtures.atDesk(f.x, f.y, x, y, yaw)) return true;
		return false;
	}

	public function atDoor(x:Float, y:Float, ?z:Float):Bool {
		for (f in reachable("frontDoors", x, y, z)) if (Fixtures.atDoor(f.x, f.y, x, y)) return true;
		return false;
	}

	public function awayFromDoors(x:Float, y:Float, ?z:Float):Bool {
		for (f in reachable("frontDoors", x, y, z)) if (!Fixtures.awayFromDoor(f.x, f.y, x, y)) return false;
		return true;
	}

	public function belowStairs(x:Float, y:Float, ?z:Float):Bool {
		for (f in reachable("grandStairs", x, y, z)) if (Fixtures.belowStairs(f.x, f.y, x, y)) return true;
		return false;
	}

	public function atTable(x:Float, y:Float, yaw:Float, ?z:Float):Bool {
		for (f in reachable("cardTable", x, y, z)) if (Fixtures.atTable(f.x, f.y, x, y, yaw)) return true;
		for (f in reachable("rouletteTable", x, y, z)) if (Fixtures.atTable(f.x, f.y, x, y, yaw)) return true;
		return false;
	}

	/** At the Private Party table's empty chair, facing the table: where multiplayer starts (§13.13). **/
	public function atPrivateTable(x:Float, y:Float, yaw:Float, ?z:Float):Bool {
		for (f in reachable("privateTable", x, y, z)) if (Fixtures.atPrivateSeat(f.x, f.y, x, y, yaw)) return true;
		return false;
	}

	/** Start facing, in radians. **/
	public var startYaw(get, never):Float;

	inline function get_startYaw():Float return data.start.facing * Math.PI / 180;
}
