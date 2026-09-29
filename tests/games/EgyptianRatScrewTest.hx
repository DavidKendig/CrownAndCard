// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import cards.Card;
import games.parlour.EgyptianRatScrew;
import rng.ChaChaRng;
import utest.Assert;

class EgyptianRatScrewTest extends utest.Test {
	static function rng(label:String) return ChaChaRng.fromSeed(TestUtil.countingSeed()).fork('test-ers/$label');

	static function h(codes:String):Array<Card> return [for (c in codes.split(" ")) Card.parse(c)];

	function testPlainCardsJustAdvanceTheTurn() {
		var g = EgyptianRatScrew.fromPiles([h("2c 3c"), h("4d 5d"), h("6h 7h"), h("8s 9s")], rng("a"));
		g.play();
		Assert.equals(1, g.turn);
		Assert.equals(1, g.center.length);
		g.play();
		Assert.equals(2, g.turn);
	}

	function testAceChallengesFourChancesThenTheOwnerTakesThePile() {
		// Seat 0 plays an ace; seat 1 must beat it in 4 chances and fails every time.
		var g = EgyptianRatScrew.fromPiles([h("As"), h("2d 3d 4d 5d"), h("6h"), h("7s")], rng("b"));
		g.play(); // seat 0: ace
		Assert.equals(1, g.turn);
		Assert.equals(4, g.challenge.remaining);
		Assert.equals(0, g.challenge.owner);
		for (_ in 0...4) g.play(); // seat 1 plays 4 plain cards
		Assert.isNull(g.challenge);
		Assert.equals(5, g.piles[0].length); // the ace plus the 4 losing cards
		Assert.equals(0, g.turn); // the winner leads next
	}

	function testAFaceCardDuringAChallengeResetsItToTheNextPlayer() {
		var g = EgyptianRatScrew.fromPiles([h("Ks 2c"), h("Qd 3d"), h("6h 7h"), h("8s 9s")], rng("c"));
		g.play(); // seat 0: king (3 chances)
		g.play(); // seat 1: queen -- resets the challenge onto seat 2, 2 chances
		Assert.equals(1, g.challenge.owner);
		Assert.equals(2, g.challenge.responder);
		Assert.equals(2, g.challenge.remaining);
	}

	function testChallengeResolvesImmediatelyIfTheResponderHasNoCards() {
		// Seat 1 has only one card against an ace's four chances: it resolves
		// as soon as they run out, without waiting for the chance count.
		var g = EgyptianRatScrew.fromPiles([h("As"), h("3d"), h("4h 5h"), h("6s 7s")], rng("d"));
		g.play(); // seat 0: ace, 4 chances
		Assert.equals(4, g.challenge.remaining);
		g.play(); // seat 1 plays their only card and still can't beat it
		Assert.isNull(g.challenge);
		Assert.equals(0, g.turn); // the owner leads next
	}

	function testDoublesAreSlappable() {
		var g = EgyptianRatScrew.fromPiles([h("2c"), h("2d")], rng("e"));
		g.play(); // seat 0: 2c
		g.play(); // seat 1: 2d -- matches
		Assert.equals("doubles", g.slappable());
		switch g.slap(1) {
			case Won(2, "doubles"):
			case other: Assert.fail('expected Won(2, doubles), got $other');
		}
		Assert.equals(0, g.center.length);
		Assert.equals(2, g.piles[1].length);
	}

	function testSandwichIsSlappable() {
		// Turns alternate 0,1,0: 5c, 9s, 5h -- the top card sandwiches the middle one.
		var g = EgyptianRatScrew.fromPiles([h("5c 5h"), h("9s")], rng("f"));
		g.play();
		g.play();
		g.play();
		Assert.equals("sandwich", g.slappable());
	}

	function testTopBottomIsSlappable() {
		// Turns alternate 0,1,0,1: 5c, 6h, 7d, 5s -- the top card matches the pile's first (bottom) card.
		var g = EgyptianRatScrew.fromPiles([h("5c 7d"), h("6h 5s")], rng("g"));
		g.play();
		g.play();
		g.play();
		g.play();
		Assert.equals("top-bottom", g.slappable());
	}

	function testMarriageIsSlappable() {
		var g = EgyptianRatScrew.fromPiles([h("Kc 6d"), h("Qh 9s")], rng("h"));
		g.play();
		g.play();
		Assert.equals("marriage", g.slappable());
	}

	function testFalseSlapBurnsACardToTheBottom() {
		var g = EgyptianRatScrew.fromPiles([h("2c 3c"), h("9d 8d")], rng("i"));
		g.play();
		Assert.equals("", g.slappable());
		switch g.slap(1) {
			case Penalty:
			case other: Assert.fail('expected Penalty, got $other');
		}
		Assert.equals(1, g.piles[1].length);
		Assert.equals(2, g.center.length);
		Assert.equals(1, g.center[0].seat); // the burned card sits at the bottom
	}

	function testAPlayerWithNoCardsCanStillSlapBackIn() {
		var g = EgyptianRatScrew.fromPiles([h("2c 2d"), h("3h")], rng("j"));
		g.piles[1] = []; // seat 1 is out of cards
		g.play(); // seat 0's first 2
		g.center.push({card: Card.parse("2s"), seat: 0}); // fake a double on top without a second card
		Assert.equals("doubles", g.slappable());
		switch g.slap(1) {
			case Won(2, "doubles"):
			case other: Assert.fail('expected a win, got $other');
		}
		Assert.equals(2, g.piles[1].length);
	}

	function testLastHolderWinsOnceThePileIsEmpty() {
		var g = EgyptianRatScrew.fromPiles([h("2c"), h("2d")], rng("k"));
		g.play();
		g.play(); // both piles empty now; the doubles on top are still slappable
		g.slap(0); // takes the 2-card center; seat 1 has nothing and the pile is empty
		Assert.equals(0, g.winner);
	}
}
