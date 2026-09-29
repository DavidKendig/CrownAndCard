// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import cards.Card;
import cards.Suit;
import games.durak.Durak;
import utest.Assert;

class DurakTest extends utest.Test {
	static function h(codes:String):Array<Card> return [for (c in codes.split(" ")) Card.parse(c)];

	/** A bare 13-card order (6 dealt each, 1 trump) to set up trumpSuit/phase before hand-editing a scenario. **/
	function baseline(trump:String):Durak {
		var g = new Durak();
		g.startDeal(h('6c 6d 7c 7d 8c 8d 9c 9d Tc Td Jc Jd $trump'));
		return g;
	}

	function testDealGivesSixEachAndSetsTrumpFromTheLastCard() {
		var g = new Durak();
		g.startDeal(h("6c 6d 7c 7d 8c 8d 9c 9d Tc Td Jc Jd 9s"));
		Assert.equals(6, g.hands[0].length);
		Assert.equals(6, g.hands[1].length);
		Assert.equals("9s", g.trumpCard.code);
		Assert.equals(Suit.Spades, g.trumpSuit);
		Assert.equals(1, g.stock.length); // just the trump card itself, drawn last
		Assert.equals(0, g.attacker);
		Assert.equals(1, g.defender);
	}

	function testBeatsFollowsSuitOrTrump() {
		var g = baseline("Ks"); // trump is spades
		Assert.isTrue(g.beats(Card.parse("9s"), Card.parse("8s"))); // higher, same suit
		Assert.isFalse(g.beats(Card.parse("8s"), Card.parse("9s"))); // lower, same suit
		Assert.isTrue(g.beats(Card.parse("6s"), Card.parse("Ac"))); // trump beats non-trump
		Assert.isFalse(g.beats(Card.parse("Ac"), Card.parse("6s"))); // non-trump can't beat trump
		Assert.isFalse(g.beats(Card.parse("Ac"), Card.parse("6d"))); // off-suit, neither trump
	}

	function testOnlyMatchingRanksCanPileOnAfterTheFirstAttack() {
		var g = baseline("Ks"); // trump spades
		g.hands[0].resize(0);
		for (c in h("6c 6d 8h")) g.hands[0].push(c);
		g.hands[1].resize(0);
		g.hands[1].push(Card.parse("Qs"));
		Assert.isTrue(g.canAttackWith(Card.parse("6c")));
		g.attack(Card.parse("6c"));
		// While the attack is still open, nothing more can be added.
		Assert.isFalse(g.canAttackWith(Card.parse("6d")));
		g.defend(0, Card.parse("Qs")); // trump beats it; ranks 6 and 12 are now on the table
		Assert.isTrue(g.canAttackWith(Card.parse("6d"))); // rank 6 is already on the table
		Assert.isFalse(g.canAttackWith(Card.parse("8h"))); // rank 8 isn't
	}

	function testASuccessfulDefenseThenFinishClearsTheTableAndSwapsRoles() {
		var g = baseline("Ks"); // trump spades; stock still holds Ks after dealing
		g.hands[0].resize(0);
		for (c in h("6c 7c 8c 9c Tc Jc")) g.hands[0].push(c);
		g.hands[1].resize(0);
		for (c in h("6d 7d 8d 9d Td Js")) g.hands[1].push(c); // Js is trump
		g.stock.resize(0);
		for (c in h("Qc Qd")) g.stock.push(c);

		g.attack(Card.parse("6c"));
		Assert.isFalse(g.legalDefends(0).indexOf(Card.parse("Td")) >= 0); // wrong suit, not trump
		Assert.isTrue(g.legalDefends(0).indexOf(Card.parse("Js")) >= 0); // trump beats it
		g.defend(0, Card.parse("Js"));
		Assert.isTrue(g.canFinish);

		g.finish();
		Assert.equals(2, g.discarded);
		Assert.equals(0, g.table.length);
		Assert.equals(1, g.attacker); // roles swapped
		Assert.equals(0, g.defender);
		Assert.equals(6, g.hands[0].length); // refilled from the stock
		Assert.equals(6, g.hands[1].length);
		Assert.equals(0, g.stock.length); // Qc, Qd handed out
	}

	function testTakingTheTableKeepsTheSameRoles() {
		var g = baseline("6h"); // trump hearts; neither hand below holds a heart
		g.hands[0].resize(0);
		for (c in h("Ac 2c 3c 4c 5c 7c")) g.hands[0].push(c);
		g.hands[1].resize(0);
		for (c in h("6d 7d 8d 9d Td Jd")) g.hands[1].push(c);
		g.stock.resize(0);

		g.attack(Card.parse("Ac"));
		Assert.equals(0, g.legalDefends(0).length); // no clubs, no trump: nothing beats it
		g.take();
		Assert.equals(7, g.hands[1].length); // picked up the ace
		Assert.equals(0, g.table.length);
		Assert.equals(0, g.attacker); // roles unchanged
		Assert.equals(1, g.defender);
		Assert.equals(Attacking, g.phase);
	}

	function testTheAttackerLeftEmptyIsSafeAndTheOtherSideIsTheDurak() {
		var g = baseline("Ks");
		g.hands[0].resize(0);
		g.hands[0].push(Card.parse("6c"));
		g.hands[1].resize(0);
		for (c in h("7c 9d")) g.hands[1].push(c); // beats it with 7c, keeps 9d
		g.stock.resize(0);

		g.attack(Card.parse("6c"));
		g.defend(0, Card.parse("7c"));
		g.finish();

		Assert.equals(GameOver, g.phase);
		Assert.equals(1, g.durak);
		Assert.equals(0, g.hands[0].length);
		Assert.equals(1, g.hands[1].length);
	}

	function testBothEmptyingAtOnceIsADraw() {
		var g = baseline("Ks");
		g.hands[0].resize(0);
		g.hands[0].push(Card.parse("6c"));
		g.hands[1].resize(0);
		g.hands[1].push(Card.parse("7c"));
		g.stock.resize(0);

		g.attack(Card.parse("6c"));
		g.defend(0, Card.parse("7c"));
		g.finish();

		Assert.equals(GameOver, g.phase);
		Assert.equals(-1, g.durak);
	}
}
