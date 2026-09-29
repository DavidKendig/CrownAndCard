// SPDX-License-Identifier: AGPL-3.0-or-later
package games.rummy;

import cards.Card;
import cards.Deck;
import cards.Suit;

typedef Meld = Array<Card>;

/** The best grouping found for a hand: its melds, what's left over, and that leftover's point total. **/
typedef HandValue = {melds:Array<Meld>, deadwood:Array<Card>, deadwoodPoints:Int};

enum abstract Phase(String) to String {
	var Draw = "draw";
	var Discard = "discard";
	var RoundOver = "round over";
	var GameOver = "game over";
}

/**
	Gin Rummy (bicyclecards.com): two players, 10 cards each, the rest face
	down as the stock with one card turned to start the discard pile. Each
	turn is draw (from the stock or the discard pile) then discard, unless
	the draw leaves a hand worth knocking: 10 points of deadwood or less.

	A set is 3-4 cards of one rank; a run is 3 or more consecutive cards of
	one suit (ace low, no wrap to king). Deadwood is whatever's left over
	once melds are chosen to leave as little of it, by point value, as
	possible (aces 1, tens and courts 10, everything else its rank).

	Knocking lays down the knocker's melds; the opponent lays down theirs
	and may lay off their own deadwood onto the knocker's melds. The
	knocker scores the difference in final deadwood; going out at exactly
	0 (gin) blocks the lay-off and adds a bonus. If the opponent's deadwood,
	after laying off, comes out equal or lower, they score the difference
	instead, plus an undercut bonus. First to 100 wins.
**/
class GinRummy {
	public static inline var HAND_SIZE = 10;
	public static inline var MAX_DEADWOOD_TO_KNOCK = 10;
	public static inline var GIN_BONUS = 25;
	public static inline var UNDERCUT_BONUS = 25;
	public static inline var WINNING_SCORE = 100;

	public final hands:Array<Array<Card>> = [[], []];
	public final stock:Array<Card> = [];
	public final discardPile:Array<Card> = [];
	public var turn(default, null) = 0;

	/** Flips before each deal, so the first deal's dealer is 1 and seat 0 (the player) acts first. **/
	public var dealer(default, null) = 0;
	public var phase(default, null):Phase = Draw;
	public final scores:Array<Int> = [0, 0];

	/** The seat that knocked to end the round, or -1 for a wash (the stock ran out first). **/
	public var knocker(default, null) = -1;

	public var lastGin(default, null) = false;
	public var lastUndercut(default, null) = false;
	public var lastScorer(default, null) = -1;
	public var lastPoints(default, null) = 0;
	public var lastMelds(default, null):Array<Array<Meld>> = [[], []];
	public var lastDeadwood(default, null):Array<Array<Card>> = [[], []];
	public var winner(default, null) = -1;

	public function new() {}

	public function dealFrom(rng:rng.IRng):Void {
		var deck = Deck.standard();
		rng.shuffle(deck);
		startDeal(deck);
	}

	/** Test hook: deals from a known stock order (the first 20 cards are the two hands, the 21st starts the discard). **/
	public function startDeal(order:Array<Card>):Void {
		hands[0].resize(0);
		hands[1].resize(0);
		stock.resize(0);
		discardPile.resize(0);
		var cards = order.copy();
		dealer = 1 - dealer;
		var nonDealer = 1 - dealer;
		for (_ in 0...HAND_SIZE) {
			hands[dealer].push(cards.shift());
			hands[nonDealer].push(cards.shift());
		}
		discardPile.push(cards.shift());
		for (c in cards) stock.push(c);
		turn = nonDealer;
		phase = Draw;
		knocker = -1;
		lastScorer = -1;
	}

	public static function pointValue(rank:Int):Int return rank == Card.ACE ? 1 : rank >= 10 ? 10 : rank;

	/** Ace-low ordering for runs: ace is 1, everything else keeps its rank. **/
	static function seqRank(rank:Int):Int return rank == Card.ACE ? 1 : rank;

	// --- Melding ---------------------------------------------------------

	static function setCandidates(hand:Array<Card>):Array<Meld> {
		var byRank = new Map<Int, Array<Card>>();
		for (c in hand) {
			var list = byRank.exists(c.rank) ? byRank.get(c.rank) : [];
			list.push(c);
			byRank.set(c.rank, list);
		}
		var out = [];
		for (list in byRank) {
			if (list.length >= 3) out.push(list.copy());
			if (list.length == 4) for (skip in 0...4) out.push([for (i in 0...4) if (i != skip) list[i]]);
		}
		return out;
	}

	/** Each maximal same-suit run, plus it trimmed by one card from either end (bounded, not every sub-length). **/
	static function runCandidates(hand:Array<Card>):Array<Meld> {
		var out = [];
		for (suit in Suit.ALL) {
			var cards = [for (c in hand) if (c.suit == suit) c];
			cards.sort((a, b) -> seqRank(a.rank) - seqRank(b.rank));
			var i = 0;
			while (i < cards.length) {
				var j = i;
				while (j + 1 < cards.length && seqRank(cards[j + 1].rank) == seqRank(cards[j].rank) + 1) j++;
				var len = j - i + 1;
				if (len >= 3) {
					out.push(cards.slice(i, j + 1));
					if (len >= 4) {
						out.push(cards.slice(i, j));
						out.push(cards.slice(i + 1, j + 1));
					}
				}
				i = j + 1;
			}
		}
		return out;
	}

