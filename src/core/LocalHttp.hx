// SPDX-License-Identifier: AGPL-3.0-or-later
package core;

#if sys
import sys.net.Host;
import sys.net.Socket;
import sys.thread.Deque;
import sys.thread.Thread;

/**
	The native build's side of the launcher's local API (what `fetch` and
	`EventSource` do in the browser): plain HTTP/1.1 to 127.0.0.1, nothing else.

	- `request` queues a call on one worker thread, so calls arrive in the
	  order they were made (multiplayer moves depend on it) and a slow launcher
	  never stalls a frame. `done` runs on the main thread.
	- `requestNow` blocks; for the last word before the game exits.
	- `stream` reads server-sent events on a thread of its own.
**/
class LocalHttp {
	static inline var TIMEOUT = 5.0;

	static var queue:Null<Deque<Void->Void>>;

	/** Splits a local URL into host, port and path, or null for anything that isn't this computer. **/
	public static function parse(url:String):Null<{host:String, port:Int, path:String}> {
		var rest = null;
		for (prefix in ["http://127.0.0.1", "http://localhost"])
			if (StringTools.startsWith(url, prefix)) rest = url.substr(prefix.length);
		if (rest == null) return null;
		var port = 80;
		if (StringTools.startsWith(rest, ":")) {
			var slash = rest.indexOf("/");
			var digits = slash < 0 ? rest.substr(1) : rest.substring(1, slash);
			var p = Std.parseInt(digits);
			if (p == null || p <= 0 || p > 65535) return null;
			port = p;
			rest = slash < 0 ? "" : rest.substr(slash);
		}
		return {host: "127.0.0.1", port: port, path: rest == "" ? "/" : rest};
	}

	public static function request(method:String, url:String, ?body:String, ?done:(status:Int, text:String) -> Void):Void {
		if (queue == null) {
			var q = new Deque<Void->Void>();
			queue = q;
			Thread.create(() -> while (true) q.pop(true)());
		}
		queue.add(() -> {
			var result = requestNow(method, url, body);
			if (done != null) haxe.MainLoop.runInMainThread(() -> done(result.status, result.text));
		});
	}

	/** Blocks until the launcher answers. Status 0 means it didn't. **/
	public static function requestNow(method:String, url:String, ?body:String):{status:Int, text:String} {
		var target = parse(url);
		if (target == null) return {status: 0, text: ""};
		var socket = new Socket();
		try {
			socket.setTimeout(TIMEOUT);
			socket.connect(new Host(target.host), target.port);
			var payload = body == null ? null : haxe.io.Bytes.ofString(body);
			var head = '$method ${target.path} HTTP/1.1\r\nHost: ${target.host}:${target.port}\r\nConnection: close\r\n';
			if (payload != null) head += 'Content-Type: application/json\r\nContent-Length: ${payload.length}\r\n';
			socket.output.writeString(head + "\r\n");
			if (payload != null) socket.output.write(payload);
			socket.output.flush();
			var response = readAll(socket);
			socket.close();
			var split = response.indexOf("\r\n\r\n");
			var statusLine = response.substring(0, response.indexOf("\r\n"));
			var parts = statusLine.split(" ");
			var status = parts.length > 1 ? Std.parseInt(parts[1]) : null;
			return {status: status == null ? 0 : status, text: split < 0 ? "" : response.substr(split + 4)};
		} catch (_:Dynamic) {
			try socket.close() catch (_:Dynamic) {}
			return {status: 0, text: ""};
		}
	}

	static function readAll(socket:Socket):String {
		var out = new haxe.io.BytesBuffer();
		var buf = haxe.io.Bytes.alloc(8192);
		try {
			while (true) {
				var n = socket.input.readBytes(buf, 0, buf.length);
				if (n <= 0) break;
				out.addBytes(buf, 0, n);
			}
		} catch (_:haxe.io.Eof) {}
		return out.getBytes().toString();
	}

	/**
		Server-sent events from `url`: `onData` gets each event's data, `onEnd`
		runs once when the stream stops (unless it was closed from this side).
		Both run on the main thread.
	**/
	public static function stream(url:String, onData:String->Void, onEnd:Void->Void):EventStream {
		var s = new EventStream();
		var target = parse(url);
		if (target == null) {
			haxe.MainLoop.runInMainThread(onEnd);
			return s;
		}
		Thread.create(() -> {
			var socket = new Socket();
			try {
				socket.setTimeout(TIMEOUT);
				socket.connect(new Host(target.host), target.port);
				socket.output.writeString('GET ${target.path} HTTP/1.1\r\nHost: ${target.host}:${target.port}\r\nAccept: text/event-stream\r\n\r\n');
				socket.output.flush();
				// The launcher sends a keep-alive every few seconds; a short timeout lets close() be noticed promptly.
				socket.setTimeout(1);
				var pending = new haxe.io.BytesBuffer();
				var buf = haxe.io.Bytes.alloc(4096);
				var headerDone = false, ok = false;
				var data = new StringBuf();
				var hasData = false;
				var idle = 0.0;
				while (!s.closed) {
					var n = try socket.input.readBytes(buf, 0, buf.length) catch (e:haxe.io.Eof) -1 catch (_:Dynamic) 0;
					if (n < 0) break;
					if (n == 0) {
						idle += 1;
						if (idle > 15) break; // no keep-alive: the launcher is gone
						continue;
					}
					idle = 0;
					pending.addBytes(buf, 0, n);
					// Take every complete line and keep the unfinished tail as bytes: a read can end
					// partway through a character, which decoding early would garble.
					var bytes = pending.getBytes();
					var lines = [], start = 0;
					for (i in 0...bytes.length) if (bytes.get(i) == "\n".code) {
						lines.push(bytes.getString(start, i - start, UTF8));
						start = i + 1;
					}
					pending = new haxe.io.BytesBuffer();
					pending.addBytes(bytes, start, bytes.length - start);
					for (raw in lines) {
						var line = StringTools.endsWith(raw, "\r") ? raw.substr(0, raw.length - 1) : raw;
						if (!headerDone) {
							if (StringTools.startsWith(line, "HTTP/")) ok = line.indexOf(" 200") > 0;
							if (line == "") {
								headerDone = true;
								if (!ok) throw "refused";
							}
							continue;
						}
						if (line == "") {
							if (hasData) {
								var event = data.toString();
								haxe.MainLoop.runInMainThread(() -> if (!s.closed) onData(event));
							}
							data = new StringBuf();
							hasData = false;
						} else if (StringTools.startsWith(line, "data:")) {
							if (hasData) data.add("\n");
							data.add(StringTools.ltrim(line.substr(5)));
							hasData = true;
						}
					}
				}
			} catch (_:Dynamic) {}
			try socket.close() catch (_:Dynamic) {}
			haxe.MainLoop.runInMainThread(() -> if (!s.closed) {
				s.closed = true;
				onEnd();
			});
		});
		return s;
	}
}

class EventStream {
	/** Set by close(), or once the stream has ended and onEnd has run. **/
	public var closed = false;

	public function new() {}

	/** Stops reading; nothing more arrives. **/
	public function close():Void {
		closed = true;
	}
}
#end
