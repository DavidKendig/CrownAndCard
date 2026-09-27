// SPDX-License-Identifier: AGPL-3.0-or-later
package cards;

import utest.Assert;

class CardTest extends utest.Test {
	function testRankAndSuitRoundTrip() {
		for (i in 0...Card.COUNT) {
			var c = Card.fromIndex(i);
			Assert.equals(i, Card.of(c.rank, c.suit).index);
		}
	}

	function testParseAndCode() {
		Assert.equals("As", Card.parse("As").code);
		Assert.equals("Td", Card.parse("10d").code);
		Assert.equals("2c", Card.parse("2C").code);
		Assert.equals(Card.ACE, Card.parse("Ah").rank);
		Assert.equals(Suit.Hearts, Card.parse("Ah").suit);
	}

	function testParseRejectsGarbage() {
		Assert.raises(() -> Card.parse("Zz"));
		Assert.raises(() -> Card.parse("1s"));
		Assert.raises(() -> Card.parse(""));
	}

	function testDisplayName() {
		Assert.equals("A♠", Card.parse("As").toString());
		Assert.equals("10♥", Card.parse("Th").toString());
	}

	function testRangeChecks() {
		Assert.raises(() -> Card.of(1, Suit.Clubs));
		Assert.raises(() -> Card.of(15, Suit.Clubs));
		Assert.raises(() -> Card.fromIndex(52));
	}

	function testStandardDeckHasEveryCardOnce() {
		var deck = Deck.standard();
		Assert.equals(52, deck.length);
		var seen = [for (_ in 0...52) false];
		for (c in deck)
			seen[c.index] = true;
		Assert.equals(-1, seen.indexOf(false));
	}

	function testEuchreDeckIsNineThroughAce() {
		var deck = Deck.euchre();
		Assert.equals(24, deck.length);
		for (c in deck)
			Assert.isTrue(c.rank >= 9);
	}

	function testSuitColors() {
		Assert.isTrue(Suit.Hearts.isRed);
		Assert.isTrue(Suit.Diamonds.isRed);
		Assert.isFalse(Suit.Spades.isRed);
		Assert.isFalse(Suit.Clubs.isRed);
	}
}
