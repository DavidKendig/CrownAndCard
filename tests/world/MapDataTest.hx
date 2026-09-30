// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import utest.Assert;
import world.MapData.MapFile;

class MapDataTest extends utest.Test {
	#if sys
	function manor():MapFile return MapData.parse(sys.io.File.getContent("res/maps/manor.json"));

	function testTheManorLoadsCleanly() {
		var m = manor();
		Assert.equals("Dodriec Manor", m.name);
		Assert.equals(57, m.rows.length);
		Assert.same([], [for (p in MapData.check(m)) p.message]);
		var level = new Level(m);
		// Generated furnishings include a sealed upper gallery and plants.
		Assert.equals(1, [for(p in level.map.props) if(p.kind=="galleryDeck") p].length);
		Assert.equals(6, level.map.plants.length);
		Assert.isTrue(level.atDesk(33, 4, Math.PI / 2));
		Assert.isTrue(level.atTable(33, 34.8, Math.PI / 2));
		Assert.isTrue(level.atDoor(33, 1.5));
		Assert.isTrue(level.belowStairs(33, 13.5));
	}

	function testRoundTrip() {
		var m = manor();
		Assert.equals(MapData.stringify(m), MapData.stringify(MapData.parse(MapData.stringify(m))));
	}
	function testWestWingBedroomsAreReachableAndBedsAreSolid() {
		var level = new Level(manor()), map = level.map;
		var beds = level.fixtures("fourPosterBed");
		Assert.equals(8, beds.length);
		Assert.equals("West Bedroom Corridor", map.sectorAtWorld(9.5,5).name);
		var rooms = new Map<String,Bool>();
		// Walk from the actual spawn, through the west foyer opening, then the
		// entire corridor. Sliding checks clearance with the player's radius.
		var position = {x:level.data.start.x,y:level.data.start.y};
		function walk(x:Float,y:Float) {
			position = map.slide(position.x,position.y,x-position.x,y-position.y,.25);
			Assert.floatEquals(x,position.x,.001);
			Assert.floatEquals(y,position.y,.001);
		}
		walk(level.data.start.x,5);
		walk(9.5,5);
		walk(9.5,33.5);
		for (bed in beds) {
			var room = map.sectorAtWorld(bed.x,bed.y);
			rooms.set(room.name,true);
			Assert.isTrue(StringTools.endsWith(room.name,"Bedroom"));
			Assert.equals("bedroomCarpet",room.floorTex);
			Assert.isTrue(bed.x < level.fixtures("frontDoors")[0].x);
			Assert.isTrue(map.blocked(bed.x,bed.y,.25));
			for (dx in [-1.1,1.1]) for (dy in [-1.16,1.16])
				Assert.isTrue(map.blocked(bed.x+dx,bed.y+dy,.25));
			var entryY = bed.y-1.8;
			walk(9.5,entryY);
			walk(bed.x,entryY);
			// Both sides and the space behind the headboard stay accessible.
			walk(bed.x-2.4,entryY);
			walk(bed.x-2.4,bed.y+1.65);
			walk(bed.x+2.4,bed.y+1.65);
			walk(bed.x+2.4,entryY);
			walk(9.5,entryY);
		}
		Assert.equals(8,[for (_ in rooms.keys()) 1].length);
		Assert.equals(4,map.windows.length); // Original exterior windows survived expansion.
	}
	function testBasementStairsDescendAndReturn() {
		var level=new Level(manor()), map=level.map;
		Assert.equals(1,level.fixtures("basementStairs").length);
		Assert.equals("Basement Stairwell",map.sectorAtWorld(9.5,36).name);
		var down=map.slide(9.5,33.5,0,7,.25,0);
		Assert.floatEquals(40.5,down.y,.001);
		Assert.floatEquals(-3.6,down.z,.001);
		Assert.equals("Old Basement",map.sectorAtWorld(down.x,down.y).name);
		Assert.isFalse(map.blocked(9.5,42,.25,down.z));
		Assert.isTrue(map.blocked(4.5,54.4,.25,down.z)); // boiler
		var up=map.slide(down.x,down.y,0,-7,.25,down.z);
		Assert.floatEquals(33.5,up.y,.001);
		Assert.floatEquals(0,up.z,.001);
	}
	function testLibraryEntranceAndBookcaseAisles() {
		var data=manor(),map=new Level(data).map;
		Assert.equals("Library",map.sectorAtWorld(56.5,34).name);
		for(i in 0...36) Assert.isFalse(map.blocked(56.5,30.5+i*.2,.25));
		for(i in 0...66) Assert.isFalse(map.blocked(50+i*.2,37.2,.25));
		var cases=[for(p in map.props) if(p.kind=="libraryShelf" || p.kind=="libraryShelfDouble") p];
		Assert.equals(10,cases.length);
		for(p in cases) Assert.isTrue(map.blocked((p.x0+p.x1)/2,(p.y0+p.y1)/2,.25));
	}
	function testBathroomAccessAndFixtureClearance() {
		var data=manor(),map=new Level(data).map;
		Assert.equals("Bathroom",map.sectorAtWorld(42,34).name);
		for(i in 0...16) Assert.isFalse(map.blocked(39.5,30.5+i*.2,.25));
		for(i in 0...21) Assert.isFalse(map.blocked(39.5+i*.2,33.5,.25));
		for(i in 0...16) Assert.isFalse(map.blocked(43.5,33.5+i*.2,.25));
		for(i in 0...14) Assert.isFalse(map.blocked(43.5+i*.2,36.5,.25));
		for(kind in ["bathroomSink","bathroomToilet","bathroomRoll"]) {
			var fixtures=[for(p in map.props) if(p.kind==kind) p];
			Assert.equals(1,fixtures.length);
			var p=fixtures[0];
			Assert.isTrue(map.blocked((p.x0+p.x1)/2,(p.y0+p.y1)/2,.25));
		}
		Assert.isFalse(map.blocked(42.7,36.8,.25));
		Assert.isFalse(map.blocked(46.1,36.7,.25));
	}
	function testSecurityRoomEntranceAndEquipment() {
		var data=manor(),map=new Level(data).map;
		Assert.equals("Security Room",map.sectorAtWorld(44,25).name);
		for(i in 0...46) Assert.isFalse(map.blocked(43.5,20.5+i*.2,.25));
		Assert.equals(1,[for(p in map.props) if(p.kind=="securityVhs") p].length);
		Assert.equals(1,[for(p in map.props) if(p.kind=="securityMonitors") p].length);
		Assert.isTrue(map.blocked(43.5,30.4,.25));
		Assert.isFalse(map.blocked(44.5,29.2,.25));
	}
	function testSalonConnectsToKitchenAndHasRoundTables() {
		var data=manor(), map=new Level(data).map;
		Assert.equals("Midnight Salon",map.sectorAtWorld(23,25).name);
		// The kitchen exit and east-side salon aisle reach the bar without obstacles.
		for (i in 0...66) Assert.isFalse(map.blocked(24.6,18.5+i*.2,.25));
		var tables=[for(p in map.props) if(p.kind=="salonTable") p];
		Assert.equals(3,tables.length);
		for(p in tables) {
			Assert.isTrue(map.blocked((p.x0+p.x1)/2,(p.y0+p.y1)/2,.25));
			// Southeast corners open onto the aisle; the north end has bar stools.
			Assert.isFalse(map.blocked(p.x1+.15,p.y0-.15,.25));
		}
		var staff=[for(g in data.guests) if(g.art=="bartender") g];
		Assert.equals(1,staff.length);
		Assert.isFalse(map.blocked(staff[0].x,staff[0].y,.25));
		var singer=[for(g in data.guests) if(g.art=="salon-singer") g];
		Assert.equals(1,singer.length);
		Assert.isFalse(map.blocked(singer[0].x,singer[0].y,.25));
		Assert.same([], [for(p in MapData.check(data)) p.message]);
	}
	function testKitchenAccessAndStaffClearance() {
		var m = manor(), map = new Level(m).map;
		Assert.equals("Kitchen", map.sectorAtWorld(25.8, 17).name);
		// Enter from the foyer and reach the prep area without hitting the range.
		for (i in 0...26) Assert.isFalse(map.blocked(26.3, 13.5 + i * .2, .25));
		// The original northbound route beside the stair ropes remains open.
		for (i in 0...31) Assert.isFalse(map.blocked(27.5, 14 + i * .2, .25));
		var staff = [for (g in m.guests) if (StringTools.startsWith(g.name, "Kitchen ")) g];
		Assert.equals(4, staff.length);
		Assert.equals(2, [for (g in staff) if (g.art == "chef") g].length);
		for (g in staff) Assert.isFalse(map.blocked(g.x, g.y, .25));
		Assert.isTrue(map.blocked(23.6, 17.5, .25));
		Assert.isTrue(map.blocked(23.6, 15.3, .25)); // freezer body
		Assert.isFalse(map.blocked(24.6, 15.3, .25)); // space to approach its doors
	}
	/** The empty chair at the Private Party table is where multiplayer starts (§13.13). **/
	function testPrivateTableSeat() {
		var level = new Level(manor());
		Assert.isTrue(level.atPrivateTable(56, 24, Math.PI / 2)); // at the chair, facing the table
		Assert.isTrue(level.atPrivateTable(56.5, 23.4, Math.PI / 2));
		Assert.isFalse(level.atPrivateTable(56, 24, -Math.PI / 2)); // back to the table
		Assert.isFalse(level.atPrivateTable(53, 24, Math.PI / 2)); // another guest's place
		Assert.isFalse(level.atTable(56, 24, Math.PI / 2));
	}

