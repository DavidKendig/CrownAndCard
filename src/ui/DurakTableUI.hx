// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import cards.Card;
import games.durak.Durak;
import games.durak.DurakAi;
import ui.ButtonGlyph;
import ui.TableKit;

/**
	Seated Durak view (§5.7): you against the Colonel, one attack and one
	defense at a time (real Durak lets an attacker throw several cards at
	once; this table resolves them one pair at a time, which keeps the same
	rules and limits but never leaves more than one open card to answer).
**/
class DurakTableUI extends h2d.Object {
	static inline var AI_SECONDS = 0.7;
	static inline var ROUND_HOLD_SECONDS = 1.0;

	public var onLeave:Void->Void = () -> {};

	public var status(get, never):String;

	var game:Durak;
	final rng:rng.IRng;
	final faces:CardFaces;
	final felt:h2d.Graphics;
	final cardLayer:h2d.Object;
	final message:h2d.Text;
	final info:h2d.Text;
	final panel:h2d.Graphics;
	final panelTitle:h2d.Text;
	final panelBody:h2d.Text;
	final choices:ChoiceRow;
	final hints:HintBar;
	var cursor = 0;
	var timer = 0.0;
	var hold = 0.0;
	var note = "";
	var confirmLeave = false;
	var started = false;
	var choiceContext = "";

	public function new(parent:h2d.Object, faces:CardFaces, rng:rng.IRng) {
		super(parent);
		this.faces = faces;
		this.rng = rng;
		felt = new h2d.Graphics(this);
		cardLayer = new h2d.Object(this);
		message = TableKit.text(this, TableKit.GOLD);
		info = TableKit.text(this, TableKit.DIM);
		panel = new h2d.Graphics(this);
		panelTitle = TableKit.text(this, TableKit.GOLD);
		panelBody = TableKit.text(this, TableKit.CREAM);
		choices = new ChoiceRow(this);
		choices.onChoose = choose;
		hints = new HintBar(this);
		newGame();
	}

	function newGame():Void {
		game = new Durak();
		game.dealFrom(rng);
		cursor = 0;
		timer = hold = 0;
		note = "The Colonel cuts for trump.";
		started = true;
	}

	function get_status():String {
		return 'durak ${game.phase} attacker ${game.attacker} durak ${game.durak}';
	}

	public function sit():Void {
		confirmLeave = false;
		if (game.phase == GameOver) newGame();
	}

	var actingSeat(get, never):Int;

	inline function get_actingSeat():Int return game.phase == Attacking ? game.attacker : game.defender;

	public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		drawTable(w, cx);
		var over = game.phase == GameOver;
		if (confirmLeave) {
			choiceContext = "leave";
			drawPanel(cx, "LEAVE THE TABLE?", "This game of Durak will be abandoned.", true);
			choices.set(["Stay", "Leave"]);
			choices.handle(input);
			hints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Stay"}], cx, 340);
			if (input.back) confirmLeave = false;
			return;
		}
		if (over) {
			choiceContext = "over";
			var you = game.durak == 0;
			var draw = game.durak < 0;
			drawPanel(cx, draw ? "NO DURAK THIS TIME" : you ? "YOU ARE THE DURAK" : "THE COLONEL IS THE DURAK",
				draw ? "The stock ran out for both of you at once." : you ? "Out of cards last. Better luck next deal." : "Cleaned him out. Well played.",
				true);
			choices.set(["Play again", "Leave table"]);
			choices.handle(input);
			hints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Leave table"}], cx, 340);
			if (input.back) leave();
			return;
		}

		if (hold > 0) hold -= dt;
		else if (actingSeat != 0) aiTurn(dt);
		else humanTurn(input);

