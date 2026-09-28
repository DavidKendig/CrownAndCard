// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import cards.Suit;

/**
	Hand-drawn 5×7 letters and 7×7 suit pips for text that must stay crisp on
	the 360p grid: card indices and button prompts (§5.7, §5.10).
**/
class PixelGlyphs {
	public static inline var CHAR_W = 5;
	public static inline var CHAR_H = 7;
	public static inline var SUIT_SIZE = 7;

	static final CHARS:Map<String, Array<String>> = [
		"0" => [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
		"1" => ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
		"2" => [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
		"3" => ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
		"4" => ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
		"5" => ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
		"6" => ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
		"7" => ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
		"8" => [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
		"9" => [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
		"A" => [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
		"B" => ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
		"C" => [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
		"E" => ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
		"J" => ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
		"K" => ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
		"Q" => [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
		"S" => [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
		"s" => [".....", ".....", ".####", "#....", ".###.", "....#", "####."],
		"c" => [".....", ".....", ".###.", "#....", "#....", "#....", ".###."],
		"X" => ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
		"a" => [".....", ".....", ".###.", "....#", ".####", "#...#", ".####"],
		"e" => [".....", ".....", ".###.", "#...#", "#####", "#....", ".###."],
		"p" => [".....", ".....", "####.", "#...#", "####.", "#....", "#...."],
		// Narrow one, so "10" fits a card's index column.
		"|" => [".#.", "##.", ".#.", ".#.", ".#.", ".#.", "###"],
	];

	static final SUITS:Array<Array<String>> = [
		// Clubs, diamonds, hearts, spades (Suit order).
		["..###..", "..###..", "##.#.##", "#######", "##.#.##", "...#...", "..###.."],
		["...#...", "..###..", ".#####.", "#######", ".#####.", "..###..", "...#..."],
		[".##.##.", "#######", "#######", ".#####.", "..###..", "...#...", "......."],
		["...#...", "..###..", ".#####.", "#######", "##.#.##", "...#...", "..###.."],
	];

	/** Width in pixels of `text` with 1px spacing. **/
	public static function width(text:String):Int {
		var w = 0;
		for (i in 0...text.length) {
			var rows = CHARS.get(text.charAt(i));
			w += (rows == null ? CHAR_W : rows[0].length) + 1;
		}
		return w == 0 ? 0 : w - 1;
	}

	/** Paints `text` into `px` at (x, y) in one ARGB color. Unknown characters are skipped. **/
	public static function drawText(px:hxd.Pixels, text:String, x:Int, y:Int, color:Int):Void {
		for (i in 0...text.length) {
			var rows = CHARS.get(text.charAt(i));
			if (rows == null) {
				x += CHAR_W + 1;
				continue;
			}
			paint(px, rows, x, y, color);
			x += rows[0].length + 1;
		}
	}

	/** A 7×7 pip; `flip` turns it upside down, as on the lower half of a card. **/
	public static function drawSuit(px:hxd.Pixels, suit:Suit, x:Int, y:Int, color:Int, flip:Bool = false):Void {
		paint(px, SUITS[(suit : Int)], x, y, color, flip);
	}

	static function paint(px:hxd.Pixels, rows:Array<String>, x:Int, y:Int, color:Int, flip:Bool = false):Void {
		for (r in 0...rows.length) for (c in 0...rows[r].length)
			if (rows[r].charCodeAt(c) == "#".code) {
				var xx = x + c, yy = y + (flip ? rows.length - 1 - r : r);
				if (xx >= 0 && yy >= 0 && xx < px.width && yy < px.height) px.setPixel(xx, yy, color);
			}
	}
}
