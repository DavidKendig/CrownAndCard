// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import cards.Card;
import cards.Suit;
import games.euchre.Euchre;
import utest.Assert;

class EuchreTest extends utest.Test {
	static function h(codes:String):Array<Card> return [for (c in codes.split(" ")) Card.parse(c)];

	static function euchre24(seat0:String, seat1:String, seat2:String, seat3:String, kitty:String):Array<Card> {
		return h(seat0).concat(h(seat1)).concat(h(seat2)).concat(h(seat3)).concat(h(kitty));
	}

	function testLeftBowerCountsAsTrumpForFollowingAndPower() {
		Assert.equals(Suit.Spades, Euchre.effectiveSuit(Card.parse("Jc"), Suit.Spades)); // clubs: same color as spades
		Assert.equals(Suit.Hearts, Euchre.effectiveSuit(Card.parse("Jd"), Suit.Hearts)); // diamonds: same color as hearts
		Assert.equals(1000, Euchre.power(Card.parse("Js"), Suit.Spades, Suit.Spades)); // right bower
		Assert.equals(999, Euchre.power(Card.parse("Jc"), Suit.Spades, Suit.Spades)); // left bower
		Assert.isTrue(Euchre.power(Card.parse("Jc"), Suit.Spades, Suit.Spades) > Euchre.power(Card.parse("As"), Suit.Spades, Suit.Spades));
	}

	function testOrderingUpSetsTrumpAndTheDealerDiscards() {
		var g = new Euchre();
		g.startHand(euchre24("9c Tc Qc Kc Ac", "9d Td Qd Kd Ad", "9h Th Qh Kh Ah", "9s Ts Qs Ks As", "Js Jd Jh Jc"));
		Assert.equals(0, g.dealer); // dealer rotates from the default 3 to 0 on the first hand
		Assert.equals(1, g.bidder);
		g.orderUp(false);
		Assert.equals(Suit.Spades, g.trump);
		Assert.equals(1, g.maker);
		Assert.equals(DealerDiscard, g.phase);
		Assert.equals(5, g.hands[0].length); // the pickup happens together with the discard
		g.dealerDiscard(Card.parse("9c"));
		Assert.equals(5, g.hands[0].length);
		Assert.isFalse(g.hands[0].indexOf(Card.parse("9c")) >= 0);
		Assert.isTrue(g.hands[0].indexOf(Card.parse("Js")) >= 0);
		Assert.equals(Playing, g.phase);
		Assert.equals(1, g.leader); // left of the dealer
	}

	function testStickTheDealerForcesATrump() {
		var g = new Euchre();
		g.startHand(euchre24("9c Tc Qc Kc Ac", "9d Td Qd Kd Ad", "9h Th Qh Kh Ah", "9s Ts Qs Ks As", "Jh Jd Jc Js"));
		g.passBid1();
		g.passBid1();
		g.passBid1();
		g.passBid1();
		Assert.equals(Bid2, g.phase);
		Assert.equals(Suit.Hearts, g.turnedDownSuit);
		g.passBid2();
		g.passBid2();
		g.passBid2();
		Assert.equals(0, g.bidder); // back to the dealer
		Assert.isTrue(g.mustCallTrump);
		Assert.raises(() -> g.passBid2());
		g.callTrump(Suit.Clubs);
		Assert.equals(Suit.Clubs, g.trump);
		Assert.equals(0, g.maker);
		Assert.equals(Playing, g.phase);
	}

	function testCannotNameTheTurnedDownSuit() {
		var g = new Euchre();
		g.startHand(euchre24("9c Tc Qc Kc Ac", "9d Td Qd Kd Ad", "9h Th Qh Kh Ah", "9s Ts Qs Ks As", "Jh Jd Jc Js"));
		g.passBid1();
		g.passBid1();
		g.passBid1();
		g.passBid1();
		Assert.raises(() -> g.callTrump(Suit.Hearts));
	}

	function testGoingAloneSkipsThePartnerEntirely() {
		var g = new Euchre();
		g.startHand(euchre24("9c Tc Qc Kc Ac", "9d Td Qd Kd Ad", "9h Th Qh Kh Ah", "9s Ts Qs Ks As", "Jd Jc Jh Js"));
		g.orderUp(true); // seat 1 orders it up alone
		g.dealerDiscard(Card.parse("9c"));
		Assert.equals(Playing, g.phase);
		var partner = Euchre.partnerOf(1); // seat 3
		Assert.equals(0, g.legalPlays(partner).length);
		for (_ in 0...12) {
			if (g.phase != Playing) break;
			var seat = g.turn;
			if (seat == partner) {
				Assert.fail('seat $partner should never get a turn when their side plays alone');
				break;
			}
			g.play(seat, g.legalPlays(seat)[0]);
		}
	}

	function testMakingAllFiveTricksScoresAMarch() {
		// Seat 1 holds the right and left bowers plus the ace, king and queen of
		// spades: the top 5 of the 7 trump-ranked cards, so leading them each
		// trick always wins no matter what the others (holding no trump at all,
		// since the only other spades are stuck in the kitty) play back.
		var g = new Euchre();
		g.startHand(euchre24("9c Tc Qc Kc Ac", "Js Jc As Ks Qs", "9d Td Qd Kd Ad", "9h Th Qh Kh Ah", "Ts 9s Jd Jh"));
		g.orderUp(false); // turnUp is Ts: spades trump, seat 1 is the maker
		g.dealerDiscard(Card.parse("9c"));
		while (g.phase == Playing) g.play(g.turn, g.legalPlays(g.turn)[0]);
		Assert.equals(HandOver, g.phase);
		Assert.equals(1, g.lastMaker);
		Assert.isFalse(g.lastEuchred);
		Assert.equals(5, g.tricks[1] + g.tricks[3]); // seat 1's team took every trick
		Assert.equals(2, g.lastPoints);
		Assert.equals(2, g.scores[1]);
	}
}
