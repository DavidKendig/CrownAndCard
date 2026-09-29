// SPDX-License-Identifier: AGPL-3.0-or-later
package games.euchre;

import cards.Card;
import cards.Suit;

/** Simple heuristic Euchre: count bower and trump strength to bid, follow suit to win cheaply or duck. **/
class EuchreAi {
	static function strength(hand:Array<Card>, suit:Suit):Float {
		var score = 0.0;
		for (c in hand) {
			var eff = Euchre.effectiveSuit(c, suit);
			if (eff == suit) {
				if (c.rank == Card.JACK && c.suit == suit) score += 4;
				else if (c.rank == Card.JACK) score += 3.5;
				else score += (c.rank - 8) * 0.5 + 1;
			} else if (c.rank == Card.ACE) score += 1;
		}
		return score;
	}

	public static function shouldOrderUp(game:Euchre, seat:Int):Bool {
		var hand = game.hands[seat].copy();
		if (seat == game.dealer) hand.push(game.turnUp);
		var s = strength(hand, game.turnUp.suit);
		return s >= (seat == game.dealer ? 2.5 : 3);
	}

	/** The best suit to name (never the turned-down one), or null to pass. **/
	public static function chooseTrump(game:Euchre, seat:Int):Null<Suit> {
		var best:Null<Suit> = null, bestScore = -1.0;
		for (suit in Suit.ALL) {
			if (suit == game.turnedDownSuit) continue;
			var s = strength(game.hands[seat], suit);
			if (s > bestScore) {
				bestScore = s;
				best = suit;
			}
		}
		if (game.mustCallTrump) return best;
		return bestScore >= 3 ? best : null;
	}

	public static function shouldGoAlone(hand:Array<Card>, suit:Suit):Bool return strength(hand, suit) >= 6;

	/** The dealer's weakest card, to discard after picking up the turned-up card. **/
	public static function discard(game:Euchre):Card {
		var hand = game.hands[game.dealer];
		var worst = hand[0], worstScore = 999999.0;
		for (c in hand) {
			var s = value(game, c);
			if (s < worstScore) {
				worstScore = s;
				worst = c;
			}
		}
		return worst;
	}

	public static function play(game:Euchre, seat:Int):Card {
		var legal = game.legalPlays(seat);
		if (legal.length == 1) return legal[0];
		if (game.trick.length == 0) return lead(game, legal);
		var led = Euchre.effectiveSuit(game.trick[0].card, game.trump);
		var best = game.trick[0];
		for (p in game.trick) if (Euchre.power(p.card, game.trump, led) > Euchre.power(best.card, game.trump, led)) best = p;
		var partnerWinning = best.seat == Euchre.partnerOf(seat);
		var bestPower = Euchre.power(best.card, game.trump, led);
		var winners = [for (c in legal) if (Euchre.power(c, game.trump, led) > bestPower) c];
		var last = game.trick.length == (game.alone ? Euchre.SEATS - 2 : Euchre.SEATS - 1);
		if (partnerWinning) return lowest(game, legal);
		if (winners.length > 0) return last ? lowest(game, winners) : highest(game, winners);
		return lowest(game, legal);
	}

	static function lead(game:Euchre, legal:Array<Card>):Card {
		var trumps = [for (c in legal) if (Euchre.effectiveSuit(c, game.trump) == game.trump) c];
		if (trumps.length >= 3) return highest(game, trumps);
		var side = [for (c in legal) if (Euchre.effectiveSuit(c, game.trump) != game.trump) c];
		return lowest(game, side.length > 0 ? side : legal);
	}

	/** A trump- and bower-aware strength ordering, not just raw rank. **/
	static function value(game:Euchre, c:Card):Int {
		var eff = Euchre.effectiveSuit(c, game.trump);
		return Euchre.power(c, game.trump, eff);
	}

	static function lowest(game:Euchre, cards:Array<Card>):Card {
		var best = cards[0];
		for (c in cards) if (value(game, c) < value(game, best)) best = c;
		return best;
	}

	static function highest(game:Euchre, cards:Array<Card>):Card {
		var best = cards[0];
		for (c in cards) if (value(game, c) > value(game, best)) best = c;
		return best;
	}
}
