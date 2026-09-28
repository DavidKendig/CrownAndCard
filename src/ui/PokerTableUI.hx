// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import cards.Card;
import games.poker.HandEval;
import games.poker.PokerAi;
import games.poker.PokerTable;
import ui.ButtonGlyph;
import ui.TableKit;

/**
	Seated poker (§6.4): Texas Hold'em (the Smoking Room game) or Five-card
	draw (the Tavern Cellar's kitchen-table game), four-handed. The player
	buys in from their purse and cashes out when they leave.
**/
class PokerTableUI extends CardGameScreen {
	public static inline var BUY_IN = 100;
	static inline var AI_SECONDS = 0.8;

	final variant:Variant;
	final wallet:core.Wallet;
	final shuffle:rng.IRng;
	final aiRng:rng.IRng;
	final styles:Array<PokerStyle>;
	var table:PokerTable;
	var timer = 0.0;
	var note = "";
	var raiseIndex = 0;
	var cursor = 0;
	var marked:Array<Card> = [];
	var seated = false;
	var decisionKey = "";

	public function new(parent:h2d.Object, faces:CardFaces, variant:Variant, wallet:core.Wallet, shuffle:rng.IRng, aiRng:rng.IRng) {
		super(parent, faces);
		this.variant = variant;
		this.wallet = wallet;
		this.shuffle = shuffle;
		this.aiRng = aiRng;
		var names = variant == Holdem
			? ["You", "Deacon Crane", "Colonel Blythe", "Valentine Crake"]
			: ["You", "Tuppence Fitch", "Sir Reggie", "Colonel Blythe"];
		// Personalities from the cast (§8.1): the Deacon is patient, the Colonel bold, Crake needling, Reggie a happy fish.
		styles = variant == Holdem
			? [null, {looseness: .3, aggression: .35}, {looseness: .7, aggression: .7}, {looseness: .5, aggression: .8}]
			: [null, {looseness: .5, aggression: .7}, {looseness: .9, aggression: .2}, {looseness: .7, aggression: .7}];
		table = new PokerTable(variant, names, [0, BUY_IN, BUY_IN, BUY_IN], 1, 2, variant == Draw ? 1 : 0);
	}

	override public function status():String {
		return '${(variant : String)} hand ${table.handNumber} ${table.phase} stack ${table.seats[0].stack}';
	}

	override public function sit():Void {
		seated = false;
		confirmLeave = false;
		note = "";
		buyIn();
	}

	/** Moves up to one buy-in from the purse to the table. **/
	function buyIn():Void {
		var amount = Std.int(Math.min(BUY_IN, wallet.sovereigns));
		if (amount < table.bigBlind * 5) return;
		wallet.sovereigns -= amount;
		table.setStack(0, amount);
		seated = true;
		note = 'You buy in for $amount Sovereigns.';
		deal();
	}

	function deal():Void {
		// NPCs who went broke buy back in.
		for (i in 1...4) if (table.seats[i].stack <= 0) {
			table.setStack(i, BUY_IN);
			note = '${table.seats[i].name} buys back in.';
		}
		table.startHand(shuffle);
		timer = 0;
		raiseIndex = 0;
		marked = [];
		cursor = 0;
	}

	override function leave():Void {
		var me = table.seats[0];
		if (table.phase == Betting || table.phase == Drawing) {
			table.forfeit(0);
			// Let the others finish the hand at once.
			var guard = 0;
			while ((table.phase == Betting || table.phase == Drawing) && guard++ < 500) aiStep();
		}
		wallet.sovereigns += me.stack;
		table.setStack(0, 0);
		seated = false;
		super.leave();
	}

	override public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		begin(w, variant == Holdem ? 0x173A26 : 0x5A3A22, variant == Holdem ? 0x3A2416 : 0x2A1A10);
		drawSeats(w, cx);

		var inHand = table.phase == Betting || table.phase == Drawing;
		if (leaveCheck(input, inHand && table.seats[0].live, "You'll fold this hand and cash out your stack.")) {
			end(cx);
			return;
		}
		if (!seated) {
			title = "BUY IN";
			body = wallet.sovereigns >= table.bigBlind * 5
				? 'Take a seat for ${Std.int(Math.min(BUY_IN, wallet.sovereigns))} Sovereigns?'
				: "Your purse is too light for this table. Pemberton can advance a marker of " + core.Wallet.MARKER_ADVANCE + ".";
			var p = offer(wallet.sovereigns >= table.bigBlind * 5 ? ["Buy in", "Leave table"] : ["Accept Pemberton's marker", "Leave table"], input);
			if (p == "Buy in") buyIn();
			else if (p == "Accept Pemberton's marker") wallet.takeMarker();
			else if (p == "Leave table") leave();
			end(cx);
			return;
		}

