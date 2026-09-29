// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import cards.Card;
import cards.Suit;
import games.euchre.Euchre;
import games.euchre.EuchreAi;
import ui.ButtonGlyph;
import ui.TableKit;

/** Seated Euchre view (§5.7, §6.4): you and the Colonel against the Vasquez twins. **/
class EuchreTableUI extends h2d.Object {
	static final NAMES = ["You", "Rosalind Vasquez", "Colonel Blythe", "Rafe Vasquez"];
	static final SUIT_NAMES = ["clubs", "diamonds", "hearts", "spades"];

	static inline var AI_SECONDS = 0.7;
	static inline var TRICK_HOLD_SECONDS = 1.2;

	public var onLeave:Void->Void = () -> {};

	public var status(get, never):String;

	final game = new Euchre();
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
	var timer = 0.0;
	var hold = 0.0;
	var confirmLeave = false;
	var cursor = 0;
	var note = "";
	var started = false;
	var actions:Array<String> = [];
	var pendingSuit:Null<Suit> = null;
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

	function get_status():String return 'euchre hand ${game.handNumber} ${game.phase} score ${game.scores[0]}-${game.scores[1]}';

	public function sit():Void {
		confirmLeave = false;
		deal();
		started = true;
	}

	function deal():Void {
		game.dealFrom(rng);
		cursor = 0;
		timer = hold = 0;
		pendingSuit = null;
		note = 'Hand ${game.handNumber}. ${NAMES[game.dealer]} ${game.dealer == 0 ? "deal" : "deals"}. Turned up: ${cardName(game.turnUp)}.';
	}

	public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		drawTable(w);
		var opts:Array<String> = [], title = "", body = "";
		var items:Array<{glyph:Null<GlyphAction>, label:String}> = [];

		if (confirmLeave) {
			title = "LEAVE THE TABLE?";
			body = "This game of Euchre will be abandoned.";
			opts = ["Stay", "Leave"];
		} else if (hold > 0) {
			hold -= dt;
		} else switch game.phase {
			case Bid1:
				if (game.bidder != 0) aiTurn(dt, () -> {
					if (EuchreAi.shouldOrderUp(game, game.bidder)) {
						var alone = EuchreAi.shouldGoAlone(game.hands[game.bidder], game.turnUp.suit);
						note = '${NAMES[game.bidder]} orders it up' + (alone ? ", alone!" : ".");
						game.orderUp(alone);
						if (game.phase == DealerDiscard && game.dealer != 0) {
							game.dealerDiscard(EuchreAi.discard(game));
						}
					} else {
						note = '${NAMES[game.bidder]} passes.';
						game.passBid1();
					}
				});
				else {
					title = "ORDER IT UP?";
					body = '${cardName(game.turnUp)} is turned up.';
					opts = ["Order it up", "Order up, alone", "Pass"];
				}
			case DealerDiscard:
				if (game.dealer != 0) aiTurn(dt, () -> game.dealerDiscard(EuchreAi.discard(game)));
				else humanDiscard(input, items);
			case Bid2:
				if (game.bidder != 0) aiTurn(dt, () -> {
					var suit = EuchreAi.chooseTrump(game, game.bidder);
					if (suit != null) {
						var alone = EuchreAi.shouldGoAlone(game.hands[game.bidder], suit);
						note = '${NAMES[game.bidder]} names ${SUIT_NAMES[cast(suit, Int)]}' + (alone ? ", alone!" : ".");
						game.callTrump(suit, alone);
					} else {
						note = '${NAMES[game.bidder]} passes.';
						game.passBid2();
					}
				});
				else if (pendingSuit == null) {
					title = "NAME TRUMP";
					body = '${cardName(game.turnUp)} was turned down.' + (game.mustCallTrump ? "\nYou must name a trump." : "");
					opts = [for (s in Suit.ALL) if (s != game.turnedDownSuit) SUIT_NAMES[cast(s, Int)]];
					if (!game.mustCallTrump) opts.push("Pass");
				} else {
					title = 'TRUMP: ${SUIT_NAMES[cast(pendingSuit, Int)].toUpperCase()}';
					body = "Play alone?";
					opts = ["With my partner", "Alone"];
				}
			case Playing:
				if (game.turn == 0) humanPlay(input, items);
				else aiTurn(dt, () -> play(game.turn, EuchreAi.play(game, game.turn)));
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
			else if (game.phase != DealerDiscard) confirmLeave = true;
		}

