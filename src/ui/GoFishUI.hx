// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import games.parlour.GoFish;
import games.parlour.GoFishAi;
import ui.ButtonGlyph;
import ui.TableKit;

/** Go Fish, four-handed: you ask, they answer, and everyone remembers. **/
class GoFishUI extends CardGameScreen {
	static final NAMES = ["You", "Madame Zelenka", "Sir Reggie", "Tuppence Fitch"];
	static inline var AI_SECONDS = 1.1;
	static inline var RESULT_SECONDS = 1.3;

	final shuffle:rng.IRng;
	final aiRng:rng.IRng;
	var game:GoFish;
	var ai:GoFishAi;
	var cursor = 0;
	var target = 1;
	var timer = 0.0;
	var pause = 0.0;
	var log:Array<String> = [];

	public function new(parent:h2d.Object, faces:CardFaces, shuffle:rng.IRng, aiRng:rng.IRng) {
		super(parent, faces);
		this.shuffle = shuffle;
		this.aiRng = aiRng;
		newGame();
	}

	function newGame():Void {
		game = new GoFish(4, shuffle);
		ai = new GoFishAi(4, aiRng);
		cursor = 0;
		target = 1;
		timer = pause = 0;
		log = ["Five cards each. You ask first."];
	}

	override public function status():String {
		return 'go fish books ${[for (b in game.books) b.length].join("/")} stock ${game.stock.length}';
	}

	override public function sit():Void {
		confirmLeave = false;
		if (game.over) newGame();
	}

