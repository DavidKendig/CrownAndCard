// SPDX-License-Identifier: AGPL-3.0-or-later
package art;

import render.IndexCanvas;
import render.Palette;

/** In-game art review: includes the player body before mirrors are implemented. */
class SpritePreview extends h2d.Object {
	final sheets:Array<h2d.Tile>;
	final actor:h2d.Bitmap;
	final label:h2d.Text;
	final toggle:h2d.Object;
	var selection = 0;
	var angle = 0;
	var animationTime = 0.0;
	static final NAMES = ["Player", "Male guest standing", "Female guest standing", "Male staff", "Female staff",
		"Male guest seated", "Female guest seated", "Male guest walking", "Female guest walking"];

	public function new(art:Map<String, IndexCanvas>, palette:Palette, parent:h2d.Object) {
		super(parent);
		sheets = [for (id in SpriteArt.CHARACTERS) art.get(id).toColorTile(palette)];
		var bg = new h2d.Graphics(this);
		bg.beginFill(0x090d1b, 0.97);
		bg.drawRect(0, 0, 280, 280);
		bg.endFill();
		actor = new h2d.Bitmap(null, this);
		actor.setScale(2);
		actor.y = 22;
		label = new h2d.Text(hxd.res.DefaultFont.get(), this);
		label.x = 8;
		label.y = 248;
		label.textColor = 0xE8D8A8;
		button(this, "C: Next", 8, 264, () -> next());
		button(this, "R: Rotate", 92, 264, () -> nextAngle());
		button(this, "F2: Close", 184, 264, () -> visible = false);
		toggle = new h2d.Object(parent);
		toggle.x = 6;
		toggle.y = 338;
		button(toggle, "F2: Sprites", 0, 0, () -> visible = !visible);
		visible = false;
		refresh();
	}

	function refresh() {
		var frame = angle <= 4 ? angle : 8 - angle;
		var id = SpriteArt.CHARACTERS[selection];
		var w = SpriteArt.frameWidth(id), h = SpriteArt.frameHeight(id);
		var row = Std.int(animationTime * 4.375) % SpriteArt.animationRows(id);
		var scale = 128 / SpriteArt.density(id);
		actor.tile = sheets[selection].sub(frame * w, row * h, w, h);
		actor.scaleX = angle <= 4 ? scale : -scale;
		actor.scaleY = scale;
		actor.x = 140 + (angle <= 4 ? -1 : 1) * w * scale / 2;
		actor.y = 246 - h * scale;
		label.text = '${NAMES[selection]}  ${angle + 1}/8';
	}

	static function button(parent:h2d.Object, text:String, x:Int, y:Int, action:Void->Void) {
		var label = new h2d.Text(hxd.res.DefaultFont.get(), parent);
		label.text = text;
		label.textColor = 0xE8D8A8;
		label.setPosition(x, y);
		label.dropShadow = {dx: 1, dy: 1, color: 0, alpha: 1};
		var hit = new h2d.Interactive(label.textWidth, 16, label);
		hit.onClick = _ -> action();
	}

	function next() {
		selection = (selection + 1) % sheets.length;
		refresh();
	}

	function nextAngle() {
		angle = (angle + 1) % 8;
		refresh();
	}

	public function update(width:Int, dt:Float) {
		if (hxd.Key.isPressed(hxd.Key.F2)) visible = !visible;
		if (!visible) return;
		animationTime += dt;
		if (SpriteArt.animationRows(SpriteArt.CHARACTERS[selection]) > 1) refresh();
		x = Math.floor((width - 280) / 2);
		y = 60;
		if (hxd.Key.isPressed(hxd.Key.C)) {
			next();
		}
		if (hxd.Key.isPressed(hxd.Key.R)) {
			nextAngle();
		}
	}
}

