// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import cards.Card;
import games.rummy.GinRummy;
import games.rummy.GinRummyAi;
import ui.ButtonGlyph;
import ui.TableKit;

/** Gin Rummy against the Deacon, one hand at a time to 100. **/
class GinRummyUI extends CardGameScreen {
	static inline var AI_SECONDS = 0.8;

	final shuffle:rng.IRng;
	var game:GinRummy;
	var cursor = 0;
	var timer = 0.0;
	var note = "";

	public function new(parent:h2d.Object, faces:CardFaces, shuffle:rng.IRng) {
		super(parent, faces, "draw");
		this.shuffle = shuffle;
		newGame();
	}

	function newGame():Void {
		game = new GinRummy();
		game.dealFrom(shuffle);
		cursor = 0;
		timer = 0;
		note = "";
	}

	override public function status():String {
		return 'gin rummy ${game.phase} score ${game.scores[0]}-${game.scores[1]}';
	}

	override public function sit():Void {
		confirmLeave = false;
		if (game.phase == GameOver) newGame();
	}

	override public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		begin(w);
		drawTable(cx);
		if (leaveCheck(input, game.phase != RoundOver && game.phase != GameOver, "This game of Gin Rummy will be abandoned.")) {
			end(cx);
			return;
		}

		switch game.phase {
			case RoundOver, GameOver:
				var over = game.phase == GameOver;
				title = over ? (game.winner == 0 ? "YOU WIN THE GAME" : "THE DEACON WINS THE GAME") : roundTitle();
				body = roundBody();
				var p = offer([over ? "New game" : "Next hand", "Leave table"], input);
				if (p == "Next hand" || p == "New game") {
					if (over) game = new GinRummy();
					game.dealFrom(shuffle);
					cursor = 0;
				} else if (p == "Leave table") leave();
			case Draw:
				if (game.turn == 0) humanDraw(input);
				else aiTurn(dt);
			case Discard:
				if (game.turn == 0) humanDiscard(input);
				else aiTurn(dt);
		}
		end(cx);
	}

	function roundTitle():String {
		if (game.knocker < 0) return "NO SCORE THIS HAND";
		var who = game.lastScorer == 0 ? "You" : "The Deacon";
		return game.lastGin ? '$who GIN!' : game.lastUndercut ? '$who UNDERCUT!' : '$who KNOCKS';
	}

	function roundBody():String {
		if (game.knocker < 0) return "The stock ran out before anyone could knock.";
		var lines = [];
		lines.push('Your deadwood: ${sumPoints(game.lastDeadwood[0])}   ·   Deacon\'s deadwood: ${sumPoints(game.lastDeadwood[1])}');
		var who = game.lastScorer == 0 ? "You score" : "The Deacon scores";
		lines.push('$who ${game.lastPoints}.');
		lines.push('Score: You ${game.scores[0]}   ·   Deacon ${game.scores[1]}');
		return lines.join("\n");
	}

	static function sumPoints(cards:Array<Card>):Int {
		var total = 0;
		for (c in cards) total += GinRummy.pointValue(c.rank);
		return total;
	}

	static function cardName(c:Card):String {
		var rank = switch c.rank {
			case Card.JACK: "jack";
			case Card.QUEEN: "queen";
			case Card.KING: "king";
			case Card.ACE: "ace";
			case r: Std.string(r);
		}
		var suit = switch c.suit {
			case Clubs: "clubs";
			case Diamonds: "diamonds";
			case Hearts: "hearts";
			case Spades: "spades";
		}
		return 'the $rank of $suit';
	}

	function humanDraw(input:MenuInput):Void {
		var top = game.discardPile.length > 0 ? game.discardPile[game.discardPile.length - 1] : null;
		var opts = top == null ? ["Draw from the stock"] : ["Draw from the stock", 'Take ${cardName(top)}'];
		var p = offer(opts, input);
		if (p == "Draw from the stock") {
			game.drawFromStock(0);
			cursor = game.hands[0].length - 1;
		} else if (p != null) {
			game.drawFromDiscard(0);
			cursor = game.hands[0].length - 1;
		}
	}

	function humanDiscard(input:MenuInput):Void {
		var hand = game.hands[0];
		if (cursor >= hand.length) cursor = hand.length - 1;
		if (cursor < 0) cursor = 0;
		if (input.left) cursor = (cursor + hand.length - 1) % hand.length;
		if (input.right) cursor = (cursor + 1) % hand.length;
		var picked = hand[cursor];
		var canKnock = game.canKnock(0, picked);
		hint(Confirm, "Discard");
		if (canKnock) hint(Alt, deadwoodIfDiscarding(picked) == 0 ? "Discard for gin!" : "Discard and knock");
		if (input.confirm) game.discard(0, picked, false);
		else if (input.alt && canKnock) game.discard(0, picked, true);
		if (game.phase != Discard) cursor = 0;
	}

	function deadwoodIfDiscarding(card:Card):Int return game.deadwoodIfDiscarding(0, card);

	function aiTurn(dt:Float):Void {
		timer += dt;
		if (timer < AI_SECONDS) return;
		timer = 0;
		if (game.phase == Draw) {
			if (GinRummyAi.shouldTakeDiscard(game, 1)) game.drawFromDiscard(1) else game.drawFromStock(1);
		} else {
			var c = GinRummyAi.chooseDiscard(game, 1);
			game.discard(1, c, game.canKnock(1, c));
		}
	}

	function drawTable(cx:Float):Void {
		// The stock (face down) and the discard pile (face up), side by side.
		pile(game.stock.length, cx - 60, 96);
		label("Stock", cx - 60 + CardFaces.W / 2, 96 + CardFaces.H + 2, TableKit.DIM, 1);
		if (game.discardPile.length > 0) card(faces.face(game.discardPile[game.discardPile.length - 1]), cx + 16, 96);
		else pile(0, cx + 16, 96, false);
		label("Discard", cx + 16 + CardFaces.W / 2, 96 + CardFaces.H + 2, TableKit.DIM, 1);

		label('The Deacon: ${game.hands[1].length} cards', cx, 26, TableKit.CREAM, 1);
		label('You: ${game.hands[0].length} cards   ·   You ${game.scores[0]}  ·  Deacon ${game.scores[1]}', cx, 178, TableKit.CREAM, 1);

		if (game.phase == RoundOver || game.phase == GameOver) return;
		var hand = game.hands[0];
		var step = Math.min(30, (screenW - 40 - CardFaces.W) / Math.max(1, hand.length - 1));
		var x0 = cx - (CardFaces.W + step * (hand.length - 1)) / 2;
		var myTurn = game.turn == 0;
		for (i in 0...hand.length) {
			var lifted = myTurn && game.phase == Discard && i == cursor;
			card(hand[i] != null ? faces.face(hand[i]) : faces.back(), x0 + i * step, lifted ? 224 : 232);
		}
		if (myTurn && game.phase == Discard) label('Deadwood if you keep this hand: ${GinRummy.evaluate(hand).deadwoodPoints}', cx, 202, TableKit.DIM, 1);
	}
}
