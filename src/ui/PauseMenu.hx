// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import core.Settings;
import ui.ButtonGlyph;
import ui.TableKit;

private enum Page {
	Top;
	Options;
	ConfirmQuit;
}

/** One line on the settings page. `step` gets +1 or -1; a two-way choice flips either way. **/
private typedef Item = {label:String, key:String, value:Void->String, step:Int->Void};

/**
	The game menu (§11.4), over the paused world: Esc in fullscreen (in a
	window, Esc first frees the mouse, then opens it), or Start on a controller.

	- Resume, Settings, or Quit the game (after a confirmation).
	- Settings take effect at once (Main applies each through `onChange`) and
	  are handed to the launcher when the settings page closes (`onSave`), so
	  the next visit starts with them.
	- Keyboard: arrows or WASD choose and change, Enter picks, Esc goes back.
	  Controller: d-pad or left stick, A picks, B goes back, Start resumes.
	  Mouse: point, click the < > arrows, or click a setting to change it.
**/
class PauseMenu {
	static inline var ROW_H = 15;

	public var open(default, null) = false;

	/** The player confirmed Quit the game. **/
	public var onQuit:Void->Void = () -> {};

	/** A setting changed; the argument is its option key (see Settings.fromOptions). **/
	public var onChange:String->Void = _ -> {};

	/** The settings page closed after changes: time to save them. **/
	public var onSave:Void->Void = () -> {};

	/** A line shown in place of the button hints while something takes a moment. **/
	public var notice = "";

	final settings:Settings;
	final root:h2d.Object;
	final shade:h2d.Graphics;
	final blocker:h2d.Interactive;
	final panel:h2d.Graphics;
	final highlight:h2d.Graphics;
	final heading:h2d.Text;
	final detail:h2d.Text;
	final topChoices:ChoiceRow;
	final quitChoices:ChoiceRow;
	final hints:HintBar;
	final items:Array<Item>;
	final labels:Array<h2d.Text> = [];
	final values:Array<h2d.Text> = [];
	final rowHits:Array<h2d.Interactive> = [];
	final lessHits:Array<h2d.Interactive> = [];
	final moreHits:Array<h2d.Interactive> = [];
	final input = new MenuInput();
	var page = Top;
	var selected = 0;
	var changed = false;

	public function new(parent:h2d.Object, settings:Settings) {
		this.settings = settings;
		var s = settings;
		items = [
			flip("Display", "fullscreen", () -> s.fullscreen ? "Fullscreen" : "Windowed", () -> s.fullscreen = !s.fullscreen),
			flip("Pixel scaling (in a window)", "scaling", () -> s.scaling == Integer ? "Whole-number" : "Fill the window",
				() -> s.scaling = s.scaling == Integer ? Fit : Integer),
			flip("Render resolution", "renderHeight", () -> s.renderHeight == 720 ? "720 lines" : "480 lines",
				() -> s.renderHeight = s.renderHeight == 720 ? 480 : 720),
			range("Field of view", "fov", () -> '${s.fov} degrees', d -> s.fov = clamp(s.fov + d * 5, 70, 110)),
			range("Head bob and sway", "headBob", () -> '${s.headBob}%', d -> s.headBob = clamp(s.headBob + d * 10, 0, 100)),
			flip("Looking up and down", "lookStyle", () -> s.lookStyle == Shear ? "Classic (shear)" : "Modern (perspective)",
				() -> s.lookStyle = s.lookStyle == Shear ? Perspective : Shear),
			range("Mouse sensitivity", "mouseSensitivity", () -> '${s.mouseSensitivity}%',
				d -> s.mouseSensitivity = clamp(s.mouseSensitivity + d * 10, 25, 300)),
			flip("Show frame rate", "showFps", () -> s.showFps ? "On" : "Off", () -> s.showFps = !s.showFps),
			range("Master volume", "masterVolume", () -> '${s.masterVolume}%', d -> s.masterVolume = clamp(s.masterVolume + d * 10, 0, 100)),
			range("Music", "musicVolume", () -> '${s.musicVolume}%', d -> s.musicVolume = clamp(s.musicVolume + d * 10, 0, 100)),
			range("Effects", "effectsVolume", () -> '${s.effectsVolume}%', d -> s.effectsVolume = clamp(s.effectsVolume + d * 10, 0, 100)),
			range("Voices", "voiceVolume", () -> '${s.voiceVolume}%', d -> s.voiceVolume = clamp(s.voiceVolume + d * 10, 0, 100)),
			flip("Mute in the background", "muteInBackground", () -> s.muteInBackground ? "On" : "Off",
				() -> s.muteInBackground = !s.muteInBackground),
		];

		root = new h2d.Object(parent);
		shade = new h2d.Graphics(root);
		// Swallows clicks so nothing under the menu reacts.
		blocker = new h2d.Interactive(640, 360, root);
		panel = new h2d.Graphics(root);
		highlight = new h2d.Graphics(root);
		heading = TableKit.text(root, TableKit.GOLD);
		detail = TableKit.text(root, TableKit.CREAM);
		topChoices = new ChoiceRow(root, true);
		topChoices.onChoose = i -> switch (i) {
			case 0: close();
			case 1: showOptions();
			case 2: showQuit();
			default:
		};
		quitChoices = new ChoiceRow(root);
		quitChoices.onChoose = i -> if (i == 1) onQuit() else showTop(2);
		hints = new HintBar(root);
		// Rows and their < > arrows; the arrows go on top so they get the click.
		for (i in 0...items.length + 1) {
			labels.push(TableKit.text(root));
			values.push(TableKit.text(root));
			var row = new h2d.Interactive(10, ROW_H, root);
			row.cursor = Button;
			row.onOver = _ -> selected = i;
			row.onClick = _ -> if (i < items.length) change(i, 1) else leaveOptions();
			rowHits.push(row);
		}
		for (i in 0...items.length) {
			var less = new h2d.Interactive(24, ROW_H, root), more = new h2d.Interactive(24, ROW_H, root);
			less.cursor = more.cursor = Button;
			less.onOver = more.onOver = _ -> selected = i;
			less.onClick = _ -> change(i, -1);
			more.onClick = _ -> change(i, 1);
			lessHits.push(less);
			moreHits.push(more);
		}
		root.visible = false;
	}

