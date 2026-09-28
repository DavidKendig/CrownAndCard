// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import cards.Card;
import games.blackjack.Blackjack;
import rng.ChaChaRng;
import utest.Assert;

/** Deals a fixed card order: player, dealer up, player, dealer hole, then draws. **/
private class Stacked implements CardSource {
	final cards:Array<Card>;
	var pos = 0;

	public function new(codes:String) {
		cards = [for (c in codes.split(" ")) Card.parse(c)];
	}

	public function draw():Card {
		if (pos >= cards.length) throw 'Stacked deck ran out';
		return cards[pos++];
	}

	public function beforeRound():Bool return false;
}

class BlackjackTest extends utest.Test {
	function table(codes:String, purse = 1000):Blackjack {
		return new Blackjack(new Stacked(codes), purse);
	}

	function testTotalsAndSoftness() {
		Assert.equals(21, Blackjack.total(hand("As Kd")));
		Assert.isTrue(Blackjack.isSoft(hand("As 6d")));
		Assert.equals(17, Blackjack.total(hand("As 6d")));
		Assert.equals(12, Blackjack.total(hand("As Ad")));
		Assert.equals(21, Blackjack.total(hand("As Ad 9c")));
		Assert.isFalse(Blackjack.isSoft(hand("As 6d Tc")));
		Assert.equals(17, Blackjack.total(hand("As 6d Tc")));
		Assert.equals(22, Blackjack.total(hand("Kh Qd 2c")));
	}

	function testBetsMustBeEvenAndWithinLimits() {
		var bj = table("9s 7d 9h Tc", 30);
		Assert.isFalse(bj.canBet(1));
		Assert.isFalse(bj.canBet(3));
		Assert.isFalse(bj.canBet(52));
		Assert.isFalse(bj.canBet(40)); // more than the purse
		Assert.isTrue(bj.canBet(2));
		Assert.isTrue(bj.canBet(30));
		Assert.raises(() -> bj.deal(5));
	}

	function testNaturalPaysThreeToTwo() {
		var bj = table("As 9d Kh 7c");
		bj.deal(10);
		Assert.equals(RoundOver, bj.phase);
		Assert.equals(Natural, bj.hands[0].outcome);
		Assert.equals(1015, bj.purse);
		Assert.isTrue(bj.holeRevealed);
	}

	function testDealerStandsOnSoft17AndPlayerWins() {
		// Player 18, dealer A-6 (soft 17) stands.
		var bj = table("Ts As 8h 6d");
		bj.deal(10);
		bj.insure(false);
		bj.act(Stand);
		Assert.equals(17, bj.dealerTotal);
		Assert.equals(2, bj.dealer.length);
		Assert.equals(Win, bj.hands[0].outcome);
		Assert.equals(1010, bj.purse);
	}

	function testDealerDrawsToSeventeenAndBusts() {
		// Player 20; dealer 6-T draws the 8 and busts.
		var bj = table("Ts 6d Kh Tc 8s");
		bj.deal(10);
		bj.act(Stand);
		Assert.equals(24, bj.dealerTotal);
		Assert.equals(Win, bj.hands[0].outcome);
		Assert.equals(1010, bj.purse);
	}

	function testBustLosesWithoutDealerDrawing() {
		var bj = table("Ts 6d 5h Tc Kd 9s");
		bj.deal(10);
		bj.act(Hit);
		Assert.equals(Bust, bj.hands[0].outcome);
		Assert.equals(2, bj.dealer.length); // no live hands: the dealer doesn't draw
		Assert.equals(990, bj.purse);
	}

	function testPushReturnsTheBet() {
		var bj = table("Ts 9d 8h 9c");
		bj.deal(10);
		bj.act(Stand);
		Assert.equals(Push, bj.hands[0].outcome);
		Assert.equals(1000, bj.purse);
	}

	function testDoubleTakesOneCardAtDoubleStake() {
		var bj = table("6s 9d 5h 8c Td 5s");
		bj.deal(10);
		bj.act(Double);
		Assert.equals(3, bj.hands[0].cards.length);
		Assert.equals(20, bj.hands[0].bet);
		// Dealer 17 against 21.
		Assert.equals(Win, bj.hands[0].outcome);
		Assert.equals(1020, bj.purse);
	}

	function testSplitPlaysTwoHandsAndAllowsDoubleAfterSplit() {
		// Player 8-8 vs dealer 6. Split: hand 1 gets 3 (11), doubles onto T (21); hand 2 gets 9 (17), stands.
		// Dealer 6-T draws 7: 23, bust.
		var bj = table("8s 6d 8h Tc 3d Th 9c 7s");
		bj.deal(10);
		Assert.isTrue(bj.legal().indexOf(Split) >= 0);
		bj.act(Split);
		Assert.equals(2, bj.hands.length);
		Assert.equals(11, bj.hands[0].total);
		Assert.isTrue(bj.legal().indexOf(Double) >= 0);
		Assert.isTrue(bj.legal().indexOf(Surrender) < 0);
		bj.act(Double);
		Assert.equals(1, bj.active);
		Assert.equals(17, bj.hands[1].total);
		bj.act(Stand);
		Assert.equals(RoundOver, bj.phase);
		Assert.equals(Win, bj.hands[0].outcome);
		Assert.equals(Win, bj.hands[1].outcome);
		Assert.equals(1030, bj.purse);
	}

