// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import games.mahjong.MahjongAi;
import games.mahjong.MahjongGame;
import games.mahjong.Tiles;
import ui.ButtonGlyph;
import ui.TableKit;

/**
	Seated Mahjong (§6.4): Classic (Hong Kong-style, with flowers) or Riichi.
	You sit at the bottom; play runs to your right. Discards collect in each
	player's pond in front of them, melds beside their name. Points only: no
	Sovereigns change hands.
**/
class MahjongUI extends CardGameScreen {
	static inline var AI_SECONDS = 0.7;
	static inline var DRAW_SECONDS = 0.25;
	static inline var CLAIM_SECONDS = 0.35;
	static final WIND_NAMES = ["East", "South", "West", "North"];

	/** Makes the choice row ignore keys and the pad while you're choosing a tile. **/
	static final noInput = new MenuInput();

	final variant:Variant;
	final tiles:TileFaces;
	final shuffle:rng.IRng;
	final names:Array<String>;
	var game:MahjongGame;
	var timer = 0.0;
	var note = "";
	var cursor = 0;
	var onRow = false;
	var riichiMode = false;
	var claimKey = "";

	public function new(parent:h2d.Object, faces:CardFaces, tiles:TileFaces, variant:Variant, shuffle:rng.IRng) {
		super(parent, faces, "mahjong");
		this.variant = variant;
		this.tiles = tiles;
		this.shuffle = shuffle;
		names = variant == Riichi
			? ["You", "Prof. Oyelaran", "Valentine Crake", "Rafe Vasquez"]
			: ["You", "Baroness von Adler", "Deacon Crane", "Madame Zelenka"];
		newGame();
	}

	function newGame():Void {
		game = new MahjongGame(variant, names, shuffle);
		note = "";
		timer = 0;
	}

	override public function status():String {
		return '${(variant : String)} mahjong ${game.roundLabel()} ${game.phase} scores ${[for (p in game.players) p.score].join("/")}';
	}

	override public function sit():Void {
		confirmLeave = false;
		if (game.phase == GameOver) newGame();
	}

	inline function you():MjPlayer return game.players[0];

	function seatName(seat:Int):String return names[seat];

