// SPDX-License-Identifier: AGPL-3.0-or-later
package games.parlour;

import cards.Card;
import cards.Deck;

/** One battle: the face-up cards each war turned over, and who took the lot. **/
typedef Battle = {
	/** Face-up pairs, [you, them], one per round of the battle (more than one means war). **/
	var faceUp:Array<Array<Card>>;

	/** Every card won, face-down ones included. **/
	var cards:Int;

	var winner:Int;
}

/**
	War (bicyclecards.com): 26 cards each. Both turn up a card; the higher
	rank (aces high) takes both, to the bottom of their stack. Equal ranks
	mean war: each puts one card face down and one face up, and the higher
	face-up card takes everything; repeat while they match. First to hold all
	52 wins.

	House rule for what the printed rules leave open: a player who runs short
	in a war turns up their last card instead; one with no cards at all loses.
**/
class War {
	public static inline var YOU = 0;
	public static inline var THEM = 1;

	/** Index 0 is the top of each stack. **/
	public final stacks:Array<Array<Card>>;

	public var winner(default, null) = -1;
	public var battles(default, null) = 0;

	public function new(rng:rng.IRng) {
		var deck = Deck.standard();
		rng.shuffle(deck);
		stacks = [[for (i in 0...26) deck[i * 2]], [for (i in 0...26) deck[i * 2 + 1]]];
	}

	public static function fromStacks(a:Array<Card>, b:Array<Card>, rng:rng.IRng):War {
		var g = new War(rng);
		g.stacks[0] = a.copy();
		g.stacks[1] = b.copy();
		return g;
	}

	public function battle():Battle {
		if (winner >= 0) throw 'The game is over';
		battles++;
		var pile:Array<Card> = [];
		var faceUp:Array<Array<Card>> = [];
		while (true) {
			// Each turns up a card (the last one, if short during a war).
			var up = [for (p in 0...2) stacks[p].shift()];
			pile.push(up[0]);
			pile.push(up[1]);
			faceUp.push(up);
			if (up[0].rank != up[1].rank) {
				var w = up[0].rank > up[1].rank ? YOU : THEM;
				for (c in pile) stacks[w].push(c);
				return finish(faceUp, pile.length, w);
			}
			// War: one face down, then another face up. Out of cards entirely loses.
			for (p in 0...2) if (stacks[p].length == 0) {
				var w = 1 - p;
				for (c in pile) stacks[w].push(c);
				return finish(faceUp, pile.length, w);
			}
			for (p in 0...2) if (stacks[p].length > 1) pile.push(stacks[p].shift());
		}
	}

	function finish(faceUp:Array<Array<Card>>, count:Int, w:Int):Battle {
		if (stacks[1 - w].length == 0) winner = w;
		return {faceUp: faceUp, cards: count, winner: w};
	}
}
