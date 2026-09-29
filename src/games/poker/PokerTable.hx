// SPDX-License-Identifier: AGPL-3.0-or-later
package games.poker;

import games.PlayLog;
import cards.Card;
import cards.Deck;

enum abstract Variant(String) to String {
	var Holdem = "Texas Hold'em";
	var Draw = "Five-card draw";
}

enum abstract Phase(String) to String {
	var Waiting = "waiting";
	var Betting = "betting";
	var Drawing = "drawing";
	var HandOver = "hand over";
}

enum Action {
	Fold;
	Check;
	Call;

	/** Bet or raise so this seat's total for the round becomes `amount`. **/
	RaiseTo(amount:Int);
}

typedef Legal = {
	var canCheck:Bool;
	var toCall:Int;
	var canRaise:Bool;
	var minRaiseTo:Int;
	var maxRaiseTo:Int;
}

typedef Payout = {seat:Int, amount:Int, hand:String};

class Seat {
	public final name:String;
	public var stack:Int;
	public var cards:Array<Card> = [];
	public var folded = false;
	public var allIn = false;

	/** Chips put in during the current betting round. **/
	public var bet = 0;

	/** Chips put in this hand, antes and blinds included. **/
	public var total = 0;

	public var acted = false;

	/** False once this seat has acted and no full raise has come since (a short all-in doesn't reopen). **/
	public var canRaise = true;

	/** Out of chips before the hand: dealt out. **/
	public var sittingOut = false;

	/** Cards exchanged at the draw (Five-card draw), or -1 before drawing. **/
	public var drew = -1;

	public function new(name:String, stack:Int) {
		this.name = name;
		this.stack = stack;
	}

	public var live(get, never):Bool;

	inline function get_live():Bool return !sittingOut && !folded;

	public var canAct(get, never):Bool;

	inline function get_canAct():Bool return live && !allIn;
}

/**
	No-limit poker table (§6.4): Texas Hold'em with blinds, or Five-card draw
	with antes. Handles betting rounds, full and short all-in raises, side
	pots and the showdown. Seats run clockwise; seat 0 is the player.

	Five-card draw follows the classic game (pagat.com): everyone antes, the
	first betting round starts left of the dealer, each player may exchange up
	to three cards, and the second round starts with whoever opened the first.
	If everyone checks the first round, the hand is thrown in and the pot
	carries over to the next deal.
**/
class PokerTable {
	public static inline var MAX_DRAW = 3;

	public final variant:Variant;
	public final seats:Array<Seat>;
	public final smallBlind:Int;
	public final bigBlind:Int;
	public final ante:Int;

	public var phase(default, null):Phase = Waiting;
	public var button(default, null) = -1;

	/** Hold'em: 0 preflop, 1 flop, 2 turn, 3 river. Draw: 0 before the draw, 1 after. **/
	public var street(default, null) = 0;

	public final board:Array<Card> = [];
	public var currentBet(default, null) = 0;
	public var minRaise(default, null) = 0;
	public var toAct(default, null) = -1;

	/** Draw: whose turn it is to exchange cards. **/
	public var drawer(default, null) = -1;

	/** Dead money carried into this hand from a thrown-in deal. **/
	public var carried(default, null) = 0;

	public var results(default, null):Array<Payout> = [];

	/** True when the hand went to a showdown (cards are shown). **/
	public var showdown(default, null) = false;

	/** True when the last deal was thrown in because everyone checked. **/
	public var thrownIn(default, null) = false;

	public var handNumber(default, null) = 0;

	var deck:Array<Card> = [];
	var deckPos = 0;
	var opener = -1;

	public function new(variant:Variant, names:Array<String>, stacks:Array<Int>, smallBlind:Int, bigBlind:Int, ante:Int) {
		this.variant = variant;
		seats = [for (i in 0...names.length) new Seat(names[i], stacks[i])];
		this.smallBlind = smallBlind;
		this.bigBlind = bigBlind;
		this.ante = ante;
	}

	/** Everything in the middle: this hand's chips plus any carried pot. **/
	public var pot(get, never):Int;

