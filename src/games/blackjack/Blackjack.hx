// SPDX-License-Identifier: AGPL-3.0-or-later
package games.blackjack;

import cards.Card;

enum abstract Phase(String) to String {
	var Betting = "betting";
	var Insurance = "insurance";
	var PlayerTurn = "player";
	var RoundOver = "over";
}

enum abstract Action(String) to String {
	var Hit = "Hit";
	var Stand = "Stand";
	var Double = "Double";
	var Split = "Split";
	var Surrender = "Surrender";
}

enum abstract Outcome(String) to String {
	var Natural = "Blackjack";
	var Win = "Win";
	var Push = "Push";
	var Lose = "Lose";
	var Bust = "Bust";
	var Surrendered = "Surrender";
}

/** Where the cards come from. The table uses a real shoe; tests stack the deck. **/
interface CardSource {
	function draw():Card;

	/** Called before each round's deal; shuffles if the cut card came out, and says so. **/
	function beforeRound():Bool;
}

/** The Card Room's six-deck shoe with its cut card at 75% (§6.4). **/
class ShoeSource implements CardSource {
	final shoe:cards.Shoe;

	public function new(rng:rng.IRng) {
		shoe = new cards.Shoe(Blackjack.DECKS, Blackjack.PENETRATION, rng);
	}

	public function draw():Card return shoe.draw();

	public function beforeRound():Bool {
		if (!shoe.cutCardReached) return false;
		shoe.shuffle();
		return true;
	}

	public var remaining(get, never):Int;

	inline function get_remaining():Int return shoe.remaining;
}

class Hand {
	public final cards:Array<Card> = [];

	/** Deal sequence number of each card, so the table can reveal them in order. **/
	public final order:Array<Int> = [];

	public var bet:Int;
	public var doubled = false;
	public var fromSplit = false;
	public var splitAces = false;
	public var done = false;
	public var outcome:Null<Outcome> = null;

	/** Sovereigns returned to the purse at settlement, stake included. **/
	public var payout = 0;

	public function new(bet:Int) {
		this.bet = bet;
	}

	public var total(get, never):Int;

	inline function get_total():Int return Blackjack.total(cards);

	public var soft(get, never):Bool;

	inline function get_soft():Bool return Blackjack.isSoft(cards);

	/** Two-card 21 on an unsplit hand. A split 21 is just 21. **/
	public var natural(get, never):Bool;

	inline function get_natural():Bool return !fromSplit && cards.length == 2 && total == 21;
}

/**
	The Card Room blackjack table (§6.4): 6 decks, dealer stands on all 17s,
	double on any two cards (also after splits), split to four hands, split aces
	get one card each, late surrender, insurance, dealer peek, and blackjack
	pays 3:2. Pure rules and money: the table screen only shows this state.

	Bets are whole, even Sovereigns so that 3:2 and half-bet insurance always
	pay in full.
**/
class Blackjack {
	public static inline var DECKS = 6;
	public static inline var PENETRATION = 0.75;
	public static inline var MAX_HANDS = 4;

	/** Chip steps between the table minimum and the Pip-rank maximum (§10.1). **/
	public static final BETS = [2, 4, 10, 20, 30, 40, 50];

	public static inline var MIN_BET = 2;
	public static inline var MAX_BET = 50;

	public var purse(default, null):Int;
	public var phase(default, null):Phase = Betting;
	public final hands:Array<Hand> = [];
	public var active(default, null) = 0;
	public final dealer:Array<Card> = [];
	public final dealerOrder:Array<Int> = [];
	public var holeRevealed(default, null) = false;

	/** Deal sequence number at which the hole card turns over. **/
	public var holeRevealOrder(default, null) = 0;

	public var insuranceBet(default, null) = 0;
	public var insurancePayout(default, null) = 0;

	/** True when this round began with a fresh shuffle. **/
	public var shuffledThisRound(default, null) = false;