	function testSplitAcesGetOneCardEachAndTwentyOneIsNotBlackjack() {
		var bj = table("As 7d Ah Tc Kd 5s");
		bj.deal(10);
		bj.act(Split);
		Assert.equals(RoundOver, bj.phase);
		Assert.equals(21, bj.hands[0].total);
		Assert.isFalse(bj.hands[0].natural);
		Assert.equals(Win, bj.hands[0].outcome); // pays 1:1, not 3:2
		Assert.equals(16, bj.hands[1].total);
		Assert.equals(Lose, bj.hands[1].outcome);
		Assert.equals(1000, bj.purse);
	}

	function testSplitLimitIsFourHands() {
		var bj = table("8s 6d 8h Tc 8d 8c 8s 8h 8d 8c");
		bj.deal(2);
		bj.act(Split);
		bj.act(Split);
		bj.act(Split);
		Assert.equals(4, bj.hands.length);
		Assert.isTrue(bj.legal().indexOf(Split) < 0);
	}

	function testLateSurrenderReturnsHalf() {
		var bj = table("Ts 9d 6h Tc");
		bj.deal(10);
		bj.act(Surrender);
		Assert.equals(Surrendered, bj.hands[0].outcome);
		Assert.equals(995, bj.purse);
	}

	function testDealerPeekEndsRoundBeforeSurrender() {
		// Dealer shows T with an ace underneath: no chance to surrender.
		var bj = table("Ts Td 6h Ac");
		bj.deal(10);
		Assert.equals(RoundOver, bj.phase);
		Assert.equals(Lose, bj.hands[0].outcome);
		Assert.equals(990, bj.purse);
	}

	function testInsurancePaysTwoToOne() {
		var bj = table("Ts Ad 7h Kc");
		bj.deal(10);
		Assert.equals(Insurance, bj.phase);
		bj.insure(true);
		Assert.equals(RoundOver, bj.phase);
		Assert.equals(15, bj.insurancePayout);
		// Lost 10, insurance of 5 paid 10 more: even.
		Assert.equals(1000, bj.purse);
	}

	function testLostInsuranceAndPlayContinues() {
		var bj = table("Ts Ad 7h 6c 4s");
		bj.deal(10);
		bj.insure(true);
		Assert.equals(PlayerTurn, bj.phase);
		bj.act(Stand);
		// Dealer A-6 is a soft 17 and stands against the player's 17: a push. The insurance is lost.
		Assert.equals(Push, bj.hands[0].outcome);
		Assert.equals(995, bj.purse);
	}

	function testRevealOrderFollowsTheDeal() {
		var bj = table("Ts 6d Kh Tc 8s");
		bj.deal(10);
		Assert.same([0, 2], bj.hands[0].order);
		Assert.same([1, 3], bj.dealerOrder.slice(0, 2));
		bj.act(Stand);
		Assert.equals(4, bj.holeRevealOrder);
		Assert.equals(4, bj.dealerOrder[2]);
	}

	/** Thousands of rounds from a real shoe: money always balances and nothing throws. **/
	function testLongSessionConservesMoney() {
		var bj = new Blackjack(new ShoeSource(ChaChaRng.fromSeed(TestUtil.countingSeed()).fork("test-blackjack")), 100000);
		for (round in 0...3000) {
			var before = bj.purse;
			bj.deal(Blackjack.BETS[round % Blackjack.BETS.length]);
			if (bj.phase == Insurance) bj.insure(round % 3 == 0);
			while (bj.phase == PlayerTurn) {
				var legal = bj.legal();
				var h = bj.current;
				var choice = legal.indexOf(Split) >= 0 && round % 2 == 0 ? Split
					: legal.indexOf(Double) >= 0 && h.total == 11 ? Double
					: h.total < 17 && legal.indexOf(Hit) >= 0 ? Hit : Stand;
				bj.act(choice);
			}
			Assert.equals(RoundOver, bj.phase);
			if (bj.purse - before != bj.returned - bj.staked) {
				Assert.fail('Round $round: purse moved ${bj.purse - before}, ledger says ${bj.returned - bj.staked}');
				return;
			}
		}
		Assert.pass();
	}

	static function hand(codes:String):Array<Card> {
		return [for (c in codes.split(" ")) Card.parse(c)];
	}
}