	function get_pot():Int {
		var sum = carried;
		for (s in seats) sum += s.total;
		return sum;
	}

	public function canStart():Bool {
		var n = 0;
		for (s in seats) if (s.stack > 0) n++;
		return n >= 2;
	}

	public function startHand(rng:rng.IRng):Void {
		if (phase == Betting || phase == Drawing) throw 'A hand is in progress';
		if (!canStart()) throw 'Need two players with chips';
		handNumber++;
		PlayLog.note('Hand $handNumber is dealt');
		results = [];
		showdown = false;
		thrownIn = false;
		board.resize(0);
		street = 0;
		opener = -1;
		for (s in seats) {
			s.cards = [];
			s.folded = s.allIn = false;
			s.bet = s.total = 0;
			s.acted = false;
			s.canRaise = true;
			s.drew = -1;
			s.sittingOut = s.stack <= 0;
		}
		button = next(button, s -> !s.sittingOut);
		deck = Deck.standard();
		rng.shuffle(deck);
		deckPos = 0;

		var active = [for (i in 0...seats.length) if (!seats[i].sittingOut) i];
		currentBet = 0;
		minRaise = bigBlind;
		if (variant == Holdem) {
			// Heads-up, the button posts the small blind and acts first before the flop.
			var sb = active.length == 2 ? button : next(button, s -> !s.sittingOut);
			var bb = next(sb, s -> !s.sittingOut);
			post(sb, smallBlind);
			post(bb, bigBlind);
			currentBet = bigBlind;
			dealRound(2);
			toAct = next(bb, s -> s.canAct);
		} else {
			for (i in active) put(i, Std.int(Math.min(ante, seats[i].stack)));
			for (s in seats) s.bet = 0; // antes are dead money, not bets
			dealRound(5);
			toAct = next(button, s -> s.canAct);
		}
		phase = Betting;
		if (!needsBetting()) endRound();
	}

	function dealRound(count:Int):Void {
		for (_ in 0...count) {
			var i = button;
			for (_ in 0...seats.length) {
				i = (i + 1) % seats.length;
				if (!seats[i].sittingOut) seats[i].cards.push(draw());
			}
		}
	}

	inline function draw():Card return deck[deckPos++];

	function post(seat:Int, amount:Int):Void {
		put(seat, Std.int(Math.min(amount, seats[seat].stack)));
	}

	function put(seat:Int, amount:Int):Void {
		var s = seats[seat];
		s.stack -= amount;
		s.bet += amount;
		s.total += amount;
		if (s.stack == 0 && !s.sittingOut) s.allIn = true;
	}

	/** The next seat after `from`, clockwise, that passes `ok`; -1 if none. **/
	function next(from:Int, ok:Seat->Bool):Int {
		var n = seats.length;
		var i = from;
		for (_ in 0...n) {
			i = (i + 1 + n) % n;
			if (ok(seats[i])) return i;
		}
		return -1;
	}

	public function legal(seat:Int):Legal {
		var s = seats[seat];
		var maxTo = s.bet + s.stack;
		var minTo = currentBet == 0 ? bigBlind : currentBet + minRaise;
		return {
			canCheck: s.bet == currentBet,
			toCall: Std.int(Math.min(currentBet - s.bet, s.stack)),
			canRaise: s.canRaise && maxTo > currentBet,
			minRaiseTo: Std.int(Math.min(minTo, maxTo)),
			maxRaiseTo: maxTo,
		};
	}

