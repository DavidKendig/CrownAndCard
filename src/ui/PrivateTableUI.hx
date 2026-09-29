// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import net.NetLink.LauncherLink;
import net.SessionControl;
import render.Palette;
import ui.ButtonGlyph;
import ui.TableKit;

private enum Stage {
	Menu;
	/** Typing a join code, or (for hosting over the internet) this PC's public address. **/
	Typing(forHost:Bool);
	Busy(message:String);
	Notice(message:String);
	Playing;
}

/**
	The Private Party table (§13.13): sitting at its empty chair and pressing
	E (or A) opens multiplayer. Host a table and share its join code, or join
	one with a code. The launcher carries the connection; while seated, the
	world waits behind a dimmed backdrop.
**/
class PrivateTableUI {
	public var open(default, null) = false;

	/** One line for the launcher's error reports, or "" when not seated. **/
	public var status(get, never):String;

	final root:h2d.Object;
	final shade:h2d.Graphics;
	final menu:h2d.Object;
	final panel:h2d.Graphics;
	final title:h2d.Text;
	final detail:h2d.Text;
	final choices:ChoiceRow;
	final hints:HintBar;
	final input = new MenuInput();
	final faces:CardFaces;
	final api:Null<String>;
	final control:Null<SessionControl>;
	var stage:Stage = Menu;
	var table:Null<NetPokerUI>;
	var typed = "";
	var skipInput = false;
	var clicked:Null<String> = null;

	/** Enter ("submit") or Escape ("back") while typing, from the key events. **/
	var keyAction = "";

	static final MENU = [
		{name: "Host a table", detail: "Texas Hold'em with friends on the same version of the game.\nYou deal; friends on your network join with the code you're given."},
		{name: "Host over the internet", detail: 'For friends elsewhere: forward TCP port 47724 on your router to\nthis PC, then give your public address so the join code points to it.'},
		{name: "Join a table", detail: "Type or paste the join code your host gave you."},
		{name: "Stand up", detail: "Step away from the table."},
	];

	public function new(parent:h2d.Object, palette:Palette, telemetry:Null<String>) {
		faces = new CardFaces(palette);
		api = LauncherLink.isLocal(telemetry) ? telemetry : null;
		control = api == null ? null : new SessionControl(api);
		root = new h2d.Object(parent);
		shade = new h2d.Graphics(root);
		menu = new h2d.Object(root);
		panel = new h2d.Graphics(menu);
		title = TableKit.text(menu, TableKit.GOLD);
		detail = TableKit.text(menu, TableKit.CREAM);
		choices = new ChoiceRow(menu, true);
		choices.onChoose = i -> clicked = currentOptions[i];
		hints = new HintBar(menu);
		root.visible = false;
		#if js
		// Typing a code: characters from the keyboard, or a whole code pasted with Ctrl+V.
		// Key events rather than per-frame key checks, so no key press is lost between frames.
		js.Browser.window.addEventListener("keydown", (e:js.html.KeyboardEvent) -> {
			if (!open || !stage.match(Typing(_)) || e.key == null) return;
			switch e.key {
				case "Enter": keyAction = "submit";
				case "Escape": keyAction = "back";
				case "Backspace": if (typed.length > 0) typed = typed.substr(0, typed.length - 1);
				default: if (e.key.length == 1 && !e.ctrlKey && !e.metaKey && !e.altKey) typeChar(e.key);
			}
		});
		js.Browser.window.addEventListener("paste", (e:Dynamic) -> {
			if (!open || !stage.match(Typing(_))) return;
			var text:String = e.clipboardData == null ? "" : e.clipboardData.getData("text");
			for (i in 0...text.length) typeChar(text.charAt(i));
		});
		// Closing the window ends the session (the table itself says goodbye first).
		js.Browser.window.addEventListener("pagehide", _ -> if (table != null && control != null) control.leave());
		#end
	}

	function get_status():String {
		if (!open) return "";
		return table != null ? table.status() : "private table: " + stage.getName().toLowerCase();
	}

	/** Sits down at the empty chair. The key press that opened it is ignored. **/
	public function show():Void {
		open = true;
		root.visible = true;
		skipInput = true;
		if (table == null) stage = Menu;
	}

	function stand():Void {
		open = false;
		root.visible = false;
	}

	var currentOptions:Array<String> = [];

	function typeChar(c:String):Void {
		var forHost = switch stage {
			case Typing(h): h;
			default: false;
		}
		var ok = forHost ? "0123456789.".indexOf(c) >= 0 : ~/^[0-9A-Za-z\- ]$/.match(c);
		if (ok && typed.length < 24) typed += forHost ? c : c.toUpperCase();
	}

