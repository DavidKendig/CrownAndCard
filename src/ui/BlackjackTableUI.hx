// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import games.blackjack.Blackjack;
import render.Palette;
import ui.ButtonGlyph;
import ui.TableKit;

/**
	Seated blackjack view (§5.7): the authored felt from res/materials, with
	the dealer's cards along the top and the player's hands on the center spot.
	Cards come out one at a time in deal order; the result waits for the last.
**/
class BlackjackTableUI extends h2d.Object {
	static inline var STEP_SECONDS = 0.3;
	static inline var HAND_SPACING = 92;
	static inline var FELT_W = 720;
	static inline var FELT_H = 360;

	public var onLeave:Void->Void = () -> {};

	/** One line for the launcher's error reports. **/
	public var status(get, never):String;

	final game:Blackjack;
	final wallet:core.Wallet;
	final faces:CardFaces;
	final felt:h2d.Bitmap;
	final cardLayer:h2d.Object;
	final labels:h2d.Object;
	final purseText:h2d.Text;
	final shoeText:h2d.Text;
	final dealerText:h2d.Text;
	final message:h2d.Text;
	final messageBand:h2d.Graphics;
	final betText:h2d.Text;
	final choices:ChoiceRow;
	final hints:HintBar;
	var betIndex = 2;
	var shown = 0.0;
	var roundsPlayed = 0;
	var actions:Array<String> = [];

	public function new(parent:h2d.Object, palette:Palette, faces:CardFaces, wallet:core.Wallet, rng:rng.IRng) {
		super(parent);
		this.faces = faces;
		this.wallet = wallet;
		game = new Blackjack(new ShoeSource(rng), wallet.sovereigns);
		felt = new h2d.Bitmap(feltTile(palette), this);
		cardLayer = new h2d.Object(this);
		labels = new h2d.Object(this);
		purseText = TableKit.text(this, TableKit.GOLD);
		shoeText = TableKit.text(this, TableKit.DIM);
		dealerText = TableKit.text(this, TableKit.CREAM);
		messageBand = new h2d.Graphics(this);
		message = TableKit.text(this, TableKit.GOLD);
		betText = TableKit.text(this, TableKit.GOLD);
		choices = new ChoiceRow(this);
		choices.onChoose = choose;
		hints = new HintBar(this);
	}

	function get_status():String {
		return 'blackjack ${game.phase} purse ${game.purse} rounds $roundsPlayed';
	}

	/** Call when the player sits down, so the purse matches the wallet. **/
	public function sit():Void {
		game.seatPurse(wallet.sovereigns);
		clampBet();
		choices.selected = 0; // "Deal", not whatever was chosen last time
	}

	var bet(get, never):Int;

	inline function get_bet():Int return Blackjack.BETS[betIndex];

	function clampBet():Void {
		while (betIndex > 0 && Blackjack.BETS[betIndex] > game.purse) betIndex--;
	}

	var dealing(get, never):Bool;

	function get_dealing():Bool return shown < totalSteps();

	function totalSteps():Int return game.sequence + (game.holeRevealed ? 1 : 0);

	/** Reveal step of the card dealt with sequence number `order` (the hole card's flip is a step too). **/
	function stepOf(order:Int):Int return order + (game.holeRevealed && order >= game.holeRevealOrder ? 1 : 0);

	public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		felt.x = Math.round(cx - FELT_W / 2);
		if (dealing) shown = Math.min(totalSteps(), shown + dt / STEP_SECONDS);
		var settled = !dealing;

		drawCards(cx);

		purseText.text = 'Purse ${game.purse} Sov' + (wallet.marker > 0 ? '   Marker ${wallet.marker}' : '');
		purseText.x = Math.round(cx - FELT_W / 2 + 44);
		if (purseText.x < 6) purseText.x = 6;
		purseText.y = 3;
		shoeText.text = "6 decks  ·  Bets 2-50 Sov";
		shoeText.x = Math.round(Math.min(w - 6, cx + FELT_W / 2 - 44) - shoeText.textWidth);
		shoeText.y = 3;

		var phase = game.phase;
		var betting = phase == Betting || (phase == RoundOver && settled);
		var broke = betting && game.purse < Blackjack.MIN_BET;
		var opts:Array<String>, usable:Array<Bool> = null;
		if (!settled) opts = [];
		else if (broke) opts = ["Accept Pemberton's marker", "Leave table"];
		else if (betting) {
			opts = ["Deal", "Leave table"];
			usable = [game.canBet(bet), true];
		} else if (phase == Insurance) opts = ["No insurance", 'Insurance (${game.hands[0].bet >> 1})'];
		else opts = [for (a in game.legal()) (a : String)];
		actions = opts;
		choices.set(opts, usable);
		choices.visible = opts.length > 0;
		if (settled) {
			if (betting && !broke && (input.up || input.down)) {
				betIndex = Std.int(Math.max(0, Math.min(Blackjack.BETS.length - 1, betIndex + (input.up ? 1 : -1))));
				clampBet();
			}
			choices.handle(input);
			if (input.back && betting) onLeave();
		}
		choices.layout(cx, 300);