	function testPrivatePartyEntranceAndSeating() {
		var m=manor(), level=new Level(m), map=level.map;
		Assert.equals("Private Party",map.sectorAtWorld(56,25).name);
		Assert.floatEquals(4.7,RainShelter.base(map,56,25));
		Assert.floatEquals(7.2,RainShelter.base(map,56,18.5));
		Assert.floatEquals(4.7,RainShelter.base(map,56,20));
		Assert.floatEquals(0,RainShelter.base(map,65,25));
		// Walk the main-hall passage between the two sentries, then into the salon.
		for(i in 0...61) Assert.isFalse(map.blocked(42+i*.2,20.5,.25));
		var guards=[for(g in m.guests) if(StringTools.startsWith(g.art,"security_")) g];
		Assert.equals(2,guards.length);
		for(g in guards) {Assert.isTrue(g.turns);Assert.isNull(g.walkTo);}
		var chair=[for(g in m.guests) if(g.art=="party_chair") g][0];
		Assert.equals(56,chair.x);
		Assert.equals(24,chair.y);
		Assert.isFalse(map.blocked(chair.x,chair.y,.25));
		Assert.equals(4,[for(g in m.guests) if(g.x>=49 && StringTools.endsWith(g.art,"_seated")) g].length);
	}
	#end

