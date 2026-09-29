// SPDX-License-Identifier: AGPL-3.0-or-later
package games.hearts;

import cards.Card;
import cards.Suit;

/** Simple heuristic Hearts: shed the dangerous cards early, duck when it can't be helped, dump the queen when it's safe. **/
class HeartsAi {
	public static function choosePass(hand:Array<Card>):Array<Card> {
		var sorted = hand.copy();
		sorted.sort((a, b) -> risk(b) - risk(a));
		return sorted.slice(0, 3);
	}

	static function risk(c:Card):Int {
		if (c.suit == Suit.Spades && c.rank == Card.QUEEN) return 200;
		if (c.suit == Suit.Spades && c.rank > Card.QUEEN) return 150 + c.rank;
		if (c.suit == Suit.Hearts) return 100 + c.rank;
		return c.rank;
	}

	public static function play(game:Hearts, seat:Int):Card {
		var legal = game.legalPlays(seat);
		if (legal.length == 1) return legal[0];
		if (game.trick.length == 0) return lead(legal);
		var led = game.trick[0].card.suit;
		var winning = game.trick[0];
		for (p in game.trick) if (p.card.suit == led && p.card.rank > winning.card.rank) winning = p;
		var following = [for (c in legal) if (c.suit == led) c];
		var last = game.trick.length == games.hearts.Hearts.SEATS - 1;
		if (following.length > 0) {
			var under = [for (c in following) if (c.rank < winning.card.rank) c];
			if (under.length > 0) return highest(under);
			if (led == Suit.Spades && winning.card.rank < Card.QUEEN) {
				for (c in following) if (c.rank == Card.QUEEN) return c; // safely dump the queen
			}
			return last ? highest(following) : lowest(following);
		}
		var sorted = legal.copy();
		sorted.sort((a, b) -> risk(b) - risk(a));
		return sorted[0];
	}

	/** A low card from whatever's least risky to lead. **/
	static function lead(legal:Array<Card>):Card {
		var sorted = legal.copy();
		sorted.sort((a, b) -> risk(a) - risk(b));
		return sorted[0];
	}

	static function lowest(cards:Array<Card>):Card {
		var best = cards[0];
		for (c in cards) if (c.rank < best.rank) best = c;
		return best;
	}

	static function highest(cards:Array<Card>):Card {
		var best = cards[0];
		for (c in cards) if (c.rank > best.rank) best = c;
		return best;
	}
}
