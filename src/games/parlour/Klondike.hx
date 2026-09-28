// SPDX-License-Identifier: AGPL-3.0-or-later
package games.parlour;

import cards.Card;
import cards.Deck;

/** A place cards can sit. **/
enum Pile {
	Stock;
	Waste;
	Foundation(i:Int);
	Tableau(i:Int);
}

typedef TableauCard = {card:Card, up:Bool};

/**
	Klondike, the standard Solitaire (bicyclecards.com): seven tableau piles
	of 1 to 7 cards with the top card face up; four foundations built up by
	suit from ace to king; the rest is the stock. Tableau piles build down in
	alternating colors, and a run of face-up cards moves as a unit. A space
	takes only a king (or a run headed by one). Face-down cards turn over
	when uncovered. Win by building all 52 onto the foundations.

	Table rules: the stock turns one card at a time, with unlimited passes;
	a foundation's top card may come back down to the tableau.
**/
class Klondike {
	public final tableau:Array<Array<TableauCard>>;
	public final foundations:Array<Array<Card>>;

	/** Face down; the last element is the top. **/
	public final stock:Array<Card>;

	/** Face up; the last element is the top. **/
	public final waste:Array<Card> = [];

	public var moves(default, null) = 0;
	public var passes(default, null) = 0;

	public function new(rng:rng.IRng) {
		var deck = Deck.standard();
		rng.shuffle(deck);
		tableau = [for (_ in 0...7) []];
		foundations = [for (_ in 0...4) []];
		var k = 0;
		for (row in 0...7) for (col in row...7) tableau[col].push({card: deck[k++], up: col == row});
		stock = deck.slice(k);
	}

	/** Turns the next stock card onto the waste, or turns the waste back over when the stock is empty. **/
	public function turnStock():Void {
		if (stock.length > 0) waste.push(stock.pop());
		else if (waste.length > 0) {
			while (waste.length > 0) stock.push(waste.pop());
			passes++;
		} else return;
		moves++;
	}

	public static inline function isRed(c:Card):Bool return c.suit.isRed;

	/** The face-up cards `count` from the top of a pile that would move. **/
	public function cardsAt(from:Pile, count:Int):Array<Card> {
		return switch from {
			case Waste: waste.length > 0 && count == 1 ? [waste[waste.length - 1]] : [];
			case Foundation(i): foundations[i].length > 0 && count == 1 ? [foundations[i][foundations[i].length - 1]] : [];
			case Tableau(i):
				var t = tableau[i];
				if (count < 1 || count > t.length || !t[t.length - count].up) [] else [for (j in t.length - count...t.length) t[j].card];
			case Stock: [];
		}
	}

	/** Face-up cards on top of a tableau pile (the most that can be picked up). **/
	public function runLength(i:Int):Int {
		var t = tableau[i], n = 0;
		var j = t.length - 1;
		while (j >= 0 && t[j].up) {
			n++;
			j--;
		}
		return n;
	}

	public function canMove(from:Pile, count:Int, to:Pile):Bool {
		var cards = cardsAt(from, count);
		if (cards.length == 0 || Type.enumEq(from, to)) return false;
		var lead = cards[0];
		return switch to {
			case Foundation(i):
				if (cards.length != 1) false else {
					var f = foundations[i];
					f.length == 0 ? lead.rank == Card.ACE : (f[f.length - 1].suit == lead.suit && rankOf(lead) == rankOf(f[f.length - 1]) + 1);
				}
			case Tableau(i):
				var t = tableau[i];
				if (t.length == 0) lead.rank == Card.KING else {
					var top = t[t.length - 1];
					top.up && isRed(top.card) != isRed(lead) && rankOf(lead) == rankOf(top.card) - 1;
				}
			default: false;
		}
	}

	/** Aces are low in Solitaire: A, 2 .. K. **/
	public static inline function rankOf(c:Card):Int return c.rank == Card.ACE ? 1 : c.rank;

	public function move(from:Pile, count:Int, to:Pile):Void {
		if (!canMove(from, count, to)) throw 'Illegal move';
		var cards = cardsAt(from, count);
		switch from {
			case Waste: waste.pop();
			case Foundation(i): foundations[i].pop();
			case Tableau(i):
				var t = tableau[i];
				t.splice(t.length - count, count);
				if (t.length > 0) t[t.length - 1].up = true;
			case Stock:
		}
		switch to {
			case Foundation(i): foundations[i].push(cards[0]);
			case Tableau(i): for (c in cards) tableau[i].push({card: c, up: true});
			default:
		}
		moves++;
	}

	/** The foundation a single card could go to, or -1. **/
	public function foundationFor(from:Pile):Int {
		for (i in 0...4) if (canMove(from, 1, Foundation(i))) return i;
		return -1;
	}

	public var won(get, never):Bool;

	function get_won():Bool {
		var n = 0;
		for (f in foundations) n += f.length;
		return n == 52;
	}

	/** True when every card is face up and the stock is spent: the rest can go up automatically. **/
	public var solvable(get, never):Bool;

	function get_solvable():Bool {
		if (stock.length > 0 || waste.length > 0) return false;
		for (t in tableau) for (c in t) if (!c.up) return false;
		return true;
	}

	/** One automatic step toward the foundations (for "finish"). Returns false when nothing moved. **/
	public function autoStep():Bool {
		var sources = [Waste].concat([for (i in 0...7) Tableau(i)]);
		for (s in sources) {
			var f = foundationFor(s);
			if (f >= 0) {
				move(s, 1, Foundation(f));
				return true;
			}
		}
		return false;
	}
}
