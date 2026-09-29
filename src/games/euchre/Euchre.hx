// SPDX-License-Identifier: AGPL-3.0-or-later
package games.euchre;

import cards.Card;
import cards.Deck;
import cards.Suit;

enum abstract Phase(String) to String {
	/** Order up the turned card as trump (the dealer's side must play it), or pass. **/
	var Bid1 = "bid1";

	/** The dealer picked it up: discard one card down to a legal 5-card hand. **/
	var DealerDiscard = "dealer discard";

	/** Name any suit but the turned-down one as trump, or pass; the dealer alone can't pass ("stick the dealer"). **/
	var Bid2 = "bid2";

	var Playing = "playing";
	var HandOver = "hand over";
	var GameOver = "game over";
}

typedef Play = {seat:Int, card:Card};

/**
	Euchre (§6.4, pagat.com): the 24-card deck, nine through ace. Seats run
	0 South (the player), 1 West, 2 North (partner), 3 East; 0 and 2 are one
	side. Five cards each; the next card is turned up. In turn from the
	dealer's left, order it up (the dealer's side must play that suit as
	trump; the dealer picks the card up and discards one) or pass. If
	everyone passes, the card turns down and a second round lets each player
	name any other suit, dealer last; if everyone else passed, the dealer
	must name one ("stick the dealer").

	The jack of the trump suit (the right bower) outranks everything; the
	same-color jack (the left bower) is second and counts as trump, not its
	printed suit, for both following suit and taking a trick. The maker's
	side must take at least 3 of the 5 tricks (1 point), or all 5 (2, or 4
	alone); falling short euchres them, and the other side scores 2. Either
	maker may play alone, sitting their partner out. First side to 10 wins.
**/
class Euchre {
	public static inline var SEATS = 4;
	public static inline var HAND_SIZE = 5;
	public static inline var WINNING_SCORE = 10;

	public var phase(default, null):Phase = Bid1;
	public final hands:Array<Array<Card>> = [for (_ in 0...SEATS) []];
	public var turnUp(default, null):Card;
	public final kitty:Array<Card> = [];
	public var trump(default, null):Null<Suit> = null;
	public var turnedDownSuit(default, null):Null<Suit> = null;
	public var maker(default, null) = -1;
	public var alone(default, null) = false;
	public var dealer(default, null) = 3;
	public var bidder(default, null) = 0;
	public var turn(default, null) = 0;
	public var leader(default, null) = 0;
	public final trick:Array<Play> = [];
	public final lastTrick:Array<Play> = [];
	public var lastWinner(default, null) = -1;
	public final tricks:Array<Int> = [for (_ in 0...SEATS) 0];
	public var tricksPlayed(default, null) = 0;
	public final scores:Array<Int> = [0, 0];
	public var handNumber(default, null) = 0;
	public var winner(default, null) = -1;
	public var lastMaker(default, null) = -1;
	public var lastAlone(default, null) = false;
	public var lastEuchred(default, null) = false;
	public var lastPoints(default, null) = 0;

	var passesThisRound = 0;

	public function new() {}

	public static inline function teamOf(seat:Int):Int return seat & 1;

	public static inline function partnerOf(seat:Int):Int return (seat + 2) % SEATS;

	public function dealFrom(rng:rng.IRng):Void {
		var deck = Deck.euchre();
		rng.shuffle(deck);
		startHand(deck);
	}

	/** Test hook: deals from a known 24-card order (5 to each seat in turn, then the 4-card kitty). **/
	public function startHand(order:Array<Card>):Void {
		if (phase == GameOver) throw "The game is over";
		if (order.length != 24) throw "Need all 24 cards";
		dealer = (dealer + 1) % SEATS;
		handNumber++;
		var cards = order.copy();
		for (s in 0...SEATS) hands[s] = cards.splice(0, HAND_SIZE);
		kitty.resize(0);
		for (c in cards) kitty.push(c);
		turnUp = kitty[0];
		trump = null;
		turnedDownSuit = null;
		maker = -1;
		alone = false;
		trick.resize(0);
		lastTrick.resize(0);
		for (s in 0...SEATS) tricks[s] = 0;
		tricksPlayed = 0;
		lastWinner = -1;
		passesThisRound = 0;
		bidder = turn = (dealer + 1) % SEATS;
		phase = Bid1;
	}

	/** True to name it, red or black to same for bowers, unrelated otherwise. **/
	static function sameColor(a:Suit, b:Suit):Bool return a.isRed == b.isRed;

	/** The suit a card plays as: the left bower plays as trump, not its own suit. **/
	public static function effectiveSuit(c:Card, trump:Suit):Suit {
		return c.rank == Card.JACK && c.suit != trump && sameColor(c.suit, trump) ? trump : c.suit;
	}

