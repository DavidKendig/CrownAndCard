// SPDX-License-Identifier: AGPL-3.0-or-later
package games.mahjong;

/**
	Mahjong tile kinds as integers:
	0-8 characters 1-9, 9-17 dots 1-9, 18-26 bamboo 1-9,
	27-30 winds (east, south, west, north), 31-33 dragons (white, green, red),
	34-37 flowers (plum, orchid, chrysanthemum, bamboo), 38-41 seasons (spring, summer, autumn, winter).
	Four copies of each of the 34 playing kinds; one of each bonus tile.
**/
class Tiles {
	public static inline var KINDS = 34;
	public static inline var EAST = 27;
	public static inline var SOUTH = 28;
	public static inline var WEST = 29;
	public static inline var NORTH = 30;
	public static inline var WHITE = 31;
	public static inline var GREEN = 32;
	public static inline var RED = 33;
	public static inline var FIRST_BONUS = 34;
	public static inline var LAST_BONUS = 41;

	static final SUIT_ART = ["characters", "dots", "bamboo"];
	static final SUIT_NAMES = ["characters", "dots", "bamboo"];
	static final HONOR_ART = ["east", "south", "west", "north", "white", "green", "red"];
	static final HONOR_NAMES = ["East wind", "South wind", "West wind", "North wind", "White dragon", "Green dragon", "Red dragon"];
	static final BONUS_ART = ["plum", "orchid", "chrysanthemum", "bamboo-flower", "spring", "summer", "autumn", "winter"];
	static final BONUS_NAMES = ["Plum", "Orchid", "Chrysanthemum", "Bamboo", "Spring", "Summer", "Autumn", "Winter"];

	public static inline function isSuited(k:Int):Bool return k < 27;

	public static inline function suit(k:Int):Int return Std.int(k / 9);

	/** 1-9 for suited tiles. **/
	public static inline function rank(k:Int):Int return k % 9 + 1;

	public static inline function isHonor(k:Int):Bool return k >= 27 && k < KINDS;

	public static inline function isWind(k:Int):Bool return k >= EAST && k <= NORTH;

	public static inline function isDragon(k:Int):Bool return k >= WHITE && k <= RED;

	public static inline function isBonus(k:Int):Bool return k >= FIRST_BONUS;

	public static inline function isTerminal(k:Int):Bool return isSuited(k) && (rank(k) == 1 || rank(k) == 9);

	public static inline function isTerminalOrHonor(k:Int):Bool return isHonor(k) || isTerminal(k);

	public static inline function isSimple(k:Int):Bool return isSuited(k) && !isTerminal(k);

	/** The art file id in res/mahjong/manifest.json. **/
	public static function art(k:Int):String {
		if (isSuited(k)) return SUIT_ART[suit(k)] + "-" + rank(k);
		if (isHonor(k)) return HONOR_ART[k - 27];
		return BONUS_ART[k - FIRST_BONUS];
	}

	public static function name(k:Int):String {
		if (isSuited(k)) return rank(k) + " " + SUIT_NAMES[suit(k)];
		if (isHonor(k)) return HONOR_NAMES[k - 27];
		return BONUS_NAMES[k - FIRST_BONUS];
	}

	/** A shuffled wall: four of every playing tile, plus the eight bonus tiles when `bonus`. **/
	public static function wall(bonus:Bool, rng:rng.IRng):Array<Int> {
		var out = [];
		for (k in 0...KINDS) for (_ in 0...4) out.push(k);
		if (bonus) for (k in FIRST_BONUS...LAST_BONUS + 1) out.push(k);
		rng.shuffle(out);
		return out;
	}

	/** The dora a Riichi indicator points to: the next tile in its suit, wind or dragon cycle. **/
	public static function doraFrom(indicator:Int):Int {
		if (isSuited(indicator)) return suit(indicator) * 9 + (rank(indicator) % 9);
		if (isWind(indicator)) return EAST + ((indicator - EAST + 1) % 4);
		return WHITE + ((indicator - WHITE + 1) % 3);
	}

	/** The seat's flower and season in Classic play (seat wind 0 = east). **/
	public static function ownBonus(k:Int, seatWind:Int):Bool {
		return isBonus(k) && (k - FIRST_BONUS) % 4 == seatWind;
	}

	public static function sort(tiles:Array<Int>):Void tiles.sort((a, b) -> a - b);

	public static function counts(tiles:Array<Int>):Array<Int> {
		var c = [for (_ in 0...KINDS) 0];
		for (t in tiles) if (t < KINDS) c[t]++;
		return c;
	}
}