	override public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		begin(w, 0x1E3348, 0x2A1A10);
		var hand = game.hands[0];
		if (cursor >= hand.length) cursor = hand.length - 1;
		if (cursor < 0) cursor = 0;
		drawTable(w, cx);
		if (leaveCheck(input, !game.over, "This game of Go Fish will be abandoned.")) {
			end(cx);
			return;
		}
		if (game.over) {
			var lead = game.leaders();
			title = lead.length > 1 ? "A TIE" : lead[0] == 0 ? "YOU WIN" : '${NAMES[lead[0]].toUpperCase()} WINS';
			body = [for (i in 0...4) '${NAMES[i]}: ${game.books[i].length} book${game.books[i].length == 1 ? "" : "s"}'].join("\n");
			var p = offer(["Play again", "Leave table"], input);
			if (p == "Play again") newGame() else if (p == "Leave table") leave();
			end(cx);
			return;
		}
		var click = takeClick();
		if (pause > 0) pause -= dt;
		else if (game.turn == 0) {
			if (input.left) cursor = nextRank(-1);
			if (input.right) cursor = nextRank(1);
			if (input.up || input.down) target = nextTarget(input.up ? -1 : 1);
			if (click >= 0 && click < 100) cursor = click;
			if (click >= 101 && click <= 103) target = click - 100;
			if (hand.length > 0) {
				var rank = hand[cursor].rank;
				var p = offer(['Ask ${short(target)} for ${CardGameScreen.rankPlural(rank)}'], input);
				hint(Confirm, "Ask");
				hint(null, InputMode.usingPad ? "D-pad: rank / player" : "Left/Right: rank  Up/Down: player");
				if (p != null) ask(0, target, rank);
			}
		} else {
			timer += dt;
			if (timer >= AI_SECONDS) {
				timer = 0;
				var c = ai.choose(game, game.turn);
				ask(game.turn, c.target, c.rank);
			}
		}
		for (k in 0...log.length) label(log[k], cx, 168 + k * 12, k == log.length - 1 ? TableKit.GOLD : TableKit.CREAM, 1);
		end(cx);
	}

	function ask(asker:Int, who:Int, rank:Int):Void {
		var r = game.ask(asker, who, rank);
		ai.observe(r);
		var a = NAMES[asker], t = asker == 0 ? short(who) : who == 0 ? "you" : short(who);
		var you = asker == 0;
		var line = '$a ${you ? "ask" : "asks"} $t for ${CardGameScreen.rankPlural(rank)}: ';
		if (r.got > 0) line += '${who == 0 ? "you hand" : short(who) + " hands"} over ${r.got}.';
		else if (r.fished != null) line += "Go fish! " + (you ? 'You draw ${CardGameScreen.cardName(r.fished)}.' : '${short(asker)} draws.')
			+ (r.again ? " That's the one!" : "");
		else line += "Go fish! The stock is empty.";
		push(line);
		for (b in r.books) push('${a} ${you ? "make" : "makes"} a book of ${CardGameScreen.rankPlural(b)}!');
		pause = RESULT_SECONDS;
		if (target == asker || game.hands[target].length == 0) target = nextTarget(1);
	}

	function push(line:String):Void {
		log.push(line);
		while (log.length > 3) log.shift();
	}

	static final SHORT = ["You", "Zelenka", "Reggie", "Tuppence"];

	static function short(seat:Int):String return SHORT[seat];

	/** Moves the cursor to the first card of the next (or previous) rank. **/
	function nextRank(dir:Int):Int {
		var hand = game.hands[0];
		if (hand.length == 0) return 0;
		var rank = hand[cursor].rank;
		var i = cursor;
		for (_ in 0...hand.length) {
			i = (i + dir + hand.length) % hand.length;
			if (hand[i].rank != rank) break;
		}
		// Land on the first card of that rank.
		while (i > 0 && hand[i - 1].rank == hand[i].rank) i--;
		return i;
	}

	function nextTarget(dir:Int):Int {
		var t = target;
		for (_ in 0...3) {
			t = t + dir;
			if (t > 3) t = 1;
			if (t < 1) t = 3;
			if (game.hands[t].length > 0) return t;
		}
		return target;
	}

	function drawTable(w:Int, cx:Float):Void {
		var myTurn = game.turn == 0 && pause <= 0 && !game.over;
		// Opponents: plates, card backs and books.
		for (i in 1...4) {
			var n = game.hands[i].length;
			var color = myTurn && i == target ? TableKit.GOLD : game.turn == i ? TableKit.GOLD : TableKit.CREAM;
			var books = game.books[i].length == 0 ? "no books" : "books " + [for (b in game.books[i]) rankShort(b)].join(" ");
			var mark = myTurn && i == target ? "> " : "";
			switch i {
				case 1:
					label(mark + NAMES[i], 20, 92, color);
					label(books, 20, 104, TableKit.DIM);
					for (k in 0...n) card(faces.back(), 20 + k * 4, 120);
					hit(101, 16, 88, 110, 92);
				case 2:
					for (k in 0...n) card(faces.back(), cx - (CardFaces.W + (n - 1) * 4) / 2 + k * 4, 34);
					label('$mark${NAMES[i]}   ·   $books', cx, 18, color, 1);
					hit(102, cx - 80, 14, 160, 76);
				case 3:
					label(mark + NAMES[i], w - 20, 92, color, 2);
					label(books, w - 20, 104, TableKit.DIM, 2);
					for (k in 0...n) card(faces.back(), w - 20 - CardFaces.W - (n - 1) * 4 + k * 4, 120);
					hit(103, w - 126, 88, 110, 92);
			}
		}
		// The stock.
		pile(game.stock.length, cx - 20, 98);
		// Your hand, grouped by rank; the chosen rank lifts.
		var hand = game.hands[0];
		var rank = hand.length > 0 ? hand[cursor].rank : -1;
		var step = Math.min(24, (w - 60 - CardFaces.W) / Math.max(1, hand.length - 1));
		var x0 = cx - (CardFaces.W + step * (hand.length - 1)) / 2;
		for (k in 0...hand.length) {
			var lift = myTurn && hand[k].rank == rank ? -6 : 0;
			card(faces.face(hand[k]), x0 + k * step, 234 + lift);
			if (myTurn) hit(k, x0 + k * step, 228, k == hand.length - 1 ? CardFaces.W : step, CardFaces.H + 6);
		}
		var mine = game.books[0].length == 0 ? "no books yet" : "books " + [for (b in game.books[0]) rankShort(b)].join(" ");
		label('You   ·   $mine', cx, 210, game.turn == 0 ? TableKit.GOLD : TableKit.CREAM, 1);
	}

	static function rankShort(r:Int):String return r == 10 ? "10" : "23456789TJQKA".charAt(r - 2);
}
