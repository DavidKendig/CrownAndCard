// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import utest.Assert;

class GridMapTest extends utest.Test {
	static inline var R = 0.25;
	static inline var STEP = 0.037; // one walking frame at 60 fps

	/** A 3 × 2 m room with walls all round: open cells span x 1..4, y 1..3. **/
	static function room():GridMap {
		var sector = {name: "Test", floorZ: 0.0, ceilZ: 3.0, floorTex: "", ceilTex: "", wallTex: "", upperTex: "", shade: 0.0};
		return new GridMap(["#####", "#aaa#", "#aaa#", "#####"], ["a" => sector]);
	}

	/** The bug that froze the player: spawning 5 cm inside the south wall. **/
	function testCanWalkOutOfAWallYouStartedIn() {
		var map = room();
		Assert.isTrue(map.blocked(2.5, 1.2, R));
		var p = map.slide(2.5, 1.2, 0, STEP, R);
		Assert.floatEquals(1.2 + STEP, p.y);
	}

	function testCannotWalkDeeperIntoAWall() {
		var p = room().slide(2.5, 1.2, 0, -STEP, R);
		Assert.floatEquals(1.2, p.y);
	}

	function testCanSlideAlongAWallWhileTouchingIt() {
		var p = room().slide(2.5, 1.2, STEP, 0, R);
		Assert.floatEquals(2.5 + STEP, p.x);
	}

	function testWallsStopYouFromOutside() {
		var map = room();
		var x = 2.0, y = 2.0;
		for (_ in 0...200) {
			var p = map.slide(x, y, STEP, 0, R);
			x = p.x;
			y = p.y;
		}
		Assert.isTrue(x <= 4 - R, 'walked into the east wall: x = $x');
		Assert.isTrue(x > 4 - R - STEP, 'stopped too early: x = $x');
	}

	function testDiagonalIntoAWallSlidesAlongIt() {
		var map = room();
		var x = 2.0, y = 2.5;
		for (_ in 0...40) {
			var p = map.slide(x, y, STEP, STEP, R);
			x = p.x;
			y = p.y;
		}
		Assert.isTrue(y <= 3 - R, 'went through the north wall: y = $y');
		Assert.isTrue(x > 3.0, 'did not slide east along the wall: x = $x');
	}

	function testPenetrationIsZeroWhenClear() {
		Assert.floatEquals(0, room().penetration(2.5, 2.0, R));
		Assert.floatEquals(0.05, room().penetration(2.5, 1.2, R), 1e-9);
	}
}
