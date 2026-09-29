// SPDX-License-Identifier: AGPL-3.0-or-later
package games;
import utest.Assert;
import games.roulette.WheelMotion;

class WheelMotionTest extends utest.Test {
	function testEveryPocketAtDifferentFrameRates() {
		Assert.equals(37,WheelMotion.POCKETS.length);
		for(n in 0...37) for(dt in [1/30,1/60,.137,20.]) {
			var m=new WheelMotion();m.start(n);
			while(m.active) m.update(dt);
			var relative=m.ball-m.wheel+Math.PI/2;
			Assert.floatEquals(WheelMotion.POCKETS.indexOf(n)*Math.PI*2/37,relative,.000001);
			Assert.floatEquals(.55,m.radius);Assert.floatEquals(8,m.elapsed);
		}
	}
	function testCounterRotationAndDrop() {
		var m=new WheelMotion();m.start(32);var start=m.ball;m.update(1);
		Assert.isTrue(m.wheel>0);Assert.isTrue(m.ball<start);Assert.floatEquals(.755,m.radius);
		m.update(5);Assert.isTrue(m.radius<.755);Assert.isTrue(m.active);
		m.update(2);var angle=m.wheel;m.update(100);Assert.floatEquals(angle,m.wheel);
		m.start(0);Assert.floatEquals(Math.sin(angle),Math.sin(m.wheel));Assert.isTrue(m.active);
	}
	function testPocketCaptureIsContinuous() {
		for(n in 0...37) {
			var m=new WheelMotion();m.start(n);m.update(6.99999);var a=m.ball;
			m.update(.00001);Assert.floatEquals(Math.sin(a),Math.sin(m.ball),.00001);
			Assert.floatEquals(Math.cos(a),Math.cos(m.ball),.00001);
		}
	}
}
