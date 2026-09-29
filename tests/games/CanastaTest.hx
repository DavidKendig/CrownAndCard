// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import cards.Card;
import games.canasta.Canasta;
import rng.ChaChaRng;
import utest.Assert;

class CanastaTest extends utest.Test {
	static function rng(label:String) return ChaChaRng.fromSeed(TestUtil.countingSeed()).fork('test-canasta/$label');

	static function h(codes:String):Array<Card> return [for (c in codes.split(" ")) Card.parse(c)];

	/** A throwaway deal that just needs to populate the stock; tests overwrite both hands directly. **/
	function baseline():Canasta {
		var g = new Canasta();
		var order = h("3c 3d 4c 4d 5c 5d 6c 6d 7c 7d 8c 8d 9c 9d Tc Td Jc Jd Qc Qd Kc Kd Ac Ad Kh");
		g.startDeal(order);
		return g;
	}

	function testMeldingThreeNaturalsWorks() {
		var g = baseline();
		g.drawFromStock();
		g.hands[0].resize(0);
		for (c in h("7c 7d 7h Kc")) g.hands[0].push(c);
		g.meld(h("7c 7d 7h"));
		Assert.equals(1, g.melds[0].length);
		Assert.equals(7, g.melds[0][0].rank);
		Assert.equals(3, g.melds[0][0].cards.length);
		Assert.equals(1, g.hands[0].length);
	}

	function testWildCardsCannotOutnumberNaturals() {
		var g = baseline();
		g.drawFromStock();
		g.hands[0].resize(0);
		for (c in h("7c 2d 2h Kc")) g.hands[0].push(c);
		Assert.raises(() -> g.meld(h("7c 2d 2h"))); // 1 natural, 2 wild: too many wild
	}

	function testTwoNaturalsAndAWildCanCompleteAMeld() {
		var g = baseline();
		g.drawFromStock();
		g.hands[0].resize(0);
		for (c in h("7c 7d 2h Kc")) g.hands[0].push(c);
		g.meld(h("7c 7d 2h")); // 2 natural + 1 wild: allowed
		Assert.equals(1, g.melds[0].length);
	}

	function testTakingTheDiscardPileNeedsTwoNaturalMatchesOrAnExistingMeld() {
		var g = baseline();
		g.discardPile.resize(0);
		g.discardPile.push(Card.parse("9c"));
		g.hands[0].resize(0);
		for (c in h("9d Kh Qc")) g.hands[0].push(c); // only 1 natural nine: not enough
		Assert.isFalse(g.canTakeDiscard());
		g.hands[0].push(Card.parse("9h")); // now 2 naturals
		Assert.isTrue(g.canTakeDiscard());
		g.takeDiscard();
		Assert.equals(0, g.discardPile.length);
		Assert.isTrue(g.hands[0].indexOf(Card.parse("9c")) >= 0);
	}

	function testGoingOutRequiresACanasta() {
		var g = baseline();
		g.drawFromStock();
		g.hands[0].resize(0);
		for (c in h("7c 7d 7h Kc")) g.hands[0].push(c);
		g.meld(h("7c 7d 7h"));
		Assert.raises(() -> g.discard(Card.parse("Kc"))); // only one card left, but no canasta yet
	}

	function testGoingOutWithACanastaScoresTheHand() {
		var g = baseline();
		g.drawFromStock();
		g.hands[0].resize(0);
		for (c in h("7c 7d 7h 7s 2c 2d 2h Kc")) g.hands[0].push(c);
		g.hands[1].resize(0);
		for (c in h("3c 4d 5h 6s Qc")) g.hands[1].push(c);
		g.meld(h("7c 7d 7h 7s 2c 2d 2h")); // 4 natural + 3 wild: a 7-card (mixed) canasta
		Assert.isTrue(g.hasCanasta(0));
		g.discard(Card.parse("Kc"));
		Assert.equals(HandOver, g.phase);
		Assert.equals(0, g.goneOut);
		// Seat 0: 4x5 (sevens) + 3x20 (wild) = 80, +300 mixed-canasta bonus, +100 for going out.
		Assert.equals(480, g.scores[0]);
		// Seat 1: no melds, all 5 cards score against them (5+5+5+5+10).
		Assert.equals(-30, g.scores[1]);
	}
}
