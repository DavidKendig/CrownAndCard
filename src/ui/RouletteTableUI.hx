// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import games.roulette.Roulette;
import ui.ButtonGlyph;
import ui.TableKit;

private enum Mode {
	Menu;
	PickSide;
	NumberPick;
	PickAmount;
}

/**
	Seated roulette view (§5.7, §6.4): single-zero wheel with La Partage.
	Straight-up numbers are picked on a real 0-36 layout grid with the pad;
	the other inside shapes (split, street, corner, six-line, basket) are
	supported by `games.roulette.Roulette` and tested, but wait on a
	mouse-driven racetrack UI (a later pass) to be offered here.

	Bets are staked as chips on the felt and don't leave the purse until the
	wheel actually spins (§7.7: the pocket is chosen first, the wheel and
	ball are choreographed to it — this table shows the landed pocket rather
	than animating the spin).
**/
class RouletteTableUI extends h2d.Object {
	static inline var FELT_H = 360;
	static final BETS = [1, 5, 10, 25, 50, 100, 250];

	static final OUTSIDE = ["Red", "Black", "Odd", "Even", "Low (1-18)", "High (19-36)", "1st Dozen", "2nd Dozen", "3rd Dozen", "1st Column",
		"2nd Column", "3rd Column", "Cancel"];

	public var onLeave:Void->Void = () -> {};

	/** One line for the launcher's error reports. **/
	public var status(get, never):String;

	final game:Roulette;
	final wallet:core.Wallet;
	final felt:h2d.Graphics;
	final gridLayer:h2d.Object;
	final gridGraphics:h2d.Graphics;
	final gridLabels:Array<h2d.Text>;
	final gridHits:Array<h2d.Interactive>;
	final resultGfx:h2d.Graphics;
	final resultLabel:h2d.Text;
	final purseText:h2d.Text;
	final messageText:h2d.Text;
	final betsText:h2d.Text;
	final choices:ChoiceRow;
	final amountChoices:ChoiceRow;
	final hints:HintBar;

	var mode:Mode = Menu;
	var category = "";
	var pendingKind:games.roulette.Roulette.BetKind = Red;
	var pendingGroup = 0;
	var pendingNumber = 0;
	var cursorRow = -1; // -1 selects the 0
	var cursorCol = 0;
	var betIndex = 2;
	var menuOptions:Array<String> = [];
	var pendingBets:Array<games.roulette.Roulette.Bet> = [];
	var lastResult:Null<games.roulette.Roulette.SpinResult> = null;
	var message = "Place your bets, then spin.";
	var spinsPlayed = 0;

	public function new(parent:h2d.Object, wallet:core.Wallet, rng:rng.IRng) {
		super(parent);
		this.wallet = wallet;
		game = new Roulette(rng, wallet.sovereigns);
		felt = new h2d.Graphics(this);
		gridLayer = new h2d.Object(this);
		gridGraphics = new h2d.Graphics(gridLayer);
		gridLabels = [for (n in 0...37) TableKit.text(gridLayer, 0xFFFFFF)];
		gridHits = [
			for (n in 0...37) {
				var h = new h2d.Interactive(1, 1, gridLayer);
				h.cursor = Button;
				var row = n == 0 ? -1 : Std.int((n - 1) / 3);
				var col = n == 0 ? 0 : (n - 1) % 3;
				h.onClick = _ -> {
					cursorRow = row;
					cursorCol = col;
					chooseNumber();
				};
				h;
			}
		];
		resultGfx = new h2d.Graphics(this);
		resultLabel = TableKit.text(this, TableKit.GOLD);
		purseText = TableKit.text(this, TableKit.GOLD);
		messageText = TableKit.text(this, TableKit.CREAM);
		betsText = TableKit.text(this, TableKit.CREAM);
		choices = new ChoiceRow(this, true);
		choices.onChoose = choose;
		amountChoices = new ChoiceRow(this);
		amountChoices.onChoose = i -> if (i == 0) placePendingBet(BETS[betIndex]) else mode = Menu;
		hints = new HintBar(this);
	}