	public function act(seat:Int, action:Action):Void {
		if (phase != Betting || seat != toAct) throw 'Seat $seat cannot act now';
		var s = seats[seat];
		var l = legal(seat);
		var betBefore = currentBet;
		switch action {
			case Fold:
				s.folded = true;
			case Check:
				if (!l.canCheck) throw 'Cannot check facing a bet';
			case Call:
				if (l.toCall == 0) throw 'Nothing to call';
				put(seat, l.toCall);
			case RaiseTo(amount):
				if (!l.canRaise) throw 'Raising is closed to seat $seat';
				if (amount > l.maxRaiseTo || amount <= currentBet || (amount < l.minRaiseTo && amount != l.maxRaiseTo))
					throw 'Illegal raise to $amount (min ${l.minRaiseTo}, max ${l.maxRaiseTo})';
				var increment = amount - currentBet;
				put(seat, amount - s.bet);
				if (increment >= minRaise || currentBet == 0) {
					// A full raise reopens the betting for everyone else.
					minRaise = Std.int(Math.max(increment, bigBlind));
					for (o in seats) if (o != s) {
						o.acted = false;
						o.canRaise = true;
					}
				}
				currentBet = amount;
				if (opener < 0) opener = seat;
		}
		PlayLog.by(s.name, (switch action {
			case Fold: "folds";
			case Check: "checks";
			case Call: 'calls ${l.toCall}';
			case RaiseTo(amount): (betBefore == 0 ? "bets " : "raises to ") + amount;
		}) + (s.allIn ? " (all in)" : ""));
		s.acted = true;
		s.canRaise = false;
		advance(seat);
	}

	function advance(from:Int):Void {
		if (liveCount() == 1) {
			awardUncontested();
			return;
		}
		if (roundComplete()) endRound();
		else toAct = next(from, o -> o.canAct && (!o.acted || o.bet < currentBet));
	}

	function liveCount():Int {
		var n = 0;
		for (s in seats) if (s.live) n++;
		return n;
	}

	function roundComplete():Bool {
		for (s in seats) if (s.canAct && (!s.acted || s.bet < currentBet)) return false;
		return true;
	}

	/** Betting only matters while two players can still act, or one faces a bet. **/
	function needsBetting():Bool {
		var actors = 0, facing = false;
		for (s in seats) if (s.canAct) {
			actors++;
			if (s.bet < currentBet) facing = true;
		}
		return actors >= 2 || facing;
	}

	function endRound():Void {
		for (s in seats) s.bet = 0;
		var noBets = currentBet == 0;
		currentBet = 0;
		minRaise = bigBlind;
		if (variant == Draw) {
			if (street == 0) {
				if (noBets && liveCount() > 1 && everyoneCouldAct()) {
					throwIn();
					return;
				}
				phase = Drawing;
				drawer = next(button, o -> o.live);
				return;
			}
			finish();
			return;
		}
		if (street >= 3) {
			finish();
			return;
		}
		street++;
		draw(); // burn
		for (_ in 0...(street == 1 ? 3 : 1)) board.push(draw());
		PlayLog.note(["", "Flop", "Turn", "River"][street] + ": " + PlayLog.cards(board));
		startRound(next(button, o -> o.canAct));
	}

	/** Everyone who could bet chose to check (no one was all-in from the antes). **/
	function everyoneCouldAct():Bool {
		for (s in seats) if (s.live && s.allIn) return false;
		return true;
	}

	function startRound(first:Int):Void {
		for (s in seats) {
			s.acted = false;
			s.canRaise = true;
		}
		phase = Betting;
		toAct = first;
		if (first < 0 || !needsBetting()) endRound();
	}

	/** Five-card draw: `seat` swaps up to three cards. **/
	public function exchange(seat:Int, discards:Array<Card>):Void {
		if (phase != Drawing || seat != drawer) throw 'Seat $seat cannot draw now';
		if (discards.length > MAX_DRAW) throw 'At most $MAX_DRAW cards may be exchanged';
		var s = seats[seat];
		for (c in discards) if (!s.cards.remove(c)) throw 'Seat $seat does not hold ${c.code}';
		for (_ in discards) s.cards.push(draw());
		s.drew = discards.length;
		PlayLog.by(s.name, discards.length == 0 ? "stands pat" : 'draws ${discards.length}');
		afterDraw(seat);
	}

	function afterDraw(seat:Int):Void {
		drawer = next(seat, o -> o.live && o.drew < 0);
		if (drawer >= 0) return;
		street = 1;
		var first = opener >= 0 && seats[opener].canAct ? opener : next(opener >= 0 ? opener : button, o -> o.canAct);
		startRound(first);
	}

