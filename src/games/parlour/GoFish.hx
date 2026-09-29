// SPDX-License-Identifier: AGPL-3.0-or-later
package games.parlour;

import games.PlayLog;
import cards.Card;
import cards.Deck;

/** What happened on one ask, for the table to narrate. **/
typedef AskResult = {
	var asker:Int;
	var target:Int;
	var rank:Int;

	/** Cards handed over by the target (0 means "Go fish!"). **/
	var got:Int;

	/** The card drawn from the stock after "Go fish!", if any. **/
	var fished:Null<Card>;

	/** The asker keeps the turn. **/
	var again:Bool;

	/** Ranks completed as books by this ask. **/
	var books:Array<Int>;
}

/**
	Go Fish (bicyclecards.com): 7 cards each for two or three players, 5 for
	four or more; the rest is the stock. On your turn ask any opponent for a
	rank you hold; they hand over all of that rank and you ask again. If they
	have none, "Go fish!": draw from the stock. Drawing the rank you asked for
	also keeps the turn. Four of a rank make a book, laid down at once. A
	player without cards draws one from the stock on their turn; with the
	stock empty, they're out. Most books when all 13 are made wins.
**/
class GoFish {
	public final hands:Array<Array<Card>>;
	public final books:Array<Array<Int>>;
	public final stock:Array<Card>;
	public var turn(default, null) = 0;
	public var over(default, null) = false;

	public function new(players:Int, rng:rng.IRng) {
		if (players < 2 || players > 6) throw 'Go Fish needs 2 to 6 players';
		hands = [for (_ in 0...players) []];
		books = [for (_ in 0...players) []];
		var deck = Deck.standard();
		rng.shuffle(deck);
		var each = players <= 3 ? 7 : 5;
		for (k in 0...each) for (p in 0...players) hands[p].push(deck[k * players + p]);
		stock = deck.slice(each * players);
		for (p in 0...players) layBooks(p);
		sortHands();
	}

	/** Test hook: explicit hands and stock (stock top first). **/
	public static function fromDeal(hands:Array<Array<Card>>, stock:Array<Card>, rng:rng.IRng):GoFish {
		var g = new GoFish(hands.length, rng);
		for (p in 0...hands.length) {
			g.hands[p].resize(0);
			for (c in hands[p]) g.hands[p].push(c);
			g.books[p].resize(0);
		}
		g.stock.resize(0);
		for (c in stock) g.stock.push(c);
		g.sortHands();
		return g;
	}

	public function ranksHeld(seat:Int):Array<Int> {
		var out = [];
		for (c in hands[seat]) if (out.indexOf(c.rank) < 0) out.push(c.rank);
		return out;
	}

	/** True once a player has no cards and can't draw: they sit out the rest. **/
	public function isOut(seat:Int):Bool return hands[seat].length == 0 && stock.length == 0;

	/** A player without cards draws one to start their turn. Returns false if they're out. **/
	public function refillIfEmpty(seat:Int):Bool {
		if (hands[seat].length > 0) return true;
		if (stock.length == 0) return false;
		hands[seat].push(stock.shift());
		return true;
	}

	public function ask(asker:Int, target:Int, rank:Int):AskResult {
		if (over) throw 'The game is over';
		if (asker != turn) throw 'Not seat $asker\'s turn';
		if (target == asker || target < 0 || target >= hands.length) throw 'Bad target $target';
		if (ranksHeld(asker).indexOf(rank) < 0) throw 'Seat $asker must hold a $rank to ask for it';
		var given = [for (c in hands[target]) if (c.rank == rank) c];
		var result:AskResult = {asker: asker, target: target, rank: rank, got: given.length, fished: null, again: false, books: []};
		if (given.length > 0) {
			for (c in given) {
				hands[target].remove(c);
				hands[asker].push(c);
			}
			result.again = true;
		} else if (stock.length > 0) {
			var card = stock.shift();
			hands[asker].push(card);
			result.fished = card;
			result.again = card.rank == rank;
		}
		// A fished card stays face down unless it's the rank asked for (then it's shown).
		var asked = 'asks ${PlayLog.who(target)} for ${PlayLog.rank(rank)}s: ';
		PlayLog.play(asker, asked + (given.length > 0 ? 'gets ${given.length}'
			: result.fished == null ? "go fish, but the pond is empty" : result.again ? "go fish, and fishes one up" : "go fish"));
		result.books = layBooks(asker);
		for (b in result.books) PlayLog.play(asker, 'lays down a book of ${PlayLog.rank(b)}s');
		sortHands();
		if (bookCount() == 13) over = true;
		else if (!result.again || !refillIfEmpty(asker)) nextTurn();
		return result;
	}

	/** Passes the turn to the next player who can still play, drawing for an empty hand. **/
	public function nextTurn():Void {
		for (k in 1...hands.length + 1) {
			var i = (turn + k) % hands.length;
			if (refillIfEmpty(i)) {
				turn = i;
				return;
			}
		}
		over = true;
	}

	function layBooks(seat:Int):Array<Int> {
		var made = [];
		for (rank in ranksHeld(seat)) {
			var of = [for (c in hands[seat]) if (c.rank == rank) c];
			if (of.length == 4) {
				for (c in of) hands[seat].remove(c);
				books[seat].push(rank);
				made.push(rank);
			}
		}
		return made;
	}

	function sortHands():Void {
		for (h in hands) h.sort((a, b) -> a.rank != b.rank ? a.rank - b.rank : a.index - b.index);
	}

	public function bookCount():Int {
		var n = 0;
		for (b in books) n += b.length;
		return n;
	}

	/** Seats with the most books (more than one on a tie). **/
	public function leaders():Array<Int> {
		var best = 0;
		for (b in books) if (b.length > best) best = b.length;
		return [for (i in 0...books.length) if (books[i].length == best) i];
	}
}
