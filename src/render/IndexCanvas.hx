// SPDX-License-Identifier: AGPL-3.0-or-later
package render;

import haxe.io.Bytes;

/**
	A grid of palette indices (Aseprite "indexed mode" in memory). Placeholder
	art is painted here in code; real art will be imported into the same form.
**/
class IndexCanvas {
	public final width:Int;
	public final height:Int;

	final data:Bytes;

	public function new(width:Int, height:Int) {
		this.width = width;
		this.height = height;
		data = Bytes.alloc(width * height);
		data.fill(0, width * height, 0);
	}

	public inline function get(x:Int, y:Int):Int {
		return (x < 0 || y < 0 || x >= width || y >= height) ? 0 : data.get(y * width + x);
	}

	public inline function set(x:Int, y:Int, index:Int):Void {
		if (x >= 0 && y >= 0 && x < width && y < height)
			data.set(y * width + x, index);
	}

	public function fillRect(x:Int, y:Int, w:Int, h:Int, index:Int):Void {
		for (yy in y...y + h)
			for (xx in x...x + w)
				set(xx, yy, index);
	}

	public function fillEllipse(cx:Float, cy:Float, rx:Float, ry:Float, index:Int):Void {
		for (yy in Math.floor(cy - ry)...Math.ceil(cy + ry) + 1)
			for (xx in Math.floor(cx - rx)...Math.ceil(cx + rx) + 1) {
				var dx = (xx + 0.5 - cx) / rx, dy = (yy + 0.5 - cy) / ry;
				if (dx * dx + dy * dy <= 1)
					set(xx, yy, index);
			}
	}

	/** A rect in one ramp, lit from the left: `lightStep` on the left edge down to `darkStep` on the right. **/
	public function shadedRect(x:Int, y:Int, w:Int, h:Int, ramp:Int, darkStep:Int, lightStep:Int):Void {
		for (xx in x...x + w) {
			var t = w <= 1 ? 0.0 : (xx - x) / (w - 1);
			var step = Math.round(lightStep + (darkStep - lightStep) * t);
			for (yy in y...y + h)
				set(xx, yy, Palette.index(ramp, step));
		}
	}

	/** An ellipse in one ramp, lit from the upper left. **/
	public function shadedEllipse(cx:Float, cy:Float, rx:Float, ry:Float, ramp:Int, darkStep:Int, lightStep:Int):Void {
		for (yy in Math.floor(cy - ry)...Math.ceil(cy + ry) + 1)
			for (xx in Math.floor(cx - rx)...Math.ceil(cx + rx) + 1) {
				var dx = (xx + 0.5 - cx) / rx, dy = (yy + 0.5 - cy) / ry;
				if (dx * dx + dy * dy <= 1) {
					var light = 1 - Math.min(1, Math.sqrt((dx + 0.5) * (dx + 0.5) + (dy + 0.5) * (dy + 0.5)) / 1.6);
					set(xx, yy, Palette.index(ramp, Math.round(darkStep + (lightStep - darkStep) * light)));
				}
			}
	}

	/** Darkens opaque pixels that touch transparency, giving sprites a crisp 1px outline. **/
	public function outline(step = 1):Void {
		var edges = [];
		for (y in 0...height)
			for (x in 0...width) {
				var i = get(x, y);
				if (i != 0 && (get(x - 1, y) == 0 || get(x + 1, y) == 0 || get(x, y - 1) == 0 || get(x, y + 1) == 0))
					edges.push(y * width + x);
			}
		for (p in edges) {
			var i = data.get(p);
			var s = Palette.stepOf(i) < step ? Palette.stepOf(i) : step;
			data.set(p, Palette.index(Palette.rampOf(i), s == 0 ? 1 : s));
		}
	}

	/** Build-style palette swap: every pixel in ramp `from` moves to ramp `to` at the same step. **/
	public function remapRamp(from:Int, to:Int):IndexCanvas {
		var out = copy();
		for (p in 0...width * height) {
			var i = data.get(p);
			if (i != 0 && Palette.rampOf(i) == from)
				out.data.set(p, Palette.index(to, Palette.stepOf(i)));
		}
		return out;
	}

	public function copy():IndexCanvas {
		var out = new IndexCanvas(width, height);
		out.data.blit(0, data, 0, width * height);
		return out;
	}

	/** Copies the opaque pixels of `src` onto this canvas at (dx, dy). **/
	public function blit(src:IndexCanvas, dx:Int, dy:Int):Void {
		for (y in 0...src.height)
			for (x in 0...src.width) {
				var i = src.get(x, y);
				if (i != 0)
					set(dx + x, dy + y, i);
			}
	}

	/**
		GPU form for the Build shader: the index in the red channel. With
		`transparentZero`, index 0 gets alpha 0 so sprites can cut out.
	**/
	public function toIndexTexture(transparentZero:Bool, repeat:Bool):h3d.mat.Texture {
		var tex = h3d.mat.Texture.fromPixels(toIndexPixels(transparentZero));
		tex.filter = Nearest;
		tex.wrap = repeat ? Repeat : Clamp;
		return tex;
	}

	public function toIndexPixels(transparentZero:Bool):hxd.Pixels {
		var px = hxd.Pixels.alloc(width, height, hxd.PixelFormat.RGBA);
		for (y in 0...height)
			for (x in 0...width) {
				var i = get(x, y);
				var alpha = (transparentZero && i == 0) ? 0 : 0xFF;
				px.setPixel(x, y, (alpha << 24) | (i << 16));
			}
		return px;
	}

	/** Full-brightness true color, for 2D layers (HUD hands, UI) that skip the shade table. **/
	public function toColorTile(palette:Palette):h2d.Tile {
		var tex = h3d.mat.Texture.fromPixels(toColorPixels(palette));
		tex.filter = Nearest;
		return h2d.Tile.fromTexture(tex);
	}

	public function toColorPixels(palette:Palette):hxd.Pixels {
		var px = hxd.Pixels.alloc(width, height, hxd.PixelFormat.RGBA);
		for (y in 0...height)
			for (x in 0...width) {
				var i = get(x, y);
				px.setPixel(x, y, i == 0 ? 0 : 0xFF000000 | palette.colors[i]);
			}
		return px;
	}
}
