// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import cards.Card;
import games.hearts.Hearts;
import games.hearts.HeartsAi;
import ui.ButtonGlyph;
import ui.TableKit;

/** Seated Hearts view (§5.7, §6.4): you against the Colonel, Tuppence and Reggie, no partnerships. **/
class HeartsTableUI extends h2d.Object {
	public static final NAMES = ["You", "Tuppence Fitch", "Colonel Blythe", "Sir Reggie"];

	static inline var AI_SECONDS = 0.6;
	static inline var TRICK_HOLD_SECONDS = 1.2;

	public var onLeave:Void->Void = () -> {};

	public var status(get, never):String;

	final game = new Hearts();
	final rng:rng.IRng;
	final faces:CardFaces;
	final bg:h2d.Graphics;
	final cardLayer:h2d.Object;
	final handHits:Array<h2d.Interactive> = [];
	final scoreText:h2d.Text;
	final plates:Array<h2d.Text>;
	final message:h2d.Text;
	final panel:h2d.Graphics;
	final panelTitle:h2d.Text;
	final panelBody:h2d.Text;
	final choices:ChoiceRow;
	final hints:HintBar;
	var timer = 0.0;
	var hold = 0.0;
	var confirmLeave = false;
	var cursor = 0;
	var selected:Array<Card> = [];
	var note = "";
	var started = false;
	var actions:Array<String> = [];
	var clickedCard:Null<Card> = null;

	public function new(parent:h2d.Object, faces:CardFaces, rng:rng.IRng) {
		super(parent);
		this.faces = faces;
		this.rng = rng;
		bg = new h2d.Graphics(this);
		cardLayer = new h2d.Object(this);
		for (i in 0...Hearts.HAND_SIZE) {
			var hit = new h2d.Interactive(CardFaces.W, CardFaces.H, this);
			hit.cursor = Button;
			hit.onOver = _ -> cursor = i;
			hit.onClick = _ -> if (i < game.hands[0].length) clickedCard = game.hands[0][i];
			handHits.push(hit);
		}
		scoreText = TableKit.text(this, TableKit.CREAM);
		plates = [for (_ in 0...4) TableKit.text(this, TableKit.CREAM)];
		message = TableKit.text(this, TableKit.GOLD);
		panel = new h2d.Graphics(this);
		panelTitle = TableKit.text(this, TableKit.GOLD);
		panelBody = TableKit.text(this, TableKit.CREAM);
		choices = new ChoiceRow(this);
		choices.onChoose = choose;
		hints = new HintBar(this);
	}

	function get_status():String return 'hearts hand ${game.handNumber} ${game.phase} score ${game.scores.join("/")}';

	public function sit():Void {
		confirmLeave = false;
		deal();
		started = true;
	}

	function deal():Void {
		game.dealFrom(rng);
		selected = [];
		cursor = 0;
		timer = hold = 0;
		note = game.phase == Passing ? passNote() : "You hold the two of clubs: lead it.";
	}

	function passNote():String {
		var dir = switch game.passDirection {
			case Left: "left, to Tuppence";
			case Right: "right, to Reggie";
			case Across: "across, to the Colonel";
			case Hold: "";
		}
		return 'Hand ${game.handNumber}. Choose 3 cards to pass $dir.';
	}

	public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		drawTable(w);
		var opts:Array<String> = [], title = "", body = "";
		var items:Array<{glyph:Null<GlyphAction>, label:String}> = [];

		if (confirmLeave) {
			title = "LEAVE THE TABLE?";
			body = "This game of Hearts will be abandoned.";
			opts = ["Stay", "Leave"];
		} else if (hold > 0) {
			hold -= dt;
		} else switch game.phase {
			case Passing:
				humanOrAiPass(input, items);
			case Playing:
				if (game.turn == 0) humanPlay(input, items);
				else aiTurn(dt, () -> play(game.turn, HeartsAi.play(game, game.turn)));
			case HandOver, GameOver:
				var over = game.phase == GameOver;
				title = over ? (game.winner == 0 ? "YOU WIN" : '${NAMES[game.winner].toUpperCase()} WINS') : 'HAND ${game.handNumber}';
				body = summary();
				opts = [over ? "New game" : "Next hand", "Leave table"];
		}
		clickedCard = null;

