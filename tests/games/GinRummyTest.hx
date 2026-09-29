// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import cards.Card;
import games.rummy.GinRummy;
import utest.Assert;

class GinRummyTest extends utest.Test {
	static function h(codes:String):Array<Card> return [for (c in codes.split(" ")) Card.parse(c)];

	/** A throwaway deal just to populate the stock; the interesting tests overwrite both hands directly. **/
	static function placeholderDeal():Array<Card> return h("2c 2d 2h 2s 3c 3d 3h 3s 4c 4d 4h 4s 5c 5d 5h 5s 6c 6d 6h 6s 7c 7d 7h");

	function testEvaluateFindsARun() {
		var hand = h("3h 4h 5h 6h 7h 2c 9d Kc As Qh");
		var r = GinRummy.evaluate(hand);
		Assert.equals(1, r.melds.length);
		Assert.equals(5, r.melds[0].length);
		Assert.equals(32, r.deadwoodPoints); // 2 + 9 + 10 + 1 + 10
	}

	function testEvaluateFindsASet() {
		var hand = h("7c 7d 7h 2c 9d Kc As Qh 4s 6s");
		var r = GinRummy.evaluate(hand);
		Assert.equals(1, r.melds.length);
		Assert.equals(3, r.melds[0].length);
		Assert.equals(42, r.deadwoodPoints); // 2 + 9 + 10 + 1 + 10 + 4 + 6
	}

	function testAceIsLowForRunsWithNoWrapPastKing() {
		var lowRun = GinRummy.evaluate(h("As 2s 3s 4c 5d 6h 7c 8d 9h Tc"));
		Assert.equals(1, lowRun.melds.length);
		Assert.equals(3, lowRun.melds[0].length);
		Assert.equals(49, lowRun.deadwoodPoints); // 4+5+6+7+8+9+10

		var noWrap = GinRummy.evaluate(h("Qs Ks As 2c 3d 4h 5c 6d 7h 8c"));
		Assert.equals(0, noWrap.melds.length);
		Assert.equals(56, noWrap.deadwoodPoints); // every card is deadwood
	}

	function testDrawingFromStockOrDiscardMovesToDiscardPhase() {
		var g = new GinRummy();
		g.startDeal(placeholderDeal());
		Assert.equals(0, g.turn); // seat 0 acts first on the opening hand
		Assert.equals(10, g.hands[0].length);
		g.drawFromStock(0);
		Assert.equals(11, g.hands[0].length);
		Assert.equals(Discard, g.phase);
	}

	function testGinBlocksLayoffAndAddsTheBonus() {
		var g = new GinRummy();
		g.startDeal(placeholderDeal());
		g.drawFromStock(0);
		g.hands[0].resize(0);
		for (c in h("7c 7d 7h 9c 9d 9h 2s 3s 4s 5s Kd")) g.hands[0].push(c);
		g.hands[1].resize(0);
		for (c in h("Ac 6d 8h Ts Jc Qd Kh 2c 4d 6h")) g.hands[1].push(c);
		Assert.equals(0, g.deadwoodIfDiscarding(0, Card.parse("Kd")));
		Assert.isTrue(g.canKnock(0, Card.parse("Kd")));
		g.discard(0, Card.parse("Kd"), true);
		Assert.equals(RoundOver, g.phase);
		Assert.equals(0, g.knocker);
		Assert.isTrue(g.lastGin);
		Assert.equals(0, g.lastScorer);
		Assert.equals(92, g.lastPoints); // 67 (no lay-off blocked by gin) + 25 bonus
		Assert.equals(92, g.scores[0]);
	}

	function testAKnockLaysOffOntoTheKnockersMelds() {
		var g = new GinRummy();
		g.startDeal(placeholderDeal());
		g.drawFromStock(0);
		// A set of 7s (unrelated to the run's suit or rank) and a 2-6 spade run, so
		// the ace of spades below can only ever lay off onto the run, unambiguously.
		g.hands[0].resize(0);
		for (c in h("7c 7d 7h 2s 3s 4s 5s 6s 9d Ac Kd")) g.hands[0].push(c);
		g.hands[1].resize(0);
		for (c in h("As 2c 3d 4h 5c 6d 8h 9h Jc Qd")) g.hands[1].push(c);
		Assert.equals(10, g.deadwoodIfDiscarding(0, Card.parse("Kd"))); // the set and run leave 9d and Ac over
		g.discard(0, Card.parse("Kd"), true);
		Assert.isFalse(g.lastGin);
		Assert.isFalse(g.lastUndercut);
		Assert.equals(0, g.lastScorer);
		Assert.equals(47, g.lastPoints); // opponent's 58 minus the ace laid onto the run (57), minus the knocker's 10
		Assert.equals(47, g.scores[0]);
	}

	function testATieOrLowerOpponentDeadwoodUndercutsTheKnocker() {
		var g = new GinRummy();
		g.startDeal(placeholderDeal());
		g.drawFromStock(0);
		g.hands[0].resize(0);
		for (c in h("7c 7d 7h 2s 3s 4s 5s 6s 9c Ah Kd")) g.hands[0].push(c);
		g.hands[1].resize(0);
		for (c in h("Tc Td Th Qc Qd Qh 2h 3h 4h Ks")) g.hands[1].push(c);
		Assert.equals(10, g.deadwoodIfDiscarding(0, Card.parse("Kd")));
		g.discard(0, Card.parse("Kd"), true);
		Assert.isFalse(g.lastGin);
		Assert.isTrue(g.lastUndercut);
		Assert.equals(1, g.lastScorer);
		Assert.equals(25, g.lastPoints); // tied deadwood: the bonus only, no difference to add
		Assert.equals(25, g.scores[1]);
	}
}
