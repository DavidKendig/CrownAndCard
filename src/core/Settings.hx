// SPDX-License-Identifier: AGPL-3.0-or-later
package core;

enum abstract Scaling(String) to String {
	/** Whole-number upscaling with letterboxing (§5.2). **/
	var Integer = "integer";

	/** Fill the window height, even at fractional scales. **/
	var Fit = "fit";
}

enum abstract LookStyle(String) to String {
	/** Build-style y-shearing: the image slides, walls stay vertical (§5.5). **/
	var Shear = "shear";

	/** True perspective pitch (comfort option, §11.4). **/
	var Perspective = "perspective";
}

/**
	Player-facing graphics and audio options. The launcher passes them in as
	`--key=value` arguments (native) or URL parameters (web); see LaunchOptions.
	Every value is clamped, so a bad option can never break the game.
**/
class Settings {
	// Graphics
	public var fullscreen = false;
	public var windowWidth = 1280;
	public var windowHeight = 720;
	public var scaling:Scaling = Integer;

	/** Horizontal field of view in degrees, measured at 16:9. **/
	public var fov = 90;

	/** Head bob and hand sway, 0–100 %. **/
	public var headBob = 100;

	public var lookStyle:LookStyle = Shear;
	public var showFps = true;

	// Audio: there is no audio system yet. Values are kept and reported so the
	// pass-through can be checked end to end, and will drive the mixer later.
	public var masterVolume = 80;
	public var musicVolume = 70;
	public var effectsVolume = 80;
	public var voiceVolume = 80;
	public var muteInBackground = true;

	public function new() {}

	public static function fromOptions(options:Map<String, String>):Settings {
		var s = new Settings();
		s.fullscreen = bool(options, "fullscreen", s.fullscreen);
		s.windowWidth = int(options, "windowWidth", s.windowWidth, 640, 7680);
		s.windowHeight = int(options, "windowHeight", s.windowHeight, 360, 4320);
		s.scaling = options.get("scaling") == "fit" ? Fit : Integer;
		s.fov = int(options, "fov", s.fov, 70, 110);
		s.headBob = int(options, "headBob", s.headBob, 0, 100);
		s.lookStyle = options.get("lookStyle") == "perspective" ? Perspective : Shear;
		s.showFps = bool(options, "showFps", s.showFps);
		s.masterVolume = int(options, "masterVolume", s.masterVolume, 0, 100);
		s.musicVolume = int(options, "musicVolume", s.musicVolume, 0, 100);
		s.effectsVolume = int(options, "effectsVolume", s.effectsVolume, 0, 100);
		s.voiceVolume = int(options, "voiceVolume", s.voiceVolume, 0, 100);
		s.muteInBackground = bool(options, "muteInBackground", s.muteInBackground);
		return s;
	}

	/** Vertical FOV in degrees for Heaps' camera, from the horizontal FOV at 16:9. **/
	public function verticalFov():Float {
		var h = fov * Math.PI / 180;
		return 2 * Math.atan(Math.tan(h / 2) / (16 / 9)) * 180 / Math.PI;
	}

	/** Plain object for telemetry reports. **/
	public function toReport():Dynamic {
		return {
			fullscreen: fullscreen,
			windowWidth: windowWidth,
			windowHeight: windowHeight,
			scaling: (scaling : String),
			fov: fov,
			headBob: headBob,
			lookStyle: (lookStyle : String),
			showFps: showFps,
			masterVolume: masterVolume,
			musicVolume: musicVolume,
			effectsVolume: effectsVolume,
			voiceVolume: voiceVolume,
			muteInBackground: muteInBackground,
		};
	}

	static function int(options:Map<String, String>, key:String, fallback:Int, min:Int, max:Int):Int {
		var v = options.exists(key) ? Std.parseInt(options.get(key)) : null;
		if (v == null)
			return fallback;
		return v < min ? min : (v > max ? max : v);
	}

	static function bool(options:Map<String, String>, key:String, fallback:Bool):Bool {
		return switch (options.get(key)) {
			case "1", "true", "yes", "on": true;
			case "0", "false", "no", "off": false;
			default: fallback;
		}
	}
}
