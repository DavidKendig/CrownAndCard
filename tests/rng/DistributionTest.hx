// SPDX-License-Identifier: AGPL-3.0-or-later
package rng;

import utest.Assert;

/**
	Statistical checks on the derived values (§7.9). Seeds are fixed, so these
	are deterministic; the thresholds are p = 0.0001 critical values.
**/
class DistributionTest extends utest.Test {
	static final BOUNDS = [2, 3, 6, 37, 38, 52];

	function testBelowStaysInRange() {
		var rng = ChaChaRng.fromSeed(TestUtil.countingSeed());
		for (bound in [1, 2, 3, 6, 37, 38, 52, 312, 1000, 0x7FFFFFFF]) {
			for (_ in 0...2000) {
				var x = rng.below(bound);
				if (x < 0 || x >= bound) {
					Assert.fail('below($bound) returned $x');
					return;
				}
			}
		}
		Assert.pass();
	}

	function testBelowRejectsBadBounds() {
		var rng = ChaChaRng.fromSeed(TestUtil.countingSeed());
		Assert.raises(() -> rng.below(0));
		Assert.raises(() -> rng.below(-5));
	}

	function testBelowIsUniform_ChaCha() {
		checkBelowUniform(ChaChaRng.fromSeed(TestUtil.countingSeed()));
	}

	function testBelowIsUniform_Xoshiro() {
		checkBelowUniform(new Xoshiro128ss(1, 2, 3, 4));
	}

	function testBetweenIsInclusive() {
		var rng = ChaChaRng.fromSeed(TestUtil.countingSeed());
		var seen = [for (_ in 0...6) false];
		for (_ in 0...1000)
			seen[rng.between(1, 6) - 1] = true;
		Assert.same([true, true, true, true, true, true], seen);
	}

	function testNextFloatRange() {
		var rng = ChaChaRng.fromSeed(TestUtil.countingSeed());
		for (_ in 0...5000) {
			var f = rng.nextFloat();
			if (f < 0 || f >= 1) {
				Assert.fail('nextFloat() returned $f');
				return;
			}
		}
		Assert.pass();
	}

	/**
		Every one of the 120 orderings of 5 items must be equally likely.
		This catches the classic off-by-one shuffle bugs.
	**/
	function testShuffleGivesEveryPermutationEqually() {
		var rng = ChaChaRng.fromSeed(TestUtil.countingSeed());
		var counts = new Map<String, Int>();
		var trials = 60000;
		for (_ in 0...trials) {
			var items = [0, 1, 2, 3, 4];
			rng.shuffle(items);
			var key = items.join("");
			counts.set(key, (counts.exists(key) ? counts.get(key) : 0) + 1);
		}
		var observed = [for (v in counts) v];
		Assert.equals(120, observed.length);
		var chi = TestUtil.chiSquare(observed, trials);
		Assert.isTrue(chi < TestUtil.chiSquareCritical(119), 'chi-square $chi too high');
	}

	function testPickWeightedFollowsWeights() {
		var rng = ChaChaRng.fromSeed(TestUtil.countingSeed());
		var counts = [0, 0, 0];
		for (_ in 0...40000)
			counts[rng.pickWeighted([0, 1, 2], [1, 0, 3])]++;
		Assert.equals(0, counts[1]);
		// Expect a 1:3 split between items 0 and 2.
		var ratio = counts[2] / counts[0];
		Assert.isTrue(ratio > 2.85 && ratio < 3.15, 'ratio $ratio');
	}

	function testPickWeightedRejectsBadWeights() {
		var rng = ChaChaRng.fromSeed(TestUtil.countingSeed());
		Assert.raises(() -> rng.pickWeighted([1, 2], [0, 0]));
		Assert.raises(() -> rng.pickWeighted([1, 2], [1, -1]));
		Assert.raises(() -> rng.pickWeighted([1, 2], [1]));
	}

	static function checkBelowUniform(rng:IRng) {
		for (bound in BOUNDS) {
			var total = bound * 500;
			var counts = [for (_ in 0...bound) 0];
			for (_ in 0...total)
				counts[rng.below(bound)]++;
			var chi = TestUtil.chiSquare(counts, total);
			Assert.isTrue(chi < TestUtil.chiSquareCritical(bound - 1), 'below($bound): chi-square $chi too high');
		}
	}
}
