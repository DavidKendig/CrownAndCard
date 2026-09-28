// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import cards.Card;
import games.parlour.GoFish;
import games.parlour.GoFishAi;
import games.parlour.Klondike;
import games.parlour.Slapjack;
import games.parlour.War;
import rng.ChaChaRng;
import utest.Assert;

class ParlourTest extends utest.Test {
	static function h(codes:String):Array<Card> return codes == "" ? [] : [for (c in codes.split(" ")) Card.parse(c)];

	static function rng(label:String) return ChaChaRng.fromSeed(TestUtil.countingSeed()).fork('test-parlour/$label');

	// --- Slapjack ---

	function testSlapjackDealsEveryCard() {
		var g = new Slapjack(3, rng("sj-deal"));
		Assert.equals(52, g.count(0) + g.count(1) + g.count(2));
		Assert.equals(18, g.count(0));
	}

	function testSlappingAJackTakesThePile() {
		var g = Slapjack.fromPiles([h("2c 3c"), h("Jd 4d"), h("5h 6h")], rng("sj-jack"));
		g.flip(); // 2c
		g.flip(); // Jd
		Assert.isTrue(g.jackShowing);
		Assert.same(Won(2), g.slap(2));
		Assert.equals(4, g.count(2));
		Assert.equals(0, g.center.length);
	}

	function testWrongSlapPaysTheCardsOwner() {
		var g = Slapjack.fromPiles([h("2c 3c"), h("9d 4d"), h("5h 6h")], rng("sj-wrong"));
		g.flip(); // 2c from seat 0
		Assert.same(Penalty(0), g.slap(2));
		Assert.equals(2, g.count(0)); // 3c plus the paid card
		Assert.equals(1, g.count(2));
	}

	function testOutOfCardsGetsOneLastChance() {
		var g = Slapjack.fromPiles([h("2c"), h("3d Jd"), h("5h 6h 7h")], rng("sj-last"));
		g.flip(); // seat 0 plays its last card
		Assert.isTrue(g.lastChance[0]);
		g.flip(); // 3d
		g.flip(); // 5h
		g.flip(); // Jd (seat 0 is skipped)
		Assert.same(Won(4), g.slap(2));
		Assert.isTrue(g.out[0]);
	}

	function testSlapjackGameEnds() {
		var r = rng("sj-sim");
		var g = new Slapjack(3, r);
		var steps = 0;
		while (g.winner < 0 && steps++ < 20000) {
			if (g.jackShowing) {
				var s = r.below(3);
				while (g.out[s]) s = (s + 1) % 3;
				g.slap(s);
			} else g.flip();
		}
		Assert.isTrue(g.winner >= 0);
		Assert.equals(52, g.count(g.winner));
	}

	// --- Go Fish ---

	function testGoFishDealSizes() {
		Assert.equals(7, new GoFish(3, rng("gf-3")).hands[0].length);
		var four = new GoFish(4, rng("gf-4"));
		Assert.equals(5, four.hands[0].length + four.books[0].length * 4);
		Assert.equals(32, four.stock.length);
	}

	function testAskingHandsOverAllOfARank() {
		var g = GoFish.fromDeal([h("7c 9d"), h("7d 7h 2s"), h("3c")], h("4c 5c"), rng("gf-ask"));
		var r = g.ask(0, 1, 7);
		Assert.equals(2, r.got);
		Assert.isTrue(r.again);
		Assert.equals(0, g.turn);
		Assert.equals(1, g.hands[1].length);
	}

	function testGoFishDrawsAndPassesTheTurn() {
		var g = GoFish.fromDeal([h("7c 9d"), h("2s"), h("3c")], h("4c 5c"), rng("gf-fish"));
		var r = g.ask(0, 1, 9);
		Assert.equals(0, r.got);
		Assert.equals("4c", r.fished.code);
		Assert.isFalse(r.again);
		Assert.equals(1, g.turn);
	}

	function testFishingYourWishKeepsTheTurnAndBooksAreLaid() {
		var g = GoFish.fromDeal([h("9c 9d 9h 2d"), h("2s"), h("3c")], h("9s 5c"), rng("gf-wish"));
		var r = g.ask(0, 2, 9);
		Assert.isTrue(r.again);
		Assert.same([9], r.books);
		Assert.same([9], g.books[0]);
		Assert.equals(0, g.turn);
	}

	function testCannotAskForARankYouDoNotHold() {
		var g = GoFish.fromDeal([h("7c"), h("2s"), h("3c")], [], rng("gf-bad"));
		Assert.raises(() -> g.ask(0, 1, 2));
	}

