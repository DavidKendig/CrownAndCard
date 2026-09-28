// SPDX-License-Identifier: AGPL-3.0-or-later
package games.spades;

import cards.Card;
import cards.Suit;
import games.spades.SpadesGame.Play;

/**
	Normal-difficulty Spades play (§9.3): rule-based bidding and card play with
	card tracking (played cards and shown voids). Deterministic: the same
	position always gets the same answer, so it needs no random stream.
**/
class SpadesAi {
	public static function bid(game:SpadesGame, seat:Int):Int {
		var hand = game.hands[seat];
		var partnerBid = game.bids[SpadesGame.partnerOf(seat)];
		var spades = ranks(hand, Suit.Spades);
		var estimate = 0.0;
		for (suit in [Suit.Hearts, Suit.Clubs, Suit.Diamonds]) {
			var r = ranks(hand, suit), len = r.length;
			var hasA = r.indexOf(Card.ACE) >= 0, hasK = r.indexOf(Card.KING) >= 0, hasQ = r.indexOf(Card.QUEEN) >= 0;
			if (hasA) estimate += len <= 5 ? 1 : 0.6;
			if (hasK && len >= 2 && len <= 5) estimate += hasA ? 0.9 : 0.6;
			if (hasQ && len >= 3 && len <= 4 && (hasA || hasK)) estimate += 0.3;
			// Short suits let spare spades ruff.
			var spare = spades.length - 3;
			if (len == 0 && spare >= 0) estimate += spades.length >= 4 ? 1.2 : 0.7;
			else if (len == 1 && spare >= 1) estimate += 0.5;
		}
		var s = spades.length;
		if (spades.indexOf(Card.ACE) >= 0) estimate += 1;
		if (spades.indexOf(Card.KING) >= 0) estimate += s >= 2 ? 1 : 0.4;
		if (spades.indexOf(Card.QUEEN) >= 0) estimate += s >= 3 ? 0.9 : 0.2;
		if (spades.indexOf(Card.JACK) >= 0 && s >= 4) estimate += 0.6;
		if (s > 4) estimate += (s - 4) * 0.8;

		// Nil: very few winners, no high spades, and the partner isn't already nil.
		var highSpade = s == 0 ? 0 : spades[0];
		var aces = 0;
		for (c in hand) if (c.rank == Card.ACE) aces++;
		if (estimate < 1.3 && highSpade <= 10 && s <= 3 && aces == 0 && partnerBid != 0) return 0;

		var result = Std.int(Math.max(1, Math.round(estimate)));
		// Keep the side's contract possible.
		if (partnerBid != null && partnerBid + result > SpadesGame.HAND_SIZE) result = SpadesGame.HAND_SIZE - partnerBid;
		return Std.int(Math.max(1, Math.min(SpadesGame.HAND_SIZE, result)));
	}

	public static function play(game:SpadesGame, seat:Int):Card {
		var legal = game.legalPlays(seat);
		if (legal.length == 0) throw 'Seat $seat has no legal play';
		if (legal.length == 1) return legal[0];
		var partner = SpadesGame.partnerOf(seat);
		var myNil = game.bids[seat] == 0 && game.tricks[seat] == 0;
		var partnerNil = game.bids[partner] == 0 && game.tricks[partner] == 0;
		var trick = game.trick;
		var team = SpadesGame.teamOf(seat);
		var contractMade = game.teamBid(team) > 0 && game.teamTricks(team) >= game.teamBid(team);

		if (trick.length == 0) return lead(game, seat, legal, myNil, partnerNil, contractMade);

		var led = trick[0].card.suit;
		var best = SpadesGame.winning(trick);
		var winners = [for (c in legal) if (SpadesGame.beats(c, best.card, led)) c];
		var losers = [for (c in legal) if (!SpadesGame.beats(c, best.card, led)) c];
		var last = trick.length == SpadesGame.SEATS - 1;

		if (myNil) return losers.length > 0 ? highest(losers) : highest(legal);

		if (partnerNil) {
			var partnerPlayed = false;
			for (p in trick) if (p.seat == partner) partnerPlayed = true;
			// Cover the nil: take over when the partner is winning, or play high before them.
			if (partnerPlayed && best.seat == partner) return winners.length > 0 ? lowest(winners) : discard(legal);
			if (!partnerPlayed) return winners.length > 0 ? highest(winners) : discard(legal);
		}

		var partnerWinning = best.seat == partner;
		if (partnerWinning && (last || isBoss(game, seat, best.card))) return discard(losers.length > 0 ? losers : legal);

		if (contractMade) {
			// Contract made: duck overtricks (bags) where possible.
			if (losers.length > 0) return highest(losers);
			return lowest(winners);
		}
		if (winners.length > 0) {
			if (last) return lowest(winners);
			var bosses = [for (c in winners) if (isBoss(game, seat, c)) c];
			if (bosses.length > 0) return lowest(bosses);
			// Second hand low; third hand high.
			if (trick.length == 1 && losers.length > 0) return discard(losers);
			return highest(winners);
		}
		return discard(legal);
	}