	override public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		begin(w);
		var playing = game.phase == Draw || game.phase == Act || game.phase == Claims;
		drawTable(w, cx);
		if (leaveCheck(input, playing, "This game of Mahjong will be abandoned.")) {
			end(cx, 160);
			return;
		}
		switch game.phase {
			case Waiting:
				game.startHand();
				note = '${game.roundLabel()}. ${seatName(game.dealer)} ${game.dealer == 0 ? "deal" : "deals"}.';
			case Draw:
				timer += dt;
				if (timer >= DRAW_SECONDS) {
					timer = 0;
					game.draw();
					if (game.phase == Act && game.turn == 0) {
						cursor = handOrder().length;
						onRow = false;
						riichiMode = false;
						var drawn = you().drawn;
						note = drawn >= 0 ? 'You draw the ${Tiles.name(drawn)}.' : "";
					}
				}
			case Act:
				if (game.turn == 0) myTurn(input);
				else {
					timer += dt;
					if (timer >= AI_SECONDS) {
						timer = 0;
						aiTurn(game.turn);
					}
				}
			case Claims:
				var waiting = game.undecided();
				if (waiting.indexOf(0) >= 0 && waiting.length == 1) myClaim(input);
				else {
					timer += dt;
					if (timer >= CLAIM_SECONDS) {
						timer = 0;
						for (s in waiting) if (s != 0) decideFor(s, MahjongAi.claim(game, s));
					}
					if (game.phase == Claims && game.undecided().indexOf(0) >= 0) myClaim(input);
				}
			case HandOver, GameOver:
				handOver(input);
		}
		if (note != "" && title == "") label(note, cx, 146, TableKit.GOLD, 1);
		end(cx, 160);
	}

	// --- Your turn ---

	/** Your tiles as shown: the concealed hand, then the drawn tile set apart at the end. **/
	function handOrder():Array<Int> {
		var p = you();
		var out = p.hand.copy();
		if (p.drawn >= 0) {
			out.remove(p.drawn);
			out.push(p.drawn);
		}
		return out;
	}

	function myTurn(input:MenuInput):Void {
		var p = you();
		var order = handOrder();
		var legal = riichiMode ? game.riichiDiscards(0) : game.legalDiscards(0);
		var opts = [];
		if (game.canTsumo(0)) opts.push(variant == Riichi ? "Tsumo" : "Mahjong");
		for (k in game.kongOptions(0)) opts.push('Kong ${Tiles.name(k)}');
		if (game.canRiichi(0)) opts.push(riichiMode ? "Cancel riichi" : "Riichi");
		if (opts.length == 0) onRow = false;
		if (opts.length > 0 && input.up) onRow = true;
		if (input.down) onRow = false;
		var p2 = offer(opts, onRow ? input : noInput);
		if (p2 != null) {
			if (p2 == "Tsumo" || p2 == "Mahjong") {
				game.tsumo(0);
				return;
			}
			if (p2 == "Riichi" || p2 == "Cancel riichi") {
				riichiMode = p2 == "Riichi";
				onRow = false;
				note = riichiMode ? "Riichi: choose a discard that keeps your hand ready." : "";
				return;
			}
			if (StringTools.startsWith(p2, "Kong ")) {
				for (k in game.kongOptions(0)) if ('Kong ${Tiles.name(k)}' == p2) {
					game.kong(0, k);
					note = 'You declare a kong of ${Tiles.name(k)}.';
				}
				return;
			}
		}
		if (cursor >= order.length) cursor = order.length - 1;
		if (!onRow) {
			if (input.left) cursor = (cursor + order.length - 1) % order.length;
			if (input.right) cursor = (cursor + 1) % order.length;
		}
		var click = takeClick();
		var pick = click >= 0 && click < order.length ? order[click] : (!onRow && input.confirm ? order[cursor] : -1);
		if (pick >= 0 && legal.indexOf(pick) >= 0) {
			var declare = riichiMode;
			game.discard(0, pick, declare);
			note = declare ? 'Riichi! You discard the ${Tiles.name(pick)}.' : "";
			riichiMode = false;
			timer = 0;
		} else if (pick >= 0) note = p.riichi ? "In riichi you discard the tile you draw." : riichiMode ? "That discard wouldn't leave your hand ready." : "";
		hint(Confirm, onRow ? "Choose" : "Discard");
		hint(null, onRow ? (InputMode.usingPad ? "D-pad down: tiles" : "Down: tiles") : opts.length > 0 ? (InputMode.usingPad ? "D-pad up: actions" : "Up: actions") : (InputMode.usingPad ? "D-pad: choose" : "Left/Right: choose"));
		if (note == "") note = p.riichi ? "Riichi: your drawn tile goes unless it wins." : "Your turn: discard a tile.";
	}

	function aiTurn(seat:Int):Void {
		switch MahjongAi.turn(game, seat) {
			case Win:
				game.tsumo(seat);
			case DeclareKong(k):
				game.kong(seat, k);
				note = '${seatName(seat)} declares a kong of ${Tiles.name(k)}.';
			case Discard(tile, riichi):
				game.discard(seat, tile, riichi);
				note = (riichi ? '${seatName(seat)} declares riichi! ' : "") + '${seatName(seat)} discards the ${Tiles.name(tile)}.';
		}
	}

	// --- Claims ---

	function claimLabel(c:Claim):String {
		return switch c {
			case Ron: variant == Riichi ? "Ron" : "Mahjong";
			case Pon: variant == Riichi ? "Pon" : "Pung";
			case Kan: variant == Riichi ? "Kan" : "Kong";
			case Chi(low): (variant == Riichi ? "Chi " : "Chow ") + '${Tiles.rank(low)}-${Tiles.rank(low) + 1}-${Tiles.rank(low) + 2}';
		}
	}

	function myClaim(input:MenuInput):Void {
		var options = game.pending[0];
		if (options == null) return;
		var labels = ["Pass"].concat([for (o in options) claimLabel(o)]);
		var d = game.lastDiscard;
		note = '${seatName(d.seat)} discards the ${Tiles.name(d.tile)}. Claim it?';
		// A new prompt starts on the win when there is one, so it's never passed by accident.
		var key = '${d.seat}/${game.players[d.seat].discards.length}';
		if (key != claimKey) {
			claimKey = key;
			choices.set(labels);
			choices.selected = options.indexOf(Ron) >= 0 ? labels.indexOf(claimLabel(Ron)) : 0;
		}
		var picked = offer(labels, input);
		hint(Confirm, "Choose");
		if (picked == null) return;
		var claim:Null<Claim> = null;
		for (o in options) if (claimLabel(o) == picked) claim = o;
		if (claim == null) note = "";
		decideFor(0, claim);
	}

	function decideFor(seat:Int, claim:Null<Claim>):Void {
		var d = game.lastDiscard;
		var before = [for (p in game.players) p.melds.length];
		game.decide(seat, claim);
		// Narrate what actually happened (a pung outranks a chow, a win outranks both).
		if (game.phase != Claims && game.result == null) {
			for (s in 0...4) if (game.players[s].melds.length > before[s]) {
				var m = game.players[s].melds[game.players[s].melds.length - 1];
				var word = switch m.type {
					case Chow: variant == Riichi ? "chi" : "chow";
					case Pung: variant == Riichi ? "pon" : "pung";
					default: variant == Riichi ? "kan" : "kong";
				}
				note = '${seatName(s)} ${s == 0 ? "call" : "calls"} $word on the ${Tiles.name(d.tile)}.';
			}
		}
		if (game.phase == Act && game.turn == 0) {
			cursor = handOrder().length - 1;
			onRow = false;
		}
		timer = 0;
	}

	// --- End of a hand ---

	function handOver(input:MenuInput):Void {
		var r = game.result;
		var over = game.phase == GameOver;
		var lines = r == null ? [] : r.lines.copy();
		if (r != null && r.value != "") lines.push(r.value);
		if (r != null) {
			var changes = [for (i in 0...4) if (r.deltas[i] != 0) '${seatName(i)} ${r.deltas[i] > 0 ? "+" : ""}${r.deltas[i]}'];
			if (changes.length > 0) lines.push(changes.join("   "));
		}
		if (over) {
			var order = game.standings();
			lines.push("");
			for (i in 0...4) lines.push('${i + 1}. ${seatName(order[i])}  ${game.players[order[i]].score}');
		}
		title = over ? (game.standings()[0] == 0 ? "YOU TOP THE TABLE" : '${seatName(game.standings()[0]).toUpperCase()} TOPS THE TABLE') : (r == null ? "HAND OVER" : r.title.toUpperCase());
		body = lines.join("\n");
		note = "";
		var p = offer([over ? "New game" : "Next hand", "Leave table"], input);
		if (p == "Next hand") {
			game.startHand();
			note = '${game.roundLabel()}. ${seatName(game.dealer)} ${game.dealer == 0 ? "deal" : "deals"}.';
		} else if (p == "New game") newGame();
		else if (p == "Leave table") leave();
	}

	// --- Drawing ---

	function drawTable(w:Int, cx:Float):Void {
		if (game.phase == Waiting) return;
		// Round, wall and dora.
		label('${game.roundLabel()}  ·  Wall ${game.tilesLeft}' + (game.riichiSticks > 0 ? '  ·  Sticks ${game.riichiSticks}' : ""), 8, 4, TableKit.DIM);
		if (variant == Riichi) {
			label("Dora", w - 8 - 5 * (TileFaces.SW + 1) - 4, 10, TableKit.DIM, 2);
			for (i in 0...5) card(i < game.doraShown ? tiles.face(game.indicators[i], true) : tiles.back(true), w - 8 - (5 - i) * (TileFaces.SW + 1), 4);
		}
		// Players: plates, melds and ponds. Seat 1 is on your right, 2 across, 3 on your left.
		var pondX = [cx - 66, cx + 76, cx - 66, cx - 208];
		var pondY = [180.0, 90.0, 26.0, 90.0];
		for (s in 0...4) {
			var p = game.players[s];
			var wind = WIND_NAMES[game.seatWind(s)];
			var active = (game.phase == Act || game.phase == Draw) && game.turn == s;
			var color = active ? TableKit.GOLD : TableKit.CREAM;
			var tag = p.riichi ? "  RIICHI" : "";
			var flowers = variant == Classic && p.flowers.length > 0 ? '  ·  ${p.flowers.length} flower${p.flowers.length == 1 ? "" : "s"}' : "";
			switch s {
				case 0:
					label('You  ·  $wind  ·  ${p.score}$tag$flowers', 8, 286, color);
				case 1:
					label(seatName(s), w - 8, 44, color, 2);
					label('$wind  ·  ${p.score}$tag', w - 8, 56, color, 2);
					if (flowers != "") label(flowers.substr(5), w - 8, 68, TableKit.DIM, 2);
				case 2:
					label('${seatName(s)}  ·  $wind  ·  ${p.score}$tag$flowers', cx, 14, color, 1);
				case 3:
					label(seatName(s), 8, 44, color);
					label('$wind  ·  ${p.score}$tag', 8, 56, color);
					if (flowers != "") label(flowers.substr(5), 8, 68, TableKit.DIM);
			}
			pond(p, pondX[s], pondY[s]);
			melds(s, w, cx);
		}
		// Your hand.
		var p = you();
		if (game.phase == HandOver || game.phase == GameOver || p.hand.length == 0) return;
		var order = handOrder();
		var myTurn = game.phase == Act && game.turn == 0;
		var legal = myTurn ? (riichiMode ? game.riichiDiscards(0) : game.legalDiscards(0)) : [];
		var meldWidth = p.melds.length * (4 * (TileFaces.SW + 1) + 6);
		var total = order.length * (TileFaces.W + 1) + (p.drawn >= 0 ? 6 : 0);
		var x0 = Math.round(Math.max(8, cx - (total + meldWidth) / 2));
		for (i in 0...order.length) {
			var gap = p.drawn >= 0 && i == order.length - 1 ? 6 : 0;
			var x = x0 + i * (TileFaces.W + 1) + gap;
			var lifted = myTurn && !onRow && i == cursor;
			var dim = myTurn && legal.indexOf(order[i]) < 0;
			card(tiles.face(order[i]), x, lifted ? 294 : 300, dim);
			if (myTurn) hit(i, x, 294, TileFaces.W, TileFaces.H + 6);
		}
	}

	/** Discards, six to a row; claimed ones dimmed, the riichi tile marked. **/
	function pond(p:MjPlayer, x:Float, y:Float):Void {
		for (i in 0...p.discards.length) {
			var col = i % 6, row = Std.int(i / 6);
			var tx = x + col * (TileFaces.SW + 1), ty = y + row * (TileFaces.SH + 1);
			card(tiles.face(p.discards[i], true), tx, ty, p.claimed[i]);
			if (i == p.riichiDiscard) label("^", tx + TileFaces.SW / 2, ty + TileFaces.SH - 6, TableKit.GOLD, 1);
		}
	}

	function melds(s:Int, w:Int, cx:Float):Void {
		var p = game.players[s];
		var step = TileFaces.SW + 1;
		for (i in 0...p.melds.length) {
			var m = p.melds[i];
			var kinds = switch m.type {
				case Chow: [m.kind, m.kind + 1, m.kind + 2];
				case Pung: [m.kind, m.kind, m.kind];
				default: [m.kind, m.kind, m.kind, m.kind];
			}
			var x:Float, y:Float;
			switch s {
				case 0:
					// Right of your hand.
					var order = handOrder();
					var total = order.length * (TileFaces.W + 1) + (p.drawn >= 0 ? 6 : 0);
					var meldWidth = p.melds.length * (4 * step + 6);
					var x0 = Math.max(8, cx - (total + meldWidth) / 2);
					x = x0 + total + 6 + i * (4 * step + 6);
					y = 312;
				case 1:
					x = w - 8 - kinds.length * step;
					y = 84 + i * (TileFaces.SH + 3);
				case 2:
					x = cx + 76 + (i % 2) * (4 * step + 6);
					y = 26 + Std.int(i / 2) * (TileFaces.SH + 3);
				default:
					x = 8;
					y = 84 + i * (TileFaces.SH + 3);
			}
			for (j in 0...kinds.length) {
				// A closed kong shows its end tiles face down.
				var faceDown = m.type == ClosedKong && (j == 0 || j == 3);
				card(faceDown ? tiles.back(true) : tiles.face(kinds[j], true), x + j * step, y);
			}
		}
	}
}
