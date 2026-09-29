// SPDX-License-Identifier: AGPL-3.0-or-later
package games.canasta;

import cards.Card;
import cards.Deck;

typedef Meld = {rank:Int, cards:Array<Card>};

enum abstract Phase(String) to String {
	var Draw = "draw";
	var Turn = "turn";
	var HandOver = "hand over";
	var GameOver = "game over";
}

/**
	Two-player Canasta, simplified: this engine has no joker (the card model
	only has the standard 52), so two decks (104 cards) and the deuces alone
	are wild. Dropped from full Canasta for the same reason of scope: the
	red-three bonus/penalty, the black-three block on the last discard, and
	freezing the pile. What's kept is the game's core identity: melds of 3+
	one rank, wild cards limited to no more than the natural cards in the
	meld, a 7+ card meld is a canasta, and going out needs at least one.

	Each turn: draw from the stock, or take the whole discard pile if its
	top card would extend an existing meld or 2+ natural cards in hand can
	meld it fresh; then meld freely; then discard to end the turn. A hand
	ends when the stock runs out (no score) or a player empties their hand
	with a canasta down (100 bonus, and the discard on the way out still
	scores). First to 5000 wins.
**/
class Canasta {
	public static inline var HAND_SIZE = 11;
	public static inline var WINNING_SCORE = 5000;
	public static inline var WILD_RANK = 2;

	public var phase(default, null):Phase = Draw;
	public final hands:Array<Array<Card>> = [[], []];
	public final stock:Array<Card> = [];
	public final discardPile:Array<Card> = [];
	public var melds(default, null):Array<Array<Meld>> = [[], []];
	public var turn(default, null) = 0;
	public var dealer(default, null) = 0;
	public final scores:Array<Int> = [0, 0];
	public var goneOut(default, null) = -1;
	public var winner(default, null) = -1;

	public function new() {}

	public function dealFrom(rng:rng.IRng):Void {
		var deck = Deck.standard().concat(Deck.standard());
		rng.shuffle(deck);
		startDeal(deck);
	}

	/** Test hook: deals from a known stock order. **/
	public function startDeal(order:Array<Card>):Void {
		hands[0].resize(0);
		hands[1].resize(0);
		stock.resize(0);
		discardPile.resize(0);
		melds = [[], []];
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
		goneOut = -1;
		phase = Draw;
	}

	public static inline function isWild(c:Card):Bool return c.rank == WILD_RANK;

	public static function pointValue(c:Card):Int {
		if (isWild(c) || c.rank == Card.ACE) return 20;
		if (c.rank >= 8) return 10;
		return 5;
	}

	public function drawFromStock():Void {
		if (phase != Draw) throw "Not drawing now";
		if (stock.length == 0) {
			goneOut = -1;
			phase = HandOver;
			return;
		}
		hands[turn].push(stock.shift());
		phase = Turn;
	}

	/** Whether the discard pile's top card could be taken right now. **/
	public function canTakeDiscard():Bool {
		if (phase != Draw || discardPile.length == 0) return false;
		var top = discardPile[discardPile.length - 1];
		if (isWild(top)) return false;
		var naturalInHand = 0;
		for (c in hands[turn]) if (!isWild(c) && c.rank == top.rank) naturalInHand++;
		if (naturalInHand >= 2) return true;
		for (m in melds[turn]) if (m.rank == top.rank) return true;
		return false;
	}

	public function takeDiscard():Void {
		if (!canTakeDiscard()) throw "Cannot take the discard pile now";
		for (c in discardPile) hands[turn].push(c);
		discardPile.resize(0);
		phase = Turn;
	}

	/** The rank a group of cards would meld as, or null if it's not a legal meld. **/
	static function meldOf(cards:Array<Card>):Null<Int> {
		var natural = [for (c in cards) if (!isWild(c)) c];
		var wild = cards.length - natural.length;
		if (cards.length < 3 || natural.length == 0 || wild > natural.length) return null;
		var rank = natural[0].rank;
		for (c in natural) if (c.rank != rank) return null;
		return rank;
	}

	public function meld(cards:Array<Card>):Void {
		if (phase != Turn) throw "Cannot meld now";
		var rank = meldOf(cards);
		if (rank == null) throw "Not a legal meld";
		for (c in cards) if (hands[turn].indexOf(c) < 0) throw 'Does not hold ${c.code}';
		for (c in cards) hands[turn].remove(c);
		melds[turn].push({rank: rank, cards: cards.copy()});
	}

	/** Adds cards from the hand onto one of this player's existing melds. **/
	public function layOn(meldIndex:Int, cards:Array<Card>):Void {
		if (phase != Turn) throw "Cannot meld now";
		if (meldIndex < 0 || meldIndex >= melds[turn].length) throw "No such meld";
		var m = melds[turn][meldIndex];
		var rank = meldOf(m.cards.concat(cards));
		if (rank == null || rank != m.rank) throw "Cannot add those cards to that meld";
		for (c in cards) if (hands[turn].indexOf(c) < 0) throw 'Does not hold ${c.code}';
		for (c in cards) hands[turn].remove(c);
		for (c in cards) m.cards.push(c);
	}

	public function hasCanasta(seat:Int):Bool {
		for (m in melds[seat]) if (m.cards.length >= 7) return true;
		return false;
	}

	public function discard(card:Card):Void {
		if (phase != Turn) throw "Cannot discard now";
		if (isWild(card)) throw "Wild cards cannot be discarded";
		if (hands[turn].indexOf(card) < 0) throw 'Does not hold ${card.code}';
		if (hands[turn].length == 1 && !hasCanasta(turn)) throw "Cannot go out without a canasta";
		hands[turn].remove(card);
		discardPile.push(card);
		if (hands[turn].length == 0) {
			endHand(turn);
			return;
		}
		turn = 1 - turn;
		phase = Draw;
	}

	function endHand(outSeat:Int):Void {
		goneOut = outSeat;
		for (seat in 0...2) {
			var total = 0;
			for (m in melds[seat]) {
				for (c in m.cards) total += pointValue(c);
				if (m.cards.length >= 7) total += allNatural(m) ? 500 : 300;
			}
			for (c in hands[seat]) total -= pointValue(c);
			if (seat == outSeat) total += 100;
			scores[seat] += total;
		}
		if (scores[0] >= WINNING_SCORE || scores[1] >= WINNING_SCORE) {
			winner = scores[0] == scores[1] ? -1 : (scores[0] > scores[1] ? 0 : 1);
			phase = winner >= 0 ? GameOver : HandOver;
		} else phase = HandOver;
	}

	static function allNatural(m:Meld):Bool {
		for (c in m.cards) if (isWild(c)) return false;
		return true;
	}
}
