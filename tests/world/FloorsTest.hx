// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import utest.Assert;
import world.MapData.MapFile;

/** Floors above and below the ground floor (§13.6): the format, the stacked grid, and walking between storeys. **/
class FloorsTest extends utest.Test {
	static inline var R = 0.25;
	static inline var STEP = 0.037; // one walking frame at 60 fps

	/** 12 × 12 cells from a rule; walls all round. **/
	static function plan(cell:(Int, Int) -> String):Array<String> {
		return [for (r in 0...12) {
			var cy = 11 - r, line = "";
			for (cx in 0...12) line += cx == 0 || cy == 0 || cx == 11 || cy == 11 ? "#" : cell(cx, cy);
			line;
		}];
	}

	static function room(key:String, name:String, floorZ:Float, ceilZ:Float):MapData.SectorDef
		return {key: key, name: name, floorZ: floorZ, ceilZ: ceilZ, floorTex: "parquet", ceilTex: "coffer", wallTex: "damask", upperTex: "damaskUpper", shade: 8};

	/**
		Three storeys over one grid. Ground floor: a hall, and a stairwell (x 4-7,
		y 2-7) whose stone stairs go down 3.6 m. Basement, 3.6 m down: a cellar
		north of the stairs (y 8-10). First floor, 3.6 m up: a study over the
		north of the hall, with the front desk in it.
	**/
	static function house():MapFile {
		var m = MapData.blank("House", 12, 12);
		m.sectors = [room("a", "Hall", 0, 3.5), room("t", "Stairwell", -3.6, 3.4), room("c", "Cellar", 0, 3.5), room("u", "Study", 0, 3)];
		m.rows = plan((cx, cy) -> cx >= 4 && cx <= 7 && cy >= 2 && cy <= 7 ? "t" : "a");
		m.floors = [
			{level: -1, name: "Basement", elevation: -3.6, rows: plan((cx, cy) -> cy >= 8 && cy <= 10 ? "c" : "#")},
			{level: 1, name: "First floor", elevation: 3.6, rows: plan((cx, cy) -> cy >= 6 && cy <= 10 ? "u" : "#")},
		];
		m.fixtures = [{type: "basementStairs", x: 6, y: 2}, {type: "frontDesk", x: 5.5, y: 9.5, floor: 1}];
		m.lights = [{x: 5, y: 8, z: 3, radius: 6, power: 8, floor: 1}];
		m.props = [{x0: 2, y0: 9, x1: 3, y1: 10, height: .9, baseZ: 0, topTex: "tableWood", sideTex: "tableWood", floor: 1}];
		m.start = {x: 6, y: 1.5, facing: 90};
		return m;
	}

	static function errors(m:MapFile):Array<String>
		return [for (p in MapData.check(m)) if (p.error) p.message];

	static function warnings(m:MapFile):Array<String>
		return [for (p in MapData.check(m)) if (!p.error) p.message];

	function testAOneFloorMapIsStillVersion1() {
		var text = MapData.stringify(MapData.blank("Flat"));
		Assert.isTrue(text.indexOf('"version": 1') >= 0);
		Assert.equals(-1, text.indexOf('"floors"'));
		Assert.equals(-1, text.indexOf('"floor"'));
	}

	function testFloorsRoundTrip() {
		var m = house();
		var text = MapData.stringify(m);
		Assert.isTrue(text.indexOf('"version": 2') >= 0);
		var back = MapData.parse(text);
		Assert.equals(2, back.floors.length);
		Assert.equals(1, back.fixtures[1].floor);
		Assert.isNull(back.fixtures[0].floor);
		Assert.equals(1, back.lights[0].floor);
		Assert.equals(1, back.props[0].floor);
		var again = MapData.stringify(back);
		Assert.equals(again, MapData.stringify(MapData.parse(again)));
	}

	function testTheHouseChecksClean() {
		Assert.same([], errors(house()));
		Assert.same([], warnings(house()));
	}