		drawCards(w, cx);
		drawPanel(cx, title, body, opts.length > 0);
		message.text = hold > 0 && game.lastWinner >= 0 ? '${NAMES[game.lastWinner]} ${game.lastWinner == 0 ? "take" : "takes"} the trick.' : note;
		message.x = Math.round(cx - message.textWidth / 2);
		message.y = 198;
		hints.show(items, cx, 340);
	}

	function humanDiscard(input:MenuInput, items:Array<{glyph:Null<GlyphAction>, label:String}>):Void {
		var hand = game.hands[0].concat([game.turnUp]);
		if (cursor >= hand.length) cursor = hand.length - 1;
		if (input.left) cursor = (cursor + hand.length - 1) % hand.length;
		if (input.right) cursor = (cursor + 1) % hand.length;
		var pick = clickedCard != null ? clickedCard : input.confirm ? hand[cursor] : null;
		if (pick != null) game.dealerDiscard(pick);
		note = "Pick up the turned card and discard one.";
		items.push({glyph: Confirm, label: "Discard"});
		items.push({glyph: null, label: InputMode.usingPad ? "D-pad: choose" : "Left/Right: choose"});
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
		return 'the $rank of ${SUIT_NAMES[cast(c.suit, Int)]}';
	}

	function choose(i:Int):Void {
		var label = actions[i];
		switch label {
			case "Stay": confirmLeave = false;
			case "Leave", "Leave table": onLeave();
			case "Next hand": deal();
			case "New game":
				game.scores[0] = game.scores[1] = 0;
				deal();
			case "Order it up": game.orderUp(false);
			case "Order up, alone": game.orderUp(true);
			case "Pass":
				if (game.phase == Bid1) game.passBid1() else game.passBid2();
			case "With my partner": game.callTrump(pendingSuit, false);
			case "Alone": game.callTrump(pendingSuit, true);
			default:
				var idx = SUIT_NAMES.indexOf(label);
				if (idx >= 0) pendingSuit = cast idx;
		}
	}

	function summary():String {
		var lines = [];
		if (game.lastMaker >= 0) {
			var makerNames = Euchre.teamOf(game.lastMaker) == 0 ? "You and the Colonel" : "The Vasquez twins";
			lines.push(game.lastEuchred ? '$makerNames were euchred.' : '$makerNames made it' + (game.lastAlone ? " alone" : "") + '.');
			lines.push('+ ${game.lastPoints}');
		}
		lines.push('Score: You ${game.scores[0]}   ·   Them ${game.scores[1]}');
		return lines.join("\n");
	}

	function drawTable(w:Int):Void {
		bg.clear();
		bg.beginFill(0x0B3D24, 1);
		bg.drawRect(0, 0, w, 360);
		bg.endFill();
		scoreText.text = 'Us ${game.scores[0]}   Them ${game.scores[1]}' + (game.trump != null ? '   ·   Trump: ${SUIT_NAMES[cast(game.trump, Int)]}' : "");
		scoreText.x = Math.round(w / 2 - scoreText.textWidth / 2);
		scoreText.y = 4;
	}

	function drawCards(w:Int, cx:Float):Void {
		cardLayer.removeChildren();
		var back = faces.back();
		for (seat in [1, 2, 3]) {
			var n = game.hands[seat].length;
			if (seat == 2) {
				var x0 = cx - (CardFaces.W + (n - 1) * 6) / 2;
				for (i in 0...n) bitmap(back, x0 + i * 6, -34);
			} else {
				var y0 = 150 - (CardFaces.H + (n - 1) * 6) / 2;
				for (i in 0...n) bitmap(back, seat == 1 ? -26.0 : w - 14.0, y0 + i * 6);
			}
		}
		if (game.phase == Bid1 || game.phase == Bid2 || game.phase == DealerDiscard) bitmap(faces.face(game.turnUp), cx - CardFaces.W / 2, 150);
		plates[2].text = '${NAMES[2]} (partner)   ${game.hands[2].length} cards';
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
			var active = game.phase == Playing ? game.turn == s : game.phase == DealerDiscard ? game.dealer == s : game.bidder == s;
			plates[s].textColor = active && hold <= 0 ? TableKit.GOLD : TableKit.CREAM;
		}

		if (game.phase == Playing) {
			var spots = [{x: cx - 20, y: 134.0}, {x: cx - 80, y: 90.0}, {x: cx - 20, y: 44.0}, {x: cx + 40, y: 90.0}];
			for (p in (hold > 0 ? game.lastTrick : game.trick)) bitmap(faces.face(p.card), spots[p.seat].x, spots[p.seat].y);
		}

		var hand = game.hands[0];
		var isDiscarding = game.phase == DealerDiscard && game.dealer == 0;
		var shown = isDiscarding ? hand.concat([game.turnUp]) : hand;
		var myTurn = (game.phase == Playing && game.turn == 0 && hold <= 0) || isDiscarding;
		var legal = game.phase == Playing && myTurn ? game.legalPlays(0) : [];
		var step = Math.min(22, (w - 40 - CardFaces.W) / Math.max(1, shown.length - 1));
		var x0 = cx - (CardFaces.W + step * (shown.length - 1)) / 2;
		for (i in 0...shown.length) {
			var c = shown[i];
			var lifted = myTurn && i == cursor;
			var b = bitmap(faces.face(c), x0 + i * step, lifted ? 226 : 234);
			if (game.phase == Playing && myTurn && legal.indexOf(c) < 0) b.color.set(.5, .5, .55);
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
