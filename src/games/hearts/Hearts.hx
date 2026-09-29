// SPDX-License-Identifier: AGPL-3.0-or-later
package games.hearts;

import games.PlayLog;
import cards.Card;
import cards.Deck;
import cards.Suit;

enum abstract Phase(String) to String {
	var Passing = "passing";
	var Playing = "playing";
	var HandOver = "hand over";
	var GameOver = "game over";
}

/** Who a hand's passing goes to, rotating hand to hand; `Hold` skips passing. **/
enum abstract PassDirection(Int) {
	var Left;
	var Right;
	var Across;
	var Hold;
}

typedef Play = {seat:Int, card:Card};

/**
	Hearts (§6.4, bicyclecards.com): four seats, no partnerships. Passing
	rotates left, right, across, then a held hand with no passing, repeating.
	Each heart scores 1 point; the queen of spades scores 13. Whoever holds
	the two of clubs after passing leads it to start play, and must follow
	suit if able. Hearts can't be led until broken (played to an earlier
	trick, or led because nothing else is held), and neither the two of
	clubs' trick nor a hand with no hearts broken yet may be opened with the
	queen of spades unless nothing else is held.

	Shooting the moon: taking every heart and the queen in one hand scores
	the shooter 0 and everyone else 26 instead of the usual tally. Lowest
	score when someone reaches 100 wins (ties play on).
**/
class Hearts {
	public static inline var SEATS = 4;
	public static inline var HAND_SIZE = 13;
	public static inline var ENDING_SCORE = 100;
	public static inline var SHOOT_THE_MOON = 26;

	public var phase(default, null):Phase = Passing;
	public final hands:Array<Array<Card>> = [for (_ in 0...SEATS) []];
	public final passOut:Array<Array<Card>> = [for (_ in 0...SEATS) []];
	public final passIn:Array<Null<Array<Card>>> = [for (_ in 0...SEATS) null];
	public var passDirection(default, null):PassDirection = Left;
	public final scores:Array<Int> = [0, 0, 0, 0];
	public final tricks:Array<Array<Card>> = [for (_ in 0...SEATS) []];
	public var turn(default, null) = 0;
	public var leader(default, null) = 0;
	public var heartsBroken(default, null) = false;
	public final trick:Array<Play> = [];
	public final lastTrick:Array<Play> = [];
	public var lastWinner(default, null) = -1;
	public var tricksPlayed(default, null) = 0;
	public var handNumber(default, null) = 0;
	public final played:Array<Card> = [];
	public final voids:Array<Array<Bool>> = [for (_ in 0...SEATS) [false, false, false, false]];
	public var shooter(default, null) = -1;
	public var winner(default, null) = -1;

	public function new() {}

	public function dealFrom(rng:rng.IRng):Void {
		var deck = Deck.standard();
		rng.shuffle(deck);
		startHand([for (s in 0...SEATS) deck.slice(s * HAND_SIZE, (s + 1) * HAND_SIZE)]);
	}

	/** Test hook: starts a hand from given hands. **/
	public function startHand(dealt:Array<Array<Card>>):Void {
		if (phase == GameOver) throw 'The game is over';
		if (dealt.length != SEATS) throw 'Need $SEATS hands';
		for (s in 0...SEATS) {
			if (dealt[s].length != HAND_SIZE) throw 'Each hand needs $HAND_SIZE cards';
			hands[s] = dealt[s].copy();
			passOut[s] = [];
			passIn[s] = null;
			tricks[s] = [];
			for (i in 0...4) voids[s][i] = false;
		}
		handNumber++;
		trick.resize(0);
		lastTrick.resize(0);
		played.resize(0);
		lastWinner = -1;
		tricksPlayed = 0;
		heartsBroken = false;
		shooter = -1;
		passDirection = handNumber == 1 ? Left : cast ((cast passDirection : Int) + 1) % 4;
		if (passDirection == Hold) {
			phase = Playing;
			leader = turn = leaderByTwoOfClubs();
		} else phase = Passing;
	}

	function leaderByTwoOfClubs():Int {
		var two = Card.of(2, Suit.Clubs);
		for (s in 0...SEATS) if (hands[s].indexOf(two) >= 0) return s;
		throw "No one holds the two of clubs";
	}

	function passTarget(seat:Int):Int {
		return switch passDirection {
			case Left: (seat + 1) % SEATS;
			case Right: (seat + SEATS - 1) % SEATS;
			case Across: (seat + 2) % SEATS;
			case Hold: seat;
		}
	}

