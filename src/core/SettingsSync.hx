// SPDX-License-Identifier: AGPL-3.0-or-later
package core;

/**
	Hands settings changed in the game menu back to the launcher (`api/settings`),
	which saves them and passes them in again next time. Without the launcher
	they last until the game closes. Only talks to this computer, like Telemetry.
**/
class SettingsSync {
	/** Returns false when there's no launcher to save them. **/
	public static function save(api:Null<String>, settings:Settings):Bool {
		if (api == null || !(StringTools.startsWith(api, "http://127.0.0.1:") || StringTools.startsWith(api, "http://localhost:")))
			return false;
		var url = (StringTools.endsWith(api, "/") ? api.substr(0, api.length - 1) : api) + "/settings";
		var body = haxe.Json.stringify(settings.toOptions());
		#if js
		js.Syntax.code("fetch({0}, {method: 'POST', body: {1}, headers: {'Content-Type': 'application/json'}}).catch(function() {})", url, body);
		#elseif sys
		LocalHttp.request("POST", url, body, (status, _) ->
			if (status < 200 || status >= 300) GameLog.warn("settings", 'The launcher didn\'t save the settings (${status == 0 ? "no answer" : "status " + status})'));
		#end
		return true;
	}
}
