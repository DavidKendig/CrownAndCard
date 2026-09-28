// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import games.craps.Craps;
import ui.ButtonGlyph;
import ui.TableKit;

private enum Mode {
	Menu;
	PickSide;
	PickNumber;
	PickAmount;
}

/**
	Seated craps view (§5.7, §6.4): Pass/Don't Pass with 3-4-5x odds,
	Come/Don't Come, Field, Place, Hardways and the one-roll props, all
	placed through a short menu tree since there's no mouse-driven layout
	board yet. The dice are shown resolved, not tumbling (§7.7: the RNG
	decides the roll first; only the choreography is future work).
**/
class CrapsTableUI extends h2d.Object {
	static inline var FELT_H = 360;
	static final BETS = [1, 5, 10, 25, 50, 100, 250];

	public var onLeave:Void->Void = () -> {};

	/** One line for the launcher's error reports. **/
	public var status(get, never):String;

	final game:Craps;
	final wallet:core.Wallet;
	final felt:h2d.Graphics;
	final dice:h2d.Graphics;
	final purseText:h2d.Text;
	final pointText:h2d.Text;
	final messageText:h2d.Text;
	final betsText:h2d.Text;
	final choices:ChoiceRow;
	final amountChoices:ChoiceRow;
	final hints:HintBar;

	var mode:Mode = Menu;
	var category = "";
	var pendingSide = "";
	var pendingNumber = 0;
	var betIndex = 2;
	var menuOptions:Array<String> = [];
	var sideOptions:Array<String> = [];
	var numberOptions:Array<String> = [];
	var lastRoll:Null<RollResult> = null;
	var message = "Place your bets, then roll the dice.";
	var rollsPlayed = 0;

	public function new(parent:h2d.Object, wallet:core.Wallet, rng:rng.IRng) {
		super(parent);
		this.wallet = wallet;
		game = new Craps(rng, wallet.sovereigns);
		felt = new h2d.Graphics(this);
		dice = new h2d.Graphics(this);
		purseText = TableKit.text(this, TableKit.GOLD);
		pointText = TableKit.text(this, TableKit.CREAM);
		messageText = TableKit.text(this, TableKit.GOLD);
		betsText = TableKit.text(this, TableKit.CREAM);
		choices = new ChoiceRow(this, true);
		choices.onChoose = choose;
		amountChoices = new ChoiceRow(this);
		amountChoices.onChoose = i -> if (i == 0) placePendingBet(BETS[betIndex]) else mode = Menu;
		hints = new HintBar(this);
	}

	function get_status():String {
		var where = game.point == null ? "come-out" : 'point ${game.point}';
		return 'craps $where purse ${game.purse} rolls $rollsPlayed';
	}

	public function sit():Void {
		game.seatPurse(wallet.sovereigns);
		mode = Menu;
	}

	public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		drawFelt(w);
		drawDice(cx);

		purseText.text = 'Purse ${game.purse} Sov' + (wallet.marker > 0 ? '   Marker ${wallet.marker}' : '');
		purseText.x = 6;
		purseText.y = 3;
		pointText.text = game.point == null ? "Come-out roll" : 'Point is ${game.point}';
		pointText.x = Math.round(cx - pointText.textWidth / 2);
		pointText.y = 3;

		messageText.text = mode == PickAmount ? amountLine() : message;
		messageText.maxWidth = Math.min(w - 24, 460);
		messageText.textAlign = Center;
		messageText.x = Math.round(cx - messageText.maxWidth / 2);
		messageText.y = 60;

		betsText.text = betsSummary();
		betsText.maxWidth = Math.min(w - 24, 460);
		betsText.textAlign = Center;
		betsText.x = Math.round(cx - betsText.maxWidth / 2);
		betsText.y = 88;

