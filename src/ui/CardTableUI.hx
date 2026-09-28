// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import games.poker.PokerTable.Variant;
import games.mahjong.MahjongGame.Variant as MahjongVariant;
import render.Palette;
import ui.ButtonGlyph;
import ui.TableKit;

/** A game the table can seat the player at. **/
private typedef Seat = {
	var view:h2d.Object;
	var sit:Void->Void;
	var update:(Int, Float, MenuInput) -> Void;
	var status:Void->String;
}

/**
	The Card Room table: stepping up to it and pressing E (or A) opens the
	game menu; choosing a game seats the player at it (GAME_DESIGN.md §4.3).
	While open, the world is paused behind a dimmed backdrop.
**/
class CardTableUI {
	public var open(get, never):Bool;

	/** One line for the launcher's error reports, or "" when not seated. **/
	public var status(get, never):String;

	public var onClose:Void->Void = () -> {};

	final root:h2d.Object;
	final shade:h2d.Graphics;
	final menu:h2d.Object;
	final menuPanel:h2d.Graphics;
	final menuTitle:h2d.Text;
	final menuDetail:h2d.Text;
	final menuChoices:ChoiceRow;
	final menuHints:HintBar;
	final gameLayer:h2d.Object;
	final input = new MenuInput();
	final palette:Palette;
	final faces:CardFaces;
	final wallet:core.Wallet;
	final master:rng.ChaChaRng;
	final seats = new Map<String, Seat>();
	var isOpen = false;
	var current:Null<Seat> = null;
	var skipInput = false;

	static final GAMES = [
		{name: "Blackjack", detail: "Six decks. Blackjack pays 3 to 2.\nDealer stands on all 17s. Bets 2 to 50."},
		{name: "Roulette", detail: "Single-zero wheel, La Partage on the\neven-money bets. Straight pays 35 to 1."},
		{name: "Craps", detail: "Pass, Don't Pass, Come, Field, Place\nand the props. Shake 'em and let fly."},
		{name: "Slots", detail: "One three-reel bandit. Its RTP is\nengraved on the brass plaque."},
		{name: "Texas Hold'em", detail: "No-limit, blinds 1 and 2, buy in for 100.\nWith the Deacon, the Colonel and Crake."},
		{name: "Five-card draw", detail: "No-limit, ante 1, draw up to three.\nWith Tuppence, Reggie and the Colonel."},
		{name: "Spades", detail: "You and Prof. Oyelaran against the\nVasquez twins. Nil and blind nil. To 500."},
		{name: "Go Fish", detail: "Ask for ranks, make books of four.\nMost books wins."},
		{name: "Slapjack", detail: "Turn cards to the middle; slap the jacks\nfirst to take the pile. Win every card."},
		{name: "War", detail: "You against Sir Reggie. Higher card\ntakes both; a tie means war."},
		{name: "Solitaire", detail: "Klondike, turning one card at a time.\nBuild every suit from ace to king."},
		{name: "Classic Mahjong", detail: "Hong Kong style with flowers and seasons.\nFaan scoring, one East round."},
		{name: "Riichi Mahjong", detail: "Japanese riichi: yaku, dora, han and fu.\nWRC rules, one East round, 25,000 start."},
		{name: "Stand up", detail: "Step away from the table."},
	];

	public function new(parent:h2d.Object, palette:Palette, wallet:core.Wallet, master:rng.ChaChaRng) {
		this.palette = palette;
		this.wallet = wallet;
		this.master = master;
		faces = new CardFaces(palette);
		root = new h2d.Object(parent);
		shade = new h2d.Graphics(root);
		gameLayer = new h2d.Object(root);
		menu = new h2d.Object(root);
		menuPanel = new h2d.Graphics(menu);
		menuTitle = TableKit.text(menu, TableKit.GOLD);
		menuDetail = TableKit.text(menu, TableKit.CREAM);
		menuChoices = new ChoiceRow(menu, true);
		menuChoices.set([for (g in GAMES) g.name]);
		menuChoices.onChoose = pick;
		menuHints = new HintBar(menu);
		root.visible = false;
	}

	function get_open():Bool return isOpen;

	function get_status():String {
		if (!isOpen) return "";
		return current == null ? "card table menu" : current.status();
	}

	/** Opens the game menu. The key press that opened it is ignored. **/
	public function show():Void {
		isOpen = true;
		current = null;
		root.visible = true;
		menu.visible = true;
		gameLayer.visible = false;
		skipInput = true;
	}

