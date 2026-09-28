// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import utest.Assert;

/** The card table's "sit down" zone, at the manor's table (centered on 13, 36). **/
class CardRoomTest extends utest.Test {
	static final NORTH = Math.PI / 2;

	static function at(x:Float, y:Float, yaw:Float) return Fixtures.atTable(13, 36, x, y, yaw);

	function testFacingTheTableFromTheGuestsSide() {
		Assert.isTrue(at(13, 34.8, NORTH));
		Assert.isTrue(at(12, 34.6, NORTH + .2));
		Assert.isTrue(at(11.2, 36, 0)); // west end, facing east
	}

	function testFacingAwayOrTooFar() {
		Assert.isFalse(at(13, 34.8, -NORTH));
		Assert.isFalse(at(13, 33.9, NORTH));
		Assert.isFalse(at(13, 30, NORTH));
	}

	function testNotFromTheDealersSide() {
		Assert.isFalse(at(13, 37.3, -NORTH));
	}
}
