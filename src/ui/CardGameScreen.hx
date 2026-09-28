// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import ui.ButtonGlyph;
import ui.TableKit;

typedef Hint = {glyph:Null<GlyphAction>, label:String};

/**
	Shared frame for the seated card-game screens (§5.7): a table surface,
	pooled card bitmaps, labels and click areas redrawn each frame, one row
	of choices (in a panel when there's a title), button hints, and the
	"leave the table?" check.

	A screen's update() calls begin(), draws and decides, then end().
**/
class CardGameScreen extends h2d.Object {
	public var onLeave:Void->Void = () -> {};

	final faces:CardFaces;
	final bg:h2d.Graphics;
	final cardLayer:h2d.Object;
	final textLayer:h2d.Object;
	final hitLayer:h2d.Object;
	final panel:h2d.Graphics;
	final panelTitle:h2d.Text;
	final panelBody:h2d.Text;
	final choices:ChoiceRow;
	final hints:HintBar;
	final bitmaps:Array<h2d.Bitmap> = [];
	final texts:Array<h2d.Text> = [];
	final hits:Array<h2d.Interactive> = [];
	final hitIds:Array<Int> = [];
	var usedBitmaps = 0;
	var usedTexts = 0;
	var usedHits = 0;
	var options:Array<String> = [];
	var picked:Null<String> = null;

	/** Id of the click area clicked since the last frame, or -1. **/
	var clicked = -1;

	/** Id of the click area under the mouse, or -1. **/
	var hovered = -1;

	var title = "";
	var body = "";
	var hintItems:Array<Hint> = [];
	var confirmLeave = false;
	var screenW = 640;

	public function new(parent:h2d.Object, faces:CardFaces) {
		super(parent);
		this.faces = faces;
		bg = new h2d.Graphics(this);
		cardLayer = new h2d.Object(this);
		hitLayer = new h2d.Object(this);
		textLayer = new h2d.Object(this);
		panel = new h2d.Graphics(this);
		panelTitle = TableKit.text(this, TableKit.GOLD);
		panelBody = TableKit.text(this, TableKit.CREAM);
		choices = new ChoiceRow(this);
		choices.onChoose = i -> picked = options[i];
		hints = new HintBar(this);
	}

	/** One line for the launcher's error reports. **/
	public function status():String return "";

	/** Called each time the player sits down at this game. **/
	public function sit():Void {}

	public function update(w:Int, dt:Float, input:MenuInput):Void {}

	/** Starts a frame: draws the table (felt inside a wooden rim) and resets the pools. **/
	function begin(w:Int, felt = 0x173A26, rim = 0x3A2416):Void {
		screenW = w;
		bg.clear();
		bg.beginFill(0x1B120C);
		bg.drawRect(0, 0, w, 360);
		bg.endFill();
		bg.beginFill(rim);
		bg.drawRect(4, 4, w - 8, 352);
		bg.endFill();
		bg.beginFill(felt);
		bg.lineStyle(1, TableKit.BRASS, 1);
		bg.drawRect(12.5, 12.5, w - 25, 335);
		bg.endFill();
		bg.lineStyle();
		usedBitmaps = usedTexts = usedHits = 0;
		title = body = "";
		hintItems = [];
		options = [];
	}

	function card(tile:h2d.Tile, x:Float, y:Float, dim = false):h2d.Bitmap {
		var b = usedBitmaps < bitmaps.length ? bitmaps[usedBitmaps] : {
			var nb = new h2d.Bitmap(null, cardLayer);
			bitmaps.push(nb);
			nb;
		}
		usedBitmaps++;
		cardLayer.addChild(b); // keeps draw order = call order
		b.tile = tile;
		b.x = Math.round(x);
		b.y = Math.round(y);
		b.visible = true;
		if (dim) b.color.set(.5, .5, .55, 1) else b.color.set(1, 1, 1, 1);
		return b;
	}

	/** A line of text; `align` 0 left of x, 1 centered on x, 2 right of x. **/
	function label(text:String, x:Float, y:Float, color = TableKit.CREAM, align = 0):h2d.Text {
		var t = usedTexts < texts.length ? texts[usedTexts] : {
			var nt = TableKit.text(textLayer);
			texts.push(nt);
			nt;
		}
		usedTexts++;
		t.visible = true;
		t.text = text;
		t.textColor = color;
		t.x = Math.round(align == 1 ? x - t.textWidth / 2 : align == 2 ? x - t.textWidth : x);
		t.y = Math.round(y);
		return t;
	}

	/** A clickable area reporting `id` through `clicked` / `hovered`. **/
	function hit(id:Int, x:Float, y:Float, w:Float, h:Float):Void {
		var i = usedHits++;
		if (i >= hits.length) {
			var nh = new h2d.Interactive(1, 1, hitLayer);
			nh.cursor = Button;
			nh.onOver = _ -> hovered = hitIds[i];
			nh.onOut = _ -> if (hovered == hitIds[i]) hovered = -1;
			nh.onClick = _ -> clicked = hitIds[i];
			hits.push(nh);
			hitIds.push(id);
		}
		hitIds[i] = id;
		var h2 = hits[i];
		h2.visible = true;
		h2.x = Math.round(x);
		h2.y = Math.round(y);
		h2.width = w;
		h2.height = h;
	}

