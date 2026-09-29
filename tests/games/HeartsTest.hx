// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import cards.Card;
import games.hearts.Hearts;
import utest.Assert;

class HeartsTest extends utest.Test {
	static function h(codes:String):Array<Card> return [for (c in codes.split(" ")) Card.parse(c)];

	/**
		Four 13-card hands: seat 0 gets `seat0Cards`, padded with filler; the
		rest get scattered filler. Deals four times to land on the 4th hand
		(the held one, Left/Right/Across/Hold), so the game is straight into
		Playing with no passing to drive through first.
	**/
	function dealWith(seat0Cards:Array<Card>):Hearts {
		var used = new Map<Int, Bool>();
		for (c in seat0Cards) used.set(c.index, true);
		var filler = [];
		var i = 0;
		while (filler.length < 52 - seat0Cards.length) {
			if (!used.exists(i)) filler.push(Card.fromIndex(i));
			i++;
		}
		var hands = [seat0Cards.copy(), [], [], []];
		var need = [13 - seat0Cards.length, 13, 13, 13];
		var pos = 0;
		for (s in 1...4) for (_ in 0...need[s]) hands[s].push(filler[pos++]);
		for (_ in 0...need[0]) hands[0].push(filler[pos++]);
		var g = new Hearts();
		for (_ in 0...4) g.startHand(hands);
		return g;
	}

	function testTheFirstTrickMustOpenWithTheTwoOfClubs() {
		var g = dealWith(h("2c 3c 4c Kh"));
		Assert.equals(Playing, g.phase); // dealWith lands on the held hand: no passing first
		var leader = g.turn;
		Assert.same([Card.parse("2c")], g.legalPlays(leader));
	}

	function testMustFollowSuitWhenPossible() {
		var seat0 = h("2c 5c 7c 9c Jc Kc 2h 3h 4h 5h 6h 7h 8h");
		var seat1 = h("3c 4c 6c 8c Tc Qc Ac 9h Th Jh Qh Kh Ah");
		var seat2 = h("2d 3d 4d 5d 6d 7d 8d 9d Td Jd Qd Kd Ad");
		var seat3 = h("2s 3s 4s 5s 6s 7s 8s 9s Ts Js Qs Ks As");
		var g = new Hearts();
		for (_ in 0...4) g.startHand([seat0, seat1, seat2, seat3]);
		Assert.equals(Playing, g.phase);
		Assert.equals(0, g.turn); // seat 0 holds the two of clubs
		g.play(0, Card.parse("2c"));
		Assert.equals(1, g.turn);
		var legal = g.legalPlays(1);
		Assert.equals(7, legal.length); // seat 1's seven clubs -- must follow
		for (c in legal) Assert.equals(cards.Suit.Clubs, c.suit);
	}

	function testHeartsCannotBeLedUntilBroken() {
		var seat0 = h("2c 2d 3d 4d 5d 6d 7d 8d 9d Td Jd Qd Kd");
		var seat1 = h("Ac 2h 3h 4h 2s 3s 4s 5s 6s 7s 8s 9s Ts");
		var seat2 = h("3c 4c 5c 6c 7c 8c 9c Tc Jc Qc Kc 5h 6h");
		var seat3 = h("7h 8h 9h Th Jh Qh Kh Ah Js Qs Ks As Ad");
		var g = new Hearts();
		for (_ in 0...4) g.startHand([seat0, seat1, seat2, seat3]);
		Assert.equals(Playing, g.phase);
		Assert.equals(0, g.turn); // seat 0 holds the two of clubs
		g.play(0, Card.parse("2c"));
		g.play(1, Card.parse("Ac")); // must follow suit, and the ace wins the trick
		g.play(2, g.legalPlays(2)[0]);
		g.play(3, g.legalPlays(3)[0]);
		Assert.equals(1, g.turn); // seat 1's ace won the trick and leads next
		Assert.isFalse(g.heartsBroken);
		var legal = g.legalPlays(1);
		Assert.equals(9, legal.length); // seat 1's nine spades -- hearts excluded though they hold three
		for (c in legal) Assert.notEquals(cards.Suit.Hearts, c.suit);
	}

	function testCardPointsAndShootingTheMoon() {
		Assert.equals(1, Hearts.cardPoints(Card.parse("5h")));
		Assert.equals(13, Hearts.cardPoints(Card.parse("Qs")));
		Assert.equals(0, Hearts.cardPoints(Card.parse("Ks")));
	}

	function testPassingMovesThreeCardsInTheRightDirection() {
		var g = dealWith(h("2c 3c 4c Kh 5d 6d 7d 8d 9d Td Jd Qd Kd"));
		Assert.equals(Playing, g.phase); // the held hand: no passing
		// One more deal wraps back around to Left.
		g.startHand([g.hands[0], g.hands[1], g.hands[2], g.hands[3]]);
		Assert.equals(Passing, g.phase);
		Assert.equals(Left, g.passDirection);
		var toPass = [g.hands[0][0], g.hands[0][1], g.hands[0][2]];
		g.setPass(0, toPass);
		for (s in 1...4) g.setPass(s, [g.hands[s][0], g.hands[s][1], g.hands[s][2]]);
		Assert.equals(Playing, g.phase);
		for (c in toPass) Assert.isTrue(g.hands[1].indexOf(c) >= 0); // left neighbor
	}
}
