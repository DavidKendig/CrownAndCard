// SPDX-License-Identifier: AGPL-3.0-or-later
package core;

/**
	Logs what happens to the game window (GameLog, §13.12): its size and
	display mode, focus, the graphics driver, controllers coming and going,
	and frames slow enough to feel (hitches).
**/
class WindowWatch {
	/** A frame longer than this is logged as a hitch. **/
	static inline var HITCH_SECONDS = .25;

	/** Loading makes the first frames slow; don't count them. **/
	static inline var SETTLE_SECONDS = 3.0;

	var mode:hxd.Window.DisplayMode;
	var width:Int;
	var height:Int;
	var resizedAt = -1.0;
	final startedAt = haxe.Timer.stamp();
	var lastFrame = -1.0;
	var lastHitchLog = -1e9;
	var hiddenHitches = 0;
	var worstHidden = 0.0;

	public function new() {
		var w = hxd.Window.getInstance();
		mode = w.displayMode;
		width = w.width;
		height = w.height;
		var engine = h3d.Engine.getCurrent();
		GameLog.info("window", 'Opened at ${width}x$height, ${modeName(mode)}' + (engine == null ? "" : ' (drawing ${engine.width}x${engine.height})'));
		if (engine != null) GameLog.info("window", "Graphics: " + engine.driver.getDriverName(true));
		w.addEventTarget(e -> switch (e.kind) {
			case EFocus: GameLog.info("window", "Focused");
			case EFocusLost: GameLog.info("window", "Lost focus");
			default:
		});
		w.addResizeEvent(() -> resizedAt = haxe.Timer.stamp());
	}

	/** Call once a frame. **/
	public function update():Void {
		GameLog.tick();
		var now = haxe.Timer.stamp();
		var w = hxd.Window.getInstance();
		if (w.displayMode != mode) {
			mode = w.displayMode;
			GameLog.info("window", "Display mode: " + modeName(mode));
		}
		// Dragging a window edge resizes every frame; log where it settles.
		if (resizedAt >= 0 && now - resizedAt > .5) {
			resizedAt = -1;
			if (w.width != width || w.height != height) {
				width = w.width;
				height = w.height;
				var engine = h3d.Engine.getCurrent();
				GameLog.info("window", 'Resized to ${width}x$height' + (engine == null ? "" : ' (drawing ${engine.width}x${engine.height})'));
			}
		}
		var frame = lastFrame < 0 ? 0 : now - lastFrame;
		lastFrame = now;
		if (frame > HITCH_SECONDS && now - startedAt > SETTLE_SECONDS) {
			// At most one hitch line every few seconds; the ones in between are counted.
			if (now - lastHitchLog > 5) {
				var extra = hiddenHitches > 0 ? ' (and $hiddenHitches more since the last report, worst ${ms(worstHidden)} ms)' : "";
				GameLog.warn("frame", 'A frame took ${ms(frame)} ms' + extra);
				lastHitchLog = now;
				hiddenHitches = 0;
				worstHidden = 0;
			} else {
				hiddenHitches++;
				worstHidden = Math.max(worstHidden, frame);
			}
		}
	}

	public static function padConnected(p:hxd.Pad):Void
		GameLog.info("input", 'Controller connected: ${p.name} (slot ${p.index})');

	public static function padDisconnected(p:hxd.Pad):Void
		GameLog.info("input", 'Controller disconnected: ${p.name} (slot ${p.index})');

	static function ms(seconds:Float):Int
		return Math.round(seconds * 1000);

	static function modeName(m:hxd.Window.DisplayMode):String
		return switch (m) {
			case Windowed: "windowed";
			case Borderless: "borderless fullscreen";
			case Fullscreen: "exclusive fullscreen";
			default: Std.string(m);
		}
}
