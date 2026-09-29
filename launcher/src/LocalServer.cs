// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace CrownAndCard.Launcher;

/**
	A tiny HTTP server on 127.0.0.1 (never reachable from other machines).

	- Serves the web build of the game (and Haxen, the map editor) from `WebRoot`.
	- Receives the game's state heartbeats and events at `api/state` and `api/event`.
	- Keeps the Guest Register at `api/save`, and custom maps at `api/maps`.
	- Lets Haxen ask for a play test at `api/playtest?map=<name>`.
	- Streams the controller to the game at `api/pad` (XInput works where the browser's gamepad support doesn't).
	- Starts and ends multiplayer sessions for the game (`api/net/state`, `host`, `join`, `leave`) and
	  carries their messages at `api/net/events` and `api/net/send` (§13.13).

	Every URL sits under a random per-launch token, so other local pages can't
	read the game files or post fake reports.
**/
sealed class LocalServer : IDisposable
{
	const int MaxHeaderBytes = 16 * 1024;
	const int MaxBodyBytes = 512 * 1024;

	readonly TcpListener listener = new(IPAddress.Loopback, 0);
	readonly string token = NewToken();
	volatile bool running = true;
	readonly GuestRegisterStore register;
	readonly MapStore maps;

	public int Port { get; }
	public string BasePath => $"/s/{token}/";
	public string BaseUrl => $"http://127.0.0.1:{Port}{BasePath}";
	public string ApiUrl => BaseUrl + "api";

	/** Folder served to the game window. Null serves nothing. **/
	public volatile string? WebRoot;

	/** Raised on a worker thread with the endpoint ("state" or "event") and the raw JSON body. **/
	public event Action<string, string>? Posted;

	/**
		Haxen asked to play a saved map. Called on a worker thread; returns null once
		the game is starting, "busy" if a game is already running, or another reason.
	**/
	public Func<string, string?>? PlaytestRequested;

	/** The multiplayer session the game may use (`api/net/events`, `api/net/send`), or null. **/
	public volatile NetSession? Net;

	/** Starts hosting when the game asks (`api/net/host`), given an optional public address. Replaceable for tests. **/
	public Func<IPAddress?, NetSession> StartHost = advertise => NetSession.Host("Player", "dev", NetSession.DefaultPort, advertise);

	/** Joins with a code when the game asks (`api/net/join`). Replaceable for tests. **/
	public Func<string, NetSession> StartJoin = code => NetSession.Join(code, "Player", "dev");

	readonly object netGate = new();

	public LocalServer(GuestRegisterStore? register = null, MapStore? maps = null)
	{
		this.register = register ?? new GuestRegisterStore(Path.Combine(Paths.DataDir, "saves", "guest-register.json"));
		this.maps = maps ?? new MapStore(Paths.MapsDir);
		listener.Start();
		Port = ((IPEndPoint)listener.LocalEndpoint).Port;
		new Thread(AcceptLoop) { IsBackground = true, Name = "LocalServer" }.Start();
	}

	void AcceptLoop()
	{
		while (running)
		{
			TcpClient client;
			try
			{
				client = listener.AcceptTcpClient();
			}
			catch
			{
				if (!running)
					return;
				continue;
			}
			ThreadPool.QueueUserWorkItem(_ => Serve(client));
		}
	}

	void Serve(TcpClient client)
	{
		try
		{
			using (client)
			{
				client.ReceiveTimeout = 10000;
				client.SendTimeout = 10000;
				Handle(client.GetStream());
				CloseGracefully(client);
			}
		}
		catch (Exception e)
		{
			Log.Write("Local server: " + e.Message);
		}
	}

	/**
		Finishes sending, then reads off anything the client sent that wasn't read
		(a refused request's body). Closing with unread data makes Windows reset the
		connection, and the client loses the response it was about to read.
	**/
	static void CloseGracefully(TcpClient client)
	{
		try
		{
			client.Client.Shutdown(SocketShutdown.Send);
			client.ReceiveTimeout = 1000;
			var buffer = new byte[8192];
			for (int total = 0; total < MaxBodyBytes;)
			{
				int n = client.Client.Receive(buffer);
				if (n <= 0)
					break;
				total += n;
			}
		}
		catch (SocketException) { }
		catch (ObjectDisposedException) { }
	}

