// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import cards.Card;
import games.canasta.Canasta;
import games.canasta.CanastaAi;
import ui.ButtonGlyph;
import ui.TableKit;

private enum Mode {
	Menu;
	PickMeldRank;
	PickLayOn;
	PickDiscard;
}

/**
	Seated Canasta view (§5.7): you against the Deacon. Melding and laying on
	always uses every natural (non-wild) card of that rank in hand at once;
	building a meld from just 2 naturals plus a wild, or holding one back,
	needs the fuller control a future mouse-driven layout would give.
**/
class CanastaTableUI extends h2d.Object {
	static inline var AI_SECONDS = 0.8;

	public var onLeave:Void->Void = () -> {};

	public var status(get, never):String;

	var game:Canasta;
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
	var mode:Mode = Menu;
	var menuOptions:Array<String> = [];
	var pendingRank = 0;
	var pendingMeldIndex = 0;
	var timer = 0.0;
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
		choices = new ChoiceRow(this, true);
		choices.onChoose = choose;
		hints = new HintBar(this);
		newGame();
	}

	function newGame():Void {
		game = new Canasta();
		game.dealFrom(rng);
		mode = Menu;
		timer = 0;
		note = "";
		started = true;
	}

	function get_status():String return 'canasta ${game.phase} score ${game.scores.join("/")}';

	public function sit():Void {
		confirmLeave = false;
		if (game.phase == GameOver) newGame();
	}

	public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		drawTable(w, cx);
		var over = game.phase == GameOver;
		if (confirmLeave) {
			choiceContext = "leave";
			drawPanel(cx, "LEAVE THE TABLE?", "This game of Canasta will be abandoned.", true);
			choices.set(["Stay", "Leave"]);
			choices.handle(input);
			hints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Stay"}], cx, 340);
			if (input.back) confirmLeave = false;
			return;
		}
		if (game.phase == HandOver || over) {
			choiceContext = "over";
			var out = game.goneOut;
			var title = out < 0 ? "THE STOCK RAN OUT" : out == 0 ? "YOU GO OUT" : "THE DEACON GOES OUT";
			var body = 'You ${game.scores[0]}   ·   Deacon ${game.scores[1]}';
			drawPanel(cx, over ? (game.winner == 0 ? "YOU WIN THE GAME" : "THE DEACON WINS THE GAME") : title, body, true);
			choices.set([over ? "New game" : "Next hand", "Leave table"]);
			choices.handle(input);
			hints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Leave table"}], cx, 340);
			if (input.back) leave();
			return;
		}

		if (game.turn == 1) aiTurn(dt);
		else humanTurn(cx, input);

		if (input.back && mode == Menu) confirmLeave = true;
	}

	function aiTurn(dt:Float):Void {
		timer += dt;
		if (timer < AI_SECONDS || game.phase != Draw) return;
		timer = 0;
		note = "The Deacon plays.";
		CanastaAi.takeTurn(game, 1);
	}

	function humanTurn(cx:Float, input:MenuInput):Void {
		switch mode {
			case Menu: updateMenu(cx, input);
			case PickMeldRank: updatePickRank(cx, input, true);
			case PickLayOn: updatePickLayOn(cx, input);
			case PickDiscard: updatePickDiscard(cx, input);
		}
	}

	function updateMenu(cx:Float, input:MenuInput):Void {
		var opts = [];
		if (game.phase == Draw) {
			opts.push("Draw from the stock");
			if (game.canTakeDiscard()) opts.push("Take the discard pile");
		} else {
			if (meldableRanks().length > 0) opts.push("Meld a rank");
			if (game.melds[0].length > 0 && hasNaturalForAnyMeld()) opts.push("Lay on a meld");
			opts.push("Discard");
		}
		choiceContext = "menu";
		menuOptions = opts;
		choices.set(opts);
		drawPanel(cx, "", "", true);
		choices.handle(input);
		hints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Leave table"}], cx, 340);
	}

	function meldableRanks():Array<Int> {
		var counts = new Map<Int, Int>();
		for (c in game.hands[0]) if (!Canasta.isWild(c)) counts.set(c.rank, (counts.exists(c.rank) ? counts.get(c.rank) : 0) + 1);
		return [for (r in counts.keys()) if (counts.get(r) >= 3) r];
	}

	function naturalsOfRank(rank:Int):Array<Card> return [for (c in game.hands[0]) if (!Canasta.isWild(c) && c.rank == rank) c];

	function hasNaturalForAnyMeld():Bool {
		for (m in game.melds[0]) if (naturalsOfRank(m.rank).length > 0) return true;
		return false;
	}

	function updatePickRank(cx:Float, input:MenuInput, forNewMeld:Bool):Void {
		var ranks = meldableRanks();
		choiceContext = "rank";
		menuOptions = [for (r in ranks) rankName(r)];
		menuOptions.push("Cancel");
		choices.set(menuOptions);
		drawPanel(cx, "MELD WHICH RANK?", "", true);
		choices.handle(input);
		hints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Cancel"}], cx, 340);
		if (input.back) mode = Menu;
	}

	function updatePickLayOn(cx:Float, input:MenuInput):Void {
		choiceContext = "layon";
		menuOptions = [for (m in game.melds[0]) if (naturalsOfRank(m.rank).length > 0) rankName(m.rank)];
		menuOptions.push("Cancel");
		choices.set(menuOptions);
		drawPanel(cx, "LAY ON WHICH MELD?", "", true);
		choices.handle(input);
		hints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Cancel"}], cx, 340);
		if (input.back) mode = Menu;
	}

	function updatePickDiscard(cx:Float, input:MenuInput):Void {
		choiceContext = "discard";
		var hand = [for (c in game.hands[0]) if (!Canasta.isWild(c)) c];
		menuOptions = [for (c in hand) cardName(c)];
		menuOptions.push("Cancel");
		choices.set(menuOptions);
		drawPanel(cx, "DISCARD WHICH CARD?", game.hands[0].length == 1 ? (game.hasCanasta(0) ? "Going out!" : "You need a canasta to go out.") : "", true);
		choices.handle(input);
		hints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Cancel"}], cx, 340);
		if (input.back) mode = Menu;
	}

	function choose(i:Int):Void {
		switch choiceContext {
			case "leave": if (i == 0) confirmLeave = false else leave();
			case "over": if (i == 0) newGame() else leave();
			case "menu": chooseMenu(menuOptions[i]);
			case "rank":
				if (menuOptions[i] == "Cancel") mode = Menu;
				else {
					var rank = meldableRanks()[i];
					try {
						game.meld(naturalsOfRank(rank));
						note = 'You meld ${rankName(rank)}s.';
					} catch (e:Dynamic) note = Std.string(e);
					mode = Menu;
				}
			case "layon":
				if (menuOptions[i] == "Cancel") mode = Menu;
				else {
					var eligible = [for (idx in 0...game.melds[0].length) if (naturalsOfRank(game.melds[0][idx].rank).length > 0) idx];
					var meldIndex = eligible[i];
					var rank = game.melds[0][meldIndex].rank;
					try {
						game.layOn(meldIndex, naturalsOfRank(rank));
						note = 'You add to the ${rankName(rank)}s.';
					} catch (e:Dynamic) note = Std.string(e);
					mode = Menu;
				}
			case "discard":
				if (menuOptions[i] == "Cancel") mode = Menu;
				else {
					var hand = [for (c in game.hands[0]) if (!Canasta.isWild(c)) c];
					try {
						game.discard(hand[i]);
						note = "";
					} catch (e:Dynamic) note = Std.string(e);
					mode = Menu;
				}
			default:
		}
	}

	function chooseMenu(label:String):Void {
		switch label {
			case "Draw from the stock":
				game.drawFromStock();
				note = "";
			case "Take the discard pile":
				game.takeDiscard();
				note = "You take the whole pile.";
			case "Meld a rank": mode = PickMeldRank;
			case "Lay on a meld": mode = PickLayOn;
			case "Discard": mode = PickDiscard;
			default:
		}
	}

	static function rankName(r:Int):String {
		return switch r {
			case Card.JACK: "jack";
			case Card.QUEEN: "queen";
			case Card.KING: "king";
			case Card.ACE: "ace";
			case n: Std.string(n);
		}
	}

	static function cardName(c:Card):String {
		var suit = switch c.suit {
			case Clubs: "clubs";
			case Diamonds: "diamonds";
			case Hearts: "hearts";
			case Spades: "spades";
		}
		return '${rankName(c.rank)} of $suit';
	}

	function leave():Void onLeave();

	function drawTable(w:Int, cx:Float):Void {
		felt.clear();
		felt.beginFill(0x0B3D24, 1);
		felt.drawRect(0, 0, w, 360);
		felt.endFill();
		cardLayer.removeChildren();

		bitmap(faces.back(), cx - 60, 40);
		info.text = 'Stock ${game.stock.length}';
		info.x = Math.round(cx - 60 + CardFaces.W / 2 - info.textWidth / 2);
		info.y = 40 + CardFaces.H + 2;
		if (game.discardPile.length > 0) bitmap(faces.face(game.discardPile[game.discardPile.length - 1]), cx + 16, 40);

		var y = 76.0;
		for (m in game.melds[1]) {
			label('Deacon: ${rankName(m.rank)} x${m.cards.length}' + (m.cards.length >= 7 ? " CANASTA" : ""), cx, y, TableKit.CREAM, 1);
			y += 14;
		}
		label('Your hand: ${game.hands[0].length}   ·   Deacon: ${game.hands[1].length}', cx, 4, TableKit.CREAM, 1);
		var my = y + 6;
		for (m in game.melds[0]) {
			label('You: ${rankName(m.rank)} x${m.cards.length}' + (m.cards.length >= 7 ? " CANASTA" : ""), cx, my, TableKit.GOLD, 1);
			my += 14;
		}

		message.text = note;
		message.x = Math.round(cx - message.textWidth / 2);
		message.y = 300;
	}

	function drawPanel(cx:Float, title:String, body:String, hasChoices:Bool):Void {
		panel.clear();
		panelTitle.visible = panelBody.visible = title != "";
		choices.visible = hasChoices;
		var top = 130.0;
		if (title != "") {
			panelTitle.text = title;
			panelBody.text = body;
			panelBody.textAlign = Center;
			var pw = Math.max(220, Math.max(panelTitle.textWidth, panelBody.textWidth) + 32);
			var ph = 26 + (body == "" ? 0 : panelBody.textHeight + 8);
			top = Math.round(Math.max(90, 130 - ph / 2));
			TableKit.panel(panel, cx - pw / 2, top, pw, ph, .92);
			panelTitle.x = Math.round(cx - panelTitle.textWidth / 2);
			panelTitle.y = top + 6;
			panelBody.maxWidth = pw - 24;
			panelBody.x = Math.round(cx - panelBody.maxWidth / 2);
			panelBody.y = top + 22;
			top += ph;
		}
		if (hasChoices) choices.layout(cx, Math.max(top + 6, 146), 170);
	}

	function label(text:String, x:Float, y:Float, color:Int, align:Int):Void {
		var t = TableKit.text(cardLayer, color);
		t.text = text;
		t.x = align == 1 ? Math.round(x - t.textWidth / 2) : Math.round(x);
		t.y = Math.round(y);
	}

	function bitmap(tile:h2d.Tile, x:Float, y:Float):h2d.Bitmap {
		var b = new h2d.Bitmap(tile, cardLayer);
		b.x = Math.round(x);
		b.y = Math.round(y);
		return b;
	}
}
