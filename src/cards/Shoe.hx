// SPDX-License-Identifier: AGPL-3.0-or-later
package cards;

import rng.IRng;

/**
	A dealing shoe of one or more 52-card decks with a cut card (§6.4).
	The whole order is fixed at shuffle time; dealing only reveals it (§7.7).
**/
class Shoe {
	public final decks:Int;

	/** Fraction of the shoe dealt before the cut card comes out (for example 0.75). **/
	public final penetration:Float;

	final rng:IRng;
	var cards:Array<Card>;
	var pos:Int;
	var cutIndex:Int;

	/** `rng` should be the table's own shuffle stream (§7.3). **/
	public function new(decks:Int, penetration:Float, rng:IRng) {
		if (decks < 1)
			throw 'Shoe needs at least one deck, got $decks';
		if (!(penetration > 0 && penetration <= 1))
			throw 'Shoe penetration must be in (0, 1], got $penetration';
		this.decks = decks;
		this.penetration = penetration;
		this.rng = rng;
		shuffle();
	}

	/** Gathers every card back and shuffles a new shoe. **/
	public function shuffle():Void {
		cards = [];
		for (_ in 0...decks)
			for (c in Deck.standard())
				cards.push(c);
		rng.shuffle(cards);
		pos = 0;
		cutIndex = Std.int(cards.length * penetration);
	}

	public function draw():Card {
		if (pos >= cards.length)
			throw 'Shoe is empty';
		return cards[pos++];
	}

	/** True once the cut card has come out: finish the round, then shuffle. **/
	public var cutCardReached(get, never):Bool;

	inline function get_cutCardReached():Bool {
		return pos >= cutIndex;
	}

	public var size(get, never):Int;

	inline function get_size():Int {
		return cards.length;
	}

	public var dealt(get, never):Int;

	inline function get_dealt():Int {
		return pos;
	}

	public var remaining(get, never):Int;

	inline function get_remaining():Int {
		return cards.length - pos;
	}
}