	void Handle(Stream stream)
	{
		if (!ReadHead(stream, out var head, out var leftover))
			return;
		var lines = head.Split(["\r\n"], StringSplitOptions.None);
		var request = lines[0].Split(' ');
		if (request.Length < 3)
		{
			Respond(stream, 400);
			return;
		}
		string method = request[0], target = request[1];
		int contentLength = 0;
		foreach (var line in lines)
		{
			var colon = line.IndexOf(':');
			if (colon > 0 && line.Substring(0, colon).Trim().Equals("Content-Length", StringComparison.OrdinalIgnoreCase))
				int.TryParse(line.Substring(colon + 1).Trim(), out contentLength);
		}
		if (contentLength < 0 || contentLength > MaxBodyBytes)
		{
			Respond(stream, 413);
			return;
		}

		var query = target.IndexOf('?');
		var path = query < 0 ? target : target.Substring(0, query);
		if (!path.StartsWith(BasePath, StringComparison.Ordinal))
		{
			Respond(stream, 404);
			return;
		}
		var sub = path.Substring(BasePath.Length);

		// Same token-protected origin as the game; no cross-origin access headers.
		if (sub == "api/maps" || sub.StartsWith("api/maps/", StringComparison.Ordinal))
		{
			try
			{
				if (sub == "api/maps")
				{
					if (method == "GET") Respond(stream, 200, "application/json", Encoding.UTF8.GetBytes(Json.Write(maps.List(), false)));
					else Respond(stream, 405);
					return;
				}
				var name = Uri.UnescapeDataString(sub.Substring("api/maps/".Length));
				if (!MapStore.ValidName(name)) { Respond(stream, 400); return; }
				switch (method)
				{
					case "GET":
						var text = maps.Read(name);
						if (text == null) Respond(stream, 404);
						else Respond(stream, 200, "application/json", Encoding.UTF8.GetBytes(text));
						break;
					case "PUT":
					case "POST":
						maps.Write(name, Encoding.UTF8.GetString(ReadBody(stream, leftover, contentLength)));
						Respond(stream, 204);
						break;
					case "DELETE":
						Respond(stream, maps.Delete(name) ? 204 : 404);
						break;
					default:
						Respond(stream, 405);
						break;
				}
			}
			catch (ArgumentException) { Respond(stream, 400); }
			catch (Exception e) { Log.Write("Maps: " + e.Message); Respond(stream, 500); }
			return;
		}

		if (sub == "api/pad" && method == "GET")
		{
			StreamPad(stream);
			return;
		}

		if (sub is "api/net/state" or "api/net/host" or "api/net/join" or "api/net/leave")
		{
			ControlNet(stream, sub.Substring("api/net/".Length), method, method == "POST" ? ReadBody(stream, leftover, contentLength) : []);
			return;
		}
		if (sub == "api/net/events" && method == "GET")
		{
			if (Net is { } session) StreamNet(stream, session);
			else Respond(stream, 409);
			return;
		}
		if (sub == "api/net/send")
		{
			if (method != "POST") { Respond(stream, 405); return; }
			if (Net is not { } session) { Respond(stream, 409); return; }
			Dictionary<string, object>? msg;
			try { msg = Json.Obj(Json.Parse(Encoding.UTF8.GetString(ReadBody(stream, leftover, contentLength)))); }
			catch (ArgumentException) { msg = null; }
			if (msg == null || !msg.TryGetValue("body", out var body)) { Respond(stream, 400); return; }
			session.SendFromGame(Json.Int(msg, -1, "to"), body);
			Respond(stream, 204);
			return;
		}

		if (sub == "api/playtest")
		{
			if (method != "POST") { Respond(stream, 405); return; }
			var map = QueryValue(query < 0 ? "" : target.Substring(query + 1), "map");
			if (!MapStore.ValidName(map) || maps.Read(map!) == null) { Respond(stream, 404); return; }
			string? refusal;
			try { refusal = PlaytestRequested == null ? "unavailable" : PlaytestRequested(map!); }
			catch (Exception e) { Log.Write("Play test: " + e.Message); refusal = "failed"; }
			Respond(stream, refusal == null ? 204 : refusal == "busy" ? 409 : 503);
			return;
		}

		if (sub == "api/save")
		{
			try
			{
				if (method == "GET") Respond(stream, 200, "application/json", Encoding.UTF8.GetBytes(register.Read()));
				else if (method == "POST")
				{
					if (contentLength > 65536) { Respond(stream, 413); return; }
					register.Write(Encoding.UTF8.GetString(ReadBody(stream, leftover, contentLength)));
					Respond(stream, 204);
				}
				else Respond(stream, 405);
			}
			catch (ArgumentException) { Respond(stream, 400); }
			catch (Exception e) { Log.Write("Guest Register: " + e.Message); Respond(stream, 500); }
			return;
		}

		if (method == "POST" && (sub == "api/state" || sub == "api/event"))
		{
			var body = ReadBody(stream, leftover, contentLength);
			Respond(stream, 204);
			Posted?.Invoke(sub.Substring(4), Encoding.UTF8.GetString(body));
			return;
		}
		if (method == "GET" || method == "HEAD")
		{
			ServeFile(stream, sub, method == "HEAD");
			return;
		}
		Respond(stream, 405);
	}