	/** Sovereigns staked and returned this round (net = returned - staked). **/
	public var staked(default, null) = 0;

	public var returned(default, null) = 0;

	/** Cards dealt so far this round, including the hole card. **/
	public var sequence(default, null) = 0;

	final source:CardSource;

	public function new(source:CardSource, purse:Int) {
		this.source = source;
		this.purse = purse;
	}

	public static function value(c:Card):Int {
		return c.rank == Card.ACE ? 11 : c.rank >= 10 ? 10 : c.rank;
	}

	public static function total(cards:Array<Card>):Int {
		var sum = 0, aces = 0;
		for (c in cards) {
			sum += value(c);
			if (c.rank == Card.ACE) aces++;
		}
		while (sum > 21 && aces > 0) {
			sum -= 10;
			aces--;
		}
		return sum;
	}

	/** True when an ace still counts as 11. **/
	public static function isSoft(cards:Array<Card>):Bool {
		var hard = 0, aces = 0;
		for (c in cards) {
			hard += c.rank == Card.ACE ? 1 : value(c);
			if (c.rank == Card.ACE) aces++;
		}
		return aces > 0 && hard + 10 <= 21;
	}

	public var upcard(get, never):Null<Card>;

	inline function get_upcard():Null<Card> return dealer.length > 0 ? dealer[0] : null;

	public var dealerTotal(get, never):Int;

	inline function get_dealerTotal():Int return total(dealer);

	/** Sets the purse when the player sits down with their wallet. Only between rounds. **/
	public function seatPurse(amount:Int):Void {
		if (phase != Betting && phase != RoundOver) throw 'Cannot change the purse mid-round';
		if (amount < 0) throw 'seatPurse(): negative amount $amount';
		purse = amount;
	}

	/** Money for the Pemberton's-marker flow; never a table outcome. **/
	public function credit(amount:Int):Void {
		if (amount < 0) throw 'credit(): negative amount $amount';
		purse += amount;
	}

	public function canBet(bet:Int):Bool {
		return (phase == Betting || phase == RoundOver) && bet >= MIN_BET && bet <= MAX_BET && bet % 2 == 0 && bet <= purse;
	}

	public function deal(bet:Int):Void {
		if (!canBet(bet)) throw 'Bet $bet is not allowed now (purse $purse, phase $phase)';
		hands.resize(0);
		dealer.resize(0);
		dealerOrder.resize(0);
		holeRevealed = false;
		holeRevealOrder = 0;
		insuranceBet = insurancePayout = 0;
		staked = returned = 0;
		sequence = 0;
		active = 0;
		shuffledThisRound = source.beforeRound();
		take(bet);
		var hand = new Hand(bet);
		hands.push(hand);
		// US order: player, dealer up, player, dealer hole.
		give(hand);
		giveDealer();
		give(hand);
		giveDealer();
		if (upcard.rank == Card.ACE && purse >= bet >> 1) {
			phase = Insurance;
			return;
		}
		afterDeal();
	}

	/** Insurance: half the bet against a dealer blackjack, paying 2:1. **/
	public function insure(takeIt:Bool):Void {
		if (phase != Insurance) throw 'No insurance offered now';
		if (takeIt) {
			insuranceBet = hands[0].bet >> 1;
			take(insuranceBet);
		}
		afterDeal();
	}

	function afterDeal():Void {
		var hand = hands[0];
		var peeks = upcard.rank == Card.ACE || value(upcard) == 10;
		if (peeks && total(dealer) == 21) {
			// The dealer peeks and turns over a blackjack: the round ends at once.
			if (insuranceBet > 0) {
				insurancePayout = insuranceBet * 3;
				pay(insurancePayout);
			}
			revealHole();
			if (hand.natural) settleHand(hand, Push, hand.bet) else settleHand(hand, Lose, 0);
			hand.done = true;
			phase = RoundOver;
			return;
		}
		if (hand.natural) {
			revealHole();
			settleHand(hand, Natural, hand.bet + Std.int(hand.bet * 3 / 2));
			hand.done = true;
			phase = RoundOver;
			return;
		}
		phase = PlayerTurn;
	}

