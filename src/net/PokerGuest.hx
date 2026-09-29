// SPDX-License-Identifier: AGPL-3.0-or-later
package net;

import games.poker.PokerTable;
import net.NetLink;
import net.NetPoker.*;

/**
	A guest at a multiplayer Hold'em table (§13.13). Shows the host's views,
	sends this player's moves, adds a seed to every shuffle, and replays each
	finished hand from the revealed seeds to check the host dealt it fairly:
	its own cards, the board, the payouts and every house player's move.
**/
class PokerGuest {
	/** The latest view from the host, or null before the first one. **/
	public var view(default, null):Dynamic = null;

	/** The last hand's check: "" (none yet), "ok", or why it failed. **/
	public var audit(default, null) = "";
	public var auditHand(default, null) = 0;

	/** Set when the session ends. **/
	public var closed(default, null):Null<String> = null;

	public var onChange:Void->Void = () -> {};

	final link:NetLink;
	final commitments = new Map<Int, String>();
	final mySeeds = new Map<Int, String>();

	/** Per hand: this player's hole cards as dealt, and the table as the hand ended. **/
	final dealt = new Map<Int, Array<String>>();
	final finalView = new Map<Int, Dynamic>();

	public function new(link:NetLink) {
		this.link = link;
		link.onEvent = onEvent;
	}

	function onEvent(e:NetEvent):Void {
		switch e {
			case Message(from, body):
				if (from == Net.HOST && body != null) handle(body);
			case Closed(reason):
				closed = reason;
				onChange();
			case Roster(_, _):
				// Ask for a seat once connected (and again after a reconnect; the host ignores repeats).
				if (!greeted) {
					greeted = true;
					link.send(Net.HOST, {t: "hello"});
				}
		}
	}

	var greeted = false;

	/** Gets up from the table (the launcher stays in the session). **/
	public function leave():Void link.send(Net.HOST, {t: "leave"});

	function handle(body:Dynamic):Void {
		switch (body.t : String) {
			case "view":
				view = body;
				var hand:Int = body.hand;
				var seats:Array<Dynamic> = body.seats;
				var you:Int = body.you;
				if (you >= 0 && you < seats.length) {
					var mine:Array<String> = seats[you].cards;
					if (mine != null && mine.length > 0 && mine[0] != "" && !dealt.exists(hand)) dealt.set(hand, mine.copy());
				}
				if (body.stage == "over") finalView.set(hand, body);
				onChange();
			case "commit":
				var hand:Int = body.hand;
				if (commitments.exists(hand) || !Fairness.validSeed(body.commit)) return;
				commitments.set(hand, body.commit);
				var seed = Fairness.newSeed();
				mySeeds.set(hand, seed);
				link.send(Net.HOST, {t: "seed", hand: hand, seed: seed});
			case "reveal":
				check(body);
				onChange();
			case "bye":
				closed = "The host left the table.";
				onChange();
			case "full":
				closed = "The table is full (six players).";
				onChange();
			default:
		}
	}

	/** Replays the revealed hand and compares it with what this player was shown. **/
	function check(reveal:Dynamic):Void {
		var hand:Int = reveal.hand;
		auditHand = hand;
		var reason = try verify(reveal, hand) catch (e:Dynamic) Std.string(e);
		audit = reason == null ? "ok" : reason;
		link.send(Net.HOST, {t: "audit", hand: hand, ok: reason == null, reason: reason == null ? "" : reason});
	}

	function verify(reveal:Dynamic, hand:Int):Null<String> {
		var commitment = commitments.get(hand);
		var seat:Int = view == null ? -1 : view.you;
		if (commitment == null) return "The host never committed to a seed for this hand.";
		var seeds:Array<String> = reveal.seeds;
		if (seeds == null || seat < 0 || seeds[seat] != mySeeds.get(hand)) return "My seed was left out of the shuffle.";
		var t = replay(reveal, commitment);
		var cards = dealt.get(hand);
		if (cards != null && codes(t.seats[seat].cards).join(" ") != cards.join(" ")) return "The cards I was dealt aren't the ones the seeds deal.";
		var end:Dynamic = finalView.get(hand);
		if (end == null) return "The host never showed how the hand ended.";
		var board:Array<String> = end.board;
		if (codes(t.board).join(" ") != board.join(" ")) return "The board isn't the one the seeds deal.";
		var shown:Array<Dynamic> = end.seats;
		var kinds:Array<String> = reveal.setup.kinds;
		// Seats dealt into the hand (not anyone who sat down during it).
		for (i in 0...t.seats.length) if (kinds[i] != "open" && !t.seats[i].sittingOut && Std.int(shown[i].stack) != t.seats[i].stack)
			return '${t.seats[i].name}\'s chips don\'t match the replay.';
		return null;
	}

	public function act(action:Action):Void {
		if (view == null) return;
		var body = encodeAction(view.you, action);
		body.t = "act";
		body.hand = view.hand;
		link.send(Net.HOST, body);
	}

	public function rebuy():Void link.send(Net.HOST, {t: "rebuy"});
}