	/**
		Streams the controller to the game as server-sent events (text/event-stream),
		polling XInput at about 120 Hz and sending only changes (plus a keep-alive).
		Ends when the page goes away or the launcher closes.
	**/
	void StreamPad(Stream stream)
	{
		var head = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: keep-alive\r\n\r\n");
		try
		{
			stream.Write(head, 0, head.Length);
			string last = "";
			var lastSent = DateTime.UtcNow;
			while (running)
			{
				var snap = XInputPad.Snapshot();
				var now = DateTime.UtcNow;
				if (snap != last || (now - lastSent).TotalSeconds > 2)
				{
					var bytes = Encoding.ASCII.GetBytes("data: " + snap + "\n\n");
					stream.Write(bytes, 0, bytes.Length);
					stream.Flush();
					last = snap;
					lastSent = now;
				}
				Thread.Sleep(8);
			}
		}
		catch (IOException)
		{
			// The game window closed or reloaded.
		}
		catch (ObjectDisposedException)
		{
		}
	}

	/**
		The game starts and ends multiplayer sessions from the Private Party table
		(§13.13): `state` (GET) reports the session, `host` and `join` (POST) start
		one, `leave` (POST) ends it. Refusals come back as {"error": reason}.
	**/
	void ControlNet(Stream stream, string action, string method, byte[] body)
	{
		if (action == "state" ? method != "GET" : method != "POST")
		{
			Respond(stream, 405);
			return;
		}
		Dictionary<string, object>? args = null;
		try { if (body.Length > 0) args = Json.Obj(Json.Parse(Encoding.UTF8.GetString(body))); }
		catch (ArgumentException) { }
		void Error(int code, string reason) =>
			Respond(stream, code, "application/json", Encoding.UTF8.GetBytes(Json.Write(new Dictionary<string, object> { ["error"] = reason }, false)));
		if (action == "leave")
		{
			lock (netGate)
			{
				Net?.Dispose();
				Net = null;
			}
			Respond(stream, 204);
			return;
		}
		if (action is "host" or "join")
		{
			lock (netGate)
			{
				if (Net is { Ended: null })
				{
					Error(409, "You're already in a multiplayer session.");
					return;
				}
				try
				{
					NetSession session;
					if (action == "host")
					{
						IPAddress? advertise = null;
						var typed = (Json.Str(args, "address") ?? "").Trim();
						if (typed.Length > 0 && (!IPAddress.TryParse(typed, out advertise) || advertise.AddressFamily != AddressFamily.InterNetwork || typed.Split('.').Length != 4))
						{
							Error(400, "The internet address should be an IPv4 address like 203.0.113.7.");
							return;
						}
						session = StartHost(advertise);
					}
					else
						session = StartJoin(Json.Str(args, "code") ?? "");
					Net?.Dispose();
					Net = session;
				}
				catch (SocketException e)
				{
					Error(503, action == "host" ? $"Couldn't host on port {NetSession.DefaultPort}: {e.Message}" : e.Message);
					return;
				}
				catch (Exception e) when (e is IOException or ArgumentException)
				{
					Error(action == "join" && e is ArgumentException ? 400 : 503, e.Message);
					return;
				}
			}
		}
		var s = Net;
		var state = new Dictionary<string, object>
		{
			["state"] = s == null ? "none" : s.Ended != null ? "ended" : s.IsHost ? "hosting" : "joined",
			["you"] = s?.You ?? -1,
			["code"] = s is { IsHost: true } ? s.JoinCode ?? "" : "",
			["reason"] = s?.Ended ?? "",
			["peers"] = s == null ? Array.Empty<object>() : s.Peers.Select(p => (object)new Dictionary<string, object> { ["id"] = p.Id, ["name"] = p.Name }).ToArray(),
		};
		Respond(stream, 200, "application/json", Encoding.UTF8.GetBytes(Json.Write(state, false)));
	}

	/** The multiplayer session's events for the game (§13.13), as server-sent events, with a keep-alive every few seconds. **/
	void StreamNet(Stream stream, NetSession session)
	{
		var head = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: keep-alive\r\n\r\n");
		using var feed = session.Subscribe();
		try
		{
			stream.Write(head, 0, head.Length);
			stream.Flush();
			while (running && !feed.Lines.IsCompleted)
			{
				var bytes = feed.Lines.TryTake(out var line, 3000)
					? Encoding.UTF8.GetBytes("data: " + line + "\n\n")
					: Encoding.ASCII.GetBytes(": keep-alive\n\n");
				stream.Write(bytes, 0, bytes.Length);
				stream.Flush();
			}
		}
		catch (IOException)
		{
			// The game window closed or reloaded.
		}
		catch (ObjectDisposedException)
		{
		}
		catch (InvalidOperationException)
		{
			// The session ended while waiting.
		}
	}