		actions = opts;
		choices.set(opts);
		choices.visible = opts.length > 0;
		if (opts.length > 0) {
			choices.handle(input);
			items.unshift({glyph: Confirm, label: "Choose"});
		}
		items.push({glyph: Back, label: confirmLeave ? "Stay" : "Leave table"});
		if (input.back && started) {
			if (confirmLeave) confirmLeave = false;
			else if (game.phase == HandOver || game.phase == GameOver) onLeave();
			else if (game.phase != Passing) confirmLeave = true;
		}

		drawCards(w, cx);
		drawPanel(cx, title, body, opts.length > 0);
		message.text = hold > 0 && game.lastWinner >= 0 ? '${NAMES[game.lastWinner]} ${game.lastWinner == 0 ? "take" : "takes"} the trick.' : note;
		message.x = Math.round(cx - message.textWidth / 2);
		message.y = 198;
		hints.show(items, cx, 340);
	}

	function humanOrAiPass(input:MenuInput, items:Array<{glyph:Null<GlyphAction>, label:String}>):Void {
		for (s in 1...4) if (game.passOut[s].length != 3) game.setPass(s, HeartsAi.choosePass(game.hands[s]));
		if (game.passOut[0].length == 3) return; // waiting on setPass() to resolve this frame
		var hand = game.hands[0];
		if (cursor >= hand.length) cursor = hand.length - 1;
		if (input.left) cursor = (cursor + hand.length - 1) % hand.length;
		if (input.right) cursor = (cursor + 1) % hand.length;
		var picked = clickedCard != null ? clickedCard : input.confirm ? hand[cursor] : null;
		if (picked != null) {
			if (selected.indexOf(picked) >= 0) selected.remove(picked);
			else if (selected.length < 3) selected.push(picked);
		}
		note = 'Choose 3 cards (${selected.length}/3).';
		hint(items, Confirm, "Select / deselect");
		if (selected.length == 3) hint(items, Alt, "Pass these 3");
		if (input.alt && selected.length == 3) game.setPass(0, selected);
	}

	function humanPlay(input:MenuInput, items:Array<{glyph:Null<GlyphAction>, label:String}>):Void {
		var legal = game.legalPlays(0);
		var hand = game.hands[0];
		if (cursor >= hand.length) cursor = hand.length - 1;
		if (input.left || input.right) {
			var step = input.left ? -1 : 1;
			for (_ in 0...hand.length) {
				cursor = (cursor + step + hand.length) % hand.length;
				if (legal.indexOf(hand[cursor]) >= 0) break;
			}
		}
		if (legal.indexOf(hand[cursor]) < 0 && legal.length > 0) cursor = hand.indexOf(legal[0]);
		var pick = clickedCard != null ? clickedCard : input.confirm ? hand[cursor] : null;
		if (pick != null && legal.indexOf(pick) >= 0) play(0, pick);
		note = game.trick.length == 0 ? "Your lead." : "Your play.";
		hint(items, Confirm, "Play card");
		items.push({glyph: null, label: InputMode.usingPad ? "D-pad: choose" : "Left/Right: choose"});
	}

	static function hint(items:Array<{glyph:Null<GlyphAction>, label:String}>, glyph:GlyphAction, label:String):Void items.push({glyph: glyph, label: label});

	function aiTurn(dt:Float, act:Void->Void):Void {
		timer += dt;
		if (timer < AI_SECONDS) return;
		timer = 0;
		act();
	}

	function play(seat:Int, card:Card):Void {
		var before = game.tricksPlayed;
		game.play(seat, card);
		note = seat == 0 ? "" : '${NAMES[seat]} plays ${cardName(card)}.';
		if (game.tricksPlayed != before) hold = TRICK_HOLD_SECONDS;
		timer = 0;
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

	function choose(i:Int):Void {
		var label = actions[i];
		switch label {
			case "Stay": confirmLeave = false;
			case "Leave", "Leave table": onLeave();
			case "Next hand": deal();
			case "New game":
				for (s in 0...4) game.scores[s] = 0;
				deal();
			default:
		}
	}

	function drawTable(w:Int):Void {
		bg.clear();
		bg.beginFill(0x0B3D24, 1);
		bg.drawRect(0, 0, w, 360);
		bg.endFill();
		scoreText.text = 'You ${game.scores[0]}   Tuppence ${game.scores[1]}   Colonel ${game.scores[2]}   Reggie ${game.scores[3]}';
		scoreText.x = Math.round(w / 2 - scoreText.textWidth / 2);
		scoreText.y = 4;
	}

	function summary():String {
		var lines = [];
		if (game.shooter >= 0) lines.push('${NAMES[game.shooter]} shot the moon!');
		for (s in 0...4) lines.push('${NAMES[s]}: ${game.scores[s]}');
		return lines.join("\n");
	}

	function drawCards(w:Int, cx:Float):Void {
		cardLayer.removeChildren();
		var back = faces.back();
		for (seat in [1, 2, 3]) {
			var n = game.hands[seat].length;
			var spot = switch seat {
				case 2: {x: cx - (CardFaces.W + (n - 1) * 6) / 2, y: -34.0};
				case 1: {x: -26.0, y: 150 - (CardFaces.H + (n - 1) * 6) / 2};
				default: {x: w - 14.0, y: 150 - (CardFaces.H + (n - 1) * 6) / 2};
			}
			for (i in 0...n) bitmap(back, seat == 2 ? spot.x + i * 6 : spot.x, seat == 2 ? spot.y : spot.y + i * 6);
		}
		plates[2].text = '${NAMES[2]}   ${game.hands[2].length} cards';
		plates[2].x = Math.round(cx - plates[2].textWidth / 2);
		plates[2].y = 26;
		plates[1].text = '${NAMES[1]}\n${game.hands[1].length} cards';
		plates[1].x = 20;
		plates[1].y = 118;
		plates[3].text = '${NAMES[3]}\n${game.hands[3].length} cards';
		plates[3].x = w - 20 - plates[3].textWidth;
		plates[3].y = 118;
		plates[0].text = '${NAMES[0]}   ${game.hands[0].length} cards';
		plates[0].x = Math.round(cx - plates[0].textWidth / 2);
		plates[0].y = 214;
		for (s in 0...4) plates[s].textColor = game.turn == s && game.phase == Playing && hold <= 0 ? TableKit.GOLD : TableKit.CREAM;

		var spots = [{x: cx - 20, y: 134.0}, {x: cx - 80, y: 90.0}, {x: cx - 20, y: 44.0}, {x: cx + 40, y: 90.0}];
		for (p in (hold > 0 ? game.lastTrick : game.trick)) bitmap(faces.face(p.card), spots[p.seat].x, spots[p.seat].y);

		var hand = game.hands[0];
		var isPassing = game.phase == Passing;
		var myTurn = (game.phase == Playing && game.turn == 0 && hold <= 0) || isPassing;
		var legal = game.phase == Playing && myTurn ? game.legalPlays(0) : [];
		var step = Math.min(22, (w - 40 - CardFaces.W) / Math.max(1, hand.length - 1));
		var x0 = cx - (CardFaces.W + step * (hand.length - 1)) / 2;
		for (i in 0...handHits.length) {
			var hit = handHits[i];
			hit.visible = i < hand.length && myTurn && !confirmLeave;
			if (i >= hand.length) continue;
			var c = hand[i];
			var isSelected = isPassing && selected.indexOf(c) >= 0;
			var lifted = (myTurn && i == cursor) || isSelected;
			var b = bitmap(faces.face(c), x0 + i * step, lifted ? 226 : 234);
			if (game.phase == Playing && myTurn && legal.indexOf(c) < 0) b.color.set(.5, .5, .55);
			hit.x = b.x;
			hit.y = b.y;
			hit.width = i == hand.length - 1 ? CardFaces.W : step;
		}
	}

	function drawPanel(cx:Float, title:String, body:String, hasChoices:Bool):Void {
		panel.clear();
		var visible = title != "";
		panelTitle.visible = panelBody.visible = visible;
		if (!visible) {
			choices.layout(cx, 300);
			return;
		}
		panelTitle.text = title;
		panelBody.text = body;
		panelBody.textAlign = Center;
		var pw = Math.max(260, Math.max(panelTitle.textWidth, panelBody.textWidth) + 32);
		var ph = 30 + panelBody.textHeight + (hasChoices ? 30 : 8);
		var top = Math.round(Math.max(40, 120 - ph / 2));
		TableKit.panel(panel, cx - pw / 2, top, pw, ph, .92);
		panelTitle.x = Math.round(cx - panelTitle.textWidth / 2);
		panelTitle.y = top + 8;
		panelBody.maxWidth = pw - 24;
		panelBody.x = Math.round(cx - panelBody.maxWidth / 2);
		panelBody.y = top + 24;
		choices.layout(cx, top + ph - 24);
	}

	function bitmap(tile:h2d.Tile, x:Float, y:Float):h2d.Bitmap {
		var b = new h2d.Bitmap(tile, cardLayer);
		b.x = Math.round(x);
		b.y = Math.round(y);
		return b;
	}
}
