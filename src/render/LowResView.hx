// SPDX-License-Identifier: AGPL-3.0-or-later
package render;

/**
	The frame (§5.2): everything on screen is drawn into one image at the
	render resolution (render.Resolution: 480 lines, or 720), which is then
	scaled up to the screen with nearest-neighbor sampling. The 3D world, the
	hands and HUD, menus, card tables, cards, tiles and text all go through
	it; nothing reaches the screen any other way.

	- **Layout grid:** screens are designed on a 360-line grid (`HEIGHT`),
	  and `hud` is measured in those units. The frame draws them at the render
	  resolution, so the layout never changes with it; only the pixels get
	  finer.
	- **Windowed:** a fixed 16:9 widescreen frame (640 × 360 grid units),
	  scaled to fit the window and letterboxed or pillarboxed when the window
	  is another shape.
	- **Fullscreen:** the frame fills the whole screen. It stays 360 grid
	  units tall and its width follows the screen's aspect ratio (16:10, 21:9
	  and so on), with no bars.
**/
class LowResView {
	/** Height of the layout grid. **/
	public static inline var HEIGHT = Resolution.GRID;

	/** The widescreen frame's width in windowed mode (16:9 at 360). **/
	public static inline var WIDE = 640;

	/** The frame's width in grid units. **/
	public var width(default, null):Int = WIDE;

	/** Screen pixels per grid unit. **/
	public var scale(default, null):Float = 1;

	/** Whole-number scaling (with borders) when there's room for 2× or more, in windowed mode. Call `resize` after changing. **/
	public var integerScaling = true;

	/** Fill the whole screen (fullscreen) instead of the windowed 16:9 frame. Call `resize` after changing. **/
	public var fillScreen = false;

	/** The frame's size in pixels: `width` grid units across, the render resolution's lines down. **/
	public var renderWidth(default, null):Int = WIDE;

	public var renderHeight(get, never):Int;

	inline function get_renderHeight():Int return Resolution.lines;

	/**
		2D layer measured in grid units and positioned over the world. HUD,
		menus and table screens go here so they share the frame.
	**/
	public final hud:h2d.Object;

	/** The frame, scaled onto the screen. **/
	final screen:h2d.Bitmap;

	/** The world and the HUD, drawn into the frame (and only there). **/
	final layer:FrameLayer;

	final world:h2d.Bitmap;
	var worldTarget:Null<h3d.mat.Texture>;
	var frame:Null<h3d.mat.Texture>;

	public function new(s2d:h2d.Scene) {
		screen = new h2d.Bitmap(null, s2d);
		layer = new FrameLayer(s2d);
		world = new h2d.Bitmap(null, layer);
		hud = new h2d.Object(layer);
		resize(s2d.width, s2d.height);
	}

	public function resize(screenW:Int, screenH:Int):Void {
		if (fillScreen) {
			// Fill the height exactly and let the width follow the screen, so nothing is left black.
			scale = Math.max(1, screenH) / HEIGHT;
			width = Std.int(Math.max(320, Math.ceil(screenW / scale)));
		} else {
			// Fit the 16:9 frame inside the window; whole-number scaling when there's room for 2× (§5.2).
			var fit = Math.min(Math.max(1, screenW) / WIDE, Math.max(1, screenH) / HEIGHT);
			scale = integerScaling && fit >= 2 ? Math.floor(fit) : fit;
			width = WIDE;
		}
		var lines = Resolution.lines;
		renderWidth = Math.round(width * Resolution.density);
		if (frame == null || frame.width != renderWidth || frame.height != lines) {
			if (frame != null) {
				worldTarget.depthBuffer.dispose();
				worldTarget.dispose();
				frame.dispose();
			}
			worldTarget = new h3d.mat.Texture(renderWidth, lines, [Target]);
			worldTarget.filter = Nearest;
			worldTarget.depthBuffer = new h3d.mat.Texture(renderWidth, lines, hxd.PixelFormat.Depth24Stencil8);
			world.tile = h2d.Tile.fromTexture(worldTarget);
			frame = new h3d.mat.Texture(renderWidth, lines, [Target]);
			frame.filter = Nearest;
			screen.tile = h2d.Tile.fromTexture(frame);
		}
		// The world image covers the frame, in grid units.
		world.tile.scaleToSize(width, HEIGHT);
		var x = Math.round((screenW - width * scale) / 2), y = Math.round((screenH - HEIGHT * scale) / 2);
		screen.setScale(scale * HEIGHT / lines);
		screen.x = x;
		screen.y = y;
		// On screen the layer lies exactly over the frame, so the mouse lands where things are drawn.
		layer.setScale(scale);
		layer.x = x;
		layer.y = y;
	}

	/**
		Draws the frame: the world (when `showWorld`) into its target, then the
		world and every 2D layer into the frame at the render resolution. Call
		before the 2D scene renders.
	**/
	public function renderFrame(engine:h3d.Engine, s3d:h3d.scene.Scene, showWorld:Bool):Void {
		world.visible = showWorld;
		if (showWorld) {
			engine.pushTarget(worldTarget);
			engine.clear(0xFF020308, 1);
			s3d.render(engine);
			engine.popTarget();
		}
		engine.pushTarget(frame);
		engine.clear(0xFF000000);
		engine.popTarget();
		// Lay the layer out in frame pixels for this pass, then put it back over the screen.
		var sx = layer.x, sy = layer.y, s = layer.scaleX;
		layer.x = layer.y = 0;
		layer.setScale(Resolution.density);
		layer.drawing = true;
		layer.drawTo(frame);
		layer.drawing = false;
		layer.x = sx;
		layer.y = sy;
		layer.setScale(s);
	}

	/** The frame as last drawn, for screenshots. **/
	public function capture():hxd.Pixels return frame.capturePixels();
}

/**
	Holds the world image and the HUD. It's drawn only into the frame; the
	screen shows the frame instead. It stays in the 2D scene, lying over the
	frame on screen, so its buttons and click areas still get the mouse.
**/
private class FrameLayer extends h2d.Object {
	public var drawing = false;

	override function drawRec(ctx:h2d.RenderContext):Void {
		if (drawing) super.drawRec(ctx);
	}
}
