// SPDX-License-Identifier: AGPL-3.0-or-later
package core;

import haxe.Json;

/**
	Error tracking (§13.12): sends state heartbeats and error events to the
	launcher, which records them per session.

	- Only active when the launcher passes a `telemetry` URL.
	- Only ever talks to this computer: URLs that aren't 127.0.0.1 or
	  localhost are refused. Nothing is uploaded anywhere.
**/
class Telemetry {
	public static final BUILD = Version.CURRENT;
	static inline var HEARTBEAT_SECONDS = 5.0;

	/** Returns the current game state for heartbeats and error reports. **/
	public var stateProvider:Void->Dynamic = () -> null;

	public final enabled:Bool;

	final endpoint:String;
	var sinceBeat = HEARTBEAT_SECONDS;
	var uptime = 0.0;

	public function new(url:Null<String>) {
		endpoint = isLocal(url) ? (StringTools.endsWith(url, "/") ? url : url + "/") : "";
		enabled = endpoint != "";
		if (url != null && !enabled)
			trace('Telemetry disabled: "$url" is not a local address');
	}

	/** Sends the start event (settings plus platform details) and hooks error reporting. **/
	public function start(settings:Settings):Void {
		if (!enabled)
			return;
		installErrorHooks();
		event("start", "Game started", null, {settings: settings.toReport(), platform: platform()});
	}

	public function update(dt:Float):Void {
		if (!enabled)
			return;
		uptime += dt;
		sinceBeat += dt;
		if (sinceBeat >= HEARTBEAT_SECONDS) {
			sinceBeat = 0;
			post("state", snapshot());
		}
	}

	public function event(kind:String, message:String, ?stack:String, ?extra:Dynamic):Void {
		if (!enabled)
			return;
		post("event", {
			kind: kind,
			message: message,
			stack: stack,
			extra: extra,
			time: Date.now().toString(),
			uptimeSec: Math.round(uptime),
			state: safeState(),
		}, kind == "quit");
	}

	function snapshot():Dynamic {
		return {
			build: BUILD,
			time: Date.now().toString(),
			uptimeSec: Math.round(uptime),
			state: safeState(),
		};
	}

	/** Never let a broken state provider take down error reporting. **/
	function safeState():Dynamic {
		try {
			return stateProvider();
		} catch (e:Dynamic) {
			return {stateError: Std.string(e)};
		}
	}

	function post(path:String, data:Dynamic, finalMessage = false):Void {
		var body = Json.stringify(data);
		var url = endpoint + path;
		#if js
		if (finalMessage) {
			// sendBeacon still delivers while the page is closing.
			js.Syntax.code("navigator.sendBeacon({0}, {1})", url, body);
		} else {
			js.Syntax.code("fetch({0}, {method: 'POST', body: {1}, keepalive: true, headers: {'Content-Type': 'application/json'}}).catch(function() {})", url, body);
		}
		#elseif sys
		// Native builds post on a worker thread so a slow launcher never stalls a frame.
		sys.thread.Thread.create(() -> {
			try {
				var http = new haxe.Http(url);
				http.setHeader("Content-Type", "application/json");
				http.setPostData(body);
				http.request(true);
			} catch (_:Dynamic) {}
		});
		#end
	}

	function installErrorHooks():Void {
		#if js
		var window = js.Browser.window;
		window.addEventListener("error", (e:Dynamic) -> {
			var stack:String = e.error != null ? Std.string(e.error.stack) : null;
			event("error", Std.string(e.message), stack, {source: e.filename, line: e.lineno, column: e.colno});
		});
		window.addEventListener("unhandledrejection", (e:Dynamic) -> {
			var reason:Dynamic = e.reason;
			var stack:String = reason != null && reason.stack != null ? Std.string(reason.stack) : null;
			event("error", "Unhandled promise rejection: " + Std.string(reason), stack);
		});
		window.addEventListener("pagehide", (_) -> event("quit", "Page closed"));
		#end
	}

	static function platform():Dynamic {
		#if js
		return {
			target: "web",
			userAgent: js.Browser.navigator.userAgent,
			devicePixelRatio: js.Browser.window.devicePixelRatio,
			screen: '${js.Browser.window.screen.width}x${js.Browser.window.screen.height}',
			gpu: js.Syntax.code("(function() {
				try {
					var gl = document.createElement('canvas').getContext('webgl');
					var ext = gl && gl.getExtension('WEBGL_debug_renderer_info');
					return ext ? gl.getParameter(ext.UNMASKED_VENDOR_WEBGL) + ' / ' + gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : 'unknown';
				} catch (e) { return 'unknown'; }
			})()"),
		};
		#elseif sys
		return {target: Sys.systemName()};
		#else
		return {target: "unknown"};
		#end
	}

	static function isLocal(url:Null<String>):Bool {
		if (url == null)
			return false;
		for (prefix in ["http://127.0.0.1:", "http://localhost:", "http://127.0.0.1/", "http://localhost/"])
			if (StringTools.startsWith(url, prefix))
				return true;
		return false;
	}
}
