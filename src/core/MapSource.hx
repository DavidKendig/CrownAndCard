// SPDX-License-Identifier: AGPL-3.0-or-later
package core;

import world.MapData;

/**
	Finds the map to play (§13.6): the built-in manor, or a custom map made in
	Haxen. Under the launcher, custom maps come from its local API (saved in
	%LOCALAPPDATA%\CrownAndCard\maps); in a plain browser, from the maps Haxen
	saved in that browser; on native builds, from the maps folder.
**/
class MapSource {
	/** Browser storage key prefix Haxen saves under when there's no launcher. **/
	public static inline var STORAGE_PREFIX = "crown-and-card.haxen.map.";

	public static function builtIn():MapFile {
		return MapData.parse(hxd.Res.load("maps/manor.json").toText());
	}

	/** Loads `name` (empty = the manor), then calls `done` once with the map and a notice if it fell back. **/
	public static function load(name:Null<String>, api:Null<String>, done:(MapFile, Null<String>) -> Void):Void {
		if (name == null || name == "" || name == "manor") {
			done(builtIn(), null);
			return;
		}
		function fallback(why:String) done(builtIn(), 'Couldn\'t open the map "$name": $why Playing Dodriec Manor instead.');
		function accept(text:String) {
			var map = try MapData.parse(text) catch (e:Dynamic) {
				fallback(Std.string(e) + ".");
				return;
			}
			for (p in MapData.check(map)) if (p.error) {
				fallback(p.message);
				return;
			}
			done(map, null);
		}
		#if js
		var local = api != null && (StringTools.startsWith(api, "http://127.0.0.1:") || StringTools.startsWith(api, "http://localhost:"));
		if (local) {
			js.Browser.window.fetch(api + "/maps/" + StringTools.urlEncode(name)).then(r -> {
				if (!r.ok) throw "it isn't in your maps folder.";
				return r.text();
			}).then(text -> accept(text)).catchError(e -> fallback(Std.isOfType(e, String) ? e : "the launcher didn't answer."));
		} else {
			var text = try js.Browser.getLocalStorage().getItem(STORAGE_PREFIX + name) catch (_:Dynamic) null;
			if (text == null) fallback("it isn't saved in this browser.") else accept(text);
		}
		#elseif sys
		var root = Sys.getEnv("LOCALAPPDATA");
		var path = haxe.io.Path.join([root == null ? "." : root, "CrownAndCard", "maps", name + ".json"]);
		if (!MapData.validName(name) || !sys.FileSystem.exists(path)) fallback("it isn't in your maps folder.");
		else accept(sys.io.File.getContent(path));
		#else
		fallback("custom maps aren't supported on this platform.");
		#end
	}
}
