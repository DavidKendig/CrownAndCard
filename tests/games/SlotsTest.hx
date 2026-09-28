// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import games.slots.Slots;
import utest.Assert;

/** Feeds `spin()` a scripted sequence of `below()` reel stops. **/
private class StackedRng implements rng.IRng {
	final queue:Array<Int>;
	var pos = 0;

	public function new(queue:Array<Int>) this.queue = queue;

	function next():Int {
		if (pos >= queue.length) throw "StackedRng ran out of values";
		return queue[pos++];
	}

	public function nextU32():Int throw "not used by Slots";
	public function below(bound:Int):Int return next();
	public function between(lo:Int, hi:Int):Int return next();
	public function nextFloat():Float throw "not used by Slots";
	public function chance(p:Float):Bool throw "not used by Slots";
	public function shuffle<T>(items:Array<T>):Void throw "not used by Slots";
	public function pickWeighted<T>(items:Array<T>, weights:Array<Int>):T throw "not used by Slots";
}

class SlotsTest extends utest.Test {
	function machine(stops:Array<Int>, purse = 1000):Slots return new Slots(new StackedRng(stops), purse);

	function testThreeCrownsIsTheJackpot() {
		var g = machine([0, 0, 0]); // Crown, Crown, Crown
		var r = g.spin(5);
		Assert.same([Crown, Crown, Crown], r.symbols);
		Assert.equals(150, r.multiplier);
		Assert.equals(750, r.payout);
		Assert.equals(1745, g.purse); // 1000 - 5 + 750
	}

	function testThreeCherriesAndPartialCherries() {
		Assert.equals(10, Slots.payoutMultiplier(Cherry, Cherry, Cherry));
		Assert.equals(5, Slots.payoutMultiplier(Cherry, Cherry, Crown));
		Assert.equals(2, Slots.payoutMultiplier(Cherry, Crown, Crown));
		Assert.equals(0, Slots.payoutMultiplier(Crown, Cherry, Cherry)); // only reel 1 and 2 count
	}

	function testMatchingSuitsPayEight() {
		Assert.equals(8, Slots.payoutMultiplier(Club, Club, Club));
		Assert.equals(8, Slots.payoutMultiplier(Heart, Heart, Heart));
		Assert.equals(0, Slots.payoutMultiplier(Club, Heart, Club)); // mismatched suits don't count
	}

	function testNoMatchIsATotalLoss() {
		Assert.equals(0, Slots.payoutMultiplier(Bar, Bell, Seven));
		var g = machine([6, 3, 1]); // Bar, Bell, Seven
		var r = g.spin(5);
		Assert.equals(0, r.multiplier);
		Assert.equals(995, g.purse);
	}

	function testOnlyListedBetsAreAllowed() {
		var g = machine([0, 0, 0]);
		Assert.isFalse(g.canBet(4));
		Assert.isTrue(g.canBet(5));
		Assert.raises(() -> g.spin(4));
	}

	function testCannotBetMoreThanThePurse() {
		var g = machine([0, 0, 0], 3);
		Assert.isFalse(g.canBet(5));
		Assert.raises(() -> g.spin(5));
	}

	/** Brute-forces every one of REEL.length^3 equally likely stops (§7.9): the machine's RTP is exact, not sampled. **/
	function testRtpMatchesTheBrassPlaque() {
		var n = Slots.REEL.length;
		var total = 0;
		for (a in Slots.REEL) for (b in Slots.REEL) for (c in Slots.REEL) total += Slots.payoutMultiplier(a, b, c);
		var rtp = total / (n * n * n);
		Assert.isTrue(rtp >= 0.92 && rtp <= 0.96, 'RTP $rtp is outside the 92-96% target band');
		Assert.floatEquals(Slots.RTP, rtp, 0.0001);
	}
}
