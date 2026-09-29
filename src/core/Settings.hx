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
	Changed in the game menu, they go back to the launcher (`toOptions`,
	SettingsSync) to be passed in again next time.
**/
class Settings {
	// Graphics
	public var fullscreen = true; // the game opens fullscreen; Alt+Enter, F11 or the launcher's Display setting for a window
	public var windowWidth = 1280;
	public var windowHeight = 720;
	public var scaling:Scaling = Integer;

	/** Lines everything renders at: 480, or 720 (render.Resolution). Screens keep their 360-line layout. **/
	public var renderHeight = 480;

	/** Horizontal field of view in degrees, measured at 16:9. **/
	public var fov = 90;

	/** Head bob and hand sway, 0–100 %. **/
	public var headBob = 100;

	public var lookStyle:LookStyle = Shear;
	public var showFps = true;

	/** Mouse look speed, 25–300 %. **/
	public var mouseSensitivity = 100;

	// Weather ambience uses Master and Effects; other categories are reserved.
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
		var lines = options.exists("renderHeight") ? Std.parseInt(options.get("renderHeight")) : null;
		s.renderHeight = render.Resolution.supported(lines == null ? s.renderHeight : lines);
		s.fov = int(options, "fov", s.fov, 70, 110);
		s.headBob = int(options, "headBob", s.headBob, 0, 100);
		s.lookStyle = options.get("lookStyle") == "perspective" ? Perspective : Shear;
		s.showFps = bool(options, "showFps", s.showFps);
		s.mouseSensitivity = int(options, "mouseSensitivity", s.mouseSensitivity, 25, 300);
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
			renderHeight: renderHeight,
			fov: fov,
			headBob: headBob,
			lookStyle: (lookStyle : String),
			showFps: showFps,
			mouseSensitivity: mouseSensitivity,
			masterVolume: masterVolume,
			musicVolume: musicVolume,
			effectsVolume: effectsVolume,
			voiceVolume: voiceVolume,
			muteInBackground: muteInBackground,
		};
	}

	/** The options in the form `fromOptions` reads them (and the launcher stores them): key to string. **/
	public function toOptions():haxe.DynamicAccess<String> {
		inline function b(v:Bool) return v ? "1" : "0";
		return {
			fullscreen: b(fullscreen),
			windowWidth: Std.string(windowWidth),
			windowHeight: Std.string(windowHeight),
			scaling: (scaling : String),
			renderHeight: Std.string(renderHeight),
			fov: Std.string(fov),
			headBob: Std.string(headBob),
			lookStyle: (lookStyle : String),
			showFps: b(showFps),
			mouseSensitivity: Std.string(mouseSensitivity),
			masterVolume: Std.string(masterVolume),
			musicVolume: Std.string(musicVolume),
			effectsVolume: Std.string(effectsVolume),
			voiceVolume: Std.string(voiceVolume),
			muteInBackground: b(muteInBackground),
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