	static function flip(label:String, key:String, value:Void->String, toggle:Void->Void):Item
		return {label: label, key: key, value: value, step: _ -> toggle()};

	static function range(label:String, key:String, value:Void->String, step:Int->Void):Item
		return {label: label, key: key, value: value, step: step};

	static function clamp(v:Int, min:Int, max:Int):Int
		return v < min ? min : v > max ? max : v;

	/** Opens on the top page. `pad` is read once so a held stick or button doesn't count as a choice. **/
	public function show(pad:hxd.Pad):Void {
		open = true;
		root.visible = true;
		input.update(pad);
		input.clear();
		showTop(0);
	}

	public function close():Void {
		open = false;
		root.visible = false;
	}

	function showTop(highlighted:Int):Void {
		page = Top;
		topChoices.set(["Resume", "Settings", "Quit the game"]);
		topChoices.selected = highlighted;
	}

	function showOptions():Void {
		page = Options;
		selected = 0;
	}

	function leaveOptions():Void {
		if (changed) {
			changed = false;
			onSave();
		}
		showTop(1);
	}

	function showQuit():Void {
		page = ConfirmQuit;
		quitChoices.set(["Stay", "Quit"]);
		quitChoices.selected = 0;
	}

	function change(i:Int, direction:Int):Void {
		var item = items[i];
		var before = item.value();
		item.step(direction);
		if (item.value() != before) {
			changed = true;
			onChange(item.key);
		}
	}

	/** Call every frame; `w` is the view's width in internal pixels. **/
	public function update(w:Int, pad:hxd.Pad):Void {
		if (!open) return;
		input.update(pad);
		var start = pad.connected && pad.isPressed(pad.config.start);
		switch (page) {
			case Top:
				topChoices.handle(input);
				if (open && page == Top && (input.back || start)) close();
			case Options:
				var count = items.length + 1;
				if (input.up) selected = (selected + count - 1) % count;
				if (input.down) selected = (selected + 1) % count;
				if (selected < items.length) {
					if (input.left) change(selected, -1);
					if (input.right || input.confirm) change(selected, 1);
				} else if (input.confirm) leaveOptions();
				if (page == Options && (input.back || start)) {
					leaveOptions();
					if (start) close();
				}
			case ConfirmQuit:
				quitChoices.handle(input);
				if (page == ConfirmQuit && input.back) showTop(2);
				else if (page == ConfirmQuit && start) close();
		}
		if (open) layout(w);
	}

