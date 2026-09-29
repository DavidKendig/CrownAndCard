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
	final machine:SlotMachineArt;
	var resultMessage="";
	var shownPurse=0;
	final purseText:h2d.Text;
	final betText:h2d.Text;
	final messageText:h2d.Text;
	final plaqueText:h2d.Text;
	final choices:ChoiceRow;
	final hints:HintBar;

	var betIndex = 0;
	var lastResult:Null<SpinResult> = null;
	var message = "Drag the red grip down to pull the lever.";
	var spinsPlayed = 0;

	public function new(parent:h2d.Object, wallet:core.Wallet, rng:rng.IRng, palette:render.Palette) {
		super(parent);
		this.wallet = wallet;
		game = new Slots(rng, wallet.sovereigns);
		cabinet = new h2d.Graphics(this);
		machine = new SlotMachineArt(this,palette);
		machine.canPull=()->game.canBet(bet);
		machine.onPull=spin;
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
		machine.reset();
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
		machine.x=cx-20;machine.y=38;
		if(machine.update(dt)) message=resultMessage;

		purseText.text = 'Purse ${machine.spinning?shownPurse:game.purse} Sov' + (wallet.marker > 0 ? '   Marker ${wallet.marker}' : '');
		purseText.x = 6;
		purseText.y = 3;

		plaqueText.text = 'RTP ${Math.round(Slots.RTP * 1000) / 10}%';
		plaqueText.setScale(.6);
		plaqueText.textColor=0x21160C;
		plaqueText.x=Math.round(machine.x-plaqueText.textWidth*.3);
		plaqueText.y=197;


		messageText.text = message;
		messageText.maxWidth = Math.min(w - 24, 460);
		messageText.textAlign = Center;
		messageText.x = Math.round(cx - messageText.maxWidth / 2);
		messageText.y = 20;

		var affordable = game.canBet(bet);
		var opts = ["Pull the lever", "Leave table"];
		var busy=machine.spinning || machine.lever.held || machine.lever.latched;
		var usable = [affordable && !busy, !busy];
		choices.set(opts, usable);
		if (!busy && (input.up || input.down)) {
			betIndex = Std.int(Math.max(0, Math.min(Slots.BETS.length - 1, betIndex + (input.up ? 1 : -1))));
			clampBet();
		}
		if(!busy) choices.handle(input);
		choices.layout(cx, 312);
		if (input.back && !busy) leave();

		betText.text = 'Bet  < $bet >  Sovereigns';
		betText.x = Math.round(cx - betText.textWidth / 2);
		betText.y = 291;

		var items = [{glyph: Confirm, label: "Choose"}, {glyph: null, label: InputMode.usingPad ? "D-pad up/down: bet" : "Up/Down: bet"},
			{glyph: Back, label: "Leave table"}];
		hints.show(items, cx, 340);
		wallet.sovereigns = game.purse;
	}

	function choose(i:Int):Void {
		switch i {
			case 0: machine.pull();
			case 1: leave();
			default:
		}
	}

	function spin():Void {
		if (machine.spinning || !game.canBet(bet)) return;
		shownPurse=game.purse-bet;
		lastResult = game.spin(bet);
		spinsPlayed++;
		var names = [for (s in lastResult.symbols) '$s'];
		resultMessage = names.join(" - ") + (lastResult.multiplier > 0 ? '   Pays ${lastResult.multiplier}x: +${lastResult.payout}!' : "   No win.");
		machine.startSpin(lastResult.symbols);
		message="Reels spinning...";
	}

	function leave():Void {machine.cancelDrag();onLeave();}

	function drawCabinet(w:Int):Void {
		cabinet.clear();
		cabinet.beginFill(0x101524, 1);
		cabinet.drawRect(0, 0, w, FELT_H);
		cabinet.endFill();
	}

}
