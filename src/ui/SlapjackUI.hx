// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import cards.Card;
import games.parlour.Slapjack;
import ui.ButtonGlyph;
import ui.TableKit;

/**
	Slapjack against three quick hands from below stairs. Turning cards is
	turn-based; slapping is real time. Each opponent has a reaction time
	(Tuppence is fast, Reggie is tipsy) drawn from the table's AI stream.
**/
class SlapjackUI extends CardGameScreen {
	public static final NAMES = ["You", "Tuppence Fitch", "Sir Reggie", "Rafe Vasquez"];

	/** Reaction time: fastest possible, plus up to this much more (seconds). **/
	static final REACTION = [[0.0, 0.0], [0.30, 0.30], [0.55, 0.60], [0.38, 0.40]];

	/** Chance to slap a queen or king by mistake. **/
	static final JUMPY = [0.0, 0.03, 0.08, 0.04];

	static inline var FLIP_SECONDS = 0.7;
	static inline var RESULT_SECONDS = 1.1;

	final shuffle:rng.IRng;
	final aiRng:rng.IRng;
	var game:Slapjack;
	var timer = 0.0;
	var pause = 0.0;
	var jackTime = 0.0;
	var slapAt:Array<Float> = [];
	var lastTop:Null<Card> = null;
	var falseSlapper = -1;
	var falseAt = 0.0;
	var note = "";

	public function new(parent:h2d.Object, faces:CardFaces, shuffle:rng.IRng, aiRng:rng.IRng) {
		super(parent, faces, "slapjack");
		this.shuffle = shuffle;
		this.aiRng = aiRng;
		newGame();
	}

	function newGame():Void {
		game = new Slapjack(4, shuffle);
		timer = pause = 0;
		lastTop = null;
		note = "Tuppence deals. Watch for the jacks!";
	}

	override public function status():String {
		return 'slapjack cards ${[for (i in 0...4) game.count(i)].join("/")} winner ${game.winner}';
	}

	override public function sit():Void {
		confirmLeave = false;
		if (game.winner >= 0 || game.out[0]) newGame();
	}

	override public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		begin(w);
		drawTable(w, cx);
		var over = game.winner >= 0 || game.out[0];
		if (leaveCheck(input, !over, "This game of Slapjack will be abandoned.")) {
			end(cx);
			return;
		}
		if (over) {
			title = game.winner == 0 ? "YOU WIN EVERY CARD" : game.out[0] ? "YOU'RE OUT" : '${NAMES[game.winner].toUpperCase()} WINS';
			body = game.winner == 0 ? "Fastest hands in the cellar." : "Better luck with the next jack.";
			var p = offer(["Play again", "Leave table"], input);
			if (p == "Play again") newGame() else if (p == "Leave table") leave();
			end(cx);
			return;
		}

		// A new card on top: arm the NPCs' reactions.
		var top = game.top == null ? null : game.top.card;
		if (top != lastTop) {
			lastTop = top;
			jackTime = 0;
			falseSlapper = -1;
			if (top != null && top.rank == Card.JACK) {
				slapAt = [for (i in 0...4) REACTION[i][0] + aiRng.nextFloat() * REACTION[i][1]];
			} else if (top != null && top.rank >= Card.QUEEN) {
				for (i in 1...4) if (!game.out[i] && game.count(i) > 0 && aiRng.chance(JUMPY[i])) {
					falseSlapper = i;
					falseAt = 0.25 + aiRng.nextFloat() * 0.3;
				}
			}
		}

		var click = takeClick();
		var slapped = input.alt || click == 100;
		if (pause > 0) pause -= dt;
		else if (slapped) slap(0);
		else if (game.jackShowing) {
			jackTime += dt;
			var first = -1;
			for (i in 1...4) if (!game.out[i] && jackTime >= slapAt[i] && (first < 0 || slapAt[i] < slapAt[first])) first = i;
			if (first >= 0) slap(first);
		} else {
			jackTime += dt;
			if (falseSlapper > 0 && jackTime >= falseAt) {
				slap(falseSlapper);
				falseSlapper = -1;
			} else if (game.turn == 0) {
				if (input.confirm || click == 101) {
					game.flip();
					note = "";
				}
			} else {
				timer += dt;
				if (timer >= FLIP_SECONDS) {
					timer = 0;
					game.flip();
					note = "";
				}
			}
		}
		if (game.turn == 0 && !game.jackShowing && pause <= 0) hint(Confirm, "Turn a card");
		hint(Alt, "Slap!");
		if (note != "") label(note, cx, 196, TableKit.GOLD, 1);
		end(cx);
	}

	function slap(seat:Int):Void {
		if (game.out[seat]) return;
		var who = NAMES[seat];
		var you = seat == 0;
		note = switch game.slap(seat) {
			case Empty: "";
			case Won(n): '$who ${you ? "slap" : "slaps"} the jack and ${you ? "take" : "takes"} $n cards!';
			case Penalty(to): to == seat ? '$who ${you ? "slap" : "slaps"} ${you ? "your" : "their"} own card: it goes under the pile.'
				: '$who ${you ? "slap" : "slaps"} ${CardGameScreen.cardName(lastTop)}... and ${you ? "pay" : "pays"} ${NAMES[to]} a card.';
			case NothingToPay: '$who ${you ? "slap" : "slaps"} too soon, with nothing left to pay.';
		}
		if (note != "") pause = RESULT_SECONDS;
		timer = 0;
	}

	function drawTable(w:Int, cx:Float):Void {
		// The center pile, with the last few cards fanned under the top.
		var n = game.center.length;
		for (k in Std.int(Math.max(0, n - 4))...n) {
			var depth = n - 1 - k;
			card(faces.face(game.center[k].card), cx - 20 - depth * 6, 118 - depth * 3);
		}
		if (n == 0) pile(0, cx - 20, 118, false);
		hit(100, cx - 44, 106, 88, 76);
		label('${n} in the center', cx, 178, TableKit.DIM, 1);
		// Everyone's face-down pile.
		var spots = [{x: cx - 20, y: 236.0}, {x: 40.0, y: 118.0}, {x: cx - 20, y: 34.0}, {x: w - 80.0, y: 118.0}];
		for (i in 0...4) {
			var s = spots[i];
			pile(game.count(i), s.x, s.y);
			var color = game.out[i] ? TableKit.DIM : game.turn == i ? TableKit.GOLD : TableKit.CREAM;
			var tag = game.out[i] ? " (out)" : game.lastChance[i] ? " (last chance)" : "";
			switch i {
				case 0: label(NAMES[i] + tag, cx, 222, color, 1);
				case 2: label(NAMES[i] + tag, cx, 20, color, 1);
				default: label(NAMES[i] + tag, s.x + 20, 102, color, 1);
			}
		}
		hit(101, cx - 20, 236, CardFaces.W, CardFaces.H);
	}
}