	/** The lowest-deadwood grouping found for a hand (a bounded search, not exhaustive on pathological hands). **/
	public static function evaluate(hand:Array<Card>):HandValue {
		var candidates = setCandidates(hand).concat(runCandidates(hand));
		var best:Array<Meld> = [];
		var bestValue = -1;
		function overlaps(chosen:Array<Meld>, c:Meld):Bool {
			for (m in chosen) for (card in m) if (c.indexOf(card) >= 0) return true;
			return false;
		}
		function meldedValue(chosen:Array<Meld>):Int {
			var total = 0;
			for (m in chosen) for (c in m) total += pointValue(c.rank);
			return total;
		}
		function search(i:Int, chosen:Array<Meld>):Void {
			if (i == candidates.length) {
				var v = meldedValue(chosen);
				if (v > bestValue) {
					bestValue = v;
					best = chosen.copy();
				}
				return;
			}
			search(i + 1, chosen);
			if (!overlaps(chosen, candidates[i])) {
				chosen.push(candidates[i]);
				search(i + 1, chosen);
				chosen.pop();
			}
		}
		search(0, []);
		var melded = [for (m in best) for (c in m) c];
		var deadwood = [for (c in hand) if (melded.indexOf(c) < 0) c];
		var points = 0;
		for (c in deadwood) points += pointValue(c.rank);
		return {melds: best, deadwood: deadwood, deadwoodPoints: points};
	}

	static function canLayOff(meld:Meld, card:Card):Bool {
		if (meld.length == 0) return false;
		var sameRank = true;
		for (c in meld) if (c.rank != meld[0].rank) sameRank = false;
		if (sameRank) return meld.length < 4 && card.rank == meld[0].rank;
		for (c in meld) if (c.suit != meld[0].suit) return false;
		if (card.suit != meld[0].suit) return false;
		var ranks = [for (c in meld) seqRank(c.rank)];
		ranks.sort((a, b) -> a - b);
		var cr = seqRank(card.rank);
		return cr == ranks[0] - 1 || cr == ranks[ranks.length - 1] + 1;
	}

	// --- Turns -------------------------------------------------------------

	public function drawFromStock(seat:Int):Void {
		if (phase != Draw || seat != turn) throw 'Seat $seat cannot draw now';
		if (stock.length == 0) throw 'The stock is empty';
		hands[seat].push(stock.shift());
		phase = Discard;
	}

	public function drawFromDiscard(seat:Int):Void {
		if (phase != Draw || seat != turn) throw 'Seat $seat cannot draw now';
		if (discardPile.length == 0) throw 'The discard pile is empty';
		hands[seat].push(discardPile.pop());
		phase = Discard;
	}

	/** Deadwood the seat would be left with if they discarded this card right now. **/
	public function deadwoodIfDiscarding(seat:Int, card:Card):Int {
		var rest = hands[seat].copy();
		rest.remove(card);
		return evaluate(rest).deadwoodPoints;
	}

	public function canKnock(seat:Int, card:Card):Bool return deadwoodIfDiscarding(seat, card) <= MAX_DEADWOOD_TO_KNOCK;

	/** Discards one card, ending the turn; `knock` also ends the round if the resulting deadwood allows it. **/
	public function discard(seat:Int, card:Card, knock:Bool = false):Void {
		if (phase != Discard || seat != turn) throw 'Seat $seat cannot discard now';
		if (hands[seat].indexOf(card) < 0) throw 'Seat $seat does not hold ${card.code}';
		if (knock && !canKnock(seat, card)) throw 'Deadwood is too high to knock';
		hands[seat].remove(card);
		discardPile.push(card);
		if (knock) {
			resolveRound(seat);
			return;
		}
		if (stock.length <= 2) {
			knocker = -1;
			lastScorer = -1;
			phase = RoundOver;
			return;
		}
		turn = 1 - seat;
		phase = Draw;
	}

	function resolveRound(seat:Int):Void {
		knocker = seat;
		var opp = 1 - seat;
		var knockerEval = evaluate(hands[seat]);
		var knockerMelds = [for (m in knockerEval.melds) m.copy()];
		var gin = knockerEval.deadwoodPoints == 0;
		var oppEval = evaluate(hands[opp]);
		var oppDeadwood = oppEval.deadwood.copy();
		var oppPoints = oppEval.deadwoodPoints;
		if (!gin) {
			var changed = true;
			while (changed) {
				changed = false;
				for (c in oppDeadwood.copy()) {
					for (m in knockerMelds) {
						if (canLayOff(m, c)) {
							m.push(c);
							oppDeadwood.remove(c);
							oppPoints -= pointValue(c.rank);
							changed = true;
							break;
						}
					}
				}
			}
		}
		lastMelds = [knockerMelds, oppEval.melds];
		lastDeadwood = [knockerEval.deadwood, oppDeadwood];
		lastGin = gin;
		var diff = oppPoints - knockerEval.deadwoodPoints;
		if (gin) {
			lastScorer = seat;
			lastPoints = diff + GIN_BONUS;
			lastUndercut = false;
		} else if (diff > 0) {
			lastScorer = seat;
			lastPoints = diff;
			lastUndercut = false;
		} else {
			lastScorer = opp;
			lastPoints = -diff + UNDERCUT_BONUS;
			lastUndercut = true;
		}
		scores[lastScorer] += lastPoints;
		phase = RoundOver;
		if (scores[0] >= WINNING_SCORE || scores[1] >= WINNING_SCORE) {
			winner = scores[0] == scores[1] ? -1 : (scores[0] > scores[1] ? 0 : 1);
			if (winner >= 0) phase = GameOver;
		}
	}
}