	function testEachStoreyIsItsOwnRoomOverTheSameCell() {
		var level = new Level(house());
		// x 5.5, y 9.5: the cellar, the hall and the study are stacked.
		Assert.equals("Cellar", level.map.sectorAtWorld(5.5, 9.5, -3.6).name);
		Assert.equals("Hall", level.map.sectorAtWorld(5.5, 9.5, 0).name);
		Assert.equals("Study", level.map.sectorAtWorld(5.5, 9.5, 3.6).name);
		Assert.equals(-1, level.map.levelAt(5.5, 9.5, -3.6));
		Assert.equals(1, level.map.levelAt(5.5, 9.5, 3.6));
		// Without a height, a cell is the ground floor's, as before floors.
		Assert.equals("Hall", level.map.sectorAtWorld(5.5, 9.5).name);
		// Rooms carry world heights.
		Assert.floatEquals(-3.6, level.map.sectorAtWorld(5.5, 9.5, -3.6).floorZ);
		Assert.floatEquals(6.6, level.map.sectorAtWorld(5.5, 9.5, 3.6).ceilZ);
	}

	function testWallsBelongToTheirStorey() {
		var map = new Level(house()).map;
		// The first floor is solid over the south of the hall: a wall up there, open floor down here.
		Assert.isTrue(map.blocked(2.5, 2.5, R, 3.6));
		Assert.isFalse(map.blocked(2.5, 2.5, R, 0));
		// The basement is solid beside the stairwell.
		Assert.isTrue(map.blocked(3.5, 4.5, R, -2));
	}

	function testWalkingDownTheBasementStairsAndBackUp() {
		var map = new Level(house()).map;
		var x = 6.0, y = 1.5, z = map.floorAt(x, y);
		Assert.floatEquals(0, z);
		for (_ in 0...400) {
			var p = map.slide(x, y, 0, STEP, R, z);
			x = p.x;
			y = p.y;
			z = p.z;
		}
		Assert.isTrue(y > 9, 'walked to y $y');
		Assert.floatEquals(-3.6, z);
		Assert.equals("Cellar", map.sectorAtWorld(x, y, z).name);
		Assert.equals(-1, map.levelAt(x, y, z));
		for (_ in 0...400) {
			var p = map.slide(x, y, 0, -STEP, R, z);
			x = p.x;
			y = p.y;
			z = p.z;
		}
		Assert.isTrue(y < 2, 'walked back to y $y');
		Assert.floatEquals(0, z);
		Assert.equals("Hall", map.sectorAtWorld(x, y, z).name);
	}

	function testThingsOnAFloorStandAtItsHeight() {
		var level = new Level(house());
		Assert.floatEquals(6.6, level.lights[0].z);
		var table = [for (p in level.map.props) if (p.topTex == "tableWood" && p.x0 == 2) p][0];
		Assert.floatEquals(3.6, table.baseZ);
		Assert.floatEquals(4.5, table.height);
		// The desk's counter is raised with it.
		var counter = [for (p in level.map.props) if (p.topTex == "stone" && p.y0 < 9.5 && p.y1 > 9.5 && p.baseZ != null && p.baseZ > 4) p];
		Assert.equals(1, counter.length);
	}

	function testFixturesWorkOnlyOnTheirFloor() {
		var level = new Level(house());
		var north = Math.PI / 2;
		Assert.isTrue(level.atDesk(5.5, 7.5, north, 3.6));
		Assert.isFalse(level.atDesk(5.5, 7.5, north, 0));
		Assert.isTrue(level.atDesk(5.5, 7.5, north)); // without a height: any floor, as before floors
	}

	function testStartingUpstairs() {
		var m = house();
		m.start = {x: 5.5, y: 7.5, facing: 90, floor: 1};
		var level = new Level(m);
		Assert.floatEquals(3.6, level.startFeetZ());
		Assert.same([], errors(m));
	}

	function testRoomsOnTwoFloorsCantFillTheSameSpace() {
		var m = house();
		m.sectors[0].ceilZ = 5; // the hall now rises through the study
		var e = errors(m);
		Assert.equals(1, e.length);
		Assert.isTrue(e[0].indexOf("fill the same space") >= 0, e[0]);
	}

