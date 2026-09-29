// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import cards.Card;
import games.poker.HandEval;
import games.poker.PokerTable;
import net.NetLink;
import net.PokerGuest;
import net.PokerHost;
import ui.ButtonGlyph;
import ui.TableKit;

/**
	The multiplayer Hold'em table (§13.13), for the host and guests alike. It
	draws whatever view this player has (the host builds its own, guests get
	theirs from the host) with the player at the bottom and up to five others
	around the felt. The host also runs the lobby: dealing and house players.
**/
class NetPokerUI extends CardGameScreen {
	/** Seat spots by position relative to you: 0 you (bottom), then clockwise. **/
	static final SPOTS = [
		{x: 0.5, y: 212, align: 1},
		{x: 0.0, y: 190, align: 0},
		{x: 0.0, y: 62, align: 0},
		{x: 0.5, y: 18, align: 1},
		{x: 1.0, y: 62, align: 2},
		{x: 1.0, y: 190, align: 2},
	];

	final host:Null<PokerHost>;
	final guest:Null<PokerGuest>;

	/** The code guests join with, shown to the host in the lobby. **/
	public var joinCode = "";
	var raiseIndex = 0;
	var decisionKey = "";

	final link:NetLink;
	#if js
	final onPageHide:js.html.Event->Void;
	var timer:Null<Int> = null;
	#end

	public function new(parent:h2d.Object, faces:CardFaces, link:NetLink, isHost:Bool, hostName:String) {
		super(parent, faces, "holdem");
		this.link = link;
		if (isHost) {
			host = new PokerHost(link, hostName);
			guest = null;
		} else {
			guest = new PokerGuest(link);
			host = null;
		}
		#if js
		// Closing the window gets up from the table (and a host's closes it for everyone).
		onPageHide = _ -> goodbye();
		js.Browser.window.addEventListener("pagehide", onPageHide);
		// Browsers stop drawing hidden, minimized or covered windows, but the host's
		// table has to keep dealing for everyone: a timer runs it whenever frames stop.
		if (host != null) timer = js.Browser.window.setInterval(() -> if (haxe.Timer.stamp() - lastRun > .4) runHost(), 500);
		#end
	}

	/** Gets up (telling the others), stops listening, and removes the screen. **/
	public function dispose():Void {
		goodbye();
		link.close();
		#if js
		js.Browser.window.removeEventListener("pagehide", onPageHide);
		if (timer != null) js.Browser.window.clearInterval(timer);
		timer = null;
		#end
		remove();
	}

	var lastRun = -1.0;

	/** Advances the host's table by the time since it last ran. **/
	function runHost():Void {
		var now = haxe.Timer.stamp();
		var dt = lastRun < 0 ? 0 : Math.min(5, now - lastRun);
		lastRun = now;
		host.update(dt);
	}

	var saidGoodbye = false;

	function goodbye():Void {
		if (saidGoodbye) return;
		saidGoodbye = true;
		if (host != null) host.close() else guest.leave();
	}

	function view():Dynamic return host != null ? host.viewFor(0) : guest.view;

	override public function status():String {
		var v = view();
		return v == null ? "multiplayer: connecting" : 'multiplayer ${host != null ? "host" : "guest"} hand ${v.hand} ${v.stage}';
	}

	override public function update(w:Int, dt:Float, input:MenuInput):Void {
		if (host != null) runHost();
		var cx = w / 2;
		begin(w);
		var v = view();
		if (guest != null && guest.closed != null) {
			title = "THE TABLE IS CLOSED";
			body = guest.closed;
			if (offer(["Leave table"], input) != null || input.back) leave();
			end(cx);
			return;
		}
		if (v == null) {
			label("Joining the table…", cx, 150, TableKit.GOLD, 1);
			if (input.back) leave();
			end(cx);
			return;
		}
		drawTable(w, cx, v);
		var stage:String = v.stage;
		var me:Dynamic = v.seats[v.you];
		if (leaveCheck(input, stage == "playing" && !me.folded && !me.out, "You'll fold this hand and leave the table.")) {
			end(cx);
			return;
		}
		switch stage {
			case "lobby":
				lobby(cx, v, input);
			case "seeding":
				label("Shuffling: every player adds to the seed.", cx, 184, TableKit.GOLD, 1);
			case "playing":
				if (v.legal != null) myTurn(cx, v, input);
				else {
					var up:Dynamic = v.toAct >= 0 ? v.seats[v.toAct] : null;
					label(v.note, cx, 184, TableKit.GOLD, 1);
					if (up != null) hint(null, 'Waiting for ${up.name}');
				}
			case "over":
				handOver(cx, v, input);
		}
		end(cx);
	}

	// --- Panels -----------------------------------------------------------

