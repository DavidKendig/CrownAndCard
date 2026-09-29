// SPDX-License-Identifier: AGPL-3.0-or-later
package core;

/**
	Paces the native window at the display's refresh rate, in place of the
	driver's vsync. OpenGL vsync can pace far below the display: on an AMD
	Radeon 780M at 165 Hz it held the game to 1/6 of that (27 fps) while the
	frames themselves took about 1 ms. Windowed play is composited by Windows,
	so it doesn't tear without vsync.

	It sleeps for most of the wait and spins the last moment, since a sleep
	usually runs half a millisecond over (measured on Windows 11). A frame
	that runs late resets the schedule rather than hurrying to catch up.
**/
class FramePacer {
	/** How long before the deadline to stop sleeping and spin instead. **/
	static inline var SPIN_SECONDS = .001;

	public var targetFps(default, null):Float;

	var next = -1.0;

	public function new(targetFps:Float) {
		setTarget(targetFps);
	}

	public function setTarget(fps:Float):Void {
		targetFps = fps >= 30 && fps <= 1000 ? fps : 60;
	}

	/** Call once a frame; returns when it's time for the next one. **/
	public function wait():Void {
		var interval = 1 / targetFps;
		var now = haxe.Timer.stamp();
		if (next < 0 || now - next > interval) next = now;
		next += interval;
		var sleep = next - now - SPIN_SECONDS;
		if (sleep > 0) Sys.sleep(sleep);
		while (haxe.Timer.stamp() < next) {}
	}
}
