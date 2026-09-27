// SPDX-License-Identifier: AGPL-3.0-or-later
package rng;

import cards.Deck;
import utest.Assert;

/** Expected values come from tools/rng_reference.py, an independent implementation. **/
class ChaChaRngTest extends utest.Test {
	function testStreamIsTheKeystreamInOrder() {
		// Zero key: block 0 then block 1 are RFC 8439 Appendix A.1 vectors #1 and #2.
		var rng = new ChaChaRng([0, 0, 0, 0, 0, 0, 0, 0]);
		Assert.equals("ade0b876 903df1a0 e56a5d40 28bd8653", TestUtil.hexWords([for (_ in 0...4) rng.nextU32()]));
		for (_ in 4...16)
			rng.nextU32();
		Assert.equals("bee7079f 7a385155 7c97ba98 0d082d73", TestUtil.hexWords([for (_ in 0...4) rng.nextU32()]));
	}

	function testSeededStreamMatchesReference() {
		var rng = ChaChaRng.fromSeed(TestUtil.countingSeed());
		Assert.equals("7d2bfd39 6a19c5d9 7703bd8d 494adcb8", TestUtil.hexWords([for (_ in 0...4) rng.nextU32()]));
	}

	/** Also the cross-target determinism check: every target must produce this exact digest (§7.4). **/
	function testTenThousandWordDigestMatchesReference() {
		var rng = ChaChaRng.fromSeed(TestUtil.countingSeed());
		Assert.equals("b9289456f37f933e6ca0804163a1bc2dfe4f060320e317764af7a5460391add0", TestUtil.streamDigest(rng, 10000));
	}

	function testShuffleMatchesReference() {
		var deck = Deck.standard();
		ChaChaRng.fromSeed(TestUtil.countingSeed()).shuffle(deck);
		Assert.equals("8h Qc 2c 2s 4d 3d 7h 5c 7d 9c Jh 7s Ks 6h 3h Qh 4s Js 5s Ts 6c As 2d Kd Kh 9s "
			+ "7c Ad 3c 5h Qd 3s Tc Kc Ah 9h 8s Jc 9d 6d Td 6s Ac 4c 2h Jd Th Qs 8c 4h 5d 8d",
			[for (c in deck) c.code].join(" "));
	}

	function testForkMatchesReference() {
		var child = ChaChaRng.fromSeed(TestUtil.countingSeed()).fork("table/card-room/blackjack/shuffle");
		Assert.equals("9dc2abe7 8e3716de 2042d060 cc92bbe6", TestUtil.hexWords([for (_ in 0...4) child.nextU32()]));
	}

	function testForkIgnoresParentPositionAndOrder() {
		var a = ChaChaRng.fromSeed(TestUtil.countingSeed());
		var b = ChaChaRng.fromSeed(TestUtil.countingSeed());
		for (_ in 0...1000)
			b.nextU32();
		b.fork("craps");
		var fromA = a.fork("blackjack");
		var fromB = b.fork("blackjack");
		Assert.equals(fromA.nextU32(), fromB.nextU32());
	}

	function testForkDoesNotDisturbParent() {
		var a = ChaChaRng.fromSeed(TestUtil.countingSeed());
		var b = ChaChaRng.fromSeed(TestUtil.countingSeed());
		a.fork("anything");
		Assert.equals(a.nextU32(), b.nextU32());
	}

	function testDifferentLabelsGiveDifferentStreams() {
		var root = ChaChaRng.fromSeed(TestUtil.countingSeed());
		Assert.notEquals(root.fork("a").nextU32(), root.fork("b").nextU32());
	}

	function testSaveAndRestoreMidBlock() {
		checkResume(5);
	}

	function testSaveAndRestoreAtBlockBoundary() {
		checkResume(16);
	}

	function testSaveAndRestoreBeforeFirstDraw() {
		checkResume(0);
	}

	function testSeedMustBe32Bytes() {
		Assert.raises(() -> ChaChaRng.fromSeed(haxe.io.Bytes.alloc(16)));
	}

	function testEntropySeedsDiffer() {
		Assert.notEquals(ChaChaRng.fromEntropy().fingerprint(), ChaChaRng.fromEntropy().fingerprint());
	}

	static function checkResume(drawsBeforeSave:Int) {
		var rng = ChaChaRng.fromSeed(TestUtil.countingSeed());
		for (_ in 0...drawsBeforeSave)
			rng.nextU32();
		var state = rng.saveState();
		var expected = [for (_ in 0...40) rng.nextU32()];
		var resumed = ChaChaRng.fromState(state);
		Assert.same(expected, [for (_ in 0...40) resumed.nextU32()]);
	}
}
