// SPDX-License-Identifier: AGPL-3.0-or-later
package games.spades;

import cards.Card;
import cards.Deck;
import cards.Suit;

enum abstract Phase(String) to String {
	var Bidding = "bidding";
	var Playing = "playing";
	var HandOver = "hand over";
	var GameOver = "game over";
}

typedef Play = {seat:Int, card:Card};

/** One partnership's result for a finished hand. **/
typedef TeamResult = {
	var bid:Int;
	var tricks:Int;
	var points:Int;
	var bags:Int;
	var bagPenalty:Bool;
	var nils:Array<{seat:Int, blind:Bool, made:Bool}>;
}

/**
	Partnership Spades (§6.4). Seats run clockwise: 0 South (the player),
	1 West, 2 North (partner), 3 East. Seats 0 and 2 are team 0.

	Table rules:
	- Bids 0 to 13; 0 is nil. Blind nil (bid before seeing your cards) is open
	  to a player whose side trails by 100 or more.
	- Follow suit if you can. Spades can't be led until they're broken (a spade
	  was played to an earlier trick), unless you hold nothing else.
	- Making the side's bid scores 10 per trick bid plus 1 per overtrick (bag);
	  falling short loses 10 per trick bid. Every 10 bags costs 100.
	- Nil: +100 if the bidder takes no tricks, -100 if they take any (blind nil
	  ±200). A nil bidder's tricks don't help their partner's bid; they count
	  as bags.
	- First side to 500 wins (the higher score if both reach it; a tie plays
	  on). A side at -200 or below loses.
**/
class SpadesGame {
	public static inline var SEATS = 4;
	public static inline var HAND_SIZE = 13;
	public static inline var WINNING_SCORE = 500;
	public static inline var LOSING_SCORE = -200;
	public static inline var BLIND_NIL_DEFICIT = 100;

	public var phase(default, null):Phase = Bidding;
	public final hands:Array<Array<Card>> = [for (_ in 0...SEATS) []];
	public final bids:Array<Null<Int>> = [for (_ in 0...SEATS) null];
	public final blind:Array<Bool> = [for (_ in 0...SEATS) false];
	public final tricks:Array<Int> = [for (_ in 0...SEATS) 0];
	public final scores:Array<Int> = [0, 0];
	public final bags:Array<Int> = [0, 0];
	public var dealer(default, null) = 3;
	public var turn(default, null) = 0;
	public var leader(default, null) = 0;
	public var spadesBroken(default, null) = false;
	public final trick:Array<Play> = [];

	/** The most recently completed trick and who took it, for the table to show. **/
	public final lastTrick:Array<Play> = [];

	public var lastWinner(default, null) = -1;
	public var tricksPlayed(default, null) = 0;
	public var handNumber(default, null) = 0;

	/** Every card played this hand, in order. **/
	public final played:Array<Card> = [];

	/** voids[seat][suit]: the seat showed out of that suit this hand. **/
	public final voids:Array<Array<Bool>> = [for (_ in 0...SEATS) [false, false, false, false]];

	public var lastResults(default, null):Array<TeamResult> = [];
	public var winner(default, null) = -1;

	public function new() {}

	public static inline function teamOf(seat:Int):Int return seat & 1;

	public static inline function partnerOf(seat:Int):Int return (seat + 2) % SEATS;

	/** Shuffles and deals the next hand. The dealer passes to the left each hand. **/
	public function dealFrom(rng:rng.IRng):Void {
		var deck = Deck.standard();
		rng.shuffle(deck);
		startHand([for (s in 0...SEATS) deck.slice(s * HAND_SIZE, (s + 1) * HAND_SIZE)]);
	}

	/** Starts a hand from given hands (tests and replays). **/
	public function startHand(dealt:Array<Array<Card>>):Void {
		if (phase == GameOver) throw 'The game is over';
		if (dealt.length != SEATS) throw 'Need $SEATS hands';
		var seen = new Map<Int, Bool>();
		for (h in dealt) {
			if (h.length != HAND_SIZE) throw 'Each hand needs $HAND_SIZE cards';
			for (c in h) {
				if (seen.exists(c.index)) throw 'Duplicate card ${c.code}';
				seen.set(c.index, true);
			}
		}
		dealer = (dealer + 1) % SEATS;
		handNumber++;
		for (s in 0...SEATS) {
			hands[s] = sortHand(dealt[s]);
			bids[s] = null;
			blind[s] = false;
			tricks[s] = 0;
			for (i in 0...4) voids[s][i] = false;
		}
		trick.resize(0);
		lastTrick.resize(0);
		played.resize(0);
		lastWinner = -1;
		tricksPlayed = 0;
		spadesBroken = false;
		lastResults = [];
		turn = leader = (dealer + 1) % SEATS;
		phase = Bidding;
	}

	/** Spades first, then hearts, clubs and diamonds (alternating colors), high to low. **/
	public static function sortHand(cards:Array<Card>):Array<Card> {
		var out = cards.copy();
		out.sort((a, b) -> a.suit != b.suit ? suitOrder(a.suit) - suitOrder(b.suit) : b.rank - a.rank);
		return out;
	}

	static function suitOrder(s:Suit):Int {
		return switch s {
			case Suit.Spades: 0;
			case Suit.Hearts: 1;
			case Suit.Clubs: 2;
			case Suit.Diamonds: 3;
		}
	}

	public function canBidBlindNil(seat:Int):Bool {
		return phase == Bidding && turn == seat && scores[teamOf(seat)] <= scores[1 - teamOf(seat)] - BLIND_NIL_DEFICIT;
	}

