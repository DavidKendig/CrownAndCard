// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import cards.Card;
import games.parlour.War;
import ui.ButtonGlyph;
import ui.TableKit;

/** War against Sir Reggie: turn cards one battle at a time, or let it run. **/
class WarUI extends CardGameScreen {
	static inline var AUTO_SECONDS = 0.5;

	final shuffle:rng.IRng;
	var game:War;
	var last:Null<Battle> = null;
	var auto = false;
	var timer = 0.0;

	public function new(parent:h2d.Object, faces:CardFaces, shuffle:rng.IRng) {
		super(parent, faces, "war");
		this.shuffle = shuffle;
		newGame();
	}

	function newGame():Void {
		game = new War(shuffle);
		last = null;
		auto = false;
		timer = 0;
	}

	override public function status():String {
		return 'war ${game.stacks[0].length}-${game.stacks[1].length} battles ${game.battles}';
	}

	override public function sit():Void {
		confirmLeave = false;
		if (game.winner >= 0) newGame();
	}

	override public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		begin(w);
		drawTable(cx);
		if (leaveCheck(input, false, "")) {
			end(cx);
			return;
		}
		if (game.winner >= 0) {
			title = game.winner == War.YOU ? "YOU WIN THE WAR" : "SIR REGGIE WINS THE WAR";
			body = 'All 52 cards, after ${game.battles} battles.';
			var p = offer(["Play again", "Leave table"], input);
			if (p == "Play again") newGame() else if (p == "Leave table") leave();
			end(cx);
			return;
		}
		var click = takeClick();
		if (input.alt) auto = !auto;
		if (input.confirm || click == 1) battle();
		if (auto) {
			timer += dt;
			if (timer >= AUTO_SECONDS) {
				timer = 0;
				battle();
			}
		}
		hint(Confirm, "Turn over");
		hint(Alt, auto ? "Stop auto-play" : "Auto-play");
		end(cx);
	}

	function battle():Void {
		if (game.winner < 0) last = game.battle();
	}

	function drawTable(cx:Float):Void {
		pile(game.stacks[War.THEM].length, cx - 20, 26);
		label("Sir Reggie", cx, 12, TableKit.CREAM, 1);
		pile(game.stacks[War.YOU].length, cx - 20, 262);
		label("You", cx, 248, TableKit.CREAM, 1);
		hit(1, cx - 20, 262, CardFaces.W, CardFaces.H);
		label('Battle ${game.battles}', 30, 20, TableKit.DIM);
		if (last == null) {
			label("Turn over your top card.", cx, 150, TableKit.GOLD, 1);
			return;
		}
		// Each round of the battle side by side; a war shows more than one.
		var n = last.faceUp.length;
		for (k in 0...n) {
			var x = cx - 20 + (k - (n - 1) / 2) * 52;
			card(faces.face(last.faceUp[k][War.THEM]), x, 102);
			card(faces.face(last.faceUp[k][War.YOU]), x, 162);
		}
		var decider = last.faceUp[n - 1];
		var mine = decider[War.YOU], theirs = decider[War.THEM];
		var text = last.winner == War.YOU ? 'Your ${rankName(mine)} takes ${n > 1 ? "the war" : 'the ${rankName(theirs)}'}'
			: 'Reggie\'s ${rankName(theirs)} takes ${n > 1 ? "the war" : 'your ${rankName(mine)}'}';
		label((n > 1 ? "War! " : "") + text + (n > 1 ? ': ${last.cards} cards.' : "."), cx, 222, TableKit.GOLD, 1);
	}

	static function rankName(c:Card):String {
		return switch c.rank {
			case Card.JACK: "jack";
			case Card.QUEEN: "queen";
			case Card.KING: "king";
			case Card.ACE: "ace";
			case r: Std.string(r);
		}
	}
}
