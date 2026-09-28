// SPDX-License-Identifier: AGPL-3.0-or-later
package games.poker;

import cards.Card;
import cards.Deck;
import games.poker.PokerTable;

/** How an NPC plays (§8.2, §9.2): willingness to put chips in, and to push. **/
typedef PokerStyle = {
	/** 0 tight .. 1 loose: calls lighter. **/
	var looseness:Float;

	/** 0 passive .. 1 aggressive: bets, raises and bluffs more. **/
	var aggression:Float;
}

/**
	Normal-difficulty poker opponents (§9.2): Monte Carlo equity against the
	live opponents' unknown cards, compared with the pot odds, shaded by the
	character's style. Randomness (sampling, bluffs) comes from the table's
	AI stream, like every gameplay random number (§7.2).
**/
class PokerAi {
	public static function decide(t:PokerTable, seat:Int, rng:rng.IRng, style:PokerStyle, samples = 150):Action {
		var l = t.legal(seat);
		var equity = equity(t, seat, rng, samples);
		var pot = t.pot;
		var s = t.seats[seat];
		function raiseTo(fraction:Float):Action {
			var target = t.currentBet + Std.int(Math.max(t.bigBlind, (pot + l.toCall) * fraction));
			target = Std.int(Math.max(l.minRaiseTo, Math.min(l.maxRaiseTo, target)));
			return RaiseTo(target);
		}
		if (l.toCall == 0) {
			if (l.canRaise && equity > 0.62 - 0.12 * style.aggression) return raiseTo(0.5 + 0.4 * style.aggression);
			if (l.canRaise && rng.chance(0.06 + 0.1 * style.aggression)) return raiseTo(0.5);
			return Check;
		}
		var odds = l.toCall / (pot + l.toCall);
		if (l.canRaise && equity > 0.78 - 0.1 * style.aggression) return raiseTo(0.75 + 0.5 * style.aggression);
		if (equity + 0.08 * style.looseness >= odds + 0.04) return Call;
		// A small chance to float cheap bets, and a rarer bluff-raise.
		if (l.toCall <= t.bigBlind && rng.chance(0.25 * style.looseness)) return Call;
		if (l.canRaise && l.toCall < s.stack / 4 && rng.chance(0.03 * style.aggression)) return raiseTo(1);
		return Fold;
	}

	/** Share of the pot this seat wins on average against random holdings for the other live players. **/
	public static function equity(t:PokerTable, seat:Int, rng:rng.IRng, samples:Int):Float {
		var mine = t.seats[seat].cards;
		var opponents = [for (i in 0...t.seats.length) if (i != seat && t.seats[i].live) i];
		if (opponents.length == 0) return 1;
		var known = mine.concat(t.board);
		var unknown = [for (c in Deck.standard()) if (known.indexOf(c) < 0) c];
		var handSize = t.variant == Holdem ? 2 : 5;
		var boardNeeded = t.variant == Holdem ? 5 - t.board.length : 0;
		var need = boardNeeded + handSize * opponents.length;
		var total = 0.0;
		for (_ in 0...samples) {
			// Partial Fisher-Yates: only the cards this sample needs.
			for (k in 0...need) {
				var j = k + rng.below(unknown.length - k);
				var tmp = unknown[k];
				unknown[k] = unknown[j];
				unknown[j] = tmp;
			}
			var board = t.board.concat(unknown.slice(0, boardNeeded));
			var me = HandEval.score(mine.concat(board));
			var best = true, ties = 1;
			for (o in 0...opponents.length) {
				var start = boardNeeded + o * handSize;
				var score = HandEval.score(unknown.slice(start, start + handSize).concat(board));
				if (score > me) {
					best = false;
					break;
				}
				if (score == me) ties++;
			}
			if (best) total += 1 / ties;
		}
		return total / samples;
	}

	/** Five-card draw: which cards to throw (at most three). **/
	public static function discards(hand:Array<Card>):Array<Card> {
		var score = HandEval.score(hand);
		var cat = HandEval.category(score);
		if (cat >= HandEval.STRAIGHT && cat != HandEval.QUADS) return [];
		var byRank = new Map<Int, Int>();
		for (c in hand) byRank.set(c.rank, (byRank.exists(c.rank) ? byRank.get(c.rank) : 0) + 1);
		function keepRanks(keep:Int->Bool):Array<Card> return [for (c in hand) if (!keep(byRank.get(c.rank))) c];
		switch cat {
			case HandEval.QUADS, HandEval.TRIPS: return lowest(keepRanks(n -> n >= 3), 2);
			case HandEval.TWO_PAIR: return keepRanks(n -> n >= 2);
			case HandEval.PAIR: return keepRanks(n -> n >= 2);
			default:
		}
		// Four to a flush or an open-ended straight: draw one.
		for (s in 0...4) {
			var suited = [for (c in hand) if ((c.suit : Int) == s) c];
			if (suited.length == 4) return [for (c in hand) if ((c.suit : Int) != s) c];
		}
		var sorted = hand.copy();
		sorted.sort((a, b) -> a.rank - b.rank);
		for (skip in [0, 4]) {
			var run = [for (i in 0...5) if (i != skip) sorted[i]];
			if (run[3].rank - run[0].rank == 3 && distinct(run) && run[3].rank < Card.ACE) return [sorted[skip]];
		}
		// Nothing: keep the two highest cards.
		return sorted.slice(0, 3);
	}

	static function distinct(cards:Array<Card>):Bool {
		for (i in 1...cards.length) if (cards[i].rank == cards[i - 1].rank) return false;
		return true;
	}

	static function lowest(cards:Array<Card>, n:Int):Array<Card> {
		var sorted = cards.copy();
		sorted.sort((a, b) -> a.rank - b.rank);
		return sorted.slice(0, n);
	}
}
