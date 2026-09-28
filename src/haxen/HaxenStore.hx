// SPDX-License-Identifier: AGPL-3.0-or-later
package haxen;

import js.Browser;

/**
	Where Haxen keeps maps. Opened from the launcher, it talks to the
	launcher's local API (maps are files in %LOCALAPPDATA%\CrownAndCard\maps,
	and play testing starts a real game session). Opened any other way, maps
	live in this browser's storage, where the web build of the game finds them.
**/
class HaxenStore {
	/** Same prefix the game reads (core.MapSource.STORAGE_PREFIX). **/
	static inline var PREFIX = "crown-and-card.haxen.map.";

	public final api:Null<String>;

	public function new(api:Null<String>) {
		this.api = api != null && (StringTools.startsWith(api, "http://127.0.0.1:") || StringTools.startsWith(api, "http://localhost:")) ? api : null;
	}

	/** "Saved in your maps folder" or "Saved in this browser". **/
	public var where(get, never):String;

	function get_where():String return api != null ? "your maps folder" : "this browser";

	public function list(done:(Array<String>, Null<String>) -> Void):Void {
		if (api != null) {
			Browser.window.fetch(api + "/maps").then(r -> r.ok ? r.json() : throw 'the launcher answered ${r.status}').then(names -> {
				var out:Array<String> = [for (n in (names : Array<Dynamic>)) Std.string(n)];
				out.sort(Reflect.compare);
				done(out, null);
			}).catchError(e -> done([], Std.string(e)));
			return;
		}
		var out = [];
		try {
			var s = Browser.getLocalStorage();
			for (i in 0...s.length) {
				var k = s.key(i);
				if (k != null && StringTools.startsWith(k, PREFIX)) out.push(k.substr(PREFIX.length));
			}
		} catch (e:Dynamic) {
			done([], "browser storage is unavailable");
			return;
		}
		out.sort(Reflect.compare);
		done(out, null);
	}

	public function load(name:String, done:(Null<String>, Null<String>) -> Void):Void {
		if (api != null) {
			Browser.window.fetch(api + "/maps/" + StringTools.urlEncode(name)).then(r -> r.ok ? r.text() : throw 'the launcher answered ${r.status}')
				.then(text -> done(text, null)).catchError(e -> done(null, Std.string(e)));
			return;
		}
		var text = try Browser.getLocalStorage().getItem(PREFIX + name) catch (_:Dynamic) null;
		done(text, text == null ? "it isn't saved in this browser" : null);
	}

	public function save(name:String, text:String, done:Null<String>->Void):Void {
		if (api != null) {
			Browser.window.fetch(api + "/maps/" + StringTools.urlEncode(name), {method: "PUT", body: text, headers: {"Content-Type": "application/json"}})
				.then(r -> done(r.ok ? null : r.status == 400 ? "the launcher rejected the file" : 'the launcher answered ${r.status}'))
				.catchError(e -> done("the launcher didn't answer (is it still open?)"));
			return;
		}
		try {
			Browser.getLocalStorage().setItem(PREFIX + name, text);
			done(null);
		} catch (e:Dynamic) {
			done("browser storage is full or unavailable");
		}
	}

	public function remove(name:String, done:Null<String>->Void):Void {
		if (api != null) {
			Browser.window.fetch(api + "/maps/" + StringTools.urlEncode(name), {method: "DELETE"})
				.then(r -> done(r.ok ? null : 'the launcher answered ${r.status}')).catchError(e -> done(Std.string(e)));
			return;
		}
		try Browser.getLocalStorage().removeItem(PREFIX + name) catch (_:Dynamic) {}
		done(null);
	}

	/** Starts the game on a saved map: through the launcher (a real session), or in a new tab. **/
	public function playtest(name:String, done:Null<String>->Void):Void {
		if (api != null) {
			Browser.window.fetch(api + "/playtest?map=" + StringTools.urlEncode(name), {method: "POST"})
				.then(r -> done(r.ok ? null : r.status == 409 ? "the game is already running; close it first" : 'the launcher answered ${r.status}'))
				.catchError(e -> done("the launcher didn't answer (is it still open?)"));
			return;
		}
		Browser.window.open("index.html?map=" + StringTools.urlEncode(name), "_blank");
		done(null);
	}
}
