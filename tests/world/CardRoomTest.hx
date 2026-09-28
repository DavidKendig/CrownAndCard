// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import utest.Assert;

class CardRoomTest extends utest.Test {
	static final NORTH = Math.PI / 2;

	function testFacingTheTableFromTheGuestsSide() {
		Assert.isTrue(CardRoom.atTable(13, 34.8, NORTH));
		Assert.isTrue(CardRoom.atTable(12, 34.6, NORTH + .2));
		Assert.isTrue(CardRoom.atTable(11.2, 36, 0)); // west end, facing east
	}

	function testFacingAwayOrTooFar() {
		Assert.isFalse(CardRoom.atTable(13, 34.8, -NORTH));
		Assert.isFalse(CardRoom.atTable(13, 33.9, NORTH));
		Assert.isFalse(CardRoom.atTable(13, 30, NORTH));
	}

	function testNotFromTheDealersSide() {
		Assert.isFalse(CardRoom.atTable(13, 37.3, -NORTH));
	}
}
