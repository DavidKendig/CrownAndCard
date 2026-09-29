// SPDX-License-Identifier: AGPL-3.0-or-later
package net;

import games.poker.PokerAi;
import games.poker.PokerTable;
import net.NetLink;
import net.NetPoker.*;

enum abstract SeatKind(String) to String {
	var Open = "open";
	var Human = "human";
	var House = "house";
}

class HostSeat {
	public var kind:SeatKind = Open;
	public var peer = -1;
	public var name = "";
	public var stack = 0;
	public var style:Null<PokerStyle> = null;

	/** A player who left mid-hand; the seat opens once the hand is over. **/
	public var leaving = false;

	public function new() {}
}

enum abstract Stage(String) to String {
	var Lobby = "lobby";
	var Seeding = "seeding";
	var Playing = "playing";
	var HandOver = "over";
}

/**
	The dealer of a multiplayer Hold'em table (§13.13), run by the host's game.
	Seat 0 is the host. Guests get the next free seat when they connect, and
	may act only for their own seat. Every hand is shuffled from the shared
	seed: the host commits first, the seated guests add their seeds, and the
	seeds and action log are revealed afterwards so guests can replay it.
**/
class PokerHost {
	/** How long seated guests have to send their seed before the deal goes ahead without it. **/
	public static inline var SEED_SECONDS = 8.0;

	/** How long a guest has to act before they check (or fold). **/
	public static inline var TURN_SECONDS = 45.0;

	public static inline var HOUSE_SECONDS = 0.9;

	static final HOUSE_NAMES = ["Deacon Crane", "Colonel Blythe", "Valentine Crake", "Tuppence Fitch", "Sir Reggie"];
	static final HOUSE_STYLES:Array<PokerStyle> = [
		{looseness: .3, aggression: .35}, {looseness: .7, aggression: .7}, {looseness: .5, aggression: .8},
		{looseness: .5, aggression: .7}, {looseness: .9, aggression: .2}
	];

	public final seats:Array<HostSeat> = [for (_ in 0...SEATS) new HostSeat()];
	public var stage(default, null):Stage = Lobby;
	public var table(default, null):Null<PokerTable>;
	public var hand(default, null) = 0;

	/** The latest thing that happened, for everyone's status line. **/
	public var note(default, null) = "Waiting for players.";

	/** Guests' replay checks of the last hand: seat → "ok" or the reason it failed. **/
	public final checks = new Map<Int, String>();

	/** Called whenever something visible changed. **/
	public var onChange:Void->Void = () -> {};

	final link:NetLink;
	var button = -1;
	var hostSeed = "";
	final guestSeeds = new Map<Int, String>();
	var setup:Dynamic = null;
	var actions:Array<Dynamic> = [];
	var houseRng:Null<rng.IRng>;
	var wait = 0.0;
	var decisionKey = "";

	public function new(link:NetLink, hostName:String) {
		this.link = link;
		var me = seats[0];
		me.kind = Human;
		me.peer = Net.HOST;
		me.name = cleanName(hostName, "Host");
		me.stack = STACK;
		link.onEvent = onEvent;
	}

	// --- Seats and the lobby ---------------------------------------------

	function onEvent(e:NetEvent):Void {
		switch e {
			case Roster(_, peers):
				syncPeers(peers);
			case Message(from, body):
				if (body != null) handle(from, body);
			case Closed(_):
		}
	}

	/** Names by peer id, from the launcher's roster. **/
	final names = new Map<Int, String>();

	/** A guest disconnected: their seat is freed (folding them if they're in a hand). **/
	function syncPeers(peers:Array<Peer>):Void {
		names.clear();
		for (p in peers) names.set(p.id, p.name);
		if (names.exists(Net.HOST)) seats[0].name = cleanName(names.get(Net.HOST), "Host");
		for (i in 1...SEATS) {
			var s = seats[i];
			if (s.kind == Human && s.peer >= 0 && !names.exists(s.peer)) playerLeft(i);
		}
		afterSeating();
	}