	function testATallRoomUnderWallsIsFlagged() {
		var m = house();
		m.sectors[1].ceilZ = 5; // the stairwell rises into the first floor's solid cells
		var w = warnings(m);
		Assert.equals(1, w.length);
		Assert.isTrue(w[0].indexOf("rises into") >= 0, w[0]);
	}

	function testGalleryOverAHall() {
		// A 7.5 m hall (y 2-10) with a low room under a first-floor balcony (y 1).
		var m = MapData.blank("Gallery", 12, 12);
		m.sectors = [room("h", "Great hall", 0, 7.5), room("l", "Arcade", 0, 3.5), room("b", "Balcony", 0, 3)];
		m.rows = plan((cx, cy) -> cy == 1 ? "l" : "h");
		m.floors = [{level: 1, name: "Gallery", elevation: 3.6, rows: plan((cx, cy) -> cy == 1 ? "b" : ".")}];
		Assert.same([], errors(m));
		Assert.equals(0, [for (w in warnings(m)) if (w.indexOf("open to the floor below") >= 0) w].length);
		var map = new Level(m).map;
		Assert.equals("Balcony", map.sectorAtWorld(5.5, 1.5, 3.6).name);
		// Looking out over the hall from the balcony: open, but it's a drop, so you stay up.
		Assert.equals("Great hall", map.sectorAtWorld(5.5, 4.5, 3.6).name);
		var x = 5.5, y = 1.5, z = 3.6;
		for (_ in 0...200) {
			var p = map.slide(x, y, 0, STEP, R, z);
			y = p.y;
			z = p.z;
		}
		Assert.isTrue(y < 2, 'stopped at the edge, y $y');
		Assert.floatEquals(3.6, z);
		// Down in the hall, the gallery's cells are open: nothing blocks.
		Assert.isFalse(map.blocked(5.5, 4.5, R, 0));
	}

	function testOpenCellsNeedARoomBelowThatReachesUp() {
		var m = MapData.blank("Hole", 12, 12);
		m.sectors = [room("a", "Room", 0, 3.5), room("u", "Upstairs", 0, 3)];
		m.floors = [{level: 1, name: "Upstairs", elevation: 3.6, rows: plan((cx, cy) -> cx == 5 && cy == 5 ? "." : "u")}];
		var w = [for (w in warnings(m)) if (w.indexOf("open to the floor below") >= 0) w];
		Assert.equals(1, w.length);
	}

	function testFloorsMustStackInOrder() {
		var m = house();
		m.floors[1].elevation = -5; // the first floor below the basement
		Assert.isTrue(errors(m).length > 0);
	}

	function testThingsMustBeOnAFloorTheMapHas() {
		var m = house();
		m.guests = [{name: "Lost", x: 5, y: 5, facing: 0, art: "masked_guest", floor: 7}];
		Assert.equals(1, errors(m).length);
	}

	function testAsManyFloorsAsYouLikeBothWays() {
		var m = MapData.blank("Tower", 12, 12);
		m.sectors = [room("a", "Room", 0, 3.5)];
		for (k in 1...41) for (sign in [1, -1])
			m.floors.push({level: k * sign, name: 'Floor ${k * sign}', elevation: k * sign * MapData.STOREY, rows: plan((cx, cy) -> "a")});
		Assert.same([], errors(m));
		var map = new Level(MapData.parse(MapData.stringify(m))).map;
		Assert.equals(81, map.layers.length);
		Assert.equals(40, map.levelAt(5.5, 5.5, 40 * MapData.STOREY));
		Assert.equals(-40, map.levelAt(5.5, 5.5, -40 * MapData.STOREY));
		Assert.equals(-17, map.levelAt(5.5, 5.5, -17 * MapData.STOREY + 1));
	}

	#if sys
	function testTheManorIsUnchanged() {
		var manor = MapData.parse(sys.io.File.getContent("res/maps/manor.json"));
		Assert.equals(0, manor.floors.length);
		Assert.equals(1, new Level(manor).map.layers.length);
	}
	#end
}
