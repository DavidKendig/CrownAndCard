// SPDX-License-Identifier: AGPL-3.0-or-later
package games.poker;

import cards.Card;

/**
	Poker hand evaluator (§6.2 "hand evaluator"): the best five-card hand in
	5 to 7 cards, as one integer where higher is better. The category sits in
	the top digit (base 16) and the deciding ranks follow, so plain integer
	comparison settles every showdown, kickers included.
**/
class HandEval {
	public static inline var HIGH_CARD = 0;
	public static inline var PAIR = 1;
	public static inline var TWO_PAIR = 2;
	public static inline var TRIPS = 3;
	public static inline var STRAIGHT = 4;
	public static inline var FLUSH = 5;
	public static inline var FULL_HOUSE = 6;
	public static inline var QUADS = 7;
	public static inline var STRAIGHT_FLUSH = 8;

	public static final NAMES = [
		"High card", "Pair", "Two pair", "Three of a kind", "Straight", "Flush", "Full house", "Four of a kind", "Straight flush"
	];

	static inline var DIGIT = 1048576; // 16^5

	public static function score(cards:Array<Card>):Int {
		if (cards.length < 5) throw 'Need at least 5 cards, got ${cards.length}';
		var counts = [for (_ in 0...15) 0];
		var suitMasks = [0, 0, 0, 0], suitCounts = [0, 0, 0, 0];
		var mask = 0;
		for (c in cards) {
			var s:Int = c.suit;
			counts[c.rank]++;
			suitMasks[s] |= 1 << c.rank;
			suitCounts[s]++;
			mask |= 1 << c.rank;
		}
		for (s in 0...4) if (suitCounts[s] >= 5) {
			var hi = straightHigh(suitMasks[s]);
			if (hi > 0) return make(STRAIGHT_FLUSH, [hi]);
		}
		var quads = [], trips = [], pairs = [];
		var r = Card.ACE;
		while (r >= 2) {
			switch counts[r] {
				case 4: quads.push(r);
				case 3: trips.push(r);
				case 2: pairs.push(r);
				default:
			}
			r--;
		}
		if (quads.length > 0) return make(QUADS, [quads[0]].concat(kickers(counts, [quads[0]], 1)));
		if (trips.length >= 2 || (trips.length == 1 && pairs.length > 0)) {
			var pair = trips.length >= 2 ? trips[1] : 0;
			if (pairs.length > 0 && pairs[0] > pair) pair = pairs[0];
			return make(FULL_HOUSE, [trips[0], pair]);
		}
		for (s in 0...4) if (suitCounts[s] >= 5) {
			var top = [];
			var rr = Card.ACE;
			while (rr >= 2 && top.length < 5) {
				if (suitMasks[s] & (1 << rr) != 0) top.push(rr);
				rr--;
			}
			return make(FLUSH, top);
		}
		var hi = straightHigh(mask);
		if (hi > 0) return make(STRAIGHT, [hi]);
		if (trips.length > 0) return make(TRIPS, [trips[0]].concat(kickers(counts, [trips[0]], 2)));
		if (pairs.length >= 2) return make(TWO_PAIR, [pairs[0], pairs[1]].concat(kickers(counts, [pairs[0], pairs[1]], 1)));
		if (pairs.length == 1) return make(PAIR, [pairs[0]].concat(kickers(counts, [pairs[0]], 3)));
		return make(HIGH_CARD, kickers(counts, [], 5));
	}

	public static inline function category(score:Int):Int return Std.int(score / DIGIT);

	/** "Two pair, kings and sevens" style description of a score. **/
	public static function describe(score:Int):String {
		var cat = category(score);
		var ranks = [for (i in 0...5) Std.int(score / Math.pow(16, 4 - i)) % 16];
		var text = switch cat {
			case HIGH_CARD: '${rankName(ranks[0])} high';
			case PAIR: 'Pair of ${plural(ranks[0])}';
			case TWO_PAIR: 'Two pair, ${plural(ranks[0])} and ${plural(ranks[1])}';
			case TRIPS: 'Three ${plural(ranks[0])}';
			case STRAIGHT: '${rankName(ranks[0])}-high straight';
			case FLUSH: '${rankName(ranks[0])}-high flush';
			case FULL_HOUSE: '${plural(ranks[0])} full of ${plural(ranks[1])}';
			case QUADS: 'Four ${plural(ranks[0])}';
			default: ranks[0] == Card.ACE ? "Royal flush" : '${rankName(ranks[0])}-high straight flush';
		}
		return text.charAt(0).toUpperCase() + text.substr(1);
	}

	public static function rankName(r:Int):String {
		return switch r {
			case 11: "Jack";
			case 12: "Queen";
			case 13: "King";
			case 14: "Ace";
			default: Std.string(r);
		}
	}

	static function plural(r:Int):String {
		return switch r {
			case 6: "sixes";
			case 11: "jacks";
			case 12: "queens";
			case 13: "kings";
			case 14: "aces";
			default: '${r}s';
		}
	}

	/** High card of the best straight in a rank mask (the wheel A-2-3-4-5 counts as 5-high), or 0. **/
	static function straightHigh(mask:Int):Int {
		var hi = Card.ACE;
		while (hi >= 6) {
			var run = 31 << (hi - 4);
			if (mask & run == run) return hi;
			hi--;
		}
		var wheel = (1 << Card.ACE) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5);
		return mask & wheel == wheel ? 5 : 0;
	}

	static function kickers(counts:Array<Int>, used:Array<Int>, n:Int):Array<Int> {
		var out = [];
		var r = Card.ACE;
		while (r >= 2 && out.length < n) {
			if (counts[r] > 0 && used.indexOf(r) < 0) out.push(r);
			r--;
		}
		return out;
	}

	static function make(cat:Int, ranks:Array<Int>):Int {
		var v = cat;
		for (i in 0...5) v = v * 16 + (i < ranks.length ? ranks[i] : 0);
		return v;
	}
}
