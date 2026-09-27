// SPDX-License-Identifier: AGPL-3.0-or-later
package cards;

import rng.ChaChaRng;
import utest.Assert;

class ShoeTest extends utest.Test {
	function testSixDeckShoeHasSixOfEachCard() {
		var shoe = new Shoe(6, 0.75, rng());
		Assert.equals(312, shoe.size);
		var counts = [for (_ in 0...52) 0];
		while (shoe.remaining > 0)
			counts[shoe.draw().index]++;
		for (n in counts)
			Assert.equals(6, n);
	}

	function testCutCardAtPenetration() {
		var shoe = new Shoe(6, 0.75, rng());
		for (_ in 0...233)
			shoe.draw();
		Assert.isFalse(shoe.cutCardReached);
		shoe.draw(); // card 234 = 312 * 0.75
		Assert.isTrue(shoe.cutCardReached);
	}

	function testDrawingPastTheEndThrows() {
		var shoe = new Shoe(1, 1.0, rng());
		for (_ in 0...52)
			shoe.draw();
		Assert.raises(() -> shoe.draw());
	}

	function testSameSeedSameShoe() {
		var a = new Shoe(2, 0.8, rng());
		var b = new Shoe(2, 0.8, rng());
		Assert.same([for (_ in 0...104) a.draw().index], [for (_ in 0...104) b.draw().index]);
	}

	function testReshuffleResetsAndReorders() {
		var shoe = new Shoe(1, 0.75, rng());
		var first = [for (_ in 0...52) shoe.draw().index];
		shoe.shuffle();
		Assert.equals(0, shoe.dealt);
		Assert.isFalse(shoe.cutCardReached);
		Assert.notEquals(first.join(","), [for (_ in 0...52) shoe.draw().index].join(","));
	}

	function testRejectsBadConfig() {
		Assert.raises(() -> new Shoe(0, 0.75, rng()));
		Assert.raises(() -> new Shoe(6, 0, rng()));
		Assert.raises(() -> new Shoe(6, 1.5, rng()));
	}

	static function rng() {
		return ChaChaRng.fromSeed(TestUtil.countingSeed()).fork("test-shoe");
	}
}