	/** Takes the click since last frame (and forgets it). **/
	function takeClick():Int {
		var c = clicked;
		clicked = -1;
		return c;
	}

	/** Offers a row of choices this frame; returns the one picked (keys, pad or mouse), if any. **/
	function offer(opts:Array<String>, input:MenuInput):Null<String> {
		options = opts;
		choices.set(opts);
		var p = picked;
		picked = null;
		if (p != null && opts.indexOf(p) >= 0) return p;
		if (opts.length > 0) choices.handle(input);
		p = picked;
		picked = null;
		return p;
	}

	function hint(glyph:Null<GlyphAction>, text:String):Void hintItems.push({glyph: glyph, label: text});

	/**
		The "leave the table?" check. Returns true while it's showing, or when
		the player just left, so the screen skips its own input this frame.
		`inProgress` false means leaving needs no confirmation.
	**/
	function leaveCheck(input:MenuInput, inProgress:Bool, warning:String, ?extra:String):Bool {
		if (confirmLeave) {
			title = "LEAVE THE TABLE?";
			body = warning;
			var opts = ["Stay"];
			if (extra != null) opts.push(extra);
			opts.push("Leave");
			var p = offer(opts, input);
			hint(Confirm, "Choose");
			hint(Back, "Stay");
			if (p == "Stay" || input.back) confirmLeave = false;
			else if (p == "Leave") {
				confirmLeave = false;
				leave();
			} else if (p != null) {
				confirmLeave = false;
				onExtra(p);
			}
			return true;
		}
		if (input.back) {
			if (inProgress) confirmLeave = true else leave();
			return true;
		}
		return false;
	}

	/** Called when the player leaves; screens cash out here. **/
	function leave():Void onLeave();

	function onExtra(choice:String):Void {}

	/** Finishes a frame: panel and choices, hints, and hides unused pool items. **/
	function end(cx:Float, rowY = 300.0):Void {
		panel.clear();
		var showPanel = title != "";
		panelTitle.visible = panelBody.visible = showPanel;
		choices.visible = options.length > 0;
		if (showPanel) {
			panelTitle.text = title;
			panelBody.text = body;
			panelBody.textAlign = Center;
			panelBody.maxWidth = null;
			var pw = Math.min(screenW - 24, Math.max(260, Math.max(panelTitle.textWidth, panelBody.textWidth) + 32));
			panelBody.maxWidth = pw - 24;
			var ph = 30 + (body == "" ? 0 : panelBody.textHeight) + (options.length > 0 ? 30 : 8);
			var top = Math.round(Math.max(24, 150 - ph / 2));
			TableKit.panel(panel, cx - pw / 2, top, pw, ph, .93);
			panelTitle.x = Math.round(cx - panelTitle.textWidth / 2);
			panelTitle.y = top + 8;
			panelBody.x = Math.round(cx - panelBody.maxWidth / 2);
			panelBody.y = top + 24;
			choices.layout(cx, top + ph - 24);
		} else choices.layout(cx, rowY);
		if (options.length > 0 && hintItems.length == 0) hint(Confirm, "Choose");
		var hasBack = false;
		for (h in hintItems) if (h.glyph == Back) hasBack = true;
		if (!hasBack) hint(Back, "Leave table");
		hints.show(hintItems, cx, 340);
		for (i in usedBitmaps...bitmaps.length) bitmaps[i].visible = false;
		for (i in usedTexts...texts.length) texts[i].visible = false;
		for (i in usedHits...hits.length) hits[i].visible = false;
	}

	/** Face-down stack drawn as a short pile, with its count underneath. **/
	function pile(count:Int, x:Float, y:Float, showCount = true):Void {
		if (count == 0) {
			bg.lineStyle(1, 0x6E5A34, .8);
			bg.drawRect(Math.round(x) + .5, Math.round(y) + .5, CardFaces.W - 1, CardFaces.H - 1);
			bg.lineStyle();
		}
		for (k in 0...Std.int(Math.min(4, Math.ceil(count / 8)))) card(faces.back(), x - k, y - k);
		if (showCount) label('$count', x + CardFaces.W / 2, y + CardFaces.H + 2, TableKit.DIM, 1);
	}

	static function cardName(c:cards.Card):String {
		var rank = switch c.rank {
			case cards.Card.JACK: "jack";
			case cards.Card.QUEEN: "queen";
			case cards.Card.KING: "king";
			case cards.Card.ACE: "ace";
			case r: Std.string(r);
		}
		var suit = switch c.suit {
			case Clubs: "clubs";
			case Diamonds: "diamonds";
			case Hearts: "hearts";
			case Spades: "spades";
		}
		return 'the $rank of $suit';
	}

	static function rankPlural(r:Int):String {
		return switch r {
			case 6: "sixes";
			case 11: "jacks";
			case 12: "queens";
			case 13: "kings";
			case 14: "aces";
			default: '${r}s';
		}
	}
}
