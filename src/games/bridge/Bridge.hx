// SPDX-License-Identifier: AGPL-3.0-or-later
package games.bridge;

import games.PlayLog;
import cards.Card;
import cards.Deck;
import cards.Suit;

enum abstract Strain(Int) to Int {
	var ClubsStrain = 0;
	var DiamondsStrain = 1;
	var HeartsStrain = 2;
	var SpadesStrain = 3;
	var NoTrumpStrain = 4;
}

enum abstract Phase(String) to String {
	var Bidding = "bidding";
	var Playing = "playing";
	var HandOver = "hand over";
	var GameOver = "game over";
}

typedef Play = {seat:Int, card:Card};

/**
	Contract Bridge, deliberately simplified (§6.4 lists Bridge as post-launch
	scope; this is a playable core, not tournament bridge): the auction bids
	a level (1-7) and a strain — clubs, diamonds, hearts, spades or no-trump,
	in that ascending order — each call higher than the last, or passes;
	three passes after a bid ends the auction, four with no bid throws the
	hand in. Doubling, redoubling, conventions and vulnerability are all out
	of scope.

	Whoever made the final bid declares it; their partner's hand becomes the
	dummy, laid face up, and the declarer plays it alongside their own.
	Standard follow-suit trick play, the strain's suit as trump (nothing is
	trump at no-trump).

	Scoring keeps the trick-point scale (20 a trick for a minor, 30 for a
	major, 40 then 30 at no-trump) plus a flat 50-point bonus for making the
	contract, or 50 a trick to the defense for setting it — real bridge's
	game and slam bonuses and rubber scoring are out of scope. First side to
	700 wins.
**/
class Bridge {
	public static inline var SEATS = 4;
	public static inline var HAND_SIZE = 13;
	public static inline var WINNING_SCORE = 700;

	public var phase(default, null):Phase = Bidding;
	public final hands:Array<Array<Card>> = [for (_ in 0...SEATS) []];
	public var dealer(default, null) = 3;
	public var turn(default, null) = 0;
	public var highBid(default, null):Null<{level:Int, strain:Strain, by:Int}> = null;
	public var passesInRow(default, null) = 0;
	public final callLog:Array<String> = [];
	public var declarer(default, null) = -1;
	public var dummy(default, null) = -1;

	/** The trump suit, or null at no-trump. **/
	public var trump(default, null):Null<Suit> = null;

	public var contractStrain(default, null):Null<Strain> = null;
	public var contractLevel(default, null) = 0;
	public var leader(default, null) = 0;
	public final trick:Array<Play> = [];
	public final lastTrick:Array<Play> = [];
	public var lastWinner(default, null) = -1;
	public final tricks:Array<Int> = [for (_ in 0...SEATS) 0];
	public var tricksPlayed(default, null) = 0;
	public final scores:Array<Int> = [0, 0];
	public var handNumber(default, null) = 0;
	public var winner(default, null) = -1;
	public var lastMade(default, null) = false;
	public var lastPoints(default, null) = 0;
	public var thrownIn(default, null) = false;

	public function new() {}

	public static inline function teamOf(seat:Int):Int return seat & 1;

	public static inline function partnerOf(seat:Int):Int return (seat + 2) % SEATS;

	/** Who actually decides a seat's play: the declarer chooses for the dummy. **/
	public function controllerOf(seat:Int):Int return seat == dummy ? declarer : seat;

	public function dealFrom(rng:rng.IRng):Void {
		var deck = Deck.standard();
		rng.shuffle(deck);
		startHand([for (s in 0...SEATS) deck.slice(s * HAND_SIZE, (s + 1) * HAND_SIZE)]);
	}

	/** Test hook: starts a hand from given hands. **/
	public function startHand(dealt:Array<Array<Card>>):Void {
		if (phase == GameOver) throw "The game is over";
		if (dealt.length != SEATS) throw 'Need $SEATS hands';
		for (s in 0...SEATS) {
			if (dealt[s].length != HAND_SIZE) throw 'Each hand needs $HAND_SIZE cards';
			hands[s] = dealt[s].copy();
			tricks[s] = 0;
		}
		dealer = (dealer + 1) % SEATS;
		handNumber++;
		highBid = null;
		passesInRow = 0;
		callLog.resize(0);
		declarer = dummy = -1;
		trump = null;
		contractStrain = null;
		contractLevel = 0;
		trick.resize(0);
		lastTrick.resize(0);
		lastWinner = -1;
		tricksPlayed = 0;
		thrownIn = false;
		turn = (dealer + 1) % SEATS;
		phase = Bidding;
	}

	// --- Bidding -----------------------------------------------------------

