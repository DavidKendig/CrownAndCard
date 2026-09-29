// SPDX-License-Identifier: AGPL-3.0-or-later
package games;
import utest.Assert;
import games.slots.LeverPhysics;

class LeverPhysicsTest extends utest.Test {
	function testShortPullReturnsWithoutTrigger() {
		var lever=new LeverPhysics(),count=0;
		lever.grab();lever.drag(.7);
		for(i in 0...60) if(lever.update(1/60)) count++;
		Assert.isTrue(lever.angle>.4 && lever.angle<.7);
		lever.release();
		for(i in 0...300) if(lever.update(1/60)) count++;
		Assert.equals(0,count);Assert.floatEquals(0,lever.angle,.002);Assert.isFalse(lever.latched);
	}
	function testOneTriggerPerFullPullAndRearmsAtRest() {
		for(rate in [30,60,144]) {
			var lever=new LeverPhysics(),count=0;
			lever.grab();lever.drag(9);
			for(i in 0...rate*2) {if(lever.update(1/rate)) count++;Assert.isTrue(lever.angle>=0 && lever.angle<=LeverPhysics.MAX_ANGLE);}
			Assert.equals(1,count);Assert.isTrue(lever.latched);
			lever.release();for(i in 0...rate*5) if(lever.update(1/rate)) count++;
			Assert.equals(1,count);Assert.isFalse(lever.latched);Assert.floatEquals(0,lever.angle,.002);
			lever.pull();for(i in 0...rate*6) if(lever.update(1/rate)) count++;
			Assert.equals(2,count);Assert.isFalse(lever.held);Assert.floatEquals(0,lever.angle,.002);
		}
	}
	function testReleaseKeepsMomentumAndSpringReturns() {
		var lever=new LeverPhysics();lever.grab();lever.drag(2);lever.update(.08);
		var angle=lever.angle,speed=lever.velocity;lever.release();
		Assert.isTrue(speed>0);Assert.floatEquals(speed,lever.velocity);
		lever.update(.01);Assert.isTrue(lever.angle>angle);
		for(i in 0...600) lever.update(1/120);
		Assert.floatEquals(0,lever.angle,.002);
	}
	function testFixedStepMatchesAcrossFrameRates() {
		var a=new LeverPhysics(),b=new LeverPhysics();a.grab();b.grab();a.drag(1.2);b.drag(1.2);
		for(i in 0...30) a.update(1/30);for(i in 0...120) b.update(1/120);
		Assert.floatEquals(a.angle,b.angle,.001);Assert.floatEquals(a.velocity,b.velocity,.001);
	}
}
