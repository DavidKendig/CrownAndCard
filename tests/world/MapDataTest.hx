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