	function testGoFishAiGamesFinish() {
		for (n in 0...4) {
			var r = rng('gf-sim/$n');
			var g = new GoFish(4, r);
			var ai = new GoFishAi(4, r);
			var steps = 0;
			while (!g.over && steps++ < 2000) {
				var c = ai.choose(g, g.turn);
				ai.observe(g.ask(g.turn, c.target, c.rank));
			}
			Assert.isTrue(g.over);
			Assert.equals(13, g.bookCount());
		}
	}

	// --- War ---

	function testHigherCardWins() {
		var g = War.fromStacks(h("Kc 2d"), h("Qh 3s"), rng("war-1"));
		var b = g.battle();
		Assert.equals(War.YOU, b.winner);
		Assert.equals(3, g.stacks[0].length); // 2d, then the won Kc and Qh underneath
		Assert.equals("Kc", g.stacks[0][1].code);
	}

	function testWarPutsOneDownOneUp() {
		var g = War.fromStacks(h("9c 2d Ac 5s"), h("9h 3s Kd 6h"), rng("war-2"));
		var b = g.battle();
		Assert.equals(2, b.faceUp.length);
		Assert.equals(6, b.cards);
		Assert.equals(War.YOU, b.winner);
		Assert.equals(7, g.stacks[0].length);
	}

	function testRunningOutInAWarLoses() {
		var g = War.fromStacks(h("9c"), h("9h 3s Kd"), rng("war-3"));
		var b = g.battle();
		Assert.equals(War.THEM, b.winner);
		Assert.equals(War.THEM, g.winner);
	}

	function testShortStackUsesLastCardFaceUp() {
		var g = War.fromStacks(h("9c Ac"), h("9h 3s Kd"), rng("war-4"));
		var b = g.battle();
		Assert.equals("Ac", b.faceUp[1][0].code);
		Assert.equals(War.YOU, b.winner);
	}

	// --- Klondike ---

	function testKlondikeDeal() {
		var g = new Klondike(rng("kl-deal"));
		for (i in 0...7) {
			Assert.equals(i + 1, g.tableau[i].length);
			Assert.equals(1, g.runLength(i));
		}
		Assert.equals(24, g.stock.length);
	}

	function testStockTurnsAndRecycles() {
		var g = new Klondike(rng("kl-stock"));
		for (_ in 0...24) g.turnStock();
		Assert.equals(0, g.stock.length);
		Assert.equals(24, g.waste.length);
		g.turnStock();
		Assert.equals(24, g.stock.length);
		Assert.equals(1, g.passes);
	}

	function testBuildingRules() {
		var g = new Klondike(rng("kl-rules"));
		// Rig the first two piles: black 8 onto red 9 is legal, red 8 isn't.
		g.tableau[0].resize(0);
		g.tableau[0].push({card: Card.parse("8s"), up: true});
		g.tableau[1].resize(0);
		g.tableau[1].push({card: Card.parse("4c"), up: false});
		g.tableau[1].push({card: Card.parse("9h"), up: true});
		Assert.isTrue(g.canMove(Tableau(0), 1, Tableau(1)));
		g.move(Tableau(0), 1, Tableau(1));
		Assert.equals(0, g.tableau[0].length);
		// Only a king may fill the space.
		Assert.isFalse(g.canMove(Tableau(1), 2, Tableau(0)));
		// Aces start foundations; a run moves as a unit.
		g.tableau[2].resize(0);
		g.tableau[2].push({card: Card.parse("Ad"), up: true});
		Assert.isTrue(g.canMove(Tableau(2), 1, Foundation(0)));
		g.move(Tableau(2), 1, Foundation(0));
		g.tableau[3].resize(0);
		g.tableau[3].push({card: Card.parse("Tc"), up: true});
		Assert.isTrue(g.canMove(Tableau(1), 2, Tableau(3)));
		g.move(Tableau(1), 2, Tableau(3));
		Assert.equals(3, g.tableau[3].length);
		Assert.isTrue(g.tableau[1][0].up); // the hidden 4c turned over
	}

	function testFoundationsBuildBySuitUpward() {
		var g = new Klondike(rng("kl-found"));
		g.foundations[0].push(Card.parse("Ah"));
		g.tableau[0].resize(0);
		g.tableau[0].push({card: Card.parse("2h"), up: true});
		g.tableau[1].resize(0);
		g.tableau[1].push({card: Card.parse("2s"), up: true});
		Assert.equals(0, g.foundationFor(Tableau(0)));
		Assert.equals(-1, g.foundationFor(Tableau(1)));
	}
}
