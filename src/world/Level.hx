// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import world.GridMap.Sector;
import world.MapData.FixtureDef;
import world.MapData.MapFile;

/**
	A map file turned into something playable (§13.6): the collision grid with
	its props and fixture geometry, plus the interactions the fixtures bring.
	Pure logic, shared by the game, Haxen's checks and the tests.
**/
class Level {
	public final data:MapFile;
	public final map:GridMap;

	public function new(data:MapFile) {
		this.data = data;
		var sectors = new Map<String, Sector>();
		for (s in data.sectors)
			sectors.set(s.key, {
				name: s.name,
				floorZ: s.floorZ,
				ceilZ: s.ceilZ,
				floorTex: s.floorTex,
				ceilTex: s.ceilTex,
				wallTex: s.wallTex,
				upperTex: s.upperTex,
				shade: s.shade,
			});
		map = new GridMap(data.rows, sectors);
		for (p in data.props) map.props.push(Reflect.copy(p));
		for (f in data.fixtures) Fixtures.furnish(map, f.type, f.x, f.y);
	}

	public function has(type:String):Bool {
		for (f in data.fixtures) if (f.type == type) return true;
		return false;
	}

	public function fixtures(type:String):Array<FixtureDef> return [for (f in data.fixtures) if (f.type == type) f];

	public function atDesk(x:Float, y:Float, yaw:Float):Bool {
		for (f in fixtures("frontDesk")) if (Fixtures.atDesk(f.x, f.y, x, y, yaw)) return true;
		return false;
	}

	public function atDoor(x:Float, y:Float):Bool {
		for (f in fixtures("frontDoors")) if (Fixtures.atDoor(f.x, f.y, x, y)) return true;
		return false;
	}

	public function awayFromDoors(x:Float, y:Float):Bool {
		for (f in fixtures("frontDoors")) if (!Fixtures.awayFromDoor(f.x, f.y, x, y)) return false;
		return true;
	}

	public function belowStairs(x:Float, y:Float):Bool {
		for (f in fixtures("grandStairs")) if (Fixtures.belowStairs(f.x, f.y, x, y)) return true;
		return false;
	}

	public function atTable(x:Float, y:Float, yaw:Float):Bool {
		for (f in fixtures("cardTable")) if (Fixtures.atTable(f.x, f.y, x, y, yaw)) return true;
		return false;
	}

	/** Start facing, in radians. **/
	public var startYaw(get, never):Float;

	inline function get_startYaw():Float return data.start.facing * Math.PI / 180;
}