		switch table.phase {
			case Betting:
				if (table.toAct == 0) myBet(cx, input);
				else aiTurn(dt);
			case Drawing:
				if (table.drawer == 0) myDraw(cx, input);
				else aiTurn(dt);
			case HandOver, Waiting:
				handOver(cx, input);
		}
		if (note != "" && title == "") label(note, cx, 184, TableKit.GOLD, 1);
		end(cx);
	}

	function aiTurn(dt:Float):Void {
		timer += dt;
		if (timer < AI_SECONDS) return;
		timer = 0;
		aiStep();
	}

	/** One NPC decision (a bet or a draw), narrated. **/
	function aiStep():Void {
		if (table.phase == Drawing) {
			var seat = table.drawer;
			var s = table.seats[seat];
			var toss = seat == 0 ? [] : PokerAi.discards(s.cards);
			table.exchange(seat, toss);
			note = '${s.name} ${toss.length == 0 ? "stands pat" : 'draws ${toss.length}'}.';
			return;
		}
		var seat = table.toAct;
		var s = table.seats[seat];
		var action = seat == 0 ? Fold : PokerAi.decide(table, seat, aiRng, styles[seat]);
		var before = table.currentBet, call = table.legal(seat).toCall;
		table.act(seat, action);
		note = switch action {
			case Fold: '${s.name} folds.';
			case Check: '${s.name} checks.';
			case Call: '${s.name} calls $call.';
			case RaiseTo(n): before == 0 ? '${s.name} bets $n.' : '${s.name} raises to $n.';
		}
		if (s.allIn) note = '${s.name} is all in!';
	}

	function raiseSizes():Array<Int> {
		var l = table.legal(0);
		var pot = table.pot;
		var sizes = [l.minRaiseTo];
		for (f in [0.5, 0.75, 1.0, 1.5]) {
			var v = table.currentBet + Std.int((pot + l.toCall) * f);
			if (v > l.minRaiseTo && v < l.maxRaiseTo && sizes.indexOf(v) < 0) sizes.push(v);
		}
		sizes.sort((a, b) -> a - b);
		return sizes;
	}

	function myBet(cx:Float, input:MenuInput):Void {
		var l = table.legal(0);
		var sizes = l.canRaise ? raiseSizes() : [];
		if (raiseIndex >= sizes.length) raiseIndex = sizes.length - 1;
		if (raiseIndex < 0) raiseIndex = 0;
		if (input.up && raiseIndex < sizes.length - 1) raiseIndex++;
		if (input.down && raiseIndex > 0) raiseIndex--;
		var opts = [];
		if (!l.canCheck) opts.push("Fold");
		opts.push(l.canCheck ? "Check" : 'Call ${l.toCall}');
		var raiseLabel = "";
		if (l.canRaise && sizes.length > 0 && sizes[raiseIndex] < l.maxRaiseTo) {
			raiseLabel = (table.currentBet == 0 ? "Bet " : "Raise to ") + sizes[raiseIndex];
			opts.push(raiseLabel);
		}
		if (l.canRaise) opts.push('All in ${l.maxRaiseTo}');
		var key = '${table.handNumber}/${table.street}/${table.currentBet}';
		if (key != decisionKey) {
			decisionKey = key;
			choices.set(opts);
			choices.selected = opts.indexOf(l.canCheck ? "Check" : 'Call ${l.toCall}');
		}
		var p = offer(opts, input);
		hint(Confirm, "Choose");
		if (raiseLabel != "") hint(null, InputMode.usingPad ? "D-pad up/down: size" : "Up/Down: size");
		if (p == null) return;
		var action = p == "Fold" ? Fold : p == "Check" ? Check : StringTools.startsWith(p, "Call") ? Call
			: StringTools.startsWith(p, "All in") ? RaiseTo(l.maxRaiseTo) : RaiseTo(sizes[raiseIndex]);
		table.act(0, action);
		note = "";
		timer = 0;
		raiseIndex = 0;
	}

	function myDraw(cx:Float, input:MenuInput):Void {
		var hand = table.seats[0].cards;
		if (input.left) cursor = (cursor + hand.length - 1) % hand.length;
		if (input.right) cursor = (cursor + 1) % hand.length;
		var toggle = input.alt || input.up;
		var c = takeClick();
		if (c >= 0 && c < hand.length) {
			cursor = c;
			toggle = true;
		}
		if (toggle) {
			var card = hand[cursor];
			if (marked.remove(card)) {} else if (marked.length < PokerTable.MAX_DRAW) marked.push(card);
		}
		var p = offer([marked.length == 0 ? "Stand pat" : 'Draw ${marked.length}'], input);
		note = "Mark up to three cards to exchange.";
		hint(Confirm, marked.length == 0 ? "Stand pat" : "Draw");
		hint(Alt, "Mark card");
		if (p != null) {
			table.exchange(0, marked);
			note = marked.length == 0 ? "You stand pat." : 'You draw ${marked.length}.';
			marked = [];
			timer = 0;
		}
	}

	function handOver(cx:Float, input:MenuInput):Void {
		if (table.phase == Waiting) {
			deal();
			return;
		}
		var lines = [];
		if (table.thrownIn) lines.push('Everyone checked: the cards are thrown in.\nThe pot of ${table.carried} carries to the next deal.');
		for (r in table.results) {
			var who = table.seats[r.seat].name;
			lines.push(r.hand == "" ? '$who ${r.seat == 0 ? "win" : "wins"} ${r.amount}.' : '$who ${r.seat == 0 ? "win" : "wins"} ${r.amount} with ${r.hand.charAt(0).toLowerCase() + r.hand.substr(1)}.');
		}
		title = table.results.length > 0 && table.results[0].seat == 0 ? "YOU WIN THE POT" : 'HAND ${table.handNumber}';
		body = lines.join("\n");
		var broke = table.seats[0].stack <= 0;
		var opts = broke ? (wallet.sovereigns >= table.bigBlind * 5 ? ["Buy in again", "Leave table"] : ["Leave table"]) : ["Next hand", "Leave table"];
		note = "";
		var p = offer(opts, input);
		if (p == "Next hand") deal();
		else if (p == "Buy in again") buyIn();
		else if (p == "Leave table") leave();
	}

	/** Seat positions: 0 bottom, 1 left, 2 top, 3 right. **/
	function drawSeats(w:Int, cx:Float):Void {
		var over = table.phase == HandOver;
		var reveal = over && table.showdown;
		var handSize = variant == Holdem ? 2 : 5;
		var step = variant == Holdem ? 14 : 10;
		for (i in 0...4) {
			var s = table.seats[i];
			var active = !over && ((table.phase == Betting && table.toAct == i) || (table.phase == Drawing && table.drawer == i));
			var color = s.sittingOut || s.folded ? TableKit.DIM : active ? TableKit.GOLD : TableKit.CREAM;
			var name = (i == table.button ? "(D) " : "") + s.name;
			var line2 = s.sittingOut ? "sitting out" : s.folded ? 'folded  ·  ${s.stack}' : s.allIn ? 'ALL IN  ·  bet ${s.total}' : '${s.stack}' + (s.bet > 0 ? '  ·  bet ${s.bet}' : "") + (s.drew >= 0 && variant == Draw ? '  ·  drew ${s.drew}' : "");
			var show = s.cards.length > 0 && !s.folded && !s.sittingOut;
			switch i {
				case 0:
					label('$name   $line2', cx, 212, color, 1);
				case 1:
					label(name, 20, 92, color);
					label(line2, 20, 104, color);
					if (show) for (k in 0...s.cards.length) card(reveal ? faces.face(s.cards[k]) : faces.back(), 20 + k * step, 120);
				case 2:
					if (show) for (k in 0...s.cards.length) card(reveal ? faces.face(s.cards[k]) : faces.back(), cx - (CardFaces.W + (handSize - 1) * step) / 2 + k * step, 34);
					label('$name   $line2', cx, 18, color, 1);
				case 3:
					var hw = CardFaces.W + (handSize - 1) * step;
					label(name, w - 20, 92, color, 2);
					label(line2, w - 20, 104, color, 2);
					if (show) for (k in 0...s.cards.length) card(reveal ? faces.face(s.cards[k]) : faces.back(), w - 20 - hw + k * step, 120);
			}
		}
		// The middle: pot and board.
		var pot = table.pot;
		if (table.phase == Betting || table.phase == Drawing) label('Pot $pot', cx, 98, TableKit.GOLD, 1);
		var bw = 5 * (CardFaces.W + 4) - 4;
		for (k in 0...table.board.length) card(faces.face(table.board[k]), cx - bw / 2 + k * (CardFaces.W + 4), 112);
		// Your hand.
		var me = table.seats[0];
		if (me.cards.length > 0 && !me.sittingOut) {
			var myStep = 44;
			var hw = CardFaces.W + (me.cards.length - 1) * myStep;
			var drawing = table.phase == Drawing && table.drawer == 0;
			for (k in 0...me.cards.length) {
				var c = me.cards[k];
				var lift = drawing && marked.indexOf(c) >= 0 ? -7 : 0;
				var x = cx - hw / 2 + k * myStep, y = 234 + lift;
				card(faces.face(c), x, y, me.folded);
				if (drawing) {
					hit(k, x, y, CardFaces.W, CardFaces.H);
					if (k == cursor) label("^", x + CardFaces.W / 2, 292, TableKit.GOLD, 1);
				}
			}
			if (!me.folded && (variant == Draw || table.board.length >= 3)) {
				var best = HandEval.describe(HandEval.score(me.cards.concat(table.board)));
				label(best, cx, 198, TableKit.DIM, 1);
			}
		}
	}
}