		switch mode {
			case Menu: updateMenu(cx, input);
			case PickSide: updatePickSide(cx, input);
			case PickNumber: updatePickNumber(cx, input);
			case PickAmount: updatePickAmount(cx, input);
		}
		wallet.sovereigns = game.purse;
	}

	// --- Menu levels -----------------------------------------------------

	function updateMenu(cx:Float, input:MenuInput):Void {
		choices.visible = true;
		amountChoices.visible = false;
		menuOptions = menuItems();
		choices.set(menuOptions);
		choices.layout(cx, 116, 170);
		choices.handle(input);
		hints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Leave table"}], cx, 340);
		if (input.back) leaveWithRefund();
	}

	function updatePickSide(cx:Float, input:MenuInput):Void {
		choices.visible = true;
		amountChoices.visible = false;
		choices.set(sideOptions);
		choices.layout(cx, 116, 170);
		choices.handle(input);
		hints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Cancel"}], cx, 340);
		if (input.back) mode = Menu;
	}

	function updatePickNumber(cx:Float, input:MenuInput):Void {
		choices.visible = true;
		amountChoices.visible = false;
		choices.set(numberOptions);
		choices.layout(cx, 116, 90);
		choices.handle(input);
		hints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Cancel"}], cx, 340);
		if (input.back) mode = Menu;
	}

	function updatePickAmount(cx:Float, input:MenuInput):Void {
		choices.visible = false;
		amountChoices.visible = true;
		if (input.up) betIndex = Std.int(Math.min(BETS.length - 1, betIndex + 1));
		if (input.down) betIndex = Std.int(Math.max(0, betIndex - 1));
		while (betIndex > 0 && BETS[betIndex] > game.purse) betIndex--;
		amountChoices.set(["Place bet", "Cancel"]);
		amountChoices.layout(cx, 130);
		amountChoices.handle(input);
		hints.show([{glyph: null, label: InputMode.usingPad ? "D-pad up/down: bet" : "Up/Down: bet"}, {glyph: Confirm, label: "Place bet"},
			{glyph: Back, label: "Cancel"}], cx, 340);
		if (input.back) mode = Menu;
	}

	function menuItems():Array<String> {
		var items = [];
		if (game.point == null) items.push("Line bet");
		else {
			if (game.passLine > 0 && game.passOdds < game.passLine * Craps.maxOddsMultiple(game.point)) items.push("Odds (Pass)");
			if (game.dontPass > 0 && game.dontPassOdds < game.dontPass * Craps.maxOddsMultiple(game.point)) items.push("Odds (Don't Pass)");
			items.push("Come / Don't Come");
		}
		items.push("Field");
		items.push("Place a number");
		items.push("Hardway");
		items.push("Proposition");
		items.push("Roll the dice");
		items.push("Leave table");
		return items;
	}

	function choose(i:Int):Void {
		switch mode {
			case Menu: chooseMenu(menuOptions[i]);
			case PickSide: chooseSide(sideOptions[i]);
			case PickNumber: chooseNumber(numberOptions[i]);
			case PickAmount:
		}
	}

	function chooseMenu(label:String):Void {
		switch label {
			case "Line bet":
				category = "Line";
				sideOptions = ["Pass Line", "Don't Pass", "Cancel"];
				mode = PickSide;
			case "Odds (Pass)":
				category = "OddsPass";
				mode = PickAmount;
			case "Odds (Don't Pass)":
				category = "OddsDontPass";
				mode = PickAmount;
			case "Come / Don't Come":
				category = "ComeType";
				sideOptions = ["Come", "Don't Come", "Cancel"];
				mode = PickSide;
			case "Field":
				category = "Field";
				mode = PickAmount;
			case "Place a number":
				category = "Place";
				numberOptions = ["4", "5", "6", "8", "9", "10", "Cancel"];
				mode = PickNumber;
			case "Hardway":
				category = "Hardway";
				numberOptions = ["4", "6", "8", "10", "Cancel"];
				mode = PickNumber;
			case "Proposition":
				category = "Prop";
				sideOptions = ["Any Seven", "Any Craps", "Yo", "Hi-Lo", "Cancel"];
				mode = PickSide;
			case "Roll the dice":
				doRoll();
			case "Leave table":
				leaveWithRefund();
			default:
		}
	}

	function chooseSide(label:String):Void {
		if (label == "Cancel") {
			mode = Menu;
			return;
		}
		pendingSide = label;
		mode = PickAmount;
	}

	function chooseNumber(label:String):Void {
		if (label == "Cancel") {
			mode = Menu;
			return;
		}
		pendingNumber = Std.parseInt(label);
		mode = PickAmount;
	}

	function placePendingBet(amount:Int):Void {
		try {
			switch category {
				case "Line":
					if (pendingSide == "Pass Line") game.betPassLine(amount) else game.betDontPass(amount);
				case "OddsPass":
					game.betPassOdds(amount);
				case "OddsDontPass":
					game.betDontPassOdds(amount);
				case "ComeType":
					if (pendingSide == "Come") game.betCome(amount) else game.betDontCome(amount);
				case "Field":
					game.betField(amount);
				case "Place":
					game.betPlace(pendingNumber, amount);
				case "Hardway":
					game.betHardway(pendingNumber, amount);
				case "Prop":
					switch pendingSide {
						case "Any Seven": game.betAnySeven(amount);
						case "Any Craps": game.betAnyCraps(amount);
						case "Yo": game.betYo(amount);
						case "Hi-Lo": game.betHiLo(amount);
						default:
					}
				default:
			}
			message = "Bet placed.";
		} catch (e:Dynamic) {
			message = Std.string(e);
		}
		mode = Menu;
	}

	function amountLine():String {
		var context = switch category {
			case "Line": ' on $pendingSide';
			case "OddsPass": " odds on the Pass line";
			case "OddsDontPass": " odds on Don't Pass";
			case "ComeType": ' on $pendingSide';
			case "Field": " on the Field";
			case "Place": ' on Place $pendingNumber';
			case "Hardway": ' on Hard $pendingNumber';
			case "Prop": ' on $pendingSide';
			default: "";
		}
		return 'Bet  < ${BETS[betIndex]} >  Sovereigns$context';
	}

	function doRoll():Void {
		if (!anyWagerOnTable()) {
			message = "Place a bet before you roll.";
			return;
		}
		lastRoll = game.roll();
		rollsPlayed++;
		message = lastRoll.events.length > 0 ? lastRoll.events.join(" ") : "Nothing resolves on that roll.";
	}

	function anyWagerOnTable():Bool {
		if (game.passLine > 0 || game.dontPass > 0 || game.field > 0 || game.comePending > 0 || game.dontComePending > 0 || game.anySeven > 0
			|| game.anyCraps > 0 || game.yo > 0 || game.hiLo > 0 || game.come.length > 0 || game.dontCome.length > 0)
			return true;
		for (n in game.place.keys()) if (game.place.get(n) > 0) return true;
		for (n in game.hardway.keys()) if (game.hardway.get(n) > 0) return true;
		return false;
	}

	function leaveWithRefund():Void {
		game.leaveTable();
		wallet.sovereigns = game.purse;
		onLeave();
	}

	function betsSummary():String {
		var parts = [];
		if (game.passLine > 0) parts.push('Pass ${game.passLine}' + (game.passOdds > 0 ? '+${game.passOdds} odds' : ""));
		if (game.dontPass > 0) parts.push('Don\'t Pass ${game.dontPass}' + (game.dontPassOdds > 0 ? '+${game.dontPassOdds} odds' : ""));
		for (b in game.come) parts.push('Come ${b.point}:${b.amount}' + (b.odds > 0 ? '+${b.odds}' : ""));
		for (b in game.dontCome) parts.push('Don\'t Come ${b.point}:${b.amount}' + (b.odds > 0 ? '+${b.odds}' : ""));
		if (game.field > 0) parts.push('Field ${game.field}');
		for (n in [4, 5, 6, 8, 9, 10]) if (game.place.get(n) > 0) parts.push('Place $n:${game.place.get(n)}');
		for (n in [4, 6, 8, 10]) if (game.hardway.get(n) > 0) parts.push('Hard $n:${game.hardway.get(n)}');
		if (game.anySeven > 0) parts.push('Any 7:${game.anySeven}');
		if (game.anyCraps > 0) parts.push('Any Craps:${game.anyCraps}');
		if (game.yo > 0) parts.push('Yo:${game.yo}');
		if (game.hiLo > 0) parts.push('Hi-Lo:${game.hiLo}');
		return parts.length == 0 ? "No bets on the table." : parts.join("   ");
	}

	// --- Drawing -----------------------------------------------------------

	function drawFelt(w:Int):Void {
		felt.clear();
		felt.beginFill(0x0B3D24, 1);
		felt.drawRect(0, 0, w, FELT_H);
		felt.endFill();
		felt.lineStyle(2, TableKit.BRASS, .6);
		felt.drawRect(20, 112, w - 40, 100);
		felt.lineStyle();
	}

	function drawDice(cx:Float):Void {
		dice.clear();
		if (lastRoll == null) return;
		var size = 28.0, gap = 10.0;
		drawDie(cx - size - gap / 2, 132, size, lastRoll.die1);
		drawDie(cx + gap / 2, 132, size, lastRoll.die2);
	}

	function drawDie(x:Float, y:Float, size:Float, value:Int):Void {
		dice.beginFill(0xF4EFE0, 1);
		dice.lineStyle(1, 0x1A1622, 1);
		dice.drawRect(Math.round(x), Math.round(y), size, size);
		dice.endFill();
		dice.lineStyle();
		dice.beginFill(0x1A1622, 1);
		for (p in pips(value)) dice.drawCircle(x + size * p.fx, y + size * p.fy, size * .08);
		dice.endFill();
	}

	static function pips(value:Int):Array<{fx:Float, fy:Float}> {
		return switch value {
			case 1: [{fx: .5, fy: .5}];
			case 2: [{fx: .25, fy: .25}, {fx: .75, fy: .75}];
			case 3: [{fx: .25, fy: .25}, {fx: .5, fy: .5}, {fx: .75, fy: .75}];
			case 4: [{fx: .25, fy: .25}, {fx: .75, fy: .25}, {fx: .25, fy: .75}, {fx: .75, fy: .75}];
			case 5: [{fx: .25, fy: .25}, {fx: .75, fy: .25}, {fx: .5, fy: .5}, {fx: .25, fy: .75}, {fx: .75, fy: .75}];
			case 6: [{fx: .25, fy: .2}, {fx: .75, fy: .2}, {fx: .25, fy: .5}, {fx: .75, fy: .5}, {fx: .25, fy: .8}, {fx: .75, fy: .8}];
			default: [];
		}
	}
}
