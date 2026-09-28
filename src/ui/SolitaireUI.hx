// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import games.parlour.Klondike;
import ui.ButtonGlyph;
import ui.TableKit;

/**
	Klondike solitaire. A cursor walks the piles: E / A picks cards up and puts
	them down, Space / X sends the card under the cursor to a foundation (or
	finishes the game once nothing is hidden), and the mouse can click piles.
**/
class SolitaireUI extends CardGameScreen {
	static inline var DOWN_STEP = 5;
	static inline var UP_STEP = 13;
	static inline var TOP_Y = 26;
	static inline var TABLEAU_Y = 90;
	static inline var AUTO_SECONDS = 0.07;

	final shuffle:rng.IRng;
	final overlay:h2d.Graphics;
	var game:Klondike;

	/** Row 0: stock, waste, (gap), four foundations. Row 1: the seven tableau piles. **/
	var row = 1;

	var col = 0;

	/** Tableau: how many face-up cards from the top are under the cursor. **/
	var depth = 1;

	var held:Null<{from:Pile, count:Int}> = null;
	var finishing = false;
	var timer = 0.0;
	var note = "";

	public function new(parent:h2d.Object, faces:CardFaces, shuffle:rng.IRng) {
		super(parent, faces, "solitaire");
		this.shuffle = shuffle;
		overlay = new h2d.Graphics(this);
		newGame();
	}

	function newGame():Void {
		game = new Klondike(shuffle);
		row = 1;
		col = 0;
		depth = 1;
		held = null;
		finishing = false;
		note = "";
	}

	override public function status():String {
		return 'solitaire moves ${game.moves} passes ${game.passes} won ${game.won}';
	}

	override public function sit():Void {
		confirmLeave = false;
		if (game.won) newGame();
	}

	override function onExtra(choice:String):Void {
		if (choice == "New deal") newGame();
	}

	function colX(c:Int):Float return screenW / 2 - (7 * 44 - 4) / 2 + c * 44;