	function lobby(cx:Float, v:Dynamic, input:MenuInput):Void {
		title = "MULTIPLAYER HOLD'EM";
		var seated = [for (s in (v.seats : Array<Dynamic>)) if (s.kind != "open") s.name + (s.kind == "house" ? " (house)" : "")];
		body = 'At the table: ${seated.join(", ")}.\nBlinds ${net.NetPoker.SMALL_BLIND}/${net.NetPoker.BIG_BLIND}, 1,000 chips each.';
		if (host == null) {
			body += '\n\nWaiting for ${(v.seats[0] : Dynamic).name} to deal.';
			if (offer(["Leave table"], input) == "Leave table") leave();
			return;
		}
		body += joinCode == "" ? "\n\nDeal when everyone's seated." : '\n\nJoin code:  $joinCode\nShare it with your friends, then deal when everyone\'s seated.';
		hostChoices(input, host.canDeal() ? "Deal" : null);
	}

	function handOver(cx:Float, v:Dynamic, input:MenuInput):Void {
		var results:Array<Dynamic> = v.results;
		title = results.length > 0 && results[0].seat == v.you ? "YOU WIN THE POT" : 'HAND ${v.hand}';
		var lines = [];
		for (r in results) {
			var who = r.seat == v.you ? "You" : (v.seats[r.seat] : Dynamic).name;
			var hand:String = r.hand;
			lines.push('$who ${r.seat == v.you ? "win" : "wins"} ${r.amount}' + (hand == "" ? "." : ' with ${hand.charAt(0).toLowerCase() + hand.substr(1)}.'));
		}
		lines.push(fairness(v));
		body = lines.join("\n");
		var me:Dynamic = v.seats[v.you];
		var broke = me.stack <= 0;
		if (host == null) {
			var opts = broke ? ["Buy back in", "Leave table"] : ["Leave table"];
			var p = offer(opts, input);
			hint(null, 'Waiting for ${(v.seats[0] : Dynamic).name} to deal');
			if (p == "Buy back in") guest.rebuy();
			else if (p == "Leave table") leave();
			return;
		}
		if (broke) host.rebuy(0);
		hostChoices(input, host.canDeal() ? "Next hand" : null);
	}

	/** The host's lobby row: deal, house players, leave. **/
	function hostChoices(input:MenuInput, deal:Null<String>):Void {
		var opts = [];
		if (deal != null) opts.push(deal);
		if (host.openCount() > 0) opts.push("Add house player");
		if (host.houseCount() > 0) opts.push("Remove house player");
		opts.push("Leave table");
		var p = offer(opts, input);
		if (p == deal && deal != null) host.deal();
		else if (p == "Add house player") host.addHouse();
		else if (p == "Remove house player") host.removeHouse();
		else if (p == "Leave table") leave();
	}

	/** What the shared-seed check says about the last hand. **/
	function fairness(v:Dynamic):String {
		if (guest != null) {
			if (guest.auditHand != v.hand || guest.audit == "") return "Checking the deal…";
			return guest.audit == "ok" ? "Deal checked: shuffled from everyone's seeds, and it replays exactly." : 'DEAL CHECK FAILED: ${guest.audit}';
		}
		var checks:Array<Dynamic> = v.checks;
		var failed = [for (c in checks) if (c.result != "ok") c];
		if (failed.length > 0) return 'A GUEST\'S CHECK FAILED: ${failed[0].result}';
		var guests = [for (s in (v.seats : Array<Dynamic>)) if (s.kind == "human") s].length - 1;
		return guests <= 0 ? "" : '${checks.length} of $guests guests checked the deal.';
	}

	function raiseSizes(v:Dynamic):Array<Int> {
		var l:Dynamic = v.legal;
		var pot:Int = v.pot;
		var current:Int = v.currentBet;
		var sizes = [Std.int(l.minRaiseTo)];
		for (f in [0.5, 0.75, 1.0, 1.5]) {
			var s = current + Std.int((pot + l.toCall) * f);
			if (s > l.minRaiseTo && s < l.maxRaiseTo && sizes.indexOf(s) < 0) sizes.push(s);
		}
		sizes.sort((a, b) -> a - b);
		return sizes;
	}

