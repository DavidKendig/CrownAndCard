// SPDX-License-Identifier: AGPL-3.0-or-later
package rng;

import utest.Assert;

/** Expected values come from tools/rng_reference.py. **/
class Xoshiro128ssTest extends utest.Test {
	function testFirstOutputsMatchReference() {
		var rng = new Xoshiro128ss(1, 2, 3, 4);
		Assert.equals("00002d00 00000000 005a7080 04389d80 79199d9b 61963b24 4cb9b57a de9d7431",
			TestUtil.hexWords([for (_ in 0...8) rng.nextU32()]));
	}

	function testTenThousandWordDigestMatchesReference() {
		Assert.equals("dd62d1afdfd09868dbeba87b69e7228ddd70d1568ee005228c8a39f698dc9450",
			TestUtil.streamDigest(new Xoshiro128ss(1, 2, 3, 4), 10000));
	}

	function testAllZeroStateIsRejected() {
		Assert.raises(() -> new Xoshiro128ss(0, 0, 0, 0));
	}

	function testSeededFromOutcomeStream() {
		var a = Xoshiro128ss.seededFrom(ChaChaRng.fromSeed(TestUtil.countingSeed()).fork("fx"));
		var b = Xoshiro128ss.seededFrom(ChaChaRng.fromSeed(TestUtil.countingSeed()).fork("fx"));
		Assert.equals(a.nextU32(), b.nextU32());
	}
}