	function get_status():String return 'roulette purse ${available()} spins $spinsPlayed';

	public function sit():Void {
		game.seatPurse(wallet.sovereigns);
		pendingBets = [];
		mode = Menu;
	}

	public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		drawFelt(w);
		gridLayer.visible = mode == NumberPick;
		drawResult(w);

		purseText.text = 'Purse ${available()} Sov' + (wallet.marker > 0 ? '   Marker ${wallet.marker}' : '');
		purseText.x = 6;
		purseText.y = 3;

		messageText.text = mode == PickAmount ? amountLine() : message;
		messageText.maxWidth = Math.min(w - 90, 380);
		messageText.textAlign = Center;
		messageText.x = Math.round(cx - messageText.maxWidth / 2);
		messageText.y = 20;

		betsText.visible = mode == Menu || mode == PickAmount;
		betsText.text = betsSummary();
		betsText.maxWidth = Math.min(w - 24, 460);
		betsText.textAlign = Center;
		betsText.x = Math.round(cx - betsText.maxWidth / 2);
		betsText.y = 316;

		switch mode {
			case Menu: updateMenu(cx, input);
			case PickSide: updatePickSide(cx, input);
			case NumberPick: updateNumberPick(cx, input);
			case PickAmount: updatePickAmount(cx, input);
		}
		wallet.sovereigns = game.purse;
	}

	function totalPending():Int {
		var t = 0;
		for (b in pendingBets) t += b.amount;
		return t;
	}

	function available():Int return game.purse - totalPending();

	// --- Menu levels -----------------------------------------------------

	function updateMenu(cx:Float, input:MenuInput):Void {
		choices.visible = true;
		amountChoices.visible = false;
		menuOptions = ["Straight number", "Outside bet", "Spin the wheel", "Clear bets", "Leave table"];
		choices.set(menuOptions);
		choices.layout(cx, 44, 170);
		choices.handle(input);
		hints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Leave table"}], cx, 340);
		if (input.back) leave();
	}

	function updatePickSide(cx:Float, input:MenuInput):Void {
		choices.visible = true;
		amountChoices.visible = false;
		choices.set(OUTSIDE);
		choices.layout(cx, 20, 150);
		choices.handle(input);
		hints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Cancel"}], cx, 340);
		if (input.back) mode = Menu;
	}

	function updateNumberPick(cx:Float, input:MenuInput):Void {
		choices.visible = false;
		amountChoices.visible = false;
		if (input.left) cursorCol = cursorRow < 0 ? cursorCol : (cursorCol + 2) % 3;
		if (input.right) cursorCol = cursorRow < 0 ? cursorCol : (cursorCol + 1) % 3;
		if (input.up) cursorRow = cursorRow <= -1 ? -1 : cursorRow - 1;
		if (input.down) cursorRow = cursorRow >= 11 ? 11 : cursorRow + 1;
		drawGrid(cx);
		message = 'Number  < ${cursorNumber()} >';
		hints.show([{glyph: null, label: "Arrows or click: move"}, {glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Cancel"}], cx, 340);
		if (input.confirm) chooseNumber();
		else if (input.back) mode = Menu;
	}

	function chooseNumber():Void {
		pendingNumber = cursorNumber();
		category = "Straight";
		mode = PickAmount;
	}

	function updatePickAmount(cx:Float, input:MenuInput):Void {
		choices.visible = false;
		amountChoices.visible = true;
		if (input.up) betIndex = Std.int(Math.min(BETS.length - 1, betIndex + 1));
		if (input.down) betIndex = Std.int(Math.max(0, betIndex - 1));
		while (betIndex > 0 && BETS[betIndex] > available()) betIndex--;
		amountChoices.set(["Place bet", "Cancel"]);
		amountChoices.layout(cx, 130);
		amountChoices.handle(input);
		hints.show([{glyph: null, label: InputMode.usingPad ? "D-pad up/down: bet" : "Up/Down: bet"}, {glyph: Confirm, label: "Place bet"},
			{glyph: Back, label: "Cancel"}], cx, 340);
		if (input.back) mode = Menu;
	}

	function cursorNumber():Int return cursorRow < 0 ? 0 : cursorRow * 3 + cursorCol + 1;

	function choose(i:Int):Void {
		switch mode {
			case Menu: chooseMenu(menuOptions[i]);
			case PickSide: chooseOutside(OUTSIDE[i]);
			case NumberPick, PickAmount:
		}
	}

	function chooseMenu(label:String):Void {
		switch label {
			case "Straight number":
				category = "Straight";
				mode = NumberPick;
			case "Outside bet":
				mode = PickSide;
			case "Spin the wheel":
				doSpin();
			case "Clear bets":
				pendingBets = [];
				message = "Bets cleared.";
			case "Leave table":
				leave();
			default:
		}
	}

	function chooseOutside(label:String):Void {
		if (label == "Cancel") {
			mode = Menu;
			return;
		}
		pendingGroup = 0;
		switch label {
			case "Red": pendingKind = Red;
			case "Black": pendingKind = Black;
			case "Odd": pendingKind = Odd;
			case "Even": pendingKind = Even;
			case "Low (1-18)": pendingKind = Low;
			case "High (19-36)": pendingKind = High;
			case "1st Dozen": pendingKind = Dozen; pendingGroup = 1;
			case "2nd Dozen": pendingKind = Dozen; pendingGroup = 2;
			case "3rd Dozen": pendingKind = Dozen; pendingGroup = 3;
			case "1st Column": pendingKind = Column; pendingGroup = 1;
			case "2nd Column": pendingKind = Column; pendingGroup = 2;
			case "3rd Column": pendingKind = Column; pendingGroup = 3;
			default:
		}
		category = "Outside";
		mode = PickAmount;
	}

	function placePendingBet(amount:Int):Void {
		if (amount > available()) {
			message = "Not enough left in your purse.";
			mode = Menu;
			return;
		}
		var bet = category == "Straight" ? Roulette.straight(pendingNumber, amount) : pendingKind == Dozen ? Roulette.dozen(pendingGroup, amount) :
			pendingKind == Column ? Roulette.column(pendingGroup, amount) : Roulette.outside(pendingKind, amount);
		pendingBets.push(bet);
		message = "Bet added to the layout.";
		mode = Menu;
	}

	function amountLine():String {
		var context = category == "Straight" ? ' on straight $pendingNumber' : " on " + outsideLabel();
		return 'Bet  < ${BETS[betIndex]} >  Sovereigns$context';
	}

	function outsideLabel():String {
		return switch pendingKind {
			case Dozen: '${ordinal(pendingGroup)} dozen';
			case Column: '${ordinal(pendingGroup)} column';
			case Low: "1-18";
			case High: "19-36";
			case k: Std.string(k);
		}
	}

	function doSpin():Void {
		if (pendingBets.length == 0) {
			message = "Place a bet before you spin.";
			return;
		}
		var staked = totalPending();
		lastResult = game.spin(pendingBets);
		pendingBets = [];
		spinsPlayed++;
		var net = lastResult.payout - staked;
		var color = lastResult.pocket == 0 ? "" : Roulette.isRed(lastResult.pocket) ? " red" : " black";
		message = 'The ball falls in ${lastResult.pocket}$color. ' + (net > 0 ? 'You win $net.' : net < 0 ? 'You lose ${-net}.' : "Push.");
	}

	function leave():Void {
		pendingBets = [];
		onLeave();
	}

	function betsSummary():String {
		if (pendingBets.length == 0) return "No bets on the layout.";
		return [for (b in pendingBets) betLabel(b)].join("   ") + '   (total ${totalPending()})';
	}

	function betLabel(b:games.roulette.Roulette.Bet):String {
		return switch b.kind {
			case Straight: 'Straight ${b.numbers[0]}: ${b.amount}';
			case Split: 'Split ${b.numbers[0]}-${b.numbers[1]}: ${b.amount}';
			case Street: 'Street ${b.numbers[0]}-${b.numbers[2]}: ${b.amount}';
			case Corner: 'Corner ${b.numbers[0]}: ${b.amount}';
			case SixLine: 'Six Line ${b.numbers[0]}: ${b.amount}';
			case Dozen: '${ordinal(b.group)} Dozen: ${b.amount}';
			case Column: '${ordinal(b.group)} Column: ${b.amount}';
			case Red: 'Red: ${b.amount}';
			case Black: 'Black: ${b.amount}';
			case Odd: 'Odd: ${b.amount}';
			case Even: 'Even: ${b.amount}';
			case Low: 'Low: ${b.amount}';
			case High: 'High: ${b.amount}';
		}
	}

	static function ordinal(n:Int):String {
		return switch n {
			case 1: "1st";
			case 2: "2nd";
			case 3: "3rd";
			default: '${n}th';
		}
	}

	// --- Drawing -----------------------------------------------------------

	function drawFelt(w:Int):Void {
		felt.clear();
		felt.beginFill(0x0B3D24, 1);
		felt.drawRect(0, 0, w, FELT_H);
		felt.endFill();
	}

	function drawResult(w:Int):Void {
		resultGfx.clear();
		resultLabel.visible = false;
		if (lastResult == null) return;
		var n = lastResult.pocket;
		var color = n == 0 ? 0x0B5D2E : Roulette.isRed(n) ? 0x8C2A2A : 0x1A1A1A;
		var size = 30.0, x = w - size - 10, y = 4.0;
		resultGfx.beginFill(color, 1);
		resultGfx.lineStyle(1, TableKit.GOLD, 1);
		resultGfx.drawRect(Math.round(x), Math.round(y), size, size);
		resultGfx.endFill();
		resultGfx.lineStyle();
		resultLabel.text = '$n';
		resultLabel.visible = true;
		resultLabel.x = Math.round(x + size / 2 - resultLabel.textWidth / 2);
		resultLabel.y = Math.round(y + size / 2 - resultLabel.textHeight / 2);
	}

	function drawGrid(cx:Float):Void {
		var x0 = cx - 90, y0 = 108.0, cellW = 60.0, cellH = 14.0;
		gridGraphics.clear();
		cellRect(x0, y0 - 16, 180, 16, cellColor(0), cursorRow < 0);
		gridLabels[0].text = "0";
		gridLabels[0].visible = true;
		gridLabels[0].x = Math.round(cx - gridLabels[0].textWidth / 2);
		gridLabels[0].y = Math.round(y0 - 16 + 2);
		placeHit(gridHits[0], x0, y0 - 16, 180, 16);
		for (row in 0...12) for (col in 0...3) {
			var n = row * 3 + col + 1;
			var x = x0 + col * cellW, y = y0 + row * cellH;
			cellRect(x, y, cellW, cellH, cellColor(n), cursorRow == row && cursorCol == col);
			var t = gridLabels[n];
			t.text = '$n';
			t.visible = true;
			t.x = Math.round(x + cellW / 2 - t.textWidth / 2);
			t.y = Math.round(y + 1);
			placeHit(gridHits[n], x, y, cellW, cellH);
		}
	}

	function placeHit(hit:h2d.Interactive, x:Float, y:Float, w:Float, h:Float):Void {
		hit.x = Math.round(x);
		hit.y = Math.round(y);
		hit.width = w;
		hit.height = h;
	}

	static function cellColor(n:Int):Int return n == 0 ? 0x0B5D2E : Roulette.isRed(n) ? 0x8C2A2A : 0x1A1A1A;

	function cellRect(x:Float, y:Float, w:Float, h:Float, fill:Int, selected:Bool):Void {
		gridGraphics.beginFill(fill, 1);
		gridGraphics.lineStyle(1, selected ? TableKit.GOLD : 0x3A3A3A, 1);
		gridGraphics.drawRect(Math.round(x) + .5, Math.round(y) + .5, w - 1, h - 1);
		gridGraphics.endFill();
		gridGraphics.lineStyle();
	}
}
