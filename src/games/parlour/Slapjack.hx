// SPDX-License-Identifier: AGPL-3.0-or-later
package games.parlour;

import cards.Card;
import cards.Deck;

typedef CenterCard = {card:Card, seat:Int};

enum SlapResult {
	/** Nothing to slap. **/
	Empty;

	/** Took the pile with a jack. **/
	Won(cards:Int);

	/** Slapped a non-jack: paid one card to whoever played it. **/
	Penalty(to:Int);

	/** Slapped a non-jack with no cards left to pay. **/
	NothingToPay;
}

/**
	Slapjack (bicyclecards.com): the whole pack is dealt out; in turn each
	player turns their top card face up onto the center. Whoever slaps a jack
	first takes the center pile, puts it under their own and shuffles. A wrong
	slap costs one card, paid to the player of the slapped card. A player with
	no cards stays in until the next jack; if they don't win it, they're out.
	The game ends when one player holds every card.

	Pure rules: who slapped first is decided by the table screen's clock.
**/
class Slapjack {
	/** Each player's face-down pile; index 0 is the top. **/
	public final piles:Array<Array<Card>>;

	public final center:Array<CenterCard> = [];
	public final out:Array<Bool>;
	public var turn(default, null) = 0;
	public var winner(default, null) = -1;

	/** Players who ran out and are waiting on the next jack for one last chance. **/
	public final lastChance:Array<Bool>;

	final rng:rng.IRng;

	public function new(players:Int, rng:rng.IRng) {
		this.rng = rng;
		piles = [for (_ in 0...players) []];
		out = [for (_ in 0...players) false];
		lastChance = [for (_ in 0...players) false];
		var deck = Deck.standard();
		rng.shuffle(deck);
		for (i in 0...deck.length) piles[i % players].push(deck[i]);
	}

	/** Test hook: start from given piles (top first). **/
	public static function fromPiles(piles:Array<Array<Card>>, rng:rng.IRng):Slapjack {
		var g = new Slapjack(piles.length, rng);
		for (i in 0...piles.length) {
			g.piles[i].resize(0);
			for (c in piles[i]) g.piles[i].push(c);
		}
		return g;
	}

	public var top(get, never):Null<CenterCard>;

	inline function get_top():Null<CenterCard> return center.length > 0 ? center[center.length - 1] : null;

	public var jackShowing(get, never):Bool;

	inline function get_jackShowing():Bool return top != null && top.card.rank == Card.JACK;

	/** The player whose turn it is turns their top card onto the center. **/
	public function flip():Card {
		if (winner >= 0) throw 'The game is over';
		if (piles[turn].length == 0) throw 'Seat $turn has no cards';
		var card = piles[turn].shift();
		center.push({card: card, seat: turn});
		var from = turn;
		if (piles[from].length == 0) lastChance[from] = true;
		advanceTurn(from);
		if (stalled) redealCenter();
		return card;
	}

	/**
		House rule for a case the printed rules don't cover: every card is in
		the center and no jack is showing, so no one can play. The center is
		shuffled and dealt back out to everyone still in.
	**/
	function redealCenter():Void {
		var cards = [for (c in center) c.card];
		center.resize(0);
		rng.shuffle(cards);
		var seatsIn = [for (i in 0...piles.length) if (!out[i]) i];
		for (k in 0...cards.length) piles[seatsIn[k % seatsIn.length]].push(cards[k]);
		for (i in 0...lastChance.length) lastChance[i] = false;
		turn = seatsIn[0];
	}

	public function slap(seat:Int):SlapResult {
		if (out[seat]) throw 'Seat $seat is out';
		if (center.length == 0) return Empty;
		if (jackShowing) {
			var won = [for (c in center) c.card];
			center.resize(0);
			for (c in won) piles[seat].push(c);
			rng.shuffle(piles[seat]);
			// Everyone else who was waiting on this jack is out.
			for (i in 0...piles.length) {
				if (i != seat && lastChance[i] && piles[i].length == 0) out[i] = true;
				lastChance[i] = false;
			}
			if (piles[turn].length == 0) advanceTurn(turn);
			checkWinner();
			return Won(won.length);
		}
		if (piles[seat].length == 0) return NothingToPay;
		var owner = top.seat;
		if (owner == seat) {
			// Slapping your own card: it goes under the center pile instead.
			center.insert(0, {card: piles[seat].shift(), seat: seat});
			return Penalty(seat);
		}
		piles[owner].push(piles[seat].shift());
		if (piles[seat].length == 0) lastChance[seat] = true;
		if (lastChance[owner]) lastChance[owner] = false;
		if (out[owner]) out[owner] = false;
		if (piles[turn].length == 0) advanceTurn(turn);
		return Penalty(owner);
	}

	function advanceTurn(from:Int):Void {
		var n = piles.length;
		for (k in 1...n + 1) {
			var i = (from + k) % n;
			if (!out[i] && piles[i].length > 0) {
				turn = i;
				return;
			}
		}
		// Nobody can flip: the jack must be under the center somewhere; turn stays.
		turn = from;
	}

	/** True when no one can turn a card and no jack is showing: the center goes back to its players. **/
	public var stalled(get, never):Bool;

	function get_stalled():Bool {
		if (jackShowing) return false;
		for (i in 0...piles.length) if (!out[i] && piles[i].length > 0) return false;
		return true;
	}

	function checkWinner():Void {
		var holders = [for (i in 0...piles.length) if (piles[i].length > 0) i];
		if (holders.length == 1 && center.length == 0) {
			winner = holders[0];
			for (i in 0...out.length) if (i != winner) out[i] = true;
		}
	}

	/** Cards held by a seat (its pile). **/
	public function count(seat:Int):Int return piles[seat].length;
}
