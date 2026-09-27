// SPDX-License-Identifier: AGPL-3.0-or-later
package cards;

enum abstract Suit(Int) to Int {
	var Clubs = 0;
	var Diamonds = 1;
	var Hearts = 2;
	var Spades = 3;

	public static final ALL:Array<Suit> = [Clubs, Diamonds, Hearts, Spades];

	public static inline function fromInt(i:Int):Suit {
		return cast i;
	}

	public var isRed(get, never):Bool;

	inline function get_isRed():Bool {
		return abstract == Diamonds || abstract == Hearts;
	}

	/** Display symbol: ♣ ♦ ♥ ♠ **/
	public var symbol(get, never):String;

	function get_symbol():String {
		return switch (abstract) {
			case Clubs: "♣";
			case Diamonds: "♦";
			case Hearts: "♥";
			case Spades: "♠";
		}
	}

	/** Compact ASCII letter used in card codes: c d h s **/
	public var letter(get, never):String;

	function get_letter():String {
		return "cdhs".charAt(this);
	}
}