	function layout(w:Int):Void {
		shade.clear();
		shade.beginFill(0x080B16, .62);
		shade.drawRect(0, 0, w, 360);
		shade.endFill();
		blocker.width = w;
		panel.clear();
		highlight.clear();
		var onOptions = page == Options;
		topChoices.visible = page == Top;
		quitChoices.visible = page == ConfirmQuit;
		detail.visible = page == ConfirmQuit;
		for (i in 0...labels.length) {
			labels[i].visible = values[i].visible = onOptions;
			rowHits[i].visible = onOptions;
		}
		for (i in 0...items.length) lessHits[i].visible = moreHits[i].visible = onOptions;
		heading.textAlign = Center;
		switch (page) {
			case Top:
				var pw = 240.0, ph = 118.0, left = (w - pw) / 2, top = 104.0;
				TableKit.panel(panel, left, top, pw, ph);
				heading.text = "GAME MENU";
				heading.maxWidth = pw - 24;
				heading.x = left + 12;
				heading.y = top + 12;
				topChoices.layout(w / 2, top + 34, 150);
				hints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Resume"}], w / 2, top + ph + 8);
			case ConfirmQuit:
				var pw = Math.min(360.0, w - 24), ph = 112.0, left = (w - pw) / 2, top = 110.0;
				TableKit.panel(panel, left, top, pw, ph);
				heading.text = "QUIT THE GAME?";
				heading.maxWidth = pw - 24;
				heading.x = left + 12;
				heading.y = top + 14;
				detail.text = "Leave Dodriec Manor and close the game?\nOnly your last check-in with Mr. Quill is saved.";
				detail.maxWidth = pw - 32;
				detail.textAlign = Center;
				detail.x = left + 16;
				detail.y = top + 36;
				quitChoices.layout(w / 2, top + ph - 30, 80);
				hints.show([{glyph: Confirm, label: "Choose"}, {glyph: Back, label: "Back"}], w / 2, top + ph + 8);
			case Options:
				var rows = items.length + 1;
				var pw = Math.min(400.0, w - 24), ph = 36.0 + rows * ROW_H + 8, left = (w - pw) / 2, top = Math.round((360 - ph) / 2) - 8;
				TableKit.panel(panel, left, top, pw, ph);
				heading.text = "SETTINGS";
				heading.maxWidth = pw - 24;
				heading.x = left + 12;
				heading.y = top + 10;
				var valueCenter = left + pw - 86, y0 = top + 32;
				for (i in 0...rows) {
					var y = y0 + i * ROW_H, sel = i == selected;
					if (sel) {
						highlight.beginFill(0x3A2A10, .95);
						highlight.lineStyle(1, TableKit.GOLD, 1);
						highlight.drawRect(Math.round(left + 8) + .5, y - 1.5, Math.round(pw - 16), ROW_H - 1);
						highlight.endFill();
						highlight.lineStyle();
					}
					var label = labels[i], value = values[i];
					var color = sel ? TableKit.GOLD : TableKit.CREAM;
					label.textColor = color;
					value.textColor = color;
					value.textAlign = Center;
					value.maxWidth = 150;
					if (i < items.length) {
						label.text = items[i].label;
						label.x = left + 16;
						value.text = sel ? '<  ${items[i].value()}  >' : items[i].value();
						value.x = valueCenter - 75;
					} else {
						label.text = "";
						value.text = "Back";
						value.x = w / 2 - 75;
					}
					label.y = value.y = y;
					var hit = rowHits[i];
					hit.x = left + 8;
					hit.y = y - 2;
					hit.width = pw - 16;
					if (i < items.length) {
						// Over the drawn < and >, which sit either side of the value, however wide it is.
						var half = value.calcTextWidth('<  ${items[i].value()}  >') / 2;
						lessHits[i].x = valueCenter - half - 6;
						moreHits[i].x = valueCenter + half - 18;
						lessHits[i].y = moreHits[i].y = y - 2;
					}
				}
				var pad = InputMode.usingPad;
				hints.show(notice != "" ? [{glyph: null, label: notice}] : [
					{glyph: null, label: pad ? "D-pad: choose and change" : "Arrows: choose and change"},
					{glyph: Back, label: "Back"},
				], w / 2, top + ph + 8);
		}
	}
}