	public function bid(seat:Int, amount:Int, blindNil:Bool = false):Void {
		if (phase != Bidding || seat != turn) throw 'It is not seat $seat\'s turn to bid';
		if (amount < 0 || amount > HAND_SIZE) throw 'Bid must be 0..13, got $amount';
		if (blindNil && (amount != 0 || !canBidBlindNil(seat))) throw 'Blind nil is not allowed';
		bids[seat] = amount;
		blind[seat] = blindNil;
		turn = (turn + 1) % SEATS;
		if (bids[turn] != null) {
			phase = Playing;
			turn = leader;
		}
	}

	public function legalPlays(seat:Int):Array<Card> {
		if (phase != Playing || seat != turn) return [];
		var hand = hands[seat];
		if (trick.length > 0) {
			var led = trick[0].card.suit;
			var follow = [for (c in hand) if (c.suit == led) c];
			return follow.length > 0 ? follow : hand.copy();
		}
		if (spadesBroken) return hand.copy();
		var nonSpades = [for (c in hand) if (c.suit != Suit.Spades) c];
		return nonSpades.length > 0 ? nonSpades : hand.copy();
	}

	public function isLegal(seat:Int, card:Card):Bool {
		for (c in legalPlays(seat)) if (c == card) return true;
		return false;
	}

	/** True if `a` beats `b` in a trick led with `led`. **/
	public static function beats(a:Card, b:Card, led:Suit):Bool {
		if (a.suit == b.suit) return a.rank > b.rank;
		if (a.suit == Suit.Spades) return true;
		if (b.suit == Suit.Spades) return false;
		return a.suit == led;
	}

	/** The play currently winning a trick in progress. **/
	public static function winning(plays:Array<Play>):Null<Play> {
		if (plays.length == 0) return null;
		var best = plays[0];
		for (p in plays) if (beats(p.card, best.card, plays[0].card.suit)) best = p;
		return best;
	}

	public function play(seat:Int, card:Card):Void {
		if (!isLegal(seat, card)) throw 'Seat $seat cannot play ${card.code}';
		var hand = hands[seat];
		hand.remove(card);
		if (trick.length > 0 && card.suit != trick[0].card.suit) voids[seat][(card.suit : Int)] = true;
		if (card.suit == Suit.Spades) spadesBroken = true;
		trick.push({seat: seat, card: card});
		played.push(card);
		if (trick.length < SEATS) {
			turn = (turn + 1) % SEATS;
			return;
		}
		var win = winning(trick);
		tricks[win.seat]++;
		lastTrick.resize(0);
		for (p in trick) lastTrick.push(p);
		trick.resize(0);
		lastWinner = win.seat;
		tricksPlayed++;
		turn = leader = win.seat;
		if (tricksPlayed == HAND_SIZE) scoreHand();
	}

	/** Contract for a side: the bids of its members who didn't bid nil. **/
	public function teamBid(team:Int):Int {
		var total = 0;
		for (s in [team, team + 2]) if (bids[s] != null && bids[s] > 0) total += bids[s];
		return total;
	}

	/** Tricks that count toward the side's contract (nil bidders' tricks don't). **/
	public function teamTricks(team:Int):Int {
		var total = 0;
		for (s in [team, team + 2]) if (bids[s] != 0) total += tricks[s];
		return total;
	}

	/** Clears the scores for a fresh game; the deal keeps rotating. **/
	public function newGame():Void {
		scores[0] = scores[1] = 0;
		bags[0] = bags[1] = 0;
		winner = -1;
		handNumber = 0;
		phase = HandOver;
	}

	function scoreHand():Void {
		lastResults = [];
		for (team in 0...2) {
			var scored = scoreTeam(team, bids, blind, tricks, bags[team]);
			bags[team] = scored.bagsAfter;
			scores[team] += scored.result.points;
			lastResults.push(scored.result);
		}
		winner = decideWinner(scores[0], scores[1]);
		phase = winner >= 0 ? GameOver : HandOver;
	}

	/** One side's score for a finished hand, and its running bag count after penalties. **/
	public static function scoreTeam(team:Int, bids:Array<Null<Int>>, blind:Array<Bool>, tricks:Array<Int>,
			bagsBefore:Int):{result:TeamResult, bagsAfter:Int} {
		var points = 0, newBags = 0, contract = 0, won = 0;
		var nils = [];
		for (s in [team, team + 2]) {
			if (bids[s] == 0) {
				var made = tricks[s] == 0;
				var value = blind[s] ? 200 : 100;
				points += made ? value : -value;
				// A nil bidder's tricks are bags, worth a point each.
				newBags += tricks[s];
				points += tricks[s];
				nils.push({seat: s, blind: blind[s], made: made});
			} else {
				contract += bids[s];
				won += tricks[s];
			}
		}
		if (contract > 0) {
			if (won >= contract) {
				points += 10 * contract + (won - contract);
				newBags += won - contract;
			} else points -= 10 * contract;
		}
		var bags = bagsBefore + newBags, penalty = false;
		while (bags >= 10) {
			bags -= 10;
			points -= 100;
			penalty = true;
		}
		return {
			result: {bid: contract, tricks: won, points: points, bags: newBags, bagPenalty: penalty, nils: nils},
			bagsAfter: bags
		};
	}

	/** -1 while play goes on; otherwise the winning side. **/
	public static function decideWinner(a:Int, b:Int):Int {
		if (a <= LOSING_SCORE && b > LOSING_SCORE) return 1;
		if (b <= LOSING_SCORE && a > LOSING_SCORE) return 0;
		if (a == b) return -1;
		if (a >= WINNING_SCORE || b >= WINNING_SCORE || (a <= LOSING_SCORE && b <= LOSING_SCORE)) return a > b ? 0 : 1;
		return -1;
	}
}
