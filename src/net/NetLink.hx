// SPDX-License-Identifier: AGPL-3.0-or-later
package net;

/** A player in the session, as the host's launcher numbers them: the host is 0, guests 1 and up. **/
typedef Peer = {id:Int, name:String};

enum NetEvent {
	/** Who's connected. `you` is this game's own peer id. Sent on connect and whenever someone joins or leaves. **/
	Roster(you:Int, peers:Array<Peer>);

	/** A message from another player. `from` is stamped by the host's launcher, so it can't be forged. **/
	Message(from:Int, body:Dynamic);

	/** The session is gone (the host left, or the connection dropped). **/
	Closed(reason:String);
}

/**
	The game's side of a multiplayer session (§13.13). The game never opens a
	network connection itself: its own launcher carries the messages.
**/
interface NetLink {
	var onEvent:NetEvent->Void;

	/** Sends `body` (a JSON-safe object) to one peer, or to everyone else with ALL. **/
	function send(to:Int, body:Dynamic):Void;

	/** Stops listening; nothing more arrives. **/
	function close():Void;
}

class Net {
	public static inline var HOST = 0;
	public static inline var ALL = -1;
}

/**
	The real link: server-sent events from the launcher at `api/net/events`, and
	messages posted to `api/net/send`. Only talks to this computer, like
	Telemetry.
**/
class LauncherLink implements NetLink {
	public var onEvent:NetEvent->Void = _ -> {};

	final api:String;
	#if js
	var events:Null<js.html.EventSource>;
	#elseif sys
	var events:Null<core.LocalHttp.EventStream>;

	/** The launcher said the session ended. **/
	var closed = false;
	#end

	public function new(api:String) {
		this.api = StringTools.endsWith(api, "/") ? api.substr(0, api.length - 1) : api;
		#if js
		if (!isLocal(this.api)) throw 'Multiplayer needs the launcher (got "$api")';
		events = new js.html.EventSource(this.api + "/net/events");
		events.onmessage = (e:js.html.MessageEvent) -> {
			var data:Dynamic = try haxe.Json.parse(e.data) catch (_:Dynamic) null;
			if (data != null) dispatch(data);
		};
		#elseif sys
		if (!isLocal(this.api)) throw 'Multiplayer needs the launcher (got "$api")';
		events = core.LocalHttp.stream(this.api + "/net/events", text -> {
			var data:Dynamic = try haxe.Json.parse(text) catch (_:Dynamic) null;
			if (data != null) dispatch(data);
		}, () -> {
			// A session that ended properly has already said so (a "closed" event) before the stream stops.
			if (closed) return;
			core.GameLog.warn("net", "The launcher's multiplayer stream ended");
			onEvent(Closed("Lost the connection to the launcher."));
		});
		#end
	}

	function dispatch(data:Dynamic):Void {
		switch (data.type : String) {
			case "roster":
				var peers:Array<Peer> = [];
				var raw:Array<Dynamic> = data.peers;
				if (raw != null) for (p in raw) peers.push({id: Std.int(p.id), name: Std.string(p.name)});
				onEvent(Roster(Std.int(data.you), peers));
			case "msg":
				onEvent(Message(Std.int(data.from), data.body));
			case "closed":
				#if sys
				closed = true;
				#end
				onEvent(Closed(data.reason == null ? "The session ended." : Std.string(data.reason)));
			default:
		}
	}

	public function send(to:Int, body:Dynamic):Void {
		var json = haxe.Json.stringify({to: to, body: body});
		#if js
		// keepalive: a goodbye sent as the page closes still arrives.
		js.Syntax.code("fetch({0}, {method: 'POST', body: {1}, keepalive: true, headers: {'Content-Type': 'application/json'}}).catch(function() {})", api + "/net/send", json);
		#elseif sys
		// One worker thread sends them all, so moves arrive in the order they were made.
		core.LocalHttp.request("POST", api + "/net/send", json);
		#end
	}

	public function close():Void {
		onEvent = _ -> {};
		#if js
		if (events != null) events.close();
		events = null;
		#elseif sys
		if (events != null) events.close();
		events = null;
		#end
	}

	public static function isLocal(url:Null<String>):Bool
		return url != null && (StringTools.startsWith(url, "http://127.0.0.1:") || StringTools.startsWith(url, "http://localhost:"));
}

/**
	An in-memory session for tests: the same rules as the launcher (the host is
	0, senders are stamped, guests can only reach the host), delivered when
	`flush()` runs so tests control the order.
**/
class LoopbackHub {
	final links:Array<LoopbackLink> = [];
	final queue:Array<{to:LoopbackLink, event:NetEvent}> = [];

	public function new() {}

	/** Adds a player; the first one is the host. **/
	public function join(name:String):LoopbackLink {
		var link = new LoopbackLink(this, links.length, name);
		links.push(link);
		roster();
		return link;
	}

	public function leave(link:LoopbackLink):Void {
		links.remove(link);
		if (link.id == Net.HOST) {
			for (l in links) queue.push({to: l, event: Closed("The host left.")});
			links.resize(0);
		} else roster();
	}

	function roster():Void {
		var peers = [for (l in links) ({id: l.id, name: l.name} : Peer)];
		for (l in links) queue.push({to: l, event: Roster(l.id, peers)});
	}

	function post(from:LoopbackLink, to:Int, body:Dynamic):Void {
		// Round-trip through JSON, as the real launcher does.
		var copy = haxe.Json.parse(haxe.Json.stringify(body));
		for (l in links) {
			if (l == from) continue;
			var allowed = from.id == Net.HOST ? (to == Net.ALL || to == l.id) : l.id == Net.HOST && (to == Net.HOST || to == Net.ALL);
			if (allowed) queue.push({to: l, event: Message(from.id, copy)});
		}
	}

	/** Delivers everything queued, including anything sent while delivering. **/
	public function flush():Void {
		var guard = 0;
		while (queue.length > 0 && guard++ < 100000) {
			var q = queue.shift();
			q.to.onEvent(q.event);
		}
	}
}

class LoopbackLink implements NetLink {
	public var onEvent:NetEvent->Void = _ -> {};
	public final id:Int;
	public final name:String;

	final hub:LoopbackHub;

	public function new(hub:LoopbackHub, id:Int, name:String) {
		this.hub = hub;
		this.id = id;
		this.name = name;
	}

	public function send(to:Int, body:Dynamic):Void @:privateAccess hub.post(this, to, body);

	public function close():Void onEvent = _ -> {};
}
