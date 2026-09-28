// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

/** Authored table art, snapped to the master palette on the 360p pixel grid. */
class TableSurface extends h2d.Bitmap {
	static final tiles = new Map<String, h2d.Tile>();
	public function new(name:String, parent:h2d.Object) {
		var tile = tiles.get(name);
		if (tile == null) try {
			var px = hxd.Res.load('tabletops/$name.png').toImage().getPixels(hxd.PixelFormat.RGBA);
			var palette = new render.Palette();
			var colors = new Map<Int, Int>();
			for (y in 0...px.height) for (x in 0...px.width) {
				var c = px.getPixel(x, y) & 0xFFFFFF;
				if (!colors.exists(c)) colors.set(c, 0xFF000000 | palette.colors[palette.nearest((c >> 16) & 255, (c >> 8) & 255, c & 255, 1)]);
				px.setPixel(x, y, colors.get(c));
			}
			var texture = h3d.mat.Texture.fromPixels(px);
			texture.filter = Nearest;
			tile = h2d.Tile.fromTexture(texture);
			tiles.set(name, tile);
		}
		catch (error:Dynamic) {
			trace("Tabletop " + name + ": " + Std.string(error) + "\n" + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
			throw error;
		}
		super(tile, parent);
	}

	public function fit(w:Int):Void {
		scaleX = w / tile.width;
		scaleY = 360 / tile.height;
	}
}