	/** A guest's game opened the table: give them the next free seat. **/
	function seatPeer(peer:Int):Void {
		if (seatOf(peer) >= 0 || !names.exists(peer)) {
			if (seatOf(peer) >= 0) link.send(peer, viewFor(seatOf(peer)));
			return;
		}
		var free = firstSeat(s -> s.kind == Open && !s.leaving);
		if (free < 0) {
			// Take a house player's chair if the table is full of them.
			free = firstSeat(s -> s.kind == House && !inHand(s));
			if (free < 0) {
				link.send(peer, {t: "full"});
				return;
			}
		}
		var s = seats[free];
		s.kind = Human;
		s.peer = peer;
		s.name = cleanName(names.get(peer), 'Guest $peer');
		s.stack = STACK;
		s.style = null;
		s.leaving = false;
		note = '${s.name} sits down.';
		afterSeating();
	}

	function afterSeating():Void {
		// Someone who left while the seeds were coming in no longer holds up the deal.
		if (stage == Seeding && seedsIn()) start();
		else broadcast();
	}

	/** Tells the guests this table is closing (the host left it). **/
	public function close():Void {
		for (i in 1...SEATS) if (seats[i].kind == Human && seats[i].peer >= 0) link.send(seats[i].peer, {t: "bye"});
	}

	function playerLeft(i:Int):Void {
		var s = seats[i];
		note = '${s.name} leaves the table.';
		if (inHand(s) && table != null && (stage == Playing)) {
			actions.push({seat: i, a: "forfeit"});
			table.forfeit(i);
			s.leaving = true;
			s.peer = -1;
			afterMove();
			return;
		}
		if (stage == Seeding) guestSeeds.remove(i);
		clear(s);
	}

	function clear(s:HostSeat):Void {
		s.kind = Open;
		s.peer = -1;
		s.name = "";
		s.stack = 0;
		s.style = null;
		s.leaving = false;
	}

	function inHand(s:HostSeat):Bool {
		if (table == null || !(stage == Playing || stage == Seeding)) return false;
		var i = seats.indexOf(s);
		return stage == Seeding || (table.seats[i].live);
	}

	function firstSeat(ok:HostSeat->Bool):Int {
		for (i in 1...SEATS) if (ok(seats[i])) return i;
		return -1;
	}

	function seatOf(peer:Int):Int {
		for (i in 0...SEATS) if (seats[i].kind == Human && seats[i].peer == peer) return i;
		return -1;
	}

	public function canChangeSeats():Bool return stage == Lobby || stage == HandOver;

	public function addHouse():Void {
		if (!canChangeSeats()) return;
		var i = firstSeat(s -> s.kind == Open);
		if (i < 0) return;
		var used = [for (s in seats) if (s.kind == House) s.name];
		var k = 0;
		while (k < HOUSE_NAMES.length - 1 && used.indexOf(HOUSE_NAMES[k]) >= 0) k++;
		var s = seats[i];
		s.kind = House;
		s.name = HOUSE_NAMES[k];
		s.style = HOUSE_STYLES[k];
		s.stack = STACK;
		note = '${s.name} takes a seat for the house.';
		broadcast();
	}

	public function removeHouse():Void {
		if (!canChangeSeats()) return;
		var i = SEATS - 1;
		while (i > 0 && seats[i].kind != House) i--;
		if (i <= 0) return;
		note = '${seats[i].name} leaves the table.';
		clear(seats[i]);
		broadcast();
	}

	public function houseCount():Int return [for (s in seats) if (s.kind == House) s].length;

	public function openCount():Int return [for (s in seats) if (s.kind == Open) s].length;

	/** Two players with chips (the host counts, house players count). **/
	public function canDeal():Bool {
		if (!canChangeSeats()) return false;
		var n = 0;
		for (s in seats) if (s.kind != Open && (s.stack > 0 || s.kind == House)) n++;
		return n >= 2;
	}

	/** A busted seat takes a fresh session stack before the next deal. **/
	public function rebuy(seat:Int):Void {
		var s = seats[seat];
		if (!canChangeSeats() || s.kind != Human || s.stack > 0) return;
		s.stack = STACK;
		note = '${s.name} buys back in.';
		broadcast();
	}

	// --- Dealing ------------------------------------------------------------

