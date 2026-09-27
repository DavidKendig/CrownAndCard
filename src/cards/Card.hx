// SPDX-License-Identifier: AGPL-3.0-or-later
package cards;

/**
	A playing card, stored as an index 0–51: `(rank - 2) * 4 + suit`.
	Ranks run 2–14 with the ace high (14); games that treat the ace as low
	handle that in their own rules.
**/
abstract Card(Int) {
	public static inline var COUNT = 52;
	public static inline var JACK = 11;
	public static inline var QUEEN = 12;
	public static inline var KING = 13;
	public static inline var ACE = 14;

	static inline var RANK_CODES = "23456789TJQKA";

	inline function new(index:Int) {
		this = index;
	}

	public static function of(rank:Int, suit:Suit):Card {
		if (rank < 2 || rank > ACE)
			throw 'Card rank must be 2..14, got $rank';
		return new Card((rank - 2) * 4 + (suit : Int));
	}

	public static function fromIndex(index:Int):Card {
		if (index < 0 || index >= COUNT)
			throw 'Card index must be 0..51, got $index';
		return new Card(index);
	}

	/** Parses a code such as `"As"`, `"Td"` or `"10h"`. **/
	public static function parse(code:String):Card {
		var rankPart = code.substr(0, code.length - 1).toUpperCase();
		var suitPart = code.charAt(code.length - 1).toLowerCase();
		if (rankPart == "10")
			rankPart = "T";
		var r = RANK_CODES.indexOf(rankPart);
		var s = "cdhs".indexOf(suitPart);
		if (rankPart.length != 1 || r < 0 || s < 0)
			throw 'Not a card code: "$code"';
		return of(r + 2, Suit.fromInt(s));
	}

	public var index(get, never):Int;

	inline function get_index():Int {
		return this;
	}

	public var rank(get, never):Int;

	inline function get_rank():Int {
		return (this >> 2) + 2;
	}

	public var suit(get, never):Suit;

	inline function get_suit():Suit {
		return Suit.fromInt(this & 3);
	}

	/** Compact ASCII code such as `"As"` or `"Td"`. **/
	public var code(get, never):String;

	function get_code():String {
		return RANK_CODES.charAt(rank - 2) + suit.letter;
	}

	/** Display name such as `"A♠"` or `"10♥"`. **/
	public function toString():String {
		var r = rank == 10 ? "10" : RANK_CODES.charAt(rank - 2);
		return r + suit.symbol;
	}
}