	override public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		begin(w);
		overlay.clear();
		drawTable();
		// Back cancels a held card before it offers to leave.
		if (held != null && input.back && !confirmLeave) {
			held = null;
			end(cx);
			return;
		}
		if (leaveCheck(input, game.moves > 0 && !game.won, "This deal will be abandoned.", "New deal")) {
			overlay.clear();
			end(cx);
			return;
		}
		if (game.won) {
			overlay.clear();
			title = "SOLVED";
			body = 'Every card home in ${game.moves} moves.';
			var p = offer(["New deal", "Leave table"], input);
			if (p == "New deal") newGame() else if (p == "Leave table") leave();
			end(cx);
			return;
		}
		if (finishing) {
			timer += dt;
			if (timer >= AUTO_SECONDS) {
				timer = 0;
				if (!game.autoStep()) finishing = false;
			}
			end(cx);
			return;
		}
		navigate(input);
		var click = takeClick();
		if (click >= 0) clickAt(click);
		else if (input.confirm) press();
		if (input.alt) quickSend();
		drawCursor();
		hint(Confirm, held == null ? (row == 0 && col == 0 ? "Turn card" : "Pick up") : "Put down");
		hint(Alt, game.solvable ? "Finish" : "To foundation");
		hint(Back, held == null ? "Leave table" : "Cancel");
		if (note != "") label(note, w / 2, 324, TableKit.GOLD, 1);
		end(cx);
	}

	function navigate(input:MenuInput):Void {
		if (input.left || input.right) {
			var d = input.left ? -1 : 1;
			col = (col + d + 7) % 7;
			if (row == 0 && col == 2) col = (col + d + 7) % 7;
			depth = 1;
			note = "";
		}
		if (input.up) {
			if (row == 1 && depth < game.runLength(col)) depth++;
			else if (row == 1) {
				row = 0;
				if (col == 2) col = 1;
			}
		}
		if (input.down) {
			if (row == 0) {
				row = 1;
				depth = 1;
			} else if (depth > 1) depth--;
		}
	}

	function pileAt(r:Int, c:Int):Null<Pile> {
		if (r == 1) return Tableau(c);
		return switch c {
			case 0: Stock;
			case 1: Waste;
			case 2: null;
			default: Foundation(c - 3);
		}
	}

	function press():Void {
		var here = pileAt(row, col);
		if (here == null) return;
		if (held == null) {
			switch here {
				case Stock: game.turnStock();
				case Tableau(i):
					var n = Std.int(Math.min(depth, game.runLength(i)));
					if (n > 0) held = {from: here, count: n};
				default:
					if (game.cardsAt(here, 1).length > 0) held = {from: here, count: 1};
			}
			note = "";
			return;
		}
		if (game.canMove(held.from, held.count, here)) {
			game.move(held.from, held.count, here);
			note = "";
		} else if (!Type.enumEq(held.from, here)) note = "That doesn't go there.";
		held = null;
		depth = 1;
	}

	function quickSend():Void {
		if (game.solvable) {
			finishing = true;
			held = null;
			return;
		}
		var here = held != null ? held.from : pileAt(row, col);
		if (here == null) return;
		var f = game.foundationFor(here);
		if (f >= 0) {
			game.move(here, 1, Foundation(f));
			held = null;
			depth = 1;
		} else note = "Nothing to send up from there.";
	}

	/** Clicks: 200 stock, 201 waste, 203-206 foundations, 1000 + col * 100 + card index on the tableau (99 = empty). **/
	function clickAt(id:Int):Void {
		if (id >= 1000) {
			row = 1;
			col = Std.int((id - 1000) / 100);
			var idx = (id - 1000) % 100;
			var t = game.tableau[col];
			depth = idx == 99 ? 1 : Std.int(Math.max(1, t.length - idx));
		} else {
			row = 0;
			col = id - 200;
		}
		press();
	}

	function tableauY(t:Array<TableauCard>, idx:Int):Float {
		var y = TABLEAU_Y + 0.0;
		for (k in 0...idx) y += t[k].up ? UP_STEP : DOWN_STEP;
		return y;
	}

	function drawTable():Void {
		// Stock, waste and foundations.
		pile(game.stock.length, colX(0), TOP_Y, false);
		if (game.stock.length == 0) label("Redeal", colX(0) + 20, TOP_Y + 22, TableKit.DIM, 1);
		hit(200, colX(0), TOP_Y, CardFaces.W, CardFaces.H);
		if (game.waste.length > 0) card(faces.face(game.waste[game.waste.length - 1]), colX(1), TOP_Y);
		else pile(0, colX(1), TOP_Y, false);
		hit(201, colX(1), TOP_Y, CardFaces.W, CardFaces.H);
		for (i in 0...4) {
			var f = game.foundations[i];
			if (f.length > 0) card(faces.face(f[f.length - 1]), colX(3 + i), TOP_Y) else pile(0, colX(3 + i), TOP_Y, false);
			hit(203 + i, colX(3 + i), TOP_Y, CardFaces.W, CardFaces.H);
		}
		var moves = label('Moves ${game.moves}', 20, 16, TableKit.CREAM);
		TableKit.panel(bg, 16, 13, moves.textWidth + 8, 17, .86);
		// The tableau.
		for (c in 0...7) {
			var t = game.tableau[c];
			if (t.length == 0) {
				pile(0, colX(c), TABLEAU_Y, false);
				hit(1000 + c * 100 + 99, colX(c), TABLEAU_Y, CardFaces.W, CardFaces.H);
			}
			for (k in 0...t.length) {
				var y = tableauY(t, k);
				card(t[k].up ? faces.face(t[k].card) : faces.back(), colX(c), y);
				var h = k == t.length - 1 ? CardFaces.H : (t[k].up ? UP_STEP : DOWN_STEP);
				hit(1000 + c * 100 + k, colX(c), y, CardFaces.W, h);
			}
		}
	}

	/** Gold frame on the cursor; blue frame on the held cards. **/
	function drawCursor():Void {
		if (held != null) frame(held.from, held.count, 0x7FB0F0);
		var here = pileAt(row, col);
		if (here != null) frame(here, row == 1 ? Std.int(Math.max(1, Math.min(depth, game.runLength(col)))) : 1, TableKit.GOLD);
	}

	function frame(p:Pile, count:Int, color:Int):Void {
		var fx:Float, fy:Float, fh:Float;
		switch p {
			case Tableau(c):
				var t = game.tableau[c];
				fx = colX(c);
				if (t.length == 0) {
					fy = TABLEAU_Y;
					fh = CardFaces.H;
				} else {
					var first = Std.int(Math.max(0, t.length - count));
					fy = tableauY(t, first);
					fh = tableauY(t, t.length - 1) - fy + CardFaces.H;
				}
			case Stock:
				fx = colX(0);
				fy = TOP_Y;
				fh = CardFaces.H;
			case Waste:
				fx = colX(1);
				fy = TOP_Y;
				fh = CardFaces.H;
			case Foundation(i):
				fx = colX(3 + i);
				fy = TOP_Y;
				fh = CardFaces.H;
		}
		overlay.lineStyle(1, color, 1);
		overlay.drawRect(Math.round(fx) - 1.5, Math.round(fy) - 1.5, CardFaces.W + 2, fh + 2);
		overlay.lineStyle();
	}
}