	/** Starts the next hand: commit to a seed and ask the seated guests for theirs. **/
	public function deal():Void {
		if (!canDeal()) return;
		for (s in seats) {
			if (s.leaving) clear(s);
			if (s.kind == House && s.stack <= 0) s.stack = STACK;
		}
		if (!canDeal()) return;
		hand++;
		hostSeed = Fairness.newSeed();
		guestSeeds.clear();
		checks.clear();
		stage = Seeding;
		wait = 0;
		note = "Shuffling: every player adds to the seed.";
		for (i in 1...SEATS) if (seats[i].kind == Human && seats[i].stack > 0)
			link.send(seats[i].peer, {t: "commit", hand: hand, commit: Fairness.commit(hostSeed)});
		if (seedsIn()) start();
		else broadcast();
	}

	function seedsIn():Bool {
		for (i in 1...SEATS) if (seats[i].kind == Human && seats[i].stack > 0 && !guestSeeds.exists(i)) return false;
		return true;
	}

	function start():Void {
		var seeds = [for (i in 0...SEATS) guestSeeds.exists(i) ? guestSeeds.get(i) : ""];
		var seed = Fairness.handSeed(hostSeed, seeds);
		var names = [for (s in seats) s.kind == Open ? "" : s.name];
		var stacks = [for (s in seats) s.kind == Open ? 0 : s.stack];
		setup = {
			hand: hand,
			names: names,
			kinds: [for (s in seats) (s.kind : String)],
			styles: [for (s in seats) s.style],
			stacks: stacks,
			button: button,
		};
		table = new PokerTable(Holdem, names, stacks, SMALL_BLIND, BIG_BLIND, 0);
		table.setButton(button);
		table.startHand(Fairness.shuffleRng(seed));
		button = table.button;
		houseRng = Fairness.houseRng(seed);
		actions = [];
		guestSeedsForReveal = seeds;
		stage = Playing;
		wait = 0;
		note = 'Hand $hand.';
		afterMove();
	}

	var guestSeedsForReveal:Array<String> = [];

	// --- Play ---------------------------------------------------------------

	function handle(from:Int, body:Dynamic):Void {
		if (body.t == "hello" && from != Net.HOST) {
			seatPeer(from);
			return;
		}
		var seat = seatOf(from);
		if (seat <= 0) return;
		switch (body.t : String) {
			case "leave":
				playerLeft(seat);
				afterSeating();
			case "seed":
				if (stage == Seeding && body.hand == hand && Fairness.validSeed(body.seed) && !guestSeeds.exists(seat)) {
					guestSeeds.set(seat, body.seed);
					if (seedsIn()) start();
				}
			case "act":
				if (stage == Playing && body.hand == hand && table != null && table.toAct == seat) {
					var action = decodeAction(body);
					if (action != null) apply(seat, action);
				}
			case "rebuy":
				rebuy(seat);
			case "audit":
				if (body.hand == hand) {
					checks.set(seat, body.ok == true ? "ok" : Std.string(body.reason));
					if (body.ok != true) note = '${seats[seat].name}\'s check of hand $hand FAILED: ${body.reason}';
					broadcast();
				}
			default:
		}
	}

	/** The host's own move at the table. **/
	public function act(action:Action):Void {
		if (stage == Playing && table != null && table.toAct == 0) apply(0, action);
	}

	function apply(seat:Int, action:Action):Void {
		var t = table;
		var s = t.seats[seat];
		var before = t.currentBet, call = t.legal(seat).toCall;
		try t.act(seat, action) catch (_:Dynamic) return; // an illegal move is ignored; the seat still has to act
		actions.push(encodeAction(seat, action));
		note = switch action {
			case Fold: '${s.name} folds.';
			case Check: '${s.name} checks.';
			case Call: '${s.name} calls $call.';
			case RaiseTo(n): before == 0 ? '${s.name} bets $n.' : '${s.name} raises to $n.';
		}
		if (s.allIn) note = '${s.name} is all in!';
		wait = 0;
		afterMove();
	}

	function afterMove():Void {
		if (table != null && table.phase == Phase.HandOver) finish();
		broadcast();
	}

