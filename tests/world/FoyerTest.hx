// SPDX-License-Identifier: AGPL-3.0-or-later
package world;
import utest.Assert;

/** The Entrance Hall's fixtures, placed where the manor has them. */
class FoyerTest extends utest.Test {
	static final START = {x: 13.0, y: 4.0, yaw: Math.PI / 2};
	function map():GridMap {
		var s={name:"Foyer",floorZ:0.,ceilZ:8.,floorTex:"",ceilTex:"",wallTex:"",upperTex:"",shade:0.};
		var rows=[for(_ in 0...24) "##########################"];
		for(y in 1...23) rows[y]="#eeeeeeeeeeeeeeeeeeeeeeee#";
		var m=new GridMap(rows,["e"=>s]);
		Fixtures.furnish(m,"frontDesk",13,6.7);
		Fixtures.furnish(m,"fountain",13,11);
		Fixtures.furnish(m,"grandStairs",13,14.5);
		return m;
	}
	function testSpawnAndInteractions() {
		var m=map(), s=START;
		Assert.isFalse(m.blocked(s.x,s.y,.25)); Assert.isTrue(Fixtures.atDesk(13,6.7,s.x,s.y,s.yaw));
		Assert.isFalse(Fixtures.atDesk(13,6.7,s.x,s.y,-Math.PI/2));
		Assert.isTrue(Fixtures.atDoor(13,1,13,1.5)); Assert.isFalse(Fixtures.atDoor(13,1,s.x,s.y));
		Assert.isTrue(m.blocked(13,6.5,.25)); Assert.isTrue(m.blocked(13,11,.25));
	}
	function testRopesBlockFrontAndSidesWithoutTunnelling() {
		var m=map();
		Assert.isTrue(m.slide(10,13,0,5,.25).y<13.9);
		Assert.isTrue(m.slide(7,16,5,0,.25).x<8.6);
		Assert.isTrue(m.slide(19,16,-5,0,.25).x>17.4);
	}
	function testRemovingRopesMakesStairsTraversableBothWays() {
		var m=map();
		for(p in m.props.copy()) if(p.kind=="rope") m.props.remove(p);
		var p=m.slide(13,14.2,0,6.6,.25);
		Assert.floatEquals(20.8,p.y,.001); Assert.floatEquals(3.6,m.floorAt(p.x,p.y),.001);
		p=m.slide(p.x,p.y,0,-6.6,.25);
		Assert.floatEquals(14.2,p.y,.001); Assert.floatEquals(0,m.floorAt(p.x,p.y),.001);
	}
	function testCannotStepOffHighStairSide() {
		var m=map();
		for(p in m.props.copy()) if(p.kind=="rope") m.props.remove(p);
		Assert.isTrue(m.slide(9.1,19,-1,0,.25).x>=9);
	}
	function testFountainCollisionFollowsCircularRim() {
		var m=map();
		Assert.isTrue(m.blocked(14.8,11,.25));
		Assert.isFalse(m.blocked(14.8,12.8,.25));
		Assert.isTrue(m.slide(16,11,-3,0,.25).x>=14.97);
	}
	function testFixturesFollowTheirAnchor() {
		// The same desk moved 20 m east and 3 m north checks in from the matching spot.
		Assert.isTrue(Fixtures.atDesk(33,9.7,33,7,Math.PI/2));
		Assert.isFalse(Fixtures.atDesk(33,9.7,13,4,Math.PI/2));
		Assert.isTrue(Fixtures.atTable(40,10,40,9.2,Math.PI/2));
	}
}
