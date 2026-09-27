// SPDX-License-Identifier: AGPL-3.0-or-later
package render;

/**
	Renders the 3D world into a fixed-height 360-pixel target and shows it
	scaled up with nearest-neighbor sampling (§5.2), so every on-screen pixel
	is the same size. Width follows the window's aspect ratio.
**/
class LowResView {
	public static inline var HEIGHT = 360;

	public var width(default, null):Int = 640;

	/** Screen pixels per internal pixel. **/
	public var scale(default, null):Float = 1;

	/** Whole-number scaling (with letterboxing) when there's room for 2× or more. Call `resize` after changing. **/
	public var integerScaling = true;

	/**
		2D layer measured in internal pixels and positioned over the image.
		HUD hands and text go here so they share the same pixel grid.
	**/
	public final hud:h2d.Object;

	final image:h2d.Bitmap;
	var target:h3d.mat.Texture;

	public function new(s2d:h2d.Scene) {
		image = new h2d.Bitmap(null, s2d);
		image.smooth = false;
		hud = new h2d.Object(s2d);
		resize(s2d.width, s2d.height);
	}

	public function resize(screenW:Int, screenH:Int):Void {
		// Integer scaling when there's room for at least 2× (§5.2); otherwise fill the height.
		// Width is then chosen to fill the window, so only the top and bottom can letterbox.
		var fit = Math.max(1, screenH) / HEIGHT;
		scale = integerScaling && fit >= 2 ? Math.floor(fit) : fit;
		var newWidth = Std.int(Math.max(320, Math.ceil(screenW / scale)));
		if (target == null || newWidth != width) {
			width = newWidth;
			if (target != null) {
				target.depthBuffer.dispose();
				target.dispose();
			}
			target = new h3d.mat.Texture(width, HEIGHT, [Target]);
			target.filter = Nearest;
			target.depthBuffer = new h3d.mat.Texture(width, HEIGHT, hxd.PixelFormat.Depth24Stencil8);
			image.tile = h2d.Tile.fromTexture(target);
		}
		image.setScale(scale);
		image.x = Math.round((screenW - width * scale) / 2);
		image.y = Math.round((screenH - HEIGHT * scale) / 2);
		hud.setScale(scale);
		hud.x = image.x;
		hud.y = image.y;
	}

	public function renderWorld(engine:h3d.Engine, s3d:h3d.scene.Scene):Void {
		engine.pushTarget(target);
		engine.clear(0xFF020308, 1);
		s3d.render(engine);
		engine.popTarget();
	}
}