	/** How strongly `c` can win a trick with this trump led by `led`: -1 can't win at all. **/
	public static function power(c:Card, trump:Suit, led:Suit):Int {
		if (c.rank == Card.JACK && c.suit == trump) return 1000;
		if (c.rank == Card.JACK && c.suit != trump && sameColor(c.suit, trump)) return 999;
		var suit = effectiveSuit(c, trump);
		if (suit == trump) return 900 + c.rank;
		if (suit == led) return c.rank;
		return -1;
	}

	// --- Bidding -----------------------------------------------------------

	public function orderUp(goAlone:Bool = false):Void {
		if (phase != Bid1) throw "Not ordering up now";
		trump = turnUp.suit;
		maker = bidder;
		alone = goAlone;
		phase = DealerDiscard;
	}

	public function passBid1():Void {
		if (phase != Bid1) throw "Not ordering up now";
		passesThisRound++;
		if (passesThisRound == SEATS) {
			turnedDownSuit = turnUp.suit;
			passesThisRound = 0;
			bidder = turn = (dealer + 1) % SEATS;
			phase = Bid2;
			return;
		}
		bidder = (bidder + 1) % SEATS;
	}

	public function dealerDiscard(card:Card):Void {
		if (phase != DealerDiscard) throw "Not discarding now";
		hands[dealer].push(turnUp);
		if (hands[dealer].indexOf(card) < 0) throw 'The dealer does not hold ${card.code}';
		hands[dealer].remove(card);
		startPlay();
	}

	/** True once every other seat has passed in the second round: the dealer must name a trump. **/
	public var mustCallTrump(get, never):Bool;

	inline function get_mustCallTrump():Bool return phase == Bid2 && bidder == dealer;

	public function callTrump(suit:Suit, goAlone:Bool = false):Void {
		if (phase != Bid2) throw "Not naming trump now";
		if (suit == turnedDownSuit) throw "Cannot name the turned-down suit";
		trump = suit;
		maker = bidder;
		alone = goAlone;
		startPlay();
	}

	public function passBid2():Void {
		if (phase != Bid2) throw "Not naming trump now";
		if (mustCallTrump) throw "The dealer must name a trump";
		bidder = (bidder + 1) % SEATS;
	}

	function startPlay():Void {
		phase = Playing;
		leader = turn = (dealer + 1) % SEATS;
		if (isSitting(leader)) leader = turn = nextActive(leader);
	}

	// --- Play ----------------------------------------------------------

	function isSitting(seat:Int):Bool return alone && seat == partnerOf(maker);

	function nextActive(from:Int):Int {
		var n = (from + 1) % SEATS;
		if (isSitting(n)) n = (n + 1) % SEATS;
		return n;
	}

	public function legalPlays(seat:Int):Array<Card> {
		if (phase != Playing || seat != turn || isSitting(seat)) return [];
		var hand = hands[seat];
		if (trick.length == 0) return hand.copy();
		var led = effectiveSuit(trick[0].card, trump);
		var follow = [for (c in hand) if (effectiveSuit(c, trump) == led) c];
		return follow.length > 0 ? follow : hand.copy();
	}

	public function play(seat:Int, card:Card):Void {
		if (legalPlays(seat).indexOf(card) < 0) throw 'Seat $seat cannot play ${card.code}';
		hands[seat].remove(card);
		trick.push({seat: seat, card: card});
		var activeCount = alone ? SEATS - 1 : SEATS;
		if (trick.length < activeCount) {
			turn = nextActive(seat);
			return;
		}
		var led = effectiveSuit(trick[0].card, trump);
		var win = trick[0];
		for (p in trick) if (power(p.card, trump, led) > power(win.card, trump, led)) win = p;
		tricks[win.seat]++;
		lastTrick.resize(0);
		for (p in trick) lastTrick.push(p);
		trick.resize(0);
		lastWinner = win.seat;
		tricksPlayed++;
		turn = leader = win.seat;
		if (tricksPlayed == HAND_SIZE) scoreHand();
	}

	function scoreHand():Void {
		var makerTeam = teamOf(maker);
		var madeTricks = tricks[makerTeam] + tricks[(makerTeam + 2) % SEATS];
		lastMaker = maker;
		lastAlone = alone;
		var points:Int, euchred:Bool;
		if (madeTricks < 3) {
			euchred = true;
			points = 2;
			scores[1 - makerTeam] += points;
		} else if (madeTricks == HAND_SIZE) {
			euchred = false;
			points = alone ? 4 : 2;
			scores[makerTeam] += points;
		} else {
			euchred = false;
			points = 1;
			scores[makerTeam] += points;
		}
		lastEuchred = euchred;
		lastPoints = points;
		if (scores[0] >= WINNING_SCORE || scores[1] >= WINNING_SCORE) {
			winner = scores[0] > scores[1] ? 0 : 1;
			phase = GameOver;
		} else phase = HandOver;
	}
}