	/** Folds `seat` out of turn (the player walked away mid-hand). **/
	public function forfeit(seat:Int):Void {
		var s = seats[seat];
		if (!(phase == Betting || phase == Drawing) || !s.live) return;
		if (phase == Betting && toAct == seat) {
			act(seat, Fold);
			return;
		}
		PlayLog.by(s.name, "leaves the table and folds");
		s.folded = true;
		if (liveCount() == 1) {
			awardUncontested();
			return;
		}
		if (phase == Drawing && drawer == seat) afterDraw(seat);
		else if (phase == Betting && roundComplete()) endRound();
	}

	function throwIn():Void {
		carried = pot;
		for (s in seats) s.total = 0;
		thrownIn = true;
		phase = HandOver;
		toAct = -1;
	}

	function awardUncontested():Void {
		var winner = next(-1, o -> o.live);
		var amount = pot;
		seats[winner].stack += amount;
		PlayLog.by(seats[winner].name, 'wins $amount (everyone else folded)');
		results = [{seat: winner, amount: amount, hand: ""}];
		closeHand();
	}

	/** Splits the pot into main and side pots and pays the best hand in each. **/
	function finish():Void {
		// All-ins with betting done: deal out the rest of the board.
		if (variant == Holdem) while (board.length < 5) {
			draw();
			for (_ in 0...(board.length == 0 ? 3 : 1)) board.push(draw());
		}
		showdown = true;
		var scores = [for (s in seats) s.live ? HandEval.score(s.cards.concat(board)) : -1];
		var won = [for (_ in seats) 0];
		var levels = [];
		for (s in seats) if (s.live && levels.indexOf(s.total) < 0) levels.push(s.total);
		levels.sort((a, b) -> a - b);
		var prev = 0;
		for (li in 0...levels.length) {
			var level = levels[li], amount = 0;
			for (s in seats) amount += Std.int(Math.max(0, Math.min(s.total, level) - prev));
			if (li == 0) amount += carried;
			// Chips folded players put in above the top live level go to the last pot.
			if (li == levels.length - 1) for (s in seats) if (s.total > level) amount += s.total - level;
			var eligible = [for (i in 0...seats.length) if (seats[i].live && seats[i].total >= level) i];
			var best = -1;
			for (i in eligible) if (scores[i] > best) best = scores[i];
			var winners = [for (i in eligible) if (scores[i] == best) i];
			// Odd chips go to the first winner clockwise from the button.
			winners.sort((a, b) -> ((a - button - 1 + seats.length) % seats.length) - ((b - button - 1 + seats.length) % seats.length));
			var share = Std.int(amount / winners.length), odd = amount - share * winners.length;
			for (k in 0...winners.length) won[winners[k]] += share + (k < odd ? 1 : 0);
			prev = level;
		}
		if (variant == Holdem) PlayLog.note("Board: " + PlayLog.cards(board));
		for (i in 0...seats.length) if (seats[i].live) PlayLog.by(seats[i].name, 'shows ${PlayLog.cards(seats[i].cards)}: ${HandEval.describe(scores[i])}');
		results = [];
		for (i in 0...seats.length) if (won[i] > 0) {
			seats[i].stack += won[i];
			results.push({seat: i, amount: won[i], hand: HandEval.describe(scores[i])});
			PlayLog.by(seats[i].name, 'wins ${won[i]}');
		}
		closeHand();
	}

	function closeHand():Void {
		carried = 0;
		for (s in seats) s.bet = 0;
		phase = HandOver;
		toAct = -1;
		drawer = -1;
	}

	/** Puts the dealer button on `seat` between hands (it moves on at the next deal); for replaying a recorded hand. **/
	public function setButton(seat:Int):Void {
		if (phase == Betting || phase == Drawing) throw 'Not during a hand';
		button = seat;
	}

	/** Chips go into or out of a seat between hands (buy-ins, cashing out). **/
	public function setStack(seat:Int, amount:Int):Void {
		if (phase == Betting || phase == Drawing) throw 'Not during a hand';
		seats[seat].stack = amount;
	}
}
