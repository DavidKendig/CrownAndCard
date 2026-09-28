// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import ui.ButtonGlyph;

/** Shared look for the seated-table screens: brass on navy, like the entrance dialogs. **/
class TableKit {
	public static inline var GOLD = 0xF4DBA5;
	public static inline var CREAM = 0xEFE6D2;
	public static inline var DIM = 0x9C927C;
	public static inline var GOOD = 0xA8E0A0;
	public static inline var BAD = 0xF09080;
	public static inline var BRASS = 0xC8A35E;
	public static inline var PANEL = 0x101524;

	public static function text(parent:h2d.Object, color:Int = CREAM):h2d.Text {
		var t = new h2d.Text(hxd.res.DefaultFont.get(), parent);
		t.textColor = color;
		t.dropShadow = {dx: 1, dy: 1, color: 0x000000, alpha: 1};
		return t;
	}

	/** A translucent navy panel with a brass rule, as used by the entrance dialogs. **/
	public static function panel(g:h2d.Graphics, x:Float, y:Float, w:Float, h:Float, alpha = .86):Void {
		g.beginFill(PANEL, alpha);
		g.lineStyle(1, BRASS, .9);
		g.drawRect(Math.round(x) + .5, Math.round(y) + .5, Math.round(w), Math.round(h));
		g.endFill();
		g.lineStyle();
	}
}

/**
	A row (or column) of choices: arrow keys, the d-pad or the stick move the
	highlight; E / A picks it; the mouse can hover and click.
**/
class ChoiceRow extends h2d.Object {
	public var selected = 0;
	public var onChoose:Int->Void = _ -> {};

	final vertical:Bool;
	final bg:h2d.Graphics;
	var labels:Array<String> = [];
	var enabled:Array<Bool> = [];
	final texts:Array<h2d.Text> = [];
	final hits:Array<h2d.Interactive> = [];
	var widths:Array<Float> = [];

	public function new(parent:h2d.Object, vertical = false) {
		super(parent);
		this.vertical = vertical;
		bg = new h2d.Graphics(this);
	}

	/** Replaces the choices when they change; keeps the highlight on a usable one. **/
	public function set(options:Array<String>, ?usable:Array<Bool>):Void {
		var on = usable == null ? [for (_ in options) true] : usable;
		if (options.join("|") != labels.join("|") || on.join("|") != enabled.join("|")) {
			var keep = selected < labels.length ? labels[selected] : null;
			labels = options.copy();
			enabled = on.copy();
			for (t in texts) t.remove();
			for (h in hits) h.remove();
			texts.resize(0);
			hits.resize(0);
			for (i in 0...labels.length) {
				texts.push(TableKit.text(this));
				var hit = new h2d.Interactive(10, 10, this);
				hit.cursor = Button;
				hit.onOver = _ -> if (enabled[i]) selected = i;
				hit.onClick = _ -> if (enabled[i]) {
					selected = i;
					onChoose(i);
				};
				hits.push(hit);
			}
			var again = keep == null ? -1 : labels.indexOf(keep);
			selected = again >= 0 && enabled[again] ? again : first();
		}
	}

	function first():Int {
		for (i in 0...enabled.length) if (enabled[i]) return i;
		return 0;
	}

	public function handle(input:MenuInput):Void {
		if (labels.length == 0) return;
		var step = vertical ? (input.up ? -1 : input.down ? 1 : 0) : (input.left ? -1 : input.right ? 1 : 0);
		if (step != 0) for (_ in 0...labels.length) {
			selected = (selected + step + labels.length) % labels.length;
			if (enabled[selected]) break;
		}
		if (input.confirm && enabled[selected]) onChoose(selected);
	}

	/** Lays the buttons out centered on `cx`, starting at `y`. **/
	public function layout(cx:Float, y:Float, minWidth = 0.0):Void {
		bg.clear();
		var h = 17.0, gap = 6.0;
		widths = [for (t in texts) Math.max(minWidth, t.textWidth + 16)];
		if (vertical) {
			var w = 0.0;
			for (v in widths) w = Math.max(w, v);
			for (i in 0...widths.length) widths[i] = w;
		}
		var total = 0.0;
		for (v in widths) total += v;
		total += gap * Math.max(0, widths.length - 1);
		var x = vertical ? cx - widths[0] / 2 : cx - total / 2, yy = y;
		for (i in 0...texts.length) {
			var w = widths[i], sel = i == selected && enabled[i];
			var bx = Math.round(x), by = Math.round(yy);
			bg.beginFill(sel ? 0x3A2A10 : 0x0C1020, sel ? .95 : .8);
			bg.lineStyle(1, sel ? 0xF4DBA5 : 0x6E5A34, 1);
			bg.drawRect(bx + .5, by + .5, w, h);
			bg.endFill();
			bg.lineStyle();
			var t = texts[i];
			t.text = labels[i];
			t.textColor = !enabled[i] ? 0x5A5448 : sel ? TableKit.GOLD : TableKit.CREAM;
			t.x = Math.round(bx + (w - t.textWidth) / 2);
			t.y = by + Math.round((h - t.textHeight) / 2);
			hits[i].x = bx;
			hits[i].y = by;
			hits[i].width = w;
			hits[i].height = h;
			if (vertical) yy += h + 4 else x += w + gap;
		}
	}

	public var height(get, never):Float;

	function get_height():Float return vertical ? labels.length * 21 : 17;
}

/** A centered line of button prompts: glyph, label, glyph, label... **/
class HintBar extends h2d.Object {
	var key = "";

	public function new(parent:h2d.Object) {
		super(parent);
	}

	/** `items` pairs a glyph (or null for a plain note) with its label. **/
	public function show(items:Array<{glyph:Null<GlyphAction>, label:String}>, cx:Float, y:Float):Void {
		var pad = InputMode.usingPad;
		var k = pad + "|" + [for (i in items) (i.glyph == null ? "-" : Std.string(cast i.glyph)) + i.label].join("|");
		if (k != key) {
			key = k;
			removeChildren();
			var x = 0.0;
			for (i in items) {
				if (i.glyph != null) {
					var b = new h2d.Bitmap(ButtonGlyph.tile(i.glyph, pad), this);
					b.x = x;
					x += b.tile.width + 4;
				}
				var t = TableKit.text(this, TableKit.CREAM);
				t.text = i.label;
				t.x = x;
				t.y = Math.round((ButtonGlyph.HEIGHT - t.textHeight) / 2);
				x += t.textWidth + 12;
			}
			width = x - 12;
		}
		this.x = Math.round(cx - width / 2);
		this.y = Math.round(y);
	}

	var width = 0.0;
}