	/** A seat sets aside the three cards it's passing on. **/
	public function setPass(seat:Int, cards:Array<Card>):Void {
		if (phase != Passing) throw "Not passing this hand";
		if (cards.length != 3) throw "Pass exactly 3 cards";
		for (c in cards) if (hands[seat].indexOf(c) < 0) throw 'Seat $seat does not hold ${c.code}';
		passOut[seat] = cards.copy();
		// Only the player's own pass is on show; the house players' stay face down.
		PlayLog.play(seat, seat == 0 ? "passes " + PlayLog.cards(cards) : "passes three cards");
		if (allPassed()) resolvePass();
	}

	function allPassed():Bool {
		for (s in 0...SEATS) if (passOut[s].length != 3) return false;
		return true;
	}

	function resolvePass():Void {
		for (s in 0...SEATS) passIn[passTarget(s)] = passOut[s];
		for (s in 0...SEATS) {
			for (c in passOut[s]) hands[s].remove(c);
			for (c in passIn[s]) hands[s].push(c);
		}
		phase = Playing;
		leader = turn = leaderByTwoOfClubs();
	}

	public function legalPlays(seat:Int):Array<Card> {
		if (phase != Playing || seat != turn) return [];
		var hand = hands[seat];
		if (trick.length == 0) {
			if (tricksPlayed == 0) return [Card.of(2, Suit.Clubs)];
			if (!heartsBroken) {
				var nonHearts = [for (c in hand) if (c.suit != Suit.Hearts) c];
				return nonHearts.length > 0 ? nonHearts : hand.copy();
			}
			return hand.copy();
		}
		var led = trick[0].card.suit;
		var follow = [for (c in hand) if (c.suit == led) c];
		if (follow.length > 0) return follow;
		// No hearts or the queen of spades on the very first trick, if anything else is held.
		if (tricksPlayed == 0) {
			var safe = [for (c in hand) if (c.suit != Suit.Hearts && !(c.suit == Suit.Spades && c.rank == Card.QUEEN)) c];
			return safe.length > 0 ? safe : hand.copy();
		}
		return hand.copy();
	}

	public function isLegal(seat:Int, card:Card):Bool {
		for (c in legalPlays(seat)) if (c == card) return true;
		return false;
	}

	public function play(seat:Int, card:Card):Void {
		if (!isLegal(seat, card)) throw 'Seat $seat cannot play ${card.code}';
		hands[seat].remove(card);
		if (trick.length > 0 && card.suit != trick[0].card.suit) voids[seat][(card.suit : Int)] = true;
		if (card.suit == Suit.Hearts) heartsBroken = true;
		trick.push({seat: seat, card: card});
		played.push(card);
		PlayLog.play(seat, "plays " + card.toString());
		if (trick.length < SEATS) {
			turn = (turn + 1) % SEATS;
			return;
		}
		var led = trick[0].card.suit;
		var win = trick[0];
		for (p in trick) if (p.card.suit == led && p.card.rank > win.card.rank) win = p;
		for (p in trick) tricks[win.seat].push(p.card);
		PlayLog.play(win.seat, "takes the trick");
		lastTrick.resize(0);
		for (p in trick) lastTrick.push(p);
		trick.resize(0);
		lastWinner = win.seat;
		tricksPlayed++;
		turn = leader = win.seat;
		if (tricksPlayed == HAND_SIZE) scoreHand();
	}

	public static function cardPoints(c:Card):Int {
		if (c.suit == Suit.Hearts) return 1;
		if (c.suit == Suit.Spades && c.rank == Card.QUEEN) return 13;
		return 0;
	}

	function scoreHand():Void {
		var taken = [for (s in 0...SEATS) 0];
		for (s in 0...SEATS) for (c in tricks[s]) taken[s] += cardPoints(c);
		var moon = -1;
		for (s in 0...SEATS) if (taken[s] == 26) moon = s;
		if (moon >= 0) {
			shooter = moon;
			for (s in 0...SEATS) scores[s] += s == moon ? 0 : SHOOT_THE_MOON;
		} else for (s in 0...SEATS) scores[s] += taken[s];
		var lowest = scores[0];
		for (s in 1...SEATS) if (scores[s] < lowest) lowest = scores[s];
		var atEnd = false;
		for (s in 0...SEATS) if (scores[s] >= ENDING_SCORE) atEnd = true;
		if (atEnd) {
			var winners = [for (s in 0...SEATS) if (scores[s] == lowest) s];
			winner = winners.length == 1 ? winners[0] : -1;
			phase = winner >= 0 ? GameOver : HandOver;
		} else phase = HandOver;
	}
}
