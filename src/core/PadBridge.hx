// SPDX-License-Identifier: AGPL-3.0-or-later
package core;

/**
	The controller as the launcher sees it (§11.4). The launcher reads XInput
	natively and streams it to `api/pad`, so the controller works even when the
	browser's Gamepad API can't see it: before the first button press, or
	while Steam's desktop controller layout has it turning into a mouse. The
	stream drives an hxd.Pad, so the rest of the game reads it like any pad.

	The native window doesn't need it: SDL reads XInput (and PlayStation,
	Switch and other controllers) itself, so there the bridge stays a dummy.
**/
class PadBridge {
	public final pad:hxd.Pad;

	/** haxe.Timer.stamp() of the last stick or button movement, or -1. **/
	public var lastActivity(default, null) = -1.0;

	var latest:Null<Dynamic> = null;

	public function new(api:Null<String>) {
		pad = hxd.Pad.createDummy();
		#if js
		var local = api != null && (StringTools.startsWith(api, "http://127.0.0.1:") || StringTools.startsWith(api, "http://localhost:"));
		if (local) {
			// EventSource reconnects by itself if the launcher restarts.
			var events = new js.html.EventSource(api + "/pad");
			events.onmessage = (e:js.html.MessageEvent) -> try latest = haxe.Json.parse(e.data) catch (_:Dynamic) {};
		}
		#end
	}

	/** Copies the latest state into the pad. Call once a frame, before anything reads it. **/
	@:access(hxd.Pad)
	public function update():Void {
		var s:Dynamic = latest;
		var on = s != null && s.c == 1;
		pad.connected = on;
		var bits:Int = on ? s.b : 0;
		for (i in 0...16) {
			pad.prevButtons[i] = pad.buttons[i] == true;
			pad.buttons[i] = (bits >> i) & 1 == 1;
		}
		var a:Array<Float> = on ? s.a : [0, 0, 0, 0];
		pad.rawXAxis = a[0];
		pad.rawYAxis = a[1];
		pad.rawRXAxis = a[2];
		pad.rawRYAxis = a[3];
		if (on && (bits != 0 || Math.abs(a[0]) > .35 || Math.abs(a[1]) > .35 || Math.abs(a[2]) > .35 || Math.abs(a[3]) > .35))
			lastActivity = haxe.Timer.stamp();
	}

	/** True when a pad (the browser's own) was touched this frame. **/
	public static function active(p:hxd.Pad):Bool {
		if (!p.connected) return false;
		for (b in p.buttons) if (b) return true;
		return Math.abs(p.xAxis) > .35 || Math.abs(p.yAxis) > .35 || Math.abs(p.rxAxis) > .35 || Math.abs(p.ryAxis) > .35;
	}
}
