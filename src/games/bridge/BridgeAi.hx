// SPDX-License-Identifier: AGPL-3.0-or-later
package games.bridge;

import cards.Card;
import cards.Suit;
import games.bridge.Bridge.Strain;

/** Simple heuristic Bridge: high-card points and suit length to bid, follow suit to win cheaply or duck. **/
class BridgeAi {
	static function highCardPoints(hand:Array<Card>):Int {
		var points = 0;
		for (c in hand) points += c.rank == Card.ACE ? 4 : c.rank == Card.KING ? 3 : c.rank == Card.QUEEN ? 2 : c.rank == Card.JACK ? 1 : 0;
		return points;
	}

	static function suitLength(hand:Array<Card>, suit:Suit):Int {
		var n = 0;
		for (c in hand) if (c.suit == suit) n++;
		return n;
	}

	/** A bid this hand supports, or null to pass. **/
	public static function chooseBid(game:Bridge, seat:Int):Null<{level:Int, strain:Strain}> {
		var hand = game.hands[seat];
		var points = highCardPoints(hand);
		if (points < 10) return null;
		var bestSuit = Suit.Clubs, bestLen = 0;
		for (suit in Suit.ALL) {
			var len = suitLength(hand, suit);
			if (len > bestLen) {
				bestLen = len;
				bestSuit = suit;
			}
		}
		var suitAsInt:Int = bestSuit;
		var strain:Strain = bestLen >= 4 ? cast suitAsInt : NoTrumpStrain;
		var level = points >= 22 ? 4 : points >= 16 ? 3 : points >= 13 ? 2 : 1;
		for (l in level...8) if (game.canBid(l, strain)) return {level: l, strain: strain};
		return null;
	}

	public static function play(game:Bridge, seat:Int):Card {
		var legal = game.legalPlays(seat);
		if (legal.length == 1) return legal[0];
		if (game.trick.length == 0) return lowest(legal);
		var led = game.trick[0].card.suit;
		var winning = game.trick[0];
		for (p in game.trick) if (beats(game, p.card, winning.card, led)) winning = p;
		var partnerWinning = winning.seat == Bridge.partnerOf(seat) || winning.seat == seat;
		var winners = [for (c in legal) if (beats(game, c, winning.card, led)) c];
		if (partnerWinning) return lowest(legal);
		if (winners.length > 0) return lowest(winners);
		return lowest(legal);
	}

	static function beats(game:Bridge, a:Card, b:Card, led:Suit):Bool {
		if (a.suit == b.suit) return a.rank > b.rank;
		if (game.trump != null && a.suit == game.trump) return true;
		if (game.trump != null && b.suit == game.trump) return false;
		return a.suit == led;
	}

	static function lowest(cards:Array<Card>):Card {
		var best = cards[0];
		for (c in cards) if (c.rank < best.rank) best = c;
		return best;
	}
}
