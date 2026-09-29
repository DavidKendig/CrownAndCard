// SPDX-License-Identifier: AGPL-3.0-or-later
package net;

import cards.Card;
import games.poker.PokerAi;
import games.poker.PokerTable;

/**
	The multiplayer Hold'em protocol (§13.13), shared by the host and guests.

	Host → guest:  `view` (the table as that guest may see it), `commit` (the
	host's seed hash before a hand), `reveal` (the seeds and the action log
	after it). Guest → host: `seed`, `act`, `rebuy`, `audit`.
**/
class NetPoker {
	public static inline var SEATS = 6;
	public static inline var STACK = 1000;
	public static inline var SMALL_BLIND = 5;
	public static inline var BIG_BLIND = 10;

	public static function encodeAction(seat:Int, a:Action):Dynamic {
		return switch a {
			case Fold: {seat: seat, a: "fold"};
			case Check: {seat: seat, a: "check"};
			case Call: {seat: seat, a: "call"};
			case RaiseTo(n): {seat: seat, a: "raise", n: n};
		}
	}

	/** Null for anything that isn't a well-formed action. **/
	public static function decodeAction(d:Dynamic):Null<Action> {
		if (d == null) return null;
		return switch (d.a : String) {
			case "fold": Fold;
			case "check": Check;
			case "call": Call;
			case "raise": (d.n is Int) ? RaiseTo(d.n) : null;
			default: null;
		}
	}

	public static function sameAction(a:Action, b:Action):Bool {
		return switch [a, b] {
			case [Fold, Fold], [Check, Check], [Call, Call]: true;
			case [RaiseTo(x), RaiseTo(y)]: x == y;
			default: false;
		}
	}

	public static function codes(cards:Array<Card>):Array<String> return [for (c in cards) c.code];

	/**
		Replays a revealed hand (§13.13 fair dealing): checks the host's seed
		against its commitment, reshuffles from the shared seed, reapplies every
		action (house players' moves must be exactly what the house AI would
		play) and returns the table as it should have ended. Throws a readable
		reason if anything doesn't hold.
	**/
	public static function replay(reveal:Dynamic, commitment:String):PokerTable
		// A check of a hand already played: it mustn't show up in the play log a second time.
		return games.PlayLog.quietly(() -> replayHand(reveal, commitment));

	static function replayHand(reveal:Dynamic, commitment:String):PokerTable {
		var hostSeed:String = reveal.hostSeed;
		if (!Fairness.validSeed(hostSeed) || Fairness.commit(hostSeed) != commitment)
			throw "The host's seed doesn't match the commitment it made before the deal.";
		var setup:Dynamic = reveal.setup;
		var names:Array<String> = setup.names, kinds:Array<String> = setup.kinds, stacks:Array<Int> = setup.stacks;
		var styles:Array<Dynamic> = setup.styles, seeds:Array<String> = reveal.seeds;
		if (names == null || kinds == null || stacks == null || styles == null || seeds == null || names.length != SEATS)
			throw "The host's record of the hand is incomplete.";
		var seed = Fairness.handSeed(hostSeed, seeds);
		var t = new PokerTable(Holdem, names, stacks, SMALL_BLIND, BIG_BLIND, 0);
		t.setButton(setup.button);
		t.startHand(Fairness.shuffleRng(seed));
		var house = Fairness.houseRng(seed);
		var actions:Array<Dynamic> = reveal.actions;
		for (d in actions) {
			var seat:Int = d.seat;
			if (d.a == "forfeit") {
				t.forfeit(seat);
				continue;
			}
			var action = decodeAction(d);
			if (action == null || t.phase != Betting || t.toAct != seat) throw 'Seat ${seat + 1} acted out of turn.';
			if (kinds[seat] == "house") {
				var expected = PokerAi.decide(t, seat, house, styles[seat]);
				if (!sameAction(expected, action)) throw '${names[seat]} (a house player) didn\'t play the house AI\'s move.';
			}
			try t.act(seat, action) catch (e:Dynamic) throw '${names[seat]} made an illegal move: $e';
		}
		if (t.phase != HandOver) throw "The recorded actions don't finish the hand.";
		return t;
	}
}