	function testBlankMapIsPlayable() {
		var m = MapData.blank("Test Parlour");
		var problems = MapData.check(m);
		Assert.isFalse(MapData.hasErrors(problems));
		Assert.equals(1, problems.length); // no front desk: a warning only
	}

	function testChecksCatchBrokenMaps() {
		function errors(change:MapFile->Void):Array<String> {
			var m = MapData.blank("Broken");
			change(m);
			return [for (p in MapData.check(m)) if (p.error) p.message];
		}
		Assert.equals(1, errors(m -> m.rows[3] = "#aaaaaaazaaaaaa#").length); // unknown room key
		Assert.equals(1, errors(m -> m.rows[2] = "#aa#").length); // ragged row
		Assert.equals(1, errors(m -> m.start = {x: 0.5, y: 0.5, facing: 0}).length); // start in a wall
		Assert.equals(1, errors(m -> m.sectors[0].floorTex = "lava").length);
		Assert.equals(1, errors(m -> m.name = "bad/name").length);
		Assert.equals(1, errors(m -> m.fixtures.push({type: "moat", x: 5, y: 5})).length);
		Assert.equals(0, errors(m -> m.props.push({x0: 3, y0: 3, x1: 5, y1: 5, height: 1, topTex: "stone", sideTex: "stone"})).length); // a fine prop
		// A prop right on the start point blocks it.
		Assert.equals(1, errors(m -> m.props.push({x0: 7, y0: 1.5, x1: 9, y1: 2.5, height: 1, topTex: "stone", sideTex: "stone"})).length);
	}

	function testGuestTurning() {
		function guestWith(fields:String) {
			var raw:Dynamic = haxe.Json.parse(MapData.stringify(MapData.blank("Turning")));
			raw.guests = [haxe.Json.parse('{"name": "G", "x": 5, "y": 5, "facing": 90, "art": "masked_guest"$fields}')];
			return MapData.parse(haxe.Json.stringify(raw)).guests[0];
		}
		var still = guestWith("");
		Assert.isNull(still.turns);
		Assert.isNull(still.spins);
		Assert.isTrue(guestWith(', "turns": true').turns);
		Assert.isTrue(guestWith(', "spins": true').spins);
		// Turning to face the player wins over spinning.
		var both = guestWith(', "turns": true, "spins": true');
		Assert.isTrue(both.turns);
		Assert.isNull(both.spins);
	}

	function testParseRejectsOtherFiles() {
		Assert.raises(() -> MapData.parse("{}"));
		Assert.raises(() -> MapData.parse("not json"));
		Assert.raises(() -> MapData.parse('{"format":"crown-and-card-map","version":99}'));
	}

	function testNames() {
		Assert.isTrue(MapData.validName("My Manor_2"));
		for (bad in ["", " lead", "a/b", "..", StringTools.lpad("", "x", 41)]) Assert.isFalse(MapData.validName(bad));
	}
}
