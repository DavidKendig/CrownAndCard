// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import cards.Card;

/**
	Every play at the tables, the player's and the house players' (§13.12).
	Each game model reports its moves here as they're made: a card played, a
	bid, a bet, a draw, a roll. Main connects `sink` to the game log, so they
	land in the session's log beside everything else.

	- Seat 0 is the player at every house table ("You"); the table says who
	  sits in the other seats (`sitAt`). A model that names its own seats
	  (poker, where multiplayer seats aren't fixed) passes the name to `by`.
	- Only what the table can see: a card drawn from the stock stays hidden
	  (it shows up when it's played), so the live log never gives away a
	  house player's hand.
	- Nothing is recorded until `sink` is connected, so unit tests stay quiet;
	  so does anything run `quietly` (a guest replaying a hand to check it).
**/
class PlayLog {
	/** Where plays go: the table's name and the line. **/
	public static var sink:Null<(table:String, text:String) -> Void> = null;

	static var table = "";
	static var seatNames:Array<String> = [];
	static var muted = 0;

	/** The player sat down at `name`; `seats` names each seat, the player's first. **/
	public static function sitAt(name:String, seats:Array<String>):Void {
		table = name;
		seatNames = seats;
	}

	/** Seat `seat` made a play: `what` reads after the name ("plays Q♥"). **/
	public static function play(seat:Int, what:String):Void
		record('${who(seat)}: $what');

	/** A play by a player the model names itself. **/
	public static function by(name:String, what:String):Void
		record('$name: $what');

	/** Something that isn't one player's choice: a deal, a roll, a result. **/
	public static function note(text:String):Void
		record(text);

	/** Cards as the log writes them: "Q♥ 10♠ A♦". **/
	public static function cards(list:Array<Card>):String
		return [for (c in list) c.toString()].join(" ");

	/** A rank as the log writes it: 2–10, J, Q, K, A. **/
	public static function rank(r:Int):String
		return r >= 2 && r <= 14 ? ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"][r - 2] : Std.string(r);

	public static function who(seat:Int):String
		return seat >= 0 && seat < seatNames.length ? seatNames[seat] : seat == 0 ? "You" : 'Seat $seat';

	/** Runs `f` without recording anything (replaying a hand to verify it isn't playing it). **/
	public static function quietly<T>(f:Void->T):T {
		muted++;
		try {
			var result = f();
			muted--;
			return result;
		} catch (e:Dynamic) {
			muted--;
			throw e;
		}
	}

	static function record(text:String):Void {
		if (sink == null || muted > 0) return;
		try sink(table == "" ? "Table" : table, text) catch (_:Dynamic) {}
	}
}