	function finish():Void {
		stage = HandOver;
		// Only the players dealt into this hand take their stacks from it (not anyone who sat down mid-hand).
		var names:Array<String> = setup.names, kinds:Array<String> = setup.kinds;
		for (i in 0...SEATS) {
			var s = seats[i];
			if (s.kind != Open && (s.kind : String) == kinds[i] && s.name == names[i]) s.stack = table.seats[i].stack;
		}
		var lines = [for (r in table.results) '${table.seats[r.seat].name} wins ${r.amount}' + (r.hand == "" ? "" : ' with ${r.hand.toLowerCase()}')];
		note = lines.join(". ") + ".";
		var reveal = {t: "reveal", hand: hand, hostSeed: hostSeed, seeds: guestSeedsForReveal, setup: setup, actions: actions};
		// Views first, so each guest has the final table before it checks the hand.
		broadcast();
		for (i in 1...SEATS) if (seats[i].kind == Human && seats[i].peer >= 0) link.send(seats[i].peer, reveal);
		for (s in seats) if (s.leaving) clear(s);
	}

	/** Call every frame: house players' turns and the timers. **/
	public function update(dt:Float):Void {
		switch stage {
			case Seeding:
				wait += dt;
				if (wait >= SEED_SECONDS) {
					note = "A guest's seed didn't arrive; dealing without it.";
					start();
				}
			case Playing:
				var t = table;
				if (t.phase != Betting) return;
				var s = seats[t.toAct];
				wait += dt;
				if (s.kind == House && wait >= HOUSE_SECONDS) {
					var seat = t.toAct;
					apply(seat, PokerAi.decide(t, seat, houseRng, s.style));
				} else if (s.kind == Human && t.toAct != 0 && wait >= TURN_SECONDS) {
					var seat = t.toAct;
					note = '${s.name} ran out of time.';
					apply(seat, t.legal(seat).canCheck ? Check : Fold);
				}
			default:
		}
	}

	// --- Views --------------------------------------------------------------

	function broadcast():Void {
		for (i in 1...SEATS) if (seats[i].kind == Human && seats[i].peer >= 0) link.send(seats[i].peer, viewFor(i));
		onChange();
	}

	/** The table as the player in `seat` may see it. **/
	public function viewFor(seat:Int):Dynamic {
		var t = table;
		var live = t != null && (stage == Playing || stage == HandOver);
		var showAll = live && stage == HandOver && t.showdown;
		var seatViews = [];
		for (i in 0...SEATS) {
			var s = seats[i];
			var ts = live ? t.seats[i] : null;
			var cards = [];
			if (ts != null && !ts.sittingOut && s.kind != Open) {
				var visible = i == seat || (showAll && ts.live);
				cards = visible ? codes(ts.cards) : [for (_ in ts.cards) ""];
			}
			seatViews.push({
				name: s.name,
				kind: (s.kind : String),
				stack: ts != null && !ts.sittingOut && s.kind != Open ? ts.stack : s.stack,
				bet: ts != null ? ts.bet : 0,
				total: ts != null ? ts.total : 0,
				folded: ts != null && ts.folded,
				allIn: ts != null && ts.allIn,
				out: ts == null || ts.sittingOut,
				cards: cards,
			});
		}
		var myTurn = live && stage == Playing && t.phase == Betting && t.toAct == seat;
		return {
			t: "view",
			stage: (stage : String),
			hand: hand,
			you: seat,
			button: live ? t.button : button,
			toAct: live && stage == Playing ? t.toAct : -1,
			street: live ? t.street : 0,
			pot: live ? t.pot : 0,
			currentBet: live ? t.currentBet : 0,
			board: live ? codes(t.board) : [],
			seats: seatViews,
			legal: myTurn ? t.legal(seat) : null,
			results: live && stage == HandOver ? t.results : [],
			showdown: live && stage == HandOver && t.showdown,
			note: note,
			checks: [for (k => v in checks) {seat: k, result: v}],
		};
	}

	static function cleanName(name:Null<String>, fallback:String):String {
		var n = name == null ? "" : StringTools.trim(name);
		if (n.length > 20) n = n.substr(0, 20);
		return n == "" ? fallback : n;
	}
}
