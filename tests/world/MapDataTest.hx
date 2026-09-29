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
		Assert.equals(40, m.rows.length);
		Assert.same([], [for (p in MapData.check(m)) p.message]);
		var level = new Level(m);
		// Generated furnishings include a sealed upper gallery and plants.
		Assert.equals(1, [for(p in level.map.props) if(p.kind=="galleryDeck") p].length);
		Assert.equals(6, level.map.plants.length);
		Assert.isTrue(level.atDesk(13, 4, Math.PI / 2));
		Assert.isTrue(level.atTable(13, 34.8, Math.PI / 2));
		Assert.isTrue(level.atDoor(13, 1.5));
		Assert.isTrue(level.belowStairs(13, 13.5));
	}

	function testRoundTrip() {
		var m = manor();
		Assert.equals(MapData.stringify(m), MapData.stringify(MapData.parse(MapData.stringify(m))));
	}
	function testLibraryEntranceAndBookcaseAisles() {
		var data=manor(),map=new Level(data).map;
		Assert.equals("Library",map.sectorAtWorld(36.5,34).name);
		for(i in 0...36) Assert.isFalse(map.blocked(36.5,30.5+i*.2,.25));
		for(i in 0...66) Assert.isFalse(map.blocked(30+i*.2,37.2,.25));
		var cases=[for(p in map.props) if(p.kind=="libraryShelf" || p.kind=="libraryShelfDouble") p];
		Assert.equals(10,cases.length);
		for(p in cases) Assert.isTrue(map.blocked((p.x0+p.x1)/2,(p.y0+p.y1)/2,.25));
	}
	function testBathroomAccessAndFixtureClearance() {
		var data=manor(),map=new Level(data).map;
		Assert.equals("Bathroom",map.sectorAtWorld(22,34).name);
		for(i in 0...16) Assert.isFalse(map.blocked(19.5,30.5+i*.2,.25));
		for(i in 0...21) Assert.isFalse(map.blocked(19.5+i*.2,33.5,.25));
		for(i in 0...16) Assert.isFalse(map.blocked(23.5,33.5+i*.2,.25));
		for(i in 0...14) Assert.isFalse(map.blocked(23.5+i*.2,36.5,.25));
		for(kind in ["bathroomSink","bathroomToilet","bathroomRoll"]) {
			var fixtures=[for(p in map.props) if(p.kind==kind) p];
			Assert.equals(1,fixtures.length);
			var p=fixtures[0];
			Assert.isTrue(map.blocked((p.x0+p.x1)/2,(p.y0+p.y1)/2,.25));
		}
		Assert.isFalse(map.blocked(22.7,36.8,.25));
		Assert.isFalse(map.blocked(26.1,36.7,.25));
	}
	function testSecurityRoomEntranceAndEquipment() {
		var data=manor(),map=new Level(data).map;
		Assert.equals("Security Room",map.sectorAtWorld(24,25).name);
		for(i in 0...46) Assert.isFalse(map.blocked(23.5,20.5+i*.2,.25));
		Assert.equals(1,[for(p in map.props) if(p.kind=="securityVhs") p].length);
		Assert.equals(1,[for(p in map.props) if(p.kind=="securityMonitors") p].length);
		Assert.isTrue(map.blocked(23.5,30.4,.25));
		Assert.isFalse(map.blocked(24.5,29.2,.25));
	}
	function testSalonConnectsToKitchenAndHasRoundTables() {
		var data=manor(), map=new Level(data).map;
		Assert.equals("Midnight Salon",map.sectorAtWorld(3,25).name);
		// The kitchen exit and east-side salon aisle reach the bar without obstacles.
		for (i in 0...66) Assert.isFalse(map.blocked(4.6,18.5+i*.2,.25));
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
		Assert.equals("Kitchen", map.sectorAtWorld(5.8, 17).name);
		// Enter from the foyer and reach the prep area without hitting the range.
		for (i in 0...26) Assert.isFalse(map.blocked(6.3, 13.5 + i * .2, .25));
		// The original northbound route beside the stair ropes remains open.
		for (i in 0...31) Assert.isFalse(map.blocked(7.5, 14 + i * .2, .25));
		var staff = [for (g in m.guests) if (StringTools.startsWith(g.name, "Kitchen ")) g];
		Assert.equals(4, staff.length);
		Assert.equals(2, [for (g in staff) if (g.art == "chef") g].length);
		for (g in staff) Assert.isFalse(map.blocked(g.x, g.y, .25));
		Assert.isTrue(map.blocked(3.6, 17.5, .25));
		Assert.isTrue(map.blocked(3.6, 15.3, .25)); // freezer body
		Assert.isFalse(map.blocked(4.6, 15.3, .25)); // space to approach its doors
	}
	/** The empty chair at the Private Party table is where multiplayer starts (§13.13). **/
	function testPrivateTableSeat() {
		var level = new Level(manor());
		Assert.isTrue(level.atPrivateTable(36, 24, Math.PI / 2)); // at the chair, facing the table
		Assert.isTrue(level.atPrivateTable(36.5, 23.4, Math.PI / 2));
		Assert.isFalse(level.atPrivateTable(36, 24, -Math.PI / 2)); // back to the table
		Assert.isFalse(level.atPrivateTable(33, 24, Math.PI / 2)); // another guest's place
		Assert.isFalse(level.atTable(36, 24, Math.PI / 2));
	}

	function testPrivatePartyEntranceAndSeating() {
		var m=manor(), level=new Level(m), map=level.map;
		Assert.equals("Private Party",map.sectorAtWorld(36,25).name);
		Assert.floatEquals(4.7,RainShelter.base(map,36,25));
		Assert.floatEquals(7.2,RainShelter.base(map,36,18.5));
		Assert.floatEquals(4.7,RainShelter.base(map,36,20));
		Assert.floatEquals(0,RainShelter.base(map,45,25));
		// Walk the main-hall passage between the two sentries, then into the salon.
		for(i in 0...61) Assert.isFalse(map.blocked(22+i*.2,20.5,.25));
		var guards=[for(g in m.guests) if(StringTools.startsWith(g.art,"security_")) g];
		Assert.equals(2,guards.length);
		for(g in guards) {Assert.isTrue(g.turns);Assert.isNull(g.walkTo);}
		var chair=[for(g in m.guests) if(g.art=="party_chair") g][0];
		Assert.equals(36,chair.x);
		Assert.equals(24,chair.y);
		Assert.isFalse(map.blocked(chair.x,chair.y,.25));
		Assert.equals(4,[for(g in m.guests) if(g.x>=29 && StringTools.endsWith(g.art,"_seated")) g].length);
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
