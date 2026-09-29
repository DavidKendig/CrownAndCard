// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import cards.Card;
import games.bridge.Bridge;
import games.bridge.BridgeAi;
import ui.ButtonGlyph;
import ui.TableKit;

private enum Mode {
	Menu;
	PickLevel;
	PickStrain;
}

private final STRAINS = [ClubsStrain, DiamondsStrain, HeartsStrain, SpadesStrain, NoTrumpStrain];

/** Seated (simplified) Bridge view (§5.7, §6.4): you and the Colonel against the Vasquez twins. **/
class BridgeTableUI extends h2d.Object {
	public static final NAMES = ["You", "Rosalind Vasquez", "Colonel Blythe", "Rafe Vasquez"];

	static inline var AI_SECONDS = 0.7;
	static inline var TRICK_HOLD_SECONDS = 1.2;

	public var onLeave:Void->Void = () -> {};

	public var status(get, never):String;

	final game = new Bridge();
	final rng:rng.IRng;
	final faces:CardFaces;
	final bg:h2d.Graphics;
	final cardLayer:h2d.Object;
	final scoreText:h2d.Text;
	final plates:Array<h2d.Text>;
	final message:h2d.Text;
	final panel:h2d.Graphics;
	final panelTitle:h2d.Text;
	final panelBody:h2d.Text;
	final choices:ChoiceRow;
	final hints:HintBar;
	var mode:Mode = Menu;
	var pendingLevel = 1;
	var timer = 0.0;
	var hold = 0.0;
	var confirmLeave = false;
	var cursor = 0;
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
		scoreText = TableKit.text(this, TableKit.CREAM);
		plates = [for (_ in 0...4) TableKit.text(this, TableKit.CREAM)];
		message = TableKit.text(this, TableKit.GOLD);
		panel = new h2d.Graphics(this);
		panelTitle = TableKit.text(this, TableKit.GOLD);
		panelBody = TableKit.text(this, TableKit.CREAM);
		choices = new ChoiceRow(this, true);
		choices.onChoose = choose;
		hints = new HintBar(this);
	}

	function get_status():String return 'bridge hand ${game.handNumber} ${game.phase} score ${game.scores[0]}-${game.scores[1]}';

	public function sit():Void {
		confirmLeave = false;
		deal();
		started = true;
	}

	function deal():Void {
		game.dealFrom(rng);
		mode = Menu;
		cursor = 0;
		timer = hold = 0;
		note = 'Hand ${game.handNumber}. ${NAMES[game.dealer]} ${game.dealer == 0 ? "deal" : "deals"}.';
	}

	public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		drawTable(w);
		var opts:Array<String> = [], title = "", body = "";
		var items:Array<{glyph:Null<GlyphAction>, label:String}> = [];

		if (confirmLeave) {
			title = "LEAVE THE TABLE?";
			body = "This game of Bridge will be abandoned.";
			opts = ["Stay", "Leave"];
		} else if (hold > 0) {
			hold -= dt;
		} else switch game.phase {
			case Bidding:
				if (game.turn != 0) aiTurn(dt, () -> {
					var call = BridgeAi.chooseBid(game, game.turn);
					if (call != null) {
						note = '${NAMES[game.turn]} bids ${call.level}${strainLabel(call.strain)}.';
						game.bid(game.turn, call.level, call.strain);
					} else {
						note = '${NAMES[game.turn]} passes.';
						game.pass(game.turn);
					}
				});
				else {
					opts = bidOptions();
					title = mode == Menu ? "YOUR BID" : mode == PickLevel ? "PICK A LEVEL" : 'PICK A STRAIN FOR $pendingLevel';
					body = note;
				}
			case Playing:
				var controller = game.controllerOf(game.turn);
				if (controller != 0) aiTurn(dt, () -> play(game.turn, BridgeAi.play(game, game.turn)));
				else humanPlay(input, items);
			case HandOver, GameOver:
				var over = game.phase == GameOver;
				title = over ? (game.winner == 0 ? "YOU WIN" : "THE VASQUEZ TWINS WIN") : 'HAND ${game.handNumber}';
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
			else if (mode != Menu) mode = Menu;
			else confirmLeave = true;
		}

		drawCards(w, cx);
		drawPanel(cx, title, body, opts.length > 0);
		message.text = hold > 0 && game.lastWinner >= 0 ? '${NAMES[game.lastWinner]} ${game.lastWinner == 0 ? "take" : "takes"} the trick.' : note;
		message.x = Math.round(cx - message.textWidth / 2);
		message.y = 198;
		hints.show(items, cx, 340);
	}

	/** The bidding options for the current mode (Menu/PickLevel/PickStrain); routed through `update`'s shared ChoiceRow. **/
	function bidOptions():Array<String> {
		note = game.highBid == null ? "No bid yet." : 'Current bid: ${game.highBid.level}${strainLabel(game.highBid.strain)} by ${NAMES[game.highBid.by]}.';
		return switch mode {
			case Menu: ["Bid", "Pass"];
			case PickLevel: [for (l in legalLevels()) Std.string(l)].concat(["Cancel"]);
			case PickStrain: [for (s in legalStrains(pendingLevel)) strainLabel(s)].concat(["Cancel"]);
		}
	}

	function legalLevels():Array<Int> return [for (l in 1...8) if (legalStrains(l).length > 0) l];

	function legalStrains(level:Int):Array<games.bridge.Bridge.Strain> return [for (s in STRAINS) if (game.canBid(level, s)) s];

	static function strainLabel(s:games.bridge.Bridge.Strain):String {
		return switch s {
			case ClubsStrain: "C";
			case DiamondsStrain: "D";
			case HeartsStrain: "H";
			case SpadesStrain: "S";
			case NoTrumpStrain: "NT";
		}
	}

	function humanPlay(input:MenuInput, items:Array<{glyph:Null<GlyphAction>, label:String}>):Void {
		var acting = game.turn; // the dummy's cards, when it's their turn, are still chosen by the human declarer
		var legal = game.legalPlays(acting);
		var hand = game.hands[acting];
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
		if (pick != null && legal.indexOf(pick) >= 0) play(acting, pick);
		note = acting == game.dummy ? "Play from the dummy." : game.trick.length == 0 ? "Your lead." : "Your play.";
		items.push({glyph: Confirm, label: "Play card"});
		items.push({glyph: null, label: InputMode.usingPad ? "D-pad: choose" : "Left/Right: choose"});
	}

	function aiTurn(dt:Float, act:Void->Void):Void {
		timer += dt;
		if (timer < AI_SECONDS) return;
		timer = 0;
		act();
	}

	function play(seat:Int, card:Card):Void {
		var before = game.tricksPlayed;
		game.play(seat, card);
		if (game.tricksPlayed != before) hold = TRICK_HOLD_SECONDS;
		timer = 0;
	}

	function choose(i:Int):Void {
		if (confirmLeave || game.phase == HandOver || game.phase == GameOver) {
			var label = actions[i];
			switch label {
				case "Stay": confirmLeave = false;
				case "Leave", "Leave table": onLeave();
				case "Next hand": deal();
				case "New game":
					game.scores[0] = game.scores[1] = 0;
					deal();
				default:
			}
			return;
		}
		switch mode {
			case Menu:
				if (actions[i] == "Bid") mode = PickLevel else if (actions[i] == "Pass") game.pass(0);
			case PickLevel:
				if (actions[i] == "Cancel") mode = Menu;
				else {
					pendingLevel = Std.parseInt(actions[i]);
					mode = PickStrain;
				}
			case PickStrain:
				if (actions[i] == "Cancel") mode = Menu;
				else {
					var strains = legalStrains(pendingLevel);
					game.bid(0, pendingLevel, strains[i]);
					mode = Menu;
				}
		}
	}

	function summary():String {
		if (game.thrownIn) return "No one could open the bidding: the hand is thrown in.";
		var lines = [];
		var contract = '${game.contractLevel}${strainLabel(game.contractStrain)} by ${NAMES[game.declarer]}';
		lines.push(contract + (game.lastMade ? " made" : " set") + '.  +${game.lastPoints}');
		lines.push('Score: You/Colonel ${game.scores[0]}   ·   Twins ${game.scores[1]}');
		return lines.join("\n");
	}

	function drawTable(w:Int):Void {
		bg.clear();
		bg.beginFill(0x0B3D24, 1);
		bg.drawRect(0, 0, w, 360);
		bg.endFill();
		scoreText.text = 'Us ${game.scores[0]}   Them ${game.scores[1]}' + (game.phase == Playing ? '   ·   ${game.contractLevel}${strainLabel(game.contractStrain)} by ${NAMES[game.declarer]}' : "");
		scoreText.x = Math.round(w / 2 - scoreText.textWidth / 2);
		scoreText.y = 4;
	}

	function drawCards(w:Int, cx:Float):Void {
		cardLayer.removeChildren();
		var back = faces.back();
		var dummyRevealed = game.phase == Playing;
		for (seat in [1, 2, 3]) {
			var n = game.hands[seat].length;
			var faceUp = dummyRevealed && seat == game.dummy;
			if (seat == 2) {
				var x0 = cx - (CardFaces.W + (n - 1) * (faceUp ? 16 : 6)) / 2;
				for (i in 0...n) bitmap(faceUp ? faces.face(game.hands[2][i]) : back, x0 + i * (faceUp ? 16 : 6), -34);
			} else {
				var y0 = 150 - (CardFaces.H + (n - 1) * 6) / 2;
				for (i in 0...n) bitmap(back, seat == 1 ? -26.0 : w - 14.0, y0 + i * 6);
			}
		}
		plates[2].text = '${NAMES[2]}${game.dummy == 2 ? " (dummy)" : ""}   ${game.hands[2].length} cards';
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
		for (s in 0...4) {
			var active = game.phase == Playing ? game.controllerOf(game.turn) == s || game.turn == s : game.turn == s;
			plates[s].textColor = active && hold <= 0 ? TableKit.GOLD : TableKit.CREAM;
		}

		if (game.phase == Playing) {
			var spots = [{x: cx - 20, y: 134.0}, {x: cx - 80, y: 90.0}, {x: cx - 20, y: 44.0}, {x: cx + 40, y: 90.0}];
			for (p in (hold > 0 ? game.lastTrick : game.trick)) bitmap(faces.face(p.card), spots[p.seat].x, spots[p.seat].y);
		}

		var acting = game.phase == Playing ? game.turn : 0;
		var hand = game.hands[acting];
		var myTurn = game.phase == Playing && game.controllerOf(game.turn) == 0 && hold <= 0;
		var legal = myTurn ? game.legalPlays(acting) : [];
		if (game.phase == Playing && !myTurn && acting != 0) return; // not our hand to see or act on right now
		var step = Math.min(22, (w - 40 - CardFaces.W) / Math.max(1, hand.length - 1));
		var x0 = cx - (CardFaces.W + step * (hand.length - 1)) / 2;
		for (i in 0...hand.length) {
			var c = hand[i];
			var lifted = myTurn && i == cursor;
			var b = bitmap(faces.face(c), x0 + i * step, lifted ? 226 : 234);
			if (myTurn && legal.indexOf(c) < 0) b.color.set(.5, .5, .55);
		}
	}

	function drawPanel(cx:Float, title:String, body:String, hasChoices:Bool):Void {
		panel.clear();
		var visible = title != "";
		panelTitle.visible = panelBody.visible = visible;
		if (!visible) {
			choices.layout(cx, 300, 140);
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
		choices.layout(cx, top + ph - 24, 140);
	}

	function bitmap(tile:h2d.Tile, x:Float, y:Float):h2d.Bitmap {
		var b = new h2d.Bitmap(tile, cardLayer);
		b.x = Math.round(x);
		b.y = Math.round(y);
		return b;
	}
}
