// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import cards.Card;
import cards.Suit;
import games.spades.SpadesGame;
import games.spades.SpadesAi;
import rng.ChaChaRng;
import utest.Assert;

class SpadesTest extends utest.Test {
	/** South holds every spade, West hearts, North clubs, East diamonds. **/
	function oneSuitEach():Array<Array<Card>> {
		var suits = [Suit.Spades, Suit.Hearts, Suit.Clubs, Suit.Diamonds];
		return [for (s in 0...4) [for (r in 2...15) Card.of(r, suits[s])]];
	}

	function testBiddingStartsLeftOfTheDealerAndLeadsFromThere() {
		var g = new SpadesGame();
		g.startHand(oneSuitEach());
		Assert.equals(0, g.dealer);
		Assert.equals(1, g.turn);
		g.bid(1, 0);
		g.bid(2, 1);
		g.bid(3, 1);
		Assert.equals(Bidding, g.phase);
		Assert.raises(() -> g.bid(1, 3)); // not West's turn
		g.bid(0, 12);
		Assert.equals(Playing, g.phase);
		Assert.equals(1, g.turn);
	}

	function testWholeHandWithNilAndSetContract() {
		var g = new SpadesGame();
		g.startHand(oneSuitEach());
		g.bid(1, 0); // West nil
		g.bid(2, 1); // North 1
		g.bid(3, 1); // East 1
		g.bid(0, 12); // South 12
		while (g.phase == Playing) g.play(g.turn, SpadesAi.play(g, g.turn));
		Assert.equals(13, g.tricks[0]);
		Assert.equals(HandOver, g.phase);
		// Us: bid 13, took 13. Them: West's nil made (+100), East's 1 set (-10).
		Assert.equals(130, g.scores[0]);
		Assert.equals(90, g.scores[1]);
		Assert.isTrue(g.lastResults[1].nils[0].made);
	}

	function testFollowSuitAndSpadeLeadRules() {
		var g = new SpadesGame();
		var hands = oneSuitEach();
		// Give West a spade in place of one heart, and South that heart.
		var twoOfSpades = hands[0].shift(), twoOfHearts = hands[1].shift();
		hands[0].push(twoOfHearts);
		hands[1].push(twoOfSpades);
		g.startHand(hands);
		for (s in [1, 2, 3, 0]) g.bid(s, 3);
		// West may not lead the spade before spades are broken.
		for (c in g.legalPlays(1)) Assert.isTrue(c.suit == Suit.Hearts);
		g.play(1, Card.parse("Ah"));
		Assert.isFalse(g.spadesBroken);
		// North and East have no hearts: anything goes.
		Assert.equals(13, g.legalPlays(2).length);
		g.play(2, Card.parse("2c"));
		g.play(3, Card.parse("2d"));
		// South holds the two of hearts and must follow with it.
		Assert.same([twoOfHearts.index], [for (c in g.legalPlays(0)) c.index]);
		g.play(0, twoOfHearts);
		Assert.equals(1, g.lastWinner); // West's ace of hearts
		Assert.equals(1, g.turn);
	}

	function testSpadesTrumpAndOffSuitNeverWins() {
		var ah = Card.parse("Ah"), two = Card.parse("2s"), kc = Card.parse("Kc"), th = Card.parse("Th");
		Assert.isTrue(SpadesGame.beats(two, ah, Suit.Hearts));
		Assert.isFalse(SpadesGame.beats(kc, th, Suit.Hearts));
		var w = SpadesGame.winning([{seat: 0, card: th}, {seat: 1, card: kc}, {seat: 2, card: ah}, {seat: 3, card: two}]);
		Assert.equals(3, w.seat);
	}

	function testScoringContractsBagsAndPenalty() {
		var bids:Array<Null<Int>> = [4, 0, 3, 0], blind = [false, false, false, false];
		// Team 0 bid 7, took 9: 70 + 2 bags. Starting on 9 bags: penalty.
		var r = SpadesGame.scoreTeam(0, bids, blind, [5, 0, 4, 0], 9);
		Assert.equals(7, r.result.bid);
		Assert.equals(2, r.result.bags);
		Assert.equals(72 - 100, r.result.points);
		Assert.equals(1, r.bagsAfter);
		Assert.isTrue(r.result.bagPenalty);
		// Set: took 6 of 7.
		Assert.equals(-70, SpadesGame.scoreTeam(0, bids, blind, [3, 0, 3, 0], 0).result.points);
	}

	function testNilAndBlindNilScoring() {
		var bids:Array<Null<Int>> = [0, 3, 5, 3];
		var made = SpadesGame.scoreTeam(0, bids, [false, false, false, false], [0, 0, 5, 0], 0);
		Assert.equals(100 + 50, made.result.points);
		var failed = SpadesGame.scoreTeam(0, bids, [true, false, false, false], [2, 0, 5, 0], 0);
		// Blind nil failed: -200, plus 2 bags at a point each; partner made 5.
		Assert.equals(-200 + 2 + 50, failed.result.points);
		Assert.equals(2, failed.bagsAfter);
	}

	function testBlindNilOnlyWhenTrailingByAHundred() {
		var g = new SpadesGame();
		g.startHand(oneSuitEach());
		Assert.isFalse(g.canBidBlindNil(1));
		Assert.raises(() -> g.bid(1, 0, true));
	}

	function testGameEnds() {
		Assert.equals(-1, SpadesGame.decideWinner(480, 300));
		Assert.equals(0, SpadesGame.decideWinner(510, 300));
		Assert.equals(1, SpadesGame.decideWinner(505, 520));
		Assert.equals(-1, SpadesGame.decideWinner(500, 500));
		Assert.equals(1, SpadesGame.decideWinner(-200, 40));
	}

	/** AI-only games from seeded deals: every play is legal, every hand has 13 tricks, and games finish. **/
	function testAiGamesRunToCompletion() {
		var master = ChaChaRng.fromSeed(TestUtil.countingSeed());
		for (n in 0...6) {
			var rng = master.fork('test-spades/$n');
			var g = new SpadesGame();
			var hands = 0;
			while (g.phase != GameOver && hands < 60) {
				g.dealFrom(rng);
				hands++;
				while (g.phase == Bidding) g.bid(g.turn, SpadesAi.bid(g, g.turn));
				for (s in 0...4) Assert.isTrue(g.bids[s] >= 0 && g.bids[s] <= 13);
				while (g.phase == Playing) g.play(g.turn, SpadesAi.play(g, g.turn));
				var total = 0;
				for (t in g.tricks) total += t;
				Assert.equals(13, total);
			}
			Assert.equals(GameOver, g.phase);
			Assert.isTrue(g.winner == 0 || g.winner == 1);
		}
	}
}