	void ServeFile(Stream stream, string sub, bool headOnly)
	{
		var root = WebRoot;
		if (root == null)
		{
			Respond(stream, 404);
			return;
		}
		var relative = Uri.UnescapeDataString(sub);
		if (relative.Length == 0)
			relative = "index.html";
		if (relative.Contains("..") || relative.Contains(":") || relative.Contains("\\") || relative.StartsWith("/"))
		{
			Respond(stream, 403);
			return;
		}
		var rootFull = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
		var full = Path.GetFullPath(Path.Combine(rootFull, relative.Replace('/', Path.DirectorySeparatorChar)));
		if (!full.StartsWith(rootFull, StringComparison.OrdinalIgnoreCase) || !File.Exists(full))
		{
			Respond(stream, 404);
			return;
		}
		var bytes = File.ReadAllBytes(full);
		Respond(stream, 200, ContentType(full), headOnly ? null : bytes, bytes.Length);
	}

	/** Reads up to the blank line that ends the headers; anything after it is the start of the body. **/
	static bool ReadHead(Stream stream, out string head, out byte[] leftover)
	{
		var buffer = new byte[4096];
		var data = new MemoryStream();
		head = "";
		leftover = [];
		while (data.Length < MaxHeaderBytes)
		{
			int n = stream.Read(buffer, 0, buffer.Length);
			if (n <= 0)
				return false;
			data.Write(buffer, 0, n);
			var bytes = data.GetBuffer();
			for (int i = 3; i < data.Length; i++)
			{
				if (bytes[i - 3] == '\r' && bytes[i - 2] == '\n' && bytes[i - 1] == '\r' && bytes[i] == '\n')
				{
					head = Encoding.ASCII.GetString(bytes, 0, i - 3);
					leftover = new byte[data.Length - (i + 1)];
					Array.Copy(bytes, i + 1, leftover, 0, leftover.Length);
					return true;
				}
			}
		}
		return false;
	}

	static byte[] ReadBody(Stream stream, byte[] leftover, int length)
	{
		var body = new byte[length];
		int have = Math.Min(leftover.Length, length);
		Array.Copy(leftover, body, have);
		while (have < length)
		{
			int n = stream.Read(body, have, length - have);
			if (n <= 0)
				break;
			have += n;
		}
		return body;
	}

	static void Respond(Stream stream, int code, string? contentType = null, byte[]? body = null, long length = 0)
	{
		var head = new StringBuilder()
			.Append($"HTTP/1.1 {code} {Reason(code)}\r\n")
			.Append(contentType != null ? $"Content-Type: {contentType}\r\n" : "")
			.Append($"Content-Length: {(body != null ? body.Length : length)}\r\n")
			.Append("Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n")
			.ToString();
		var headBytes = Encoding.ASCII.GetBytes(head);
		stream.Write(headBytes, 0, headBytes.Length);
		if (body != null)
			stream.Write(body, 0, body.Length);
		stream.Flush();
	}

	static string? QueryValue(string query, string key)
	{
		foreach (var pair in query.Split('&'))
		{
			var eq = pair.IndexOf('=');
			if (eq > 0 && Uri.UnescapeDataString(pair.Substring(0, eq)) == key)
				return Uri.UnescapeDataString(pair.Substring(eq + 1).Replace('+', ' '));
		}
		return null;
	}

	static string Reason(int code) => code switch
	{
		200 => "OK",
		204 => "No Content",
		400 => "Bad Request",
		403 => "Forbidden",
		404 => "Not Found",
		405 => "Method Not Allowed",
		409 => "Conflict",
		413 => "Payload Too Large",
		503 => "Service Unavailable",
		_ => "Error",
	};

	static string ContentType(string file) => Path.GetExtension(file).ToLowerInvariant() switch
	{
		".html" => "text/html; charset=utf-8",
		".js" => "text/javascript; charset=utf-8",
		".css" => "text/css; charset=utf-8",
		".json" or ".map" => "application/json",
		".png" => "image/png",
		".jpg" or ".jpeg" => "image/jpeg",
		".wasm" => "application/wasm",
		".ico" => "image/x-icon",
		".ogg" => "audio/ogg",
		".wav" => "audio/wav",
		".mp3" => "audio/mpeg",
		_ => "application/octet-stream",
	};

	static string NewToken()
	{
		var bytes = new byte[16];
		using (var rng = RandomNumberGenerator.Create())
			rng.GetBytes(bytes);
		return BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant();
	}

	public void Dispose()
	{
		running = false;
		listener.Stop();
	}
}