	public var current(get, never):Null<Hand>;

	inline function get_current():Null<Hand> return phase == PlayerTurn ? hands[active] : null;

	public function legal():Array<Action> {
		var hand = current;
		if (hand == null) return [];
		var out = [];
		var twoCards = hand.cards.length == 2;
		if (!hand.splitAces && hand.total < 21) out.push(Hit);
		out.push(Stand);
		if (twoCards && !hand.splitAces && purse >= hand.bet) out.push(Double);
		if (twoCards && hands.length < MAX_HANDS && purse >= hand.bet && value(hand.cards[0]) == value(hand.cards[1])
			&& !(hand.splitAces))
			out.push(Split);
		if (twoCards && hands.length == 1 && !hand.fromSplit) out.push(Surrender);
		return out;
	}

	public function act(action:Action):Void {
		if (legal().indexOf(action) < 0) throw '$action is not allowed now';
		var hand = hands[active];
		switch action {
			case Hit:
				give(hand);
				if (hand.total >= 21) hand.done = true;
			case Stand:
				hand.done = true;
			case Double:
				take(hand.bet);
				hand.bet *= 2;
				hand.doubled = true;
				give(hand);
				hand.done = true;
			case Split:
				take(hand.bet);
				var second = new Hand(hand.bet);
				second.fromSplit = hand.fromSplit = true;
				second.cards.push(hand.cards.pop());
				second.order.push(hand.order.pop());
				if (hand.cards[0].rank == Card.ACE) second.splitAces = hand.splitAces = true;
				hands.insert(active + 1, second);
				give(hand);
				if (hand.splitAces || hand.total == 21) hand.done = true;
			case Surrender:
				hand.done = true;
				settleHand(hand, Surrendered, hand.bet >> 1);
		}
		advance();
	}

	/** Moves to the next unfinished hand, giving split hands their second card; then the dealer plays. **/
	function advance():Void {
		while (active < hands.length && hands[active].done) {
			active++;
			if (active < hands.length) {
				var next = hands[active];
				if (next.cards.length == 1) {
					give(next);
					if (next.splitAces || next.total == 21) next.done = true;
				}
			}
		}
		if (active >= hands.length) {
			active = hands.length - 1;
			dealerPlays();
		}
	}

	function dealerPlays():Void {
		revealHole();
		var live = false;
		for (h in hands) if (h.outcome == null && h.total <= 21) live = true;
		// Stands on all 17s, soft ones included.
		if (live) while (total(dealer) < 17) giveDealer();
		var d = total(dealer);
		for (h in hands) {
			if (h.outcome != null) continue;
			var t = h.total;
			if (t > 21) settleHand(h, Bust, 0);
			else if (d > 21 || t > d) settleHand(h, Win, h.bet * 2);
			else if (t == d) settleHand(h, Push, h.bet);
			else settleHand(h, Lose, 0);
		}
		phase = RoundOver;
	}

	function settleHand(hand:Hand, outcome:Outcome, payout:Int):Void {
		hand.outcome = outcome;
		hand.payout = payout;
		pay(payout);
	}

	function revealHole():Void {
		if (holeRevealed) return;
		holeRevealed = true;
		holeRevealOrder = sequence;
	}

	function give(hand:Hand):Void {
		hand.cards.push(source.draw());
		hand.order.push(sequence++);
	}

	function giveDealer():Void {
		dealer.push(source.draw());
		dealerOrder.push(sequence++);
	}

	function take(amount:Int):Void {
		if (amount > purse) throw 'Not enough in the purse ($purse) for $amount';
		purse -= amount;
		staked += amount;
	}

	function pay(amount:Int):Void {
		purse += amount;
		returned += amount;
	}
}
