// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import cards.Card;
import games.bridge.Bridge;
import utest.Assert;

class BridgeTest extends utest.Test {
	static function h(codes:String):Array<Card> return [for (c in codes.split(" ")) Card.parse(c)];

	/** Passes seats 1,2,3 in turn so the next bidder is seat 0, then seat 0 opens. **/
	function openFromSeat0(g:Bridge, level:Int, strain:games.bridge.Strain):Void {
		g.pass(1);
		g.pass(2);
		g.pass(3);
		g.bid(0, level, strain);
	}

	function closeAuction(g:Bridge):Void {
		g.pass(1);
		g.pass(2);
		g.pass(3);
	}

	function testCanBidRequiresAHigherLevelOrStrainThanTheCurrentHighBid() {
		var g = new Bridge();
		g.startHand([for (_ in 0...4) h("2c 3c 4c 5c 6c 7c 8c 9c Tc Jc Qc Kc Ac")]);
		Assert.isTrue(g.canBid(1, ClubsStrain));
		g.pass(1);
		g.bid(2, 1, HeartsStrain);
		Assert.isFalse(g.canBid(1, ClubsStrain)); // same level, lower strain
		Assert.isFalse(g.canBid(1, DiamondsStrain)); // same level, lower strain
		Assert.isTrue(g.canBid(1, SpadesStrain)); // same level, higher strain
		Assert.isTrue(g.canBid(1, NoTrumpStrain)); // same level, higher strain
		Assert.isTrue(g.canBid(2, ClubsStrain)); // higher level, any strain
	}

	function testFourPassesWithNoBidThrowsTheHandIn() {
		var g = new Bridge();
		g.startHand([for (_ in 0...4) h("2c 3c 4c 5c 6c 7c 8c 9c Tc Jc Qc Kc Ac")]);
		g.pass(1);
		g.pass(2);
		g.pass(3);
		g.pass(0);
		Assert.isTrue(g.thrownIn);
		Assert.equals(HandOver, g.phase);
	}

	function testThreePassesAfterABidSettlesTheContract() {
		var g = new Bridge();
		g.startHand([for (_ in 0...4) h("2c 3c 4c 5c 6c 7c 8c 9c Tc Jc Qc Kc Ac")]);
		openFromSeat0(g, 3, SpadesStrain);
		closeAuction(g);
		Assert.equals(Playing, g.phase);
		Assert.equals(0, g.declarer);
		Assert.equals(2, g.dummy);
		Assert.equals(3, g.contractLevel);
		Assert.equals(SpadesStrain, g.contractStrain);
		Assert.equals(cards.Suit.Spades, g.trump);
		Assert.equals(1, g.turn); // left of declarer leads
	}

	function testNoTrumpContractHasNoTrumpSuit() {
		var g = new Bridge();
		g.startHand([for (_ in 0...4) h("2c 3c 4c 5c 6c 7c 8c 9c Tc Jc Qc Kc Ac")]);
		openFromSeat0(g, 1, NoTrumpStrain);
		closeAuction(g);
		Assert.isNull(g.trump);
	}

	function testMustFollowLedSuitWhenHoldingIt() {
		var g = new Bridge();
		var seat0 = h("2d 3d 4d 5d 6d 7d 8s 9s Ts Js Qs Ks As");
		var seat1 = h("8d 9d Td Jd Qd Kd Ad 2s 3s 4s 5s 6s 7s");
		var seat2 = h("2c 3c 4c 5c 6c 7c 8c 9c Tc Jc Qc Kc Ac");
		var seat3 = h("2h 3h 4h 5h 6h 7h 8h 9h Th Jh Qh Kh Ah");
		g.startHand([seat0, seat1, seat2, seat3]);
		openFromSeat0(g, 1, NoTrumpStrain);
		closeAuction(g);
		Assert.equals(1, g.turn);
		g.play(1, Card.parse("8d")); // leads a diamond
		g.play(2, g.legalPlays(2)[0]); // dummy can't follow, discards a club
		g.play(3, g.legalPlays(3)[0]); // can't follow either, discards a heart
		var legal = g.legalPlays(0);
		Assert.equals(6, legal.length);
		for (c in legal) Assert.equals(cards.Suit.Diamonds, c.suit);
	}

	function testMakingTheContractAwardsTrickPointsPlusBonus() {
		var g = new Bridge();
		// Declarer holds every spade (trump); dummy every club; opponents split diamonds/hearts.
		// With no other spade in play, declarer trumps in on every single trick and sweeps all 13.
		var declarerHand = h("2s 3s 4s 5s 6s 7s 8s 9s Ts Js Qs Ks As");
		var dummyHand = h("2c 3c 4c 5c 6c 7c 8c 9c Tc Jc Qc Kc Ac");
		var opp1 = h("2d 3d 4d 5d 6d 7d 8d 9d Td Jd Qd Kd Ad");
		var opp3 = h("2h 3h 4h 5h 6h 7h 8h 9h Th Jh Qh Kh Ah");
		g.startHand([declarerHand, opp1, dummyHand, opp3]);
		openFromSeat0(g, 7, SpadesStrain);
		closeAuction(g);
		while (g.phase == Playing) {
			var seat = g.turn;
			g.play(seat, g.legalPlays(seat)[0]);
		}
		Assert.equals(HandOver, g.phase);
		Assert.isTrue(g.lastMade);
		Assert.equals(13, g.tricks[0] + g.tricks[2]);
		Assert.equals(7 * 30 + 50, g.lastPoints); // major-suit tricks, no first-trick NT bonus
		Assert.equals(g.lastPoints, g.scores[0]);
		Assert.equals(0, g.scores[1]);
	}

	function testFailingTheContractAwardsUndertrickPointsToTheDefense() {
		var g = new Bridge();
		// Opponent (seat 1) holds every club (trump) and sweeps all 13 tricks; declarer's side gets none.
		var declarerHand = h("2d 3d 4d 5d 6d 7d 8d 9d Td Jd Qd Kd Ad");
		var oppTrump = h("2c 3c 4c 5c 6c 7c 8c 9c Tc Jc Qc Kc Ac");
		var dummyHand = h("2h 3h 4h 5h 6h 7h 8h 9h Th Jh Qh Kh Ah");
		var opp3 = h("2s 3s 4s 5s 6s 7s 8s 9s Ts Js Qs Ks As");
		g.startHand([declarerHand, oppTrump, dummyHand, opp3]);
		openFromSeat0(g, 1, ClubsStrain);
		closeAuction(g);
		while (g.phase == Playing) {
			var seat = g.turn;
			g.play(seat, g.legalPlays(seat)[0]);
		}
		Assert.equals(HandOver, g.phase);
		Assert.isFalse(g.lastMade);
		Assert.equals(0, g.tricks[0] + g.tricks[2]);
		Assert.equals((7) * 50, g.lastPoints); // down 7, undoubled
		Assert.equals(g.lastPoints, g.scores[1]);
		Assert.equals(0, g.scores[0]);
	}
}