	/** Builds a game's screen the first time it's chosen; its shuffle and AI streams fork from the visit's key (§7.3). **/
	function seatFor(name:String):Null<Seat> {
		if (seats.exists(name)) return seats.get(name);
		function stream(kind:String) return master.fork('table/card-room/${name.toLowerCase()}/$kind');
		function screen(s:CardGameScreen):Seat {
			s.onLeave = show;
			return {view: s, sit: s.sit, update: s.update, status: s.status};
		}
		var seat:Seat = switch name {
			case "Blackjack":
				var b = new BlackjackTableUI(gameLayer, palette, faces, wallet, stream("shuffle"));
				b.onLeave = show;
				{view: b, sit: b.sit, update: b.update, status: () -> b.status};
			case "Roulette":
				var r = new RouletteTableUI(gameLayer, wallet, stream("outcome"));
				r.onLeave = show;
				{view: r, sit: r.sit, update: r.update, status: () -> r.status};
			case "Craps":
				var c = new CrapsTableUI(gameLayer, wallet, stream("outcome"));
				c.onLeave = show;
				{view: c, sit: c.sit, update: c.update, status: () -> c.status};
			case "Slots":
				var s = new SlotsTableUI(gameLayer, wallet, stream("outcome"));
				s.onLeave = show;
				{view: s, sit: s.sit, update: s.update, status: () -> s.status};
			case "Spades":
				var s = new SpadesTableUI(gameLayer, faces, stream("shuffle"));
				s.onLeave = show;
				{view: s, sit: s.sit, update: s.update, status: () -> s.status};
			case "Texas Hold'em": screen(new PokerTableUI(gameLayer, faces, Holdem, wallet, stream("shuffle"), stream("ai")));
			case "Five-card draw": screen(new PokerTableUI(gameLayer, faces, Draw, wallet, stream("shuffle"), stream("ai")));
			case "Go Fish": screen(new GoFishUI(gameLayer, faces, stream("shuffle"), stream("ai")));
			case "Slapjack": screen(new SlapjackUI(gameLayer, faces, stream("shuffle"), stream("ai")));
			case "War": screen(new WarUI(gameLayer, faces, stream("shuffle")));
			case "Solitaire": screen(new SolitaireUI(gameLayer, faces, stream("shuffle")));
			case "Classic Mahjong": screen(new MahjongUI(gameLayer, faces, tileFaces(), MahjongVariant.Classic, stream("shuffle")));
			case "Riichi Mahjong": screen(new MahjongUI(gameLayer, faces, tileFaces(), MahjongVariant.Riichi, stream("shuffle")));
			default: null;
		}
		if (seat != null) seats.set(name, seat);
		return seat;
	}

	var tiles:Null<TileFaces>;

	function tileFaces():TileFaces {
		if (tiles == null) tiles = new TileFaces(palette);
		return tiles;
	}

	function pick(i:Int):Void {
		var seat = seatFor(GAMES[i].name);
		if (seat == null) {
			close();
			return;
		}
		for (s in seats) s.view.visible = s == seat;
		seat.sit();
		current = seat;
		menu.visible = false;
		gameLayer.visible = true;
		skipInput = true;
	}

	function close():Void {
		isOpen = false;
		current = null;
		root.visible = false;
		onClose();
	}

	public function update(w:Int, dt:Float, pad:hxd.Pad):Void {
		if (!isOpen) return;
		input.update(pad);
		if (skipInput) {
			input.clear();
			skipInput = false;
		}
		shade.clear();
		shade.beginFill(0x060812, current == null ? .55 : .8);
		shade.drawRect(0, 0, w, 360);
		shade.endFill();
		if (current != null) current.update(w, dt, input);
		else updateMenu(w);
	}

	function updateMenu(w:Int):Void {
		var cx = w / 2;
		menuChoices.handle(input);
		if (current != null || !isOpen) return;
		if (input.back) {
			close();
			return;
		}
		var pw = Math.min(360, w - 24), top = 22.0, ph = 316.0;
		menuPanel.clear();
		TableKit.panel(menuPanel, cx - pw / 2, top, pw, ph, .9);
		menuTitle.text = "THE CARD TABLE";
		menuTitle.x = Math.round(cx - menuTitle.textWidth / 2);
		menuTitle.y = top + 8;
		menuChoices.layout(cx, top + 26, 140);
		menuDetail.text = GAMES[menuChoices.selected].detail;
		menuDetail.maxWidth = pw - 24;
		menuDetail.textAlign = Center;
		menuDetail.x = Math.round(cx - menuDetail.maxWidth / 2);
		menuDetail.y = top + 26 + menuChoices.height + 8;
		menuHints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Stand up"}], cx, top + ph - 20);
	}
}