		betText.visible = betting && !broke;
		betText.text = 'Bet  < $bet >  Sovereigns';
		betText.x = Math.round(cx - betText.textWidth / 2);
		betText.y = 282;

		message.text = settled ? messageText(betting, broke) : "";
		message.maxWidth = Math.min(w - 24, 420);
		message.textAlign = Center;
		message.x = Math.round(cx - message.maxWidth / 2);
		message.y = 80;
		messageBand.clear();
		if (message.text != "") {
			var mw = message.textWidth + 16, mh = message.textHeight + 4;
			messageBand.beginFill(0x061208, .7);
			messageBand.drawRect(Math.round(cx - mw / 2), 79, Math.round(mw), Math.round(mh));
			messageBand.endFill();
		}

		var items:Array<{glyph:Null<GlyphAction>, label:String}> = [];
		if (settled && opts.length > 0) items.push({glyph: Confirm, label: "Choose"});
		if (betting && !broke) items.push({glyph: null, label: InputMode.usingPad ? "D-pad up/down: bet" : "Up/Down: bet"});
		if (betting) items.push({glyph: Back, label: "Leave table"});
		hints.visible = items.length > 0;
		hints.show(items, cx, 330);
		wallet.sovereigns = game.purse;
	}

	function messageText(betting:Bool, broke:Bool):String {
		if (broke) return "Your purse is empty. Pemberton can advance a marker of "
			+ core.Wallet.MARKER_ADVANCE + " Sovereigns.";
		if (game.phase == Insurance) return "The dealer shows an ace. Insurance?";
		if (game.phase == PlayerTurn) {
			var h = game.current;
			return game.hands.length > 1 ? 'Hand ${game.active + 1} of ${game.hands.length}: ${totalLabel(h.cards, h.soft)}' : "";
		}
		if (game.phase == RoundOver && game.hands.length > 0) {
			var net = game.returned - game.staked;
			var head = game.hands.length == 1 ? outcomeLine(game.hands[0]) : net > 0 ? "You come out ahead." : net < 0 ? "The house wins this one." : "All square.";
			var money = net > 0 ? 'You win $net.' : net < 0 ? 'You lose ${-net}.' : "Your stake comes back.";
			if (game.insurancePayout > 0) money += ' Insurance paid ${game.insurancePayout - game.insuranceBet}.';
			return '$head $money';
		}
		return game.shuffledThisRound ? "Fresh shoe. Place your bet." : "Place your bet.";
	}

	function outcomeLine(h:Hand):String {
		var d = Blackjack.total(game.dealer);
		return switch h.outcome {
			case Natural: "Blackjack!";
			case Win: d > 21 ? 'Dealer busts with $d.' : '${h.total} beats ${d}.';
			case Push: 'Push at ${h.total}.';
			case Lose: game.dealer.length == 2 && d == 21 ? "Dealer has blackjack." : '${d} beats ${h.total}.';
			case Bust: 'Bust with ${h.total}.';
			case Surrendered: "Surrendered: half your bet comes back.";
			case null: "";
		}
	}

	static function totalLabel(cards:Array<cards.Card>, soft:Bool):String {
		var t = Blackjack.total(cards);
		return soft && t < 21 ? 'soft $t' : '$t';
	}

	function choose(i:Int):Void {
		var label = actions[i];
		switch label {
			case "Deal":
				if (game.canBet(bet)) {
					game.deal(bet);
					roundsPlayed++;
					shown = 0;
				}
			case "Leave table":
				onLeave();
			case "Accept Pemberton's marker":
				wallet.takeMarker();
				game.credit(core.Wallet.MARKER_ADVANCE);
				clampBet();
			case "No insurance":
				game.insure(false);
			default:
				if (StringTools.startsWith(label, "Insurance")) game.insure(true);
				else game.act(cast label);
		}
		wallet.sovereigns = game.purse;
	}

	function drawCards(cx:Float):Void {
		cardLayer.removeChildren();
		labels.removeChildren();
		if (game.hands.length == 0) return;
		// Dealer: along the top, where the chip rack used to be.
		var visibleDealer = [];
		var dx = cx - (CardFaces.W + (game.dealer.length - 1) * 16) / 2;
		for (i in 0...game.dealer.length) {
			if (stepOf(game.dealerOrder[i]) >= shown) continue;
			var faceUp = i != 1 || (game.holeRevealed && game.holeRevealOrder < shown);
			card(faceUp ? faces.face(game.dealer[i]) : faces.back(), dx + i * 16, 21);
			if (faceUp) visibleDealer.push(game.dealer[i]);
		}
		dealerText.text = visibleDealer.length > 0 ? 'Dealer ${totalLabel(visibleDealer, Blackjack.isSoft(visibleDealer))}' : "";
		dealerText.x = Math.round(dx + CardFaces.W + (game.dealer.length - 1) * 16 + 8);
		dealerText.y = 43;

		var n = game.hands.length;
		for (hi in 0...n) {
			var h = game.hands[hi];
			var hx = Math.round(cx + (hi - (n - 1) / 2) * HAND_SPACING - (CardFaces.W + 12) / 2);
			var visible = [];
			for (i in 0...h.cards.length) {
				if (stepOf(h.order[i]) >= shown) continue;
				card(faces.face(h.cards[i]), hx + i * 12, 200 - i * 3);
				visible.push(h.cards[i]);
			}
			var activeHand = game.phase == PlayerTurn && hi == game.active && !dealing;
			var t = TableKit.text(labels, activeHand ? TableKit.GOLD : TableKit.CREAM);
			var total = visible.length > 0 ? totalLabel(visible, Blackjack.isSoft(visible)) : "";
			var result = !dealing && h.outcome != null ? '  ${resultWord(h)}' : "";
			t.text = (activeHand ? "> " : "") + '$total  ·  bet ${h.bet}' + result;
			if (h.outcome != null && !dealing)
				t.textColor = h.payout > h.bet ? TableKit.GOOD : h.payout == h.bet ? TableKit.CREAM : TableKit.BAD;
			t.x = Math.round(hx + (CardFaces.W + 12) / 2 - t.textWidth / 2);
			t.y = 258;
		}
	}

	static function resultWord(h:Hand):String {
		return switch h.outcome {
			case Natural: "BLACKJACK";
			case Win: "WIN";
			case Push: "PUSH";
			case Lose: "LOSE";
			case Bust: "BUST";
			case Surrendered: "SURRENDER";
			case null: "";
		}
	}

	function card(tile:h2d.Tile, x:Float, y:Float):Void {
		var b = new h2d.Bitmap(tile, cardLayer);
		b.x = Math.round(x);
		b.y = Math.round(y);
	}

	/** The authored felt, reduced to the 360p grid with its chip rack cleared for the dealer's cards. **/
	static function feltTile(palette:Palette):h2d.Tile {
		var src = hxd.Res.load("materials/blackjack-table.png").toImage().getPixels();
		var px = hxd.Pixels.alloc(FELT_W, FELT_H, hxd.PixelFormat.RGBA);
		var snapped = new Map<Int, Int>();
		function snap(c:Int):Int {
			var key = c & 0xFCFCFC;
			var v = snapped.get(key);
			if (v == null) {
				v = 0xFF000000 | palette.colors[palette.nearest((c >> 16) & 255, (c >> 8) & 255, c & 255, 1)];
				snapped.set(key, v);
			}
			return v;
		}
		// Plain felt color, from a clear patch beside the rack.
		var fr = 0.0, fg = 0.0, fb = 0.0, fn = 0;
		for (y in Std.int(src.height * .10)...Std.int(src.height * .20))
			for (x in Std.int(src.width * .15)...Std.int(src.width * .25)) {
				var c = src.getPixel(x, y);
				fr += (c >> 16) & 255;
				fg += (c >> 8) & 255;
				fb += c & 255;
				fn++;
			}
		var feltColor = snap((Std.int(fr / fn) << 16) | (Std.int(fg / fn) << 8) | Std.int(fb / fn));
		var sx = src.width / FELT_W, sy = src.height / FELT_H;
		for (y in 0...FELT_H) for (x in 0...FELT_W) {
			var r = 0, g = 0, b = 0, n = 0;
			for (yy in Std.int(y * sy)...Std.int((y + 1) * sy)) for (xx in Std.int(x * sx)...Std.int((x + 1) * sx)) {
				var c = src.getPixel(xx, yy);
				r += (c >> 16) & 255;
				g += (c >> 8) & 255;
				b += c & 255;
				n++;
			}
			px.setPixel(x, y, n == 0 ? feltColor : snap((Std.int(r / n) << 16) | (Std.int(g / n) << 8) | Std.int(b / n)));
		}
		// Clear the chip rack for the dealer's cards: re-lay plain felt from the clear band
		// to its left, mirrored back and forth so the weave has no seams.
		var x0 = Std.int(FELT_W * .30), x1 = Std.int(FELT_W * .70), y0 = Std.int(FELT_H * .05), y1 = Std.int(FELT_H * .235);
		var c0 = Std.int(FELT_W * .115), c1 = Std.int(FELT_W * .29), cw = c1 - c0;
		for (y in y0...y1) for (x in x0...x1) {
			var k = (x - x0) % (2 * cw);
			px.setPixel(x, y, px.getPixel(k < cw ? c0 + k : c1 - 1 - (k - cw), y));
		}
		var tex = h3d.mat.Texture.fromPixels(px);
		tex.filter = Nearest;
		return h2d.Tile.fromTexture(tex);
	}
}
