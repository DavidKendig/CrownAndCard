// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import games.slots.Slots;
import ui.ButtonGlyph;
import ui.TableKit;

/**
	The Clockwork Gallery's one-armed bandit (§5.7, §6.4): pick a bet, pull
	the lever, and the three reels land on whatever `Slots.spin()` already
	chose (§7.7). The RTP is engraved on its own brass plaque, per the
	Honest Games pillar.
**/
class SlotsTableUI extends h2d.Object {
	static inline var FELT_H = 360;

	public var onLeave:Void->Void = () -> {};

	/** One line for the launcher's error reports. **/
	public var status(get, never):String;

	final game:Slots;
	final wallet:core.Wallet;
	final cabinet:h2d.Graphics;
	final reels:h2d.Graphics;
	final reelLabels:Array<h2d.Text>;
	final purseText:h2d.Text;
	final betText:h2d.Text;
	final messageText:h2d.Text;
	final plaqueText:h2d.Text;
	final choices:ChoiceRow;
	final hints:HintBar;

	var betIndex = 0;
	var lastResult:Null<SpinResult> = null;
	var message = "Pull the lever.";
	var spinsPlayed = 0;

	public function new(parent:h2d.Object, wallet:core.Wallet, rng:rng.IRng) {
		super(parent);
		this.wallet = wallet;
		game = new Slots(rng, wallet.sovereigns);
		cabinet = new h2d.Graphics(this);
		reels = new h2d.Graphics(this);
		reelLabels = [for (_ in 0...3) TableKit.text(this, 0xFFFFFF)];
		purseText = TableKit.text(this, TableKit.GOLD);
		betText = TableKit.text(this, TableKit.GOLD);
		messageText = TableKit.text(this, TableKit.CREAM);
		plaqueText = TableKit.text(this, TableKit.DIM);
		choices = new ChoiceRow(this);
		choices.onChoose = choose;
		hints = new HintBar(this);
	}

	function get_status():String return 'slots purse ${game.purse} spins $spinsPlayed';

	public function sit():Void {
		game.seatPurse(wallet.sovereigns);
		clampBet();
		choices.selected = 0;
	}

	var bet(get, never):Int;

	inline function get_bet():Int return Slots.BETS[betIndex];

	function clampBet():Void {
		while (betIndex > 0 && Slots.BETS[betIndex] > game.purse) betIndex--;
	}

	public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		drawCabinet(w);
		drawReels(cx);

		purseText.text = 'Purse ${game.purse} Sov' + (wallet.marker > 0 ? '   Marker ${wallet.marker}' : '');
		purseText.x = 6;
		purseText.y = 3;

		plaqueText.text = 'RTP ${Math.round(Slots.RTP * 1000) / 10}% on the brass plaque.';
		plaqueText.x = Math.round(cx - plaqueText.textWidth / 2);
		plaqueText.y = 3;
		if (purseText.x + purseText.textWidth + 12 > plaqueText.x) plaqueText.visible = false else plaqueText.visible = true;

		messageText.text = message;
		messageText.maxWidth = Math.min(w - 24, 460);
		messageText.textAlign = Center;
		messageText.x = Math.round(cx - messageText.maxWidth / 2);
		messageText.y = 240;

		var affordable = game.canBet(bet);
		var opts = ["Pull the lever", "Leave table"];
		var usable = [affordable, true];
		choices.set(opts, usable);
		if (input.up || input.down) {
			betIndex = Std.int(Math.max(0, Math.min(Slots.BETS.length - 1, betIndex + (input.up ? 1 : -1))));
			clampBet();
		}
		choices.handle(input);
		choices.layout(cx, 300);
		if (input.back) leave();

		betText.text = 'Bet  < $bet >  Sovereigns';
		betText.x = Math.round(cx - betText.textWidth / 2);
		betText.y = 278;

		var items = [{glyph: Confirm, label: "Choose"}, {glyph: null, label: InputMode.usingPad ? "D-pad up/down: bet" : "Up/Down: bet"},
			{glyph: Back, label: "Leave table"}];
		hints.show(items, cx, 322);
		wallet.sovereigns = game.purse;
	}

	function choose(i:Int):Void {
		switch i {
			case 0: spin();
			case 1: leave();
			default:
		}
	}

	function spin():Void {
		if (!game.canBet(bet)) return;
		lastResult = game.spin(bet);
		spinsPlayed++;
		var names = [for (s in lastResult.symbols) '$s'];
		message = names.join(" - ") + (lastResult.multiplier > 0 ? '   Pays ${lastResult.multiplier}x: +${lastResult.payout}!' : "   No win.");
	}

	function leave():Void onLeave();

	function drawCabinet(w:Int):Void {
		cabinet.clear();
		cabinet.beginFill(0x2A1A10, 1);
		cabinet.drawRect(0, 0, w, FELT_H);
		cabinet.endFill();
	}

	function drawReels(cx:Float):Void {
		reels.clear();
		var boxW = 84.0, boxH = 60.0, gap = 10.0, total = boxW * 3 + gap * 2;
		var x0 = cx - total / 2, y = 120.0;
		for (i in 0...3) {
			var x = x0 + i * (boxW + gap);
			var s:Symbol = lastResult == null ? Blank : lastResult.symbols[i];
			reels.beginFill(symbolColor(s), 1);
			reels.lineStyle(2, TableKit.BRASS, .9);
			reels.drawRect(Math.round(x), Math.round(y), boxW, boxH);
			reels.endFill();
			reels.lineStyle();
			var t = reelLabels[i];
			t.text = lastResult == null ? "?" : '$s';
			t.x = Math.round(x + boxW / 2 - t.textWidth / 2);
			t.y = Math.round(y + boxH / 2 - t.textHeight / 2);
		}
	}

	static function symbolColor(s:Symbol):Int {
		return switch s {
			case Crown: 0xC8A35E;
			case Seven: 0xB8342A;
			case Bell: 0xD4AF37;
			case Bar: 0x8A8A8A;
			case Club | Spade: 0x1A1A1A;
			case Diamond | Heart: 0x8C2A2A;
			case Cherry: 0xB8342A;
			case Blank: 0x2A2A2A;
		}
	}
}