		drawPanel(cx, "", "", false);
		message.text = hold > 0 ? note : humanPrompt();
		message.x = Math.round(cx - message.textWidth / 2);
		message.y = 44;
		var items:Array<{glyph:Null<GlyphAction>, label:String}> = [];
		if (hold <= 0 && actingSeat == 0) {
			if (game.phase == Attacking) {
				if (legalAttacks().length > 0) items.push({glyph: Confirm, label: "Attack"});
				if (game.canFinish) items.push({glyph: Alt, label: "Finish"});
			} else {
				if (legalDefends().length > 0) items.push({glyph: Confirm, label: "Defend"});
				items.push({glyph: Alt, label: "Take the table"});
			}
			items.push({glyph: null, label: InputMode.usingPad ? "D-pad: choose a card" : "Left/Right: choose a card"});
		}
		items.push({glyph: Back, label: "Leave table"});
		if (input.back) confirmLeave = true;
		hints.show(items, cx, 340);
	}

	function legalAttacks():Array<Card> return game.phase == Attacking && game.attacker == 0 ? game.legalAttacks() : [];

	function legalDefends():Array<Card> return game.phase == Defending && game.defender == 0 ? game.legalDefends(game.table.length - 1) : [];

	function humanPrompt():String {
		if (note != "" && hold <= 0) {
			var n = note;
			note = "";
			return n;
		}
		if (actingSeat != 0) return "The Colonel is thinking...";
		if (game.phase == Attacking) return legalAttacks().length > 0 ? "Choose a card to attack with, or finish the round." : "Nothing more to add: finish the round.";
		return legalDefends().length > 0 ? "Beat the open card, or take the table." : "You can't beat it: take the table.";
	}

	function humanTurn(input:MenuInput):Void {
		var legal = game.phase == Attacking ? legalAttacks() : legalDefends();
		var hand = game.hands[0];
		if (cursor >= hand.length) cursor = hand.length - 1;
		if (cursor < 0) cursor = 0;
		if ((input.left || input.right) && legal.length > 0) {
			var step = input.left ? -1 : 1;
			for (_ in 0...hand.length) {
				cursor = (cursor + step + hand.length) % hand.length;
				if (legal.indexOf(hand[cursor]) >= 0) break;
			}
		}
		if (input.confirm && cursor < hand.length && legal.indexOf(hand[cursor]) >= 0) {
			if (game.phase == Attacking) game.attack(hand[cursor]) else game.defend(game.table.length - 1, hand[cursor]);
			if (game.canFinish) note = "";
			afterAction();
		} else if (input.alt) {
			if (game.phase == Attacking && game.canFinish) {
				game.finish();
				note = "Round to the discard.";
				hold = ROUND_HOLD_SECONDS;
			} else if (game.phase == Defending) {
				game.take();
				note = "You take the table.";
				hold = ROUND_HOLD_SECONDS;
			}
			afterAction();
		}
	}

	function aiTurn(dt:Float):Void {
		timer += dt;
		if (timer < AI_SECONDS) return;
		timer = 0;
		if (game.phase == Attacking) {
			if (game.table.length > 0 && !DurakAi.shouldKeepAttacking(game)) {
				game.finish();
				note = "The Colonel calls it done. Round to the discard.";
				hold = ROUND_HOLD_SECONDS;
			} else {
				var card = DurakAi.chooseAttack(game);
				if (card != null) {
					game.attack(card);
					note = "The Colonel attacks.";
				} else if (game.canFinish) {
					game.finish();
					note = "Round to the discard.";
					hold = ROUND_HOLD_SECONDS;
				}
			}
		} else {
			var card = DurakAi.chooseDefend(game);
			if (card != null) {
				game.defend(game.table.length - 1, card);
				note = "The Colonel defends.";
			} else {
				game.take();
				note = "The Colonel takes the table.";
				hold = ROUND_HOLD_SECONDS;
			}
		}
		afterAction();
	}

	function choose(i:Int):Void {
		switch choiceContext {
			case "leave": if (i == 0) confirmLeave = false else leave();
			case "over": if (i == 0) newGame() else leave();
			default:
		}
	}

	function afterAction():Void {
		cursor = 0;
		if (game.phase == GameOver) hold = 0;
	}

	function drawPanel(cx:Float, title:String, body:String, hasChoices:Bool):Void {
		panel.clear();
		panelTitle.visible = panelBody.visible = title != "";
		choices.visible = hasChoices;
		if (title == "") return;
		panelTitle.text = title;
		panelBody.text = body;
		panelBody.textAlign = Center;
		var pw = Math.max(260, Math.max(panelTitle.textWidth, panelBody.textWidth) + 32);
		var ph = 30 + panelBody.textHeight + (hasChoices ? 30 : 8);
		var top = Math.round(Math.max(50, 130 - ph / 2));
		TableKit.panel(panel, cx - pw / 2, top, pw, ph, .93);
		panelTitle.x = Math.round(cx - panelTitle.textWidth / 2);
		panelTitle.y = top + 8;
		panelBody.maxWidth = pw - 24;
		panelBody.x = Math.round(cx - panelBody.maxWidth / 2);
		panelBody.y = top + 24;
		if (hasChoices) choices.layout(cx, top + ph - 24);
	}

	function drawTable(w:Int, cx:Float):Void {
		felt.clear();
		felt.beginFill(0x0B3D24, 1);
		felt.drawRect(0, 0, w, 360);
		felt.endFill();
		cardLayer.removeChildren();

		// The stock, with the trump card showing beside it.
		var stockX = 20.0, stockY = 150.0;
		if (game.stock.length > 0) {
			bitmap(faces.face(game.trumpCard), stockX + 16, stockY);
			for (k in 0...Std.int(Math.min(4, Math.ceil(game.stock.length / 8)))) bitmap(faces.back(), stockX - k, stockY - k);
		} else bitmap(faces.face(game.trumpCard), stockX, stockY);
		info.text = 'Trump ${suitName(game.trumpCard.suit)}\nStock ${game.stock.length}\nDiscard ${game.discarded}';
		info.x = 20;
		info.y = stockY + CardFaces.H + 6;

		// The opponent's hand, face down.
		var oppHand = game.hands[1];
		var oppX = cx - (CardFaces.W + (oppHand.length - 1) * 10) / 2;
		for (i in 0...oppHand.length) bitmap(faces.back(), oppX + i * 10, 20);

		// The table: the beaten pairs, then the one open slot.
		var pairs = hold > 0 ? [] : game.table;
		var tableX = cx - (pairs.length * 34) / 2;
		for (i in 0...pairs.length) {
			var p = pairs[i];
			bitmap(faces.face(p.attack), tableX + i * 34, 150);
			if (p.defend != null) bitmap(faces.face(p.defend), tableX + i * 34 + 12, 138);
		}

		// The player's hand, fanned along the bottom; legal cards sit brighter.
		var hand = game.hands[0];
		var legal = actingSeat == 0 ? (game.phase == Attacking ? legalAttacks() : legalDefends()) : [];
		var step = Math.min(28, (w - 40 - CardFaces.W) / Math.max(1, hand.length - 1));
		var x0 = cx - (CardFaces.W + step * (hand.length - 1)) / 2;
		for (i in 0...hand.length) {
			var c = hand[i];
			var lifted = actingSeat == 0 && i == cursor;
			var b = bitmap(faces.face(c), x0 + i * step, lifted ? 268 : 276);
			if (actingSeat == 0 && legal.length > 0 && legal.indexOf(c) < 0) b.color.set(.5, .5, .55, 1);
		}
		var youLabel = TableKit.text(cardLayer, actingSeat == 0 && hold <= 0 ? TableKit.GOLD : TableKit.CREAM);
		youLabel.text = 'You (${hand.length})   ${game.attacker == 0 ? "attacking" : "defending"}';
		youLabel.x = Math.round(cx - youLabel.textWidth / 2);
		youLabel.y = 254;
		var oppLabel = TableKit.text(cardLayer, actingSeat == 1 && hold <= 0 ? TableKit.GOLD : TableKit.CREAM);
		oppLabel.text = 'The Colonel (${oppHand.length})   ${game.attacker == 1 ? "attacking" : "defending"}';
		oppLabel.x = Math.round(cx - oppLabel.textWidth / 2);
		oppLabel.y = 6;
	}

	static function suitName(s:cards.Suit):String {
		return switch s {
			case Clubs: "clubs";
			case Diamonds: "diamonds";
			case Hearts: "hearts";
			case Spades: "spades";
		}
	}

	function leave():Void onLeave();

	function bitmap(tile:h2d.Tile, x:Float, y:Float):h2d.Bitmap {
		var b = new h2d.Bitmap(tile, cardLayer);
		b.x = Math.round(x);
		b.y = Math.round(y);
		return b;
	}
}