	static function lead(game:SpadesGame, seat:Int, legal:Array<Card>, myNil:Bool, partnerNil:Bool, contractMade:Bool):Card {
		if (myNil) return lowest(legal);
		if (partnerNil) {
			var high = [for (c in legal) if (c.suit != Suit.Spades) c];
			return highest(high.length > 0 ? high : legal);
		}
		var bosses = [for (c in legal) if (isBoss(game, seat, c) && (c.suit != Suit.Spades || spadesLeft(game, seat) <= 0)) c];
		if (bosses.length > 0 && !contractMade) return highest(bosses);
		// Otherwise lead low from the longest side suit.
		var hand = game.hands[seat];
		var bestSuit:Null<Suit> = null, bestLen = 0;
		for (suit in [Suit.Hearts, Suit.Clubs, Suit.Diamonds]) {
			var len = 0;
			for (c in legal) if (c.suit == suit) len++;
			if (len > bestLen) {
				bestLen = len;
				bestSuit = suit;
			}
		}
		if (bestSuit != null) return lowest([for (c in legal) if (c.suit == bestSuit) c]);
		return lowest(legal);
	}

	/** True if no card that could still beat `card` in its suit is outside this seat's view. **/
	static function isBoss(game:SpadesGame, seat:Int, card:Card):Bool {
		for (rank in card.rank + 1...Card.ACE + 1) {
			var higher = Card.of(rank, card.suit);
			if (!seen(game, seat, higher)) return false;
		}
		return true;
	}

	/** Spades not yet played and not in this seat's hand. **/
	static function spadesLeft(game:SpadesGame, seat:Int):Int {
		var count = 0;
		for (rank in 2...Card.ACE + 1) if (!seen(game, seat, Card.of(rank, Suit.Spades))) count++;
		return count;
	}

	static function seen(game:SpadesGame, seat:Int, card:Card):Bool {
		return game.played.indexOf(card) >= 0 || game.hands[seat].indexOf(card) >= 0;
	}

	/** Lowest card, keeping spades when a side-suit card will do. **/
	static function discard(cards:Array<Card>):Card {
		var side = [for (c in cards) if (c.suit != Suit.Spades) c];
		return lowest(side.length > 0 ? side : cards);
	}

	static function lowest(cards:Array<Card>):Card {
		var best = cards[0];
		for (c in cards) if (c.rank < best.rank || (c.rank == best.rank && c.index < best.index)) best = c;
		return best;
	}

	static function highest(cards:Array<Card>):Card {
		var best = cards[0];
		for (c in cards) if (c.rank > best.rank || (c.rank == best.rank && c.index > best.index)) best = c;
		return best;
	}

	static function ranks(hand:Array<Card>, suit:Suit):Array<Int> {
		var out = [for (c in hand) if (c.suit == suit) c.rank];
		out.sort((a, b) -> b - a);
		return out;
	}
}
