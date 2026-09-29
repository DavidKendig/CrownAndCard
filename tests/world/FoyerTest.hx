// SPDX-License-Identifier: AGPL-3.0-or-later
package world;
import utest.Assert;

/** The Entrance Hall's fixtures, placed where the manor has them. */
class FoyerTest extends utest.Test {
	function testOneSpecialTreeAndStableRandomFlips() {
		var launch = [for (i in 0...CourtyardTrees.TOTAL) {texture:CourtyardTrees.textureName(i),flipped:CourtyardTrees.flipped(i)}];
		var variants = new Map<String,Bool>(), locations = new Map<Int,Bool>();
		var orientations = new Map<Int,Bool>();
		for (seed in 1...101) {
			var key = haxe.io.Bytes.alloc(32);
			key.setInt32(0,seed);
			var chosen = CourtyardTrees.choose(rng.ChaChaRng.fromSeed(key));
			Assert.equals(72, chosen.length);
			Assert.same(chosen, CourtyardTrees.choose(rng.ChaChaRng.fromSeed(key)));
			var count = 0;
			for (i in 0...chosen.length) {
				var tree = chosen[i];
				if (tree.texture == "tall-cedar-fbi") Assert.isFalse(tree.flipped);
				orientations.set(tree.flipped ? 1 : 0,true);
				if (CourtyardTrees.SPECIALS.indexOf(tree.texture) >= 0) {
					count++; variants.set(tree.texture,true); locations.set(i,true);
				} else Assert.equals(i % 2 == 0 ? "tall-cedar" : "tall-cypress", tree.texture);
			}
			Assert.equals(1, count);
		}
		Assert.equals(5,[for (_ in variants.keys()) 1].length);
		Assert.isTrue([for (_ in locations.keys()) 1].length > 1);
		Assert.equals(2,[for (_ in orientations.keys()) 1].length);
		Assert.same(launch, [for (i in 0...CourtyardTrees.TOTAL) {texture:CourtyardTrees.textureName(i),flipped:CourtyardTrees.flipped(i)}]);
		Assert.equals(1,[for (tree in launch) if (CourtyardTrees.SPECIALS.indexOf(tree.texture) >= 0) tree].length);
	}
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
	function testWindowOpeningsKeepCollisionAndRequireExteriorWall() {
		var m=map();
		var windows=FoyerWindows.layout(m,13,1);
		Assert.equals(4,windows.length);
		for(w in windows) {
			Assert.equals(2.0,w.x1-w.x0);
			Assert.isTrue(w.bottom>1 && w.top<8);
			Assert.isTrue(m.blocked((w.x0+w.x1)/2,.95,.25));
			Assert.isTrue(m.slide((w.x0+w.x1)/2,2,0,-3,.25).y>=1.25);
		}
		Assert.equals(0,FoyerWindows.layout(m,13,5).length);
		Assert.equals(0,FoyerWindows.layout(m,100,1).length);
	}
	function testFountainStreamsAccelerateAndLandInsideBowls() {
		for(tier in [{r0:1.,z0:1.84,r1:1.30,z1:.48,bowl:1.46},{r0:.56,z0:2.74,r1:.79,z1:1.84,bowl:.94}]) {
			var duration=FountainFlow.flightTime(tier.z0,tier.z1);
			var start=FountainFlow.position(tier.r0,tier.z0,tier.r1,tier.z1,0);
			var mid=FountainFlow.position(tier.r0,tier.z0,tier.r1,tier.z1,duration/2);
			var end=FountainFlow.position(tier.r0,tier.z0,tier.r1,tier.z1,duration);
			Assert.floatEquals(tier.z0,start.z);
			Assert.floatEquals(tier.z1,end.z);
			Assert.floatEquals(tier.r1,end.r);
			Assert.floatEquals((tier.z0-tier.z1)/4,tier.z0-mid.z);
			Assert.isTrue(end.r<tier.bowl);
			var speed=(tier.r1-tier.r0)/duration,w0=FountainFlow.width(speed,0),w1=FountainFlow.width(speed,duration);
			Assert.isTrue(w1<w0);
			Assert.floatEquals(w0*w0*speed,w1*w1*Math.sqrt(speed*speed+Math.pow(FountainFlow.GRAVITY*duration,2)),.000001);
		}
	}
	function testFountainSplashReturnsToSurface() {
		var up=1.19,life=2*up/FountainFlow.GRAVITY;
		Assert.floatEquals(0,FountainFlow.splashHeight(up,0));
		Assert.isTrue(FountainFlow.splashHeight(up,life/2)>.06);
		Assert.floatEquals(0,FountainFlow.splashHeight(up,life),.000001);
		Assert.floatEquals(0,FountainFlow.splashHeight(up,life+1));
	}
}
