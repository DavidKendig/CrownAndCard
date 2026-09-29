// SPDX-License-Identifier: AGPL-3.0-or-later
package net;

/**
	Asks the launcher to start or end a multiplayer session (§13.13): the
	launcher holds the network connection, the game only asks for it. Only
	talks to this computer, like Telemetry.
**/
class SessionControl {
	final api:String;

	public function new(api:String) {
		this.api = StringTools.endsWith(api, "/") ? api.substr(0, api.length - 1) : api;
	}

	/** Starts hosting. `address` is an optional public IPv4 address for the join code. **/
	public function host(address:String, done:(error:Null<String>, state:Dynamic) -> Void):Void
		call("POST", "host", {address: address}, done);

	public function join(code:String, done:(error:Null<String>, state:Dynamic) -> Void):Void
		call("POST", "join", {code: code}, done);

	public function leave(?done:Void->Void):Void
		call("POST", "leave", {}, (_, _) -> if (done != null) done());

	/** The session: {state: none | hosting | joined | ended, code, you, peers, reason}. **/
	public function state(done:(error:Null<String>, state:Dynamic) -> Void):Void
		call("GET", "state", null, done);

	function call(method:String, action:String, body:Dynamic, done:(error:Null<String>, state:Dynamic) -> Void):Void {
		var url = '$api/net/$action';
		var finish = (status:Int, text:String) -> {
			var data:Dynamic = try haxe.Json.parse(text) catch (_:Dynamic) null;
			if (status >= 200 && status < 300) done(null, data);
			else done(data != null && data.error != null ? Std.string(data.error) : status == 0 ? "The launcher didn't answer." : 'The launcher refused ($status).', data);
		};
		#if js
		var init:Dynamic = {method: method, keepalive: action == "leave"};
		if (body != null) {
			init.body = haxe.Json.stringify(body);
			init.headers = {"Content-Type": "application/json"};
		}
		js.Syntax.code("fetch({0}, {1}).then(function(r) { return r.text().then(function(t) { {2}(r.status, t); }); }).catch(function() { {2}(0, ''); })", url, init, finish);
		#elseif sys
		core.LocalHttp.request(method, url, body == null ? null : haxe.Json.stringify(body), finish);
		#else
		done("Multiplayer isn't available on this platform.", null);
		#end
	}
}