	function myTurn(cx:Float, v:Dynamic, input:MenuInput):Void {
		var l:Dynamic = v.legal;
		var sizes = l.canRaise ? raiseSizes(v) : [];
		raiseIndex = Std.int(Math.max(0, Math.min(raiseIndex, sizes.length - 1)));
		if (input.up && raiseIndex < sizes.length - 1) raiseIndex++;
		if (input.down && raiseIndex > 0) raiseIndex--;
		var opts = [];
		if (!l.canCheck) opts.push("Fold");
		var passive = l.canCheck ? "Check" : 'Call ${l.toCall}';
		opts.push(passive);
		var raiseLabel = "";
		if (l.canRaise && sizes.length > 0 && sizes[raiseIndex] < l.maxRaiseTo) {
			raiseLabel = (v.currentBet == 0 ? "Bet " : "Raise to ") + sizes[raiseIndex];
			opts.push(raiseLabel);
		}
		if (l.canRaise) opts.push('All in ${l.maxRaiseTo}');
		var key = '${v.hand}/${v.street}/${v.currentBet}';
		if (key != decisionKey) {
			decisionKey = key;
			choices.set(opts);
			choices.selected = opts.indexOf(passive);
		}
		label(v.note, cx, 184, TableKit.GOLD, 1);
		var p = offer(opts, input);
		hint(Confirm, "Choose");
		if (raiseLabel != "") hint(null, InputMode.usingPad ? "D-pad up/down: size" : "Up/Down: size");
		if (p == null) return;
		var action = p == "Fold" ? Fold : p == "Check" ? Check : StringTools.startsWith(p, "Call") ? Call
			: StringTools.startsWith(p, "All in") ? RaiseTo(l.maxRaiseTo) : RaiseTo(sizes[raiseIndex]);
		if (host != null) host.act(action) else guest.act(action);
		raiseIndex = 0;
	}

	override function leave():Void {
		// Walking away mid-hand folds: the host folds for itself; the host folds a guest who says they're leaving.
		var v = view();
		if (host != null && v != null && v.stage == "playing" && host.table != null && host.table.toAct == 0) host.act(Fold);
		goodbye();
		super.leave();
	}

	// --- Drawing ------------------------------------------------------------

	function drawTable(w:Int, cx:Float, v:Dynamic):Void {
		var seats:Array<Dynamic> = v.seats;
		var you:Int = v.you;
		var stage:String = v.stage;
		for (i in 0...seats.length) {
			var s:Dynamic = seats[i];
			var rel = (i - you + seats.length) % seats.length;
			if (s.kind == "open") {
				if (rel != 0) {
					var spot = SPOTS[rel];
					label("empty seat", spotX(w, spot), spot.y, TableKit.DIM, spot.align);
				}
				continue;
			}
			var active = stage == "playing" && v.toAct == i;
			var color = s.out || s.folded ? TableKit.DIM : active ? TableKit.GOLD : TableKit.CREAM;
			var name = (i == v.button && stage != "lobby" ? "(D) " : "") + s.name + (s.kind == "house" ? " ·house" : "");
			var line2 = s.out ? (stage == "lobby" ? '${s.stack}' : "sitting out") : s.folded ? 'folded  ·  ${s.stack}'
				: s.allIn ? 'ALL IN  ·  bet ${s.total}' : '${s.stack}' + (s.bet > 0 ? '  ·  bet ${s.bet}' : "");
			var cards:Array<String> = s.cards;
			if (rel == 0) {
				label('$name   $line2', cx, 212, color, 1);
				continue;
			}
			var spot = SPOTS[rel];
			var x = spotX(w, spot);
			label(name, x, spot.y, color, spot.align);
			label(line2, x, spot.y + 12, color, spot.align);
			if (cards.length > 0 && !s.folded) {
				var step = 14;
				var hw = CardFaces.W + (cards.length - 1) * step;
				var left = spot.align == 0 ? x : spot.align == 2 ? x - hw : x - hw / 2;
				for (k in 0...cards.length) card(cards[k] == "" ? faces.back() : faces.face(Card.parse(cards[k])), left + k * step, spot.y + 28);
			}
		}
		var pot:Int = v.pot;
		if (stage == "playing") label('Pot $pot', cx, 98, TableKit.GOLD, 1);
		var board:Array<String> = v.board;
		var bw = 5 * (CardFaces.W + 4) - 4;
		for (k in 0...board.length) card(faces.face(Card.parse(board[k])), cx - bw / 2 + k * (CardFaces.W + 4), 112);
		// Your hand.
		var me:Dynamic = seats[you];
		var mine:Array<String> = me.cards;
		if (mine.length > 0 && mine[0] != "") {
			var hand = [for (c in mine) Card.parse(c)];
			var step = 44;
			var hw = CardFaces.W + (hand.length - 1) * step;
			for (k in 0...hand.length) card(faces.face(hand[k]), cx - hw / 2 + k * step, 234, me.folded);
			if (!me.folded && board.length >= 3)
				label(HandEval.describe(HandEval.score(hand.concat([for (c in board) Card.parse(c)]))), cx, 198, TableKit.DIM, 1);
		}
	}

	static function spotX(w:Int, spot:{x:Float, y:Int, align:Int}):Float
		return spot.align == 0 ? 20 : spot.align == 2 ? w - 20 : w * spot.x;
}