	static function strainName(s:Strain):String {
		return switch s {
			case ClubsStrain: "C";
			case DiamondsStrain: "D";
			case HeartsStrain: "H";
			case SpadesStrain: "S";
			case NoTrumpStrain: "NT";
		}
	}

	public function canBid(level:Int, strain:Strain):Bool {
		if (phase != Bidding || level < 1 || level > 7) return false;
		if (highBid == null) return true;
		return level > highBid.level || (level == highBid.level && (strain : Int) > (highBid.strain : Int));
	}

	public function bid(seat:Int, level:Int, strain:Strain):Void {
		if (phase != Bidding || seat != turn) throw 'Not seat $seat\'s turn to bid';
		if (!canBid(level, strain)) throw "That bid is not high enough";
		highBid = {level: level, strain: strain, by: seat};
		passesInRow = 0;
		callLog.push('$level${strainName(strain)}');
		PlayLog.play(seat, 'bids $level${strainName(strain)}');
		turn = (turn + 1) % SEATS;
	}

	public function pass(seat:Int):Void {
		if (phase != Bidding || seat != turn) throw 'Not seat $seat\'s turn to bid';
		passesInRow++;
		callLog.push("Pass");
		PlayLog.play(seat, "passes");
		if (highBid == null && passesInRow == SEATS) {
			thrownIn = true;
			phase = HandOver;
			return;
		}
		if (highBid != null && passesInRow == SEATS - 1) {
			settleContract();
			return;
		}
		turn = (turn + 1) % SEATS;
	}

	/** The winning bidder declares (real bridge credits whoever on that side named the strain
		first; tracking that adds an auction-history search this simplified engine skips). **/
	function settleContract():Void {
		declarer = highBid.by;
		dummy = partnerOf(declarer);
		contractLevel = highBid.level;
		contractStrain = highBid.strain;
		trump = highBid.strain == NoTrumpStrain ? null : Suit.fromInt(highBid.strain);
		phase = Playing;
		leader = turn = (declarer + 1) % SEATS;
		PlayLog.note('Contract: $contractLevel${strainName(contractStrain)} by ${PlayLog.who(declarer)}');
	}

	// --- Play ----------------------------------------------------------

	public function legalPlays(seat:Int):Array<Card> {
		if (phase != Playing || seat != turn) return [];
		var hand = hands[seat];
		if (trick.length == 0) return hand.copy();
		var led = trick[0].card.suit;
		var follow = [for (c in hand) if (c.suit == led) c];
		return follow.length > 0 ? follow : hand.copy();
	}

	function beats(a:Card, b:Card, led:Suit):Bool {
		if (a.suit == b.suit) return a.rank > b.rank;
		if (trump != null && a.suit == trump) return true;
		if (trump != null && b.suit == trump) return false;
		return a.suit == led;
	}

	public function play(seat:Int, card:Card):Void {
		if (legalPlays(seat).indexOf(card) < 0) throw 'Seat $seat cannot play ${card.code}';
		hands[seat].remove(card);
		trick.push({seat: seat, card: card});
		PlayLog.play(seat, "plays " + card.toString() + (seat == dummy ? " (from dummy)" : ""));
		if (trick.length < SEATS) {
			turn = (turn + 1) % SEATS;
			return;
		}
		var led = trick[0].card.suit;
		var win = trick[0];
		for (p in trick) if (beats(p.card, win.card, led)) win = p;
		tricks[win.seat]++;
		PlayLog.play(win.seat, "wins the trick");
		lastTrick.resize(0);
		for (p in trick) lastTrick.push(p);
		trick.resize(0);
		lastWinner = win.seat;
		tricksPlayed++;
		turn = leader = win.seat;
		if (tricksPlayed == HAND_SIZE) scoreHand();
	}

	function scoreHand():Void {
		var declarerTeam = teamOf(declarer);
		var made2 = tricks[declarer] + tricks[dummy];
		var needed = 6 + contractLevel;
		var trickValue = contractStrain == ClubsStrain || contractStrain == DiamondsStrain ? 20 : 30;
		lastMade = made2 >= needed;
		if (lastMade) {
			var firstTrickBonus = contractStrain == NoTrumpStrain ? 10 : 0;
			lastPoints = contractLevel * trickValue + firstTrickBonus + 50;
			scores[declarerTeam] += lastPoints;
		} else {
			lastPoints = (needed - made2) * 50;
			scores[1 - declarerTeam] += lastPoints;
		}
		if (scores[0] >= WINNING_SCORE || scores[1] >= WINNING_SCORE) {
			winner = scores[0] == scores[1] ? -1 : (scores[0] > scores[1] ? 0 : 1);
			phase = winner >= 0 ? GameOver : HandOver;
		} else phase = HandOver;
	}
}