	public function update(w:Int, dt:Float, pad:hxd.Pad):Void {
		if (!open) return;
		input.update(pad);
		if (skipInput) {
			input.clear();
			skipInput = false;
		}
		shade.clear();
		shade.beginFill(0x060812, table != null ? .8 : .55);
		shade.drawRect(0, 0, w, 360);
		shade.endFill();
		if (table != null) {
			menu.visible = false;
			table.update(w, dt, input);
			return;
		}
		menu.visible = true;
		var picked = clicked;
		clicked = null;
		switch stage {
			case Menu:
				if (control == null) {
					var p = draw(w, "THE PRIVATE TABLE", "Multiplayer tables need the Crown & Card launcher.\nStart the game with the launcher's PLAY button.", ["Stand up"], input, picked, true);
					if (input.back || p != null) stand();
					return;
				}
				var names = [for (m in MENU) m.name];
				var p = draw(w, "THE PRIVATE TABLE", MENU[choices.selected < MENU.length ? choices.selected : 0].detail, names, input, picked, true);
				if (input.back || p == "Stand up") stand();
				else if (p == "Host a table") host("");
				else if (p == "Host over the internet") startTyping(true);
				else if (p == "Join a table") startTyping(false);
			case Typing(forHost):
				var what = forHost ? "Your public IPv4 address (search \"what is my IP\"), like 203.0.113.7" : "The join code, like ABCD-EFGH-JKMN-PQRS";
				var shown = typed + (Std.int(haxe.Timer.stamp() * 2) % 2 == 0 ? "_" : " ");
				var go = forHost ? "Host" : "Join";
				var p = draw(w, forHost ? "HOST OVER THE INTERNET" : "JOIN A TABLE", '$what\n\n$shown\n\nType or paste it (Ctrl+V). Enter to ${go.toLowerCase()}, Esc to go back.', [go, "Back"], input, picked, false);
				var key = keyAction;
				keyAction = "";
				if (key == "back" || p == "Back" || (pad.connected && pad.isPressed(pad.config.B))) stage = Menu;
				else if (key == "submit" || p == go) {
					if (forHost) host(StringTools.trim(typed)) else join(StringTools.trim(typed));
				}
			case Busy(message):
				draw(w, "THE PRIVATE TABLE", message, [], input, picked, false);
			case Notice(message):
				var p = draw(w, "THE PRIVATE TABLE", message, ["OK"], input, picked, true);
				if (p != null || input.back) stage = Menu;
			case Playing:
		}
	}

	function startTyping(forHost:Bool):Void {
		typed = "";
		keyAction = "";
		stage = Typing(forHost);
	}

	// A session left over from an earlier page (a reload) is ended first: this game can only be at one table.
	function host(address:String):Void {
		stage = Busy("Opening the table…");
		control.leave(() -> control.host(address, (error, state) -> {
			if (error != null) stage = Notice(error);
			else seat(true, state.code);
		}));
	}

	function join(code:String):Void {
		if (code == "") return;
		stage = Busy("Finding the table…");
		control.leave(() -> control.join(code, (error, _) -> {
			if (error != null) stage = Notice(error);
			else seat(false, "");
		}));
	}

	/** In a session: open its table. Leaving it ends the session and stands the player up. **/
	function seat(isHost:Bool, code:String):Void {
		try {
			var t = new NetPokerUI(root, faces, new LauncherLink(api), isHost, "");
			t.joinCode = code;
			t.onLeave = () -> {
				t.dispose();
				table = null;
				control.leave();
				stage = Menu;
				stand();
			};
			table = t;
			stage = Playing;
			skipInput = true;
		} catch (e:Dynamic) {
			control.leave();
			stage = Notice('Multiplayer isn\'t available: $e');
		}
	}

	/** Lays out the panel and returns the choice made this frame (keys, pad or mouse). **/
	function draw(w:Int, heading:String, text:String, options:Array<String>, input:MenuInput, picked:Null<String>, keys:Bool):Null<String> {
		var cx = w / 2;
		if (options.join("|") != currentOptions.join("|")) {
			currentOptions = options;
			choices.set(options);
		}
		choices.visible = options.length > 0;
		// Keys and the pad choose through the row (its onChoose sets `clicked`), as a click does.
		if (keys && options.length > 0) choices.handle(input);
		var chosen = picked != null ? picked : clicked;
		clicked = null;
		var pw = Math.min(440, w - 24), top = 40.0, ph = 280.0;
		panel.clear();
		TableKit.panel(panel, cx - pw / 2, top, pw, ph, .92);
		title.text = heading;
		title.x = Math.round(cx - title.textWidth / 2);
		title.y = top + 10;
		detail.text = text;
		detail.maxWidth = pw - 28;
		detail.textAlign = Center;
		detail.x = Math.round(cx - detail.maxWidth / 2);
		detail.y = top + 30;
		// A fixed row position: the text above changes with the highlighted choice, and the row mustn't move under the mouse.
		choices.layout(cx, top + 34 + Math.max(2 * 12, detail.textHeight) + 16, 150);
		var items:Array<{glyph:Null<GlyphAction>, label:String}> = keys ? [{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Back"}] : [];
		hints.show(items, cx, top + ph - 18);
		return chosen;
	}
}
