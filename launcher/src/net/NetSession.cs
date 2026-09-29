// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace CrownAndCard.Launcher;

/**
	A multiplayer session (GAME_DESIGN.md §13.13): the host's launcher listens
	for friends with a join code; each guest's launcher holds one connection
	to it. Everything between launchers is newline-delimited JSON over TCP.

	- The host relays: guests can only message the host, and the host stamps
	  every relayed message with the sender's id, so no one can speak for
	  another player. The game decides what the messages mean.
	- A guest must send the session key from the code, the same build and a
	  name within a few seconds, or it's dropped. Six players at most.
	- The game talks only to its own launcher: `Subscribe` feeds the local
	  server's `api/net/events` stream, and `SendFromGame` takes what the game
	  posts to `api/net/send`.
**/
sealed class NetSession : IDisposable
{
	public const int DefaultPort = 47724;
	public const int MaxPlayers = 6;
	const int MaxLineBytes = 256 * 1024;
	const int HelloSeconds = 5;
	const int MaxLinesPerSecond = 200;

	public sealed class Peer
	{
		public int Id { get; }
		public string Name { get; }
		public Peer(int id, string name) { Id = id; Name = name; }
	}

	/** One game's view of the session: lines for `api/net/events`. **/
	public sealed class Feed : IDisposable
	{
		public readonly BlockingCollection<string> Lines = new(new ConcurrentQueue<string>(), 4096);
		readonly NetSession owner;
		internal Feed(NetSession owner) { this.owner = owner; }
		public void Dispose() => owner.Unsubscribe(this);
	}

	sealed class Connection
	{
		public readonly TcpClient Client;
		public readonly Stream Stream;
		public readonly object WriteLock = new();
		public int Id;
		public string Name = "";
		public Connection(TcpClient client) { Client = client; Stream = client.GetStream(); }
	}

	public bool IsHost { get; }
	public string Build { get; }
	public string Name { get; }

	/** The code to share (host only). **/
	public string? JoinCode { get; private set; }

	/** The address and port the code points at (host only). **/
	public IPEndPoint? Advertised { get; private set; }

	/** This launcher's player id: 0 for the host. **/
	public int You { get; private set; }

	/** Set once the session is over, with the reason. **/
	public string? Ended { get; private set; }

	/** Raised on worker threads when the roster changes or the session ends. **/
	public event Action? Changed;

	readonly object gate = new();
	readonly List<Peer> peers = [];
	readonly List<Feed> feeds = [];
	readonly List<Connection> guests = [];
	TcpListener? listener;
	Connection? host;
	uint key;
	int nextId = 1;
	volatile bool running = true;

	NetSession(bool isHost, string name, string build)
	{
		IsHost = isHost;
		Name = CleanName(name);
		Build = build;
	}

	// --- Hosting -----------------------------------------------------------

	/** Starts listening. `advertise` overrides the address in the join code (for example a public address). **/
	public static NetSession Host(string name, string build, int port = DefaultPort, IPAddress? advertise = null)
	{
		var s = new NetSession(true, name, build);
		s.key = RandomKey();
		// A loopback-only session (tests) listens on loopback alone, so it never trips a firewall prompt.
		s.listener = new TcpListener(advertise != null && IPAddress.IsLoopback(advertise) ? IPAddress.Loopback : IPAddress.Any, port);
		s.listener.Start();
		int actual = ((IPEndPoint)s.listener.LocalEndpoint).Port;
		var address = advertise ?? LocalAddress() ?? IPAddress.Loopback;
		s.Advertised = new IPEndPoint(address, actual);
		s.JoinCode = Launcher.JoinCode.Encode(address, actual, s.key);
		s.peers.Add(new Peer(0, s.Name));
		new Thread(s.AcceptLoop) { IsBackground = true, Name = "NetSession accept" }.Start();
		return s;
	}

	void AcceptLoop()
	{
		while (running)
		{
			TcpClient client;
			try { client = listener!.AcceptTcpClient(); }
			catch { if (!running) return; continue; }
			new Thread(() => ServeGuest(client)) { IsBackground = true, Name = "NetSession guest" }.Start();
		}
	}

	void ServeGuest(TcpClient client)
	{
		var c = new Connection(client);
		try
		{
			client.NoDelay = true;
			client.ReceiveTimeout = HelloSeconds * 1000;
			var reader = new LineReader(c.Stream);
			var hello = Json.Obj(Json.Parse(reader.ReadLine() ?? ""));
			string? refusal = null;
			if (hello == null || Json.Str(hello, "t") != "hello")
				return;
			if (Json.Str(hello, "key") != key.ToString())
				refusal = "That join code isn't for this table (or the host started a new session).";
			else if (Json.Str(hello, "build") != Build)
				refusal = $"The host is on build {Build} and you're on {Json.Str(hello, "build")}. Everyone needs the same version.";
			lock (gate)
			{
				if (refusal == null && (!running || peers.Count >= MaxPlayers))
					refusal = "The table is full.";
				if (refusal == null)
				{
					c.Id = nextId++;
					c.Name = UniqueName(CleanName(Json.Str(hello, "name")));
					guests.Add(c);
					peers.Add(new Peer(c.Id, c.Name));
				}
			}
			if (refusal != null)
			{
				Write(c, Line(new Dictionary<string, object> { ["t"] = "reject", ["reason"] = refusal }));
				return;
			}
			Write(c, Line(new Dictionary<string, object> { ["t"] = "welcome", ["you"] = c.Id, ["peers"] = PeerList() }));
			RosterChanged();
			client.ReceiveTimeout = 0;
			var window = DateTime.UtcNow;
			int lines = 0;
			while (running)
			{
				var line = reader.ReadLine();
				if (line == null)
					break;
				if ((DateTime.UtcNow - window).TotalSeconds >= 1) { window = DateTime.UtcNow; lines = 0; }
				if (++lines > MaxLinesPerSecond)
					continue;
				var msg = Json.Obj(Json.Parse(line));
				// Guests may only message the host.
				if (msg != null && Json.Str(msg, "t") == "msg" && Json.Int(msg, -99, "to") is 0 or -1 && msg.TryGetValue("body", out var body))
					Publish(MsgEvent(c.Id, body));
			}
		}
		catch (Exception e) when (e is IOException or ObjectDisposedException or InvalidOperationException or ArgumentException)
		{
		}
		finally
		{
			bool was;
			lock (gate)
			{
				was = guests.Remove(c);
				if (was)
					peers.RemoveAll(p => p.Id == c.Id);
			}
			try { client.Close(); } catch { }
			if (was && running)
				RosterChanged();
		}
	}

	string UniqueName(string name)
	{
		var taken = new HashSet<string>(peers.Select(p => p.Name), StringComparer.OrdinalIgnoreCase);
		if (!taken.Contains(name))
			return name;
		for (int i = 2; ; i++)
			if (!taken.Contains($"{name} {i}"))
				return $"{name} {i}";
	}

	void RosterChanged()
	{
		var roster = Line(new Dictionary<string, object> { ["t"] = "roster", ["peers"] = PeerList() });
		foreach (var g in Guests())
			Write(g, roster);
		Publish(RosterEvent());
		Changed?.Invoke();
	}

	Connection[] Guests() { lock (gate) return guests.ToArray(); }

	// --- Joining -----------------------------------------------------------

	/** Connects to a host. Throws with a readable reason if it can't. **/
	public static NetSession Join(string code, string name, string build)
	{
		if (!Launcher.JoinCode.TryDecode(code, out var endpoint, out var key))
			throw new ArgumentException("That doesn't look like a join code (16 letters and digits, like ABCD-EFGH-JKMN-PQRS).");
		var s = new NetSession(false, name, build);
		var client = new TcpClient { NoDelay = true };
		var connect = client.BeginConnect(endpoint.Address, endpoint.Port, null, null);
		if (!connect.AsyncWaitHandle.WaitOne(TimeSpan.FromSeconds(6)) || !client.Connected)
		{
			client.Close();
			throw new IOException($"Couldn't reach the host at {endpoint}. Check the code, and that the host's firewall (and router, over the internet) lets port {endpoint.Port} in.");
		}
		client.EndConnect(connect);
		var c = new Connection(client);
		client.ReceiveTimeout = HelloSeconds * 1000;
		Write(c, Line(new Dictionary<string, object> { ["t"] = "hello", ["key"] = key.ToString(), ["build"] = build, ["name"] = s.Name }));
		var reader = new LineReader(c.Stream);
		var reply = Json.Obj(Json.Parse(reader.ReadLine() ?? "null"));
		if (reply == null)
		{
			client.Close();
			throw new IOException("The host didn't answer.");
		}
		if (Json.Str(reply, "t") == "reject")
		{
			client.Close();
			throw new IOException(Json.Str(reply, "reason") ?? "The host turned us away.");
		}
		s.host = c;
		s.You = Json.Int(reply, -1, "you");
		s.SetPeers(reply);
		client.ReceiveTimeout = 0;
		new Thread(() => s.ReadHost(reader)) { IsBackground = true, Name = "NetSession host" }.Start();
		return s;
	}

	void ReadHost(LineReader reader)
	{
		string reason = "The host ended the session.";
		try
		{
			while (running)
			{
				var line = reader.ReadLine();
				if (line == null)
					break;
				var msg = Json.Obj(Json.Parse(line));
				switch (msg == null ? null : Json.Str(msg, "t"))
				{
					case "roster":
						SetPeers(msg!);
						Publish(RosterEvent());
						Changed?.Invoke();
						break;
					case "msg":
						if (msg!.TryGetValue("body", out var body))
							Publish(MsgEvent(0, body));
						break;
				}
			}
		}
		catch (Exception e) when (e is IOException or ObjectDisposedException or InvalidOperationException or ArgumentException)
		{
			reason = "Lost the connection to the host.";
		}
		End(running ? reason : "You left the session.");
	}

	void SetPeers(Dictionary<string, object> msg)
	{
		lock (gate)
		{
			peers.Clear();
			if (Json.Get(msg, "peers") is object[] list)
				foreach (var p in list)
					peers.Add(new Peer(Json.Int(p, -1, "id"), Json.Str(p, "name") ?? "?"));
		}
	}

	// --- The game's side ---------------------------------------------------

	public IReadOnlyList<Peer> Peers { get { lock (gate) return peers.ToArray(); } }

	/** A new event stream for the game, starting with the current roster. **/
	public Feed Subscribe()
	{
		var f = new Feed(this);
		lock (gate)
		{
			feeds.Add(f);
			f.Lines.TryAdd(Ended != null ? ClosedEvent(Ended) : RosterEvent());
		}
		return f;
	}

	void Unsubscribe(Feed f)
	{
		lock (gate)
			feeds.Remove(f);
	}

	/** Something the game posted: `to` is a player id, or -1 for everyone else. **/
	public void SendFromGame(int to, object? body)
	{
		if (Ended != null || body == null)
			return;
		if (IsHost)
		{
			var line = Line(new Dictionary<string, object> { ["t"] = "msg", ["from"] = 0, ["body"] = body });
			foreach (var g in Guests())
				if (to == -1 || g.Id == to)
					Write(g, line);
		}
		else if (host != null)
			Write(host, Line(new Dictionary<string, object> { ["t"] = "msg", ["to"] = 0, ["body"] = body }));
	}

	void Publish(string line)
	{
		lock (gate)
			foreach (var f in feeds)
			{
				// A feed closed by Dispose takes nothing more.
				if (f.Lines.IsAddingCompleted)
					continue;
				try { f.Lines.TryAdd(line); }
				catch (InvalidOperationException) { }
			}
	}

	string RosterEvent() => Line(new Dictionary<string, object> { ["type"] = "roster", ["you"] = You, ["peers"] = PeerList() });

	static string MsgEvent(int from, object body) => Line(new Dictionary<string, object> { ["type"] = "msg", ["from"] = from, ["body"] = body });

	static string ClosedEvent(string reason) => Line(new Dictionary<string, object> { ["type"] = "closed", ["reason"] = reason });

	object[] PeerList()
	{
		lock (gate)
			return peers.Select(p => (object)new Dictionary<string, object> { ["id"] = p.Id, ["name"] = p.Name }).ToArray();
	}

	// --- Plumbing ------------------------------------------------------------

	static string Line(object value) => Json.Write(value, false);

	static void Write(Connection c, string line)
	{
		var bytes = Encoding.UTF8.GetBytes(line + "\n");
		try
		{
			lock (c.WriteLock)
			{
				c.Stream.Write(bytes, 0, bytes.Length);
				c.Stream.Flush();
			}
		}
		catch (Exception e) when (e is IOException or ObjectDisposedException or InvalidOperationException)
		{
			try { c.Client.Close(); } catch { }
		}
	}

	void End(string reason)
	{
		lock (gate)
		{
			if (Ended != null)
				return;
			Ended = reason;
		}
		Publish(ClosedEvent(reason));
		Changed?.Invoke();
	}

	public void Dispose()
	{
		bool wasRunning = running;
		running = false;
		End(IsHost ? "The host ended the session." : "You left the session.");
		if (!wasRunning)
			return;
		try { listener?.Stop(); } catch { }
		foreach (var g in Guests())
			try { g.Client.Close(); } catch { }
		try { host?.Client.Close(); } catch { }
		lock (gate)
			foreach (var f in feeds)
				try { f.Lines.CompleteAdding(); } catch (ObjectDisposedException) { }
	}

	static uint RandomKey()
	{
		var bytes = new byte[4];
		using (var rng = RandomNumberGenerator.Create())
			rng.GetBytes(bytes);
		return BitConverter.ToUInt32(bytes, 0);
	}

	static string CleanName(string? name)
	{
		var n = new string((name ?? "").Where(ch => !char.IsControl(ch)).ToArray()).Trim();
		if (n.Length > 20)
			n = n.Substring(0, 20).Trim();
		return n.Length == 0 ? "Guest" : n;
	}

	/** The address friends on this network would reach: the first running, non-loopback IPv4 interface, preferring one with a gateway. **/
	public static IPAddress? LocalAddress()
	{
		IPAddress? fallback = null;
		try
		{
			foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
			{
				if (ni.OperationalStatus != OperationalStatus.Up || ni.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel)
					continue;
				var props = ni.GetIPProperties();
				foreach (var ua in props.UnicastAddresses)
				{
					if (ua.Address.AddressFamily != AddressFamily.InterNetwork || IPAddress.IsLoopback(ua.Address) || ua.Address.ToString().StartsWith("169.254."))
						continue;
					if (props.GatewayAddresses.Any(g => g.Address.AddressFamily == AddressFamily.InterNetwork && !g.Address.Equals(IPAddress.Any)))
						return ua.Address;
					fallback ??= ua.Address;
				}
			}
		}
		catch (NetworkInformationException)
		{
		}
		return fallback;
	}

	/** Reads UTF-8 lines, refusing any longer than MaxLineBytes. **/
	sealed class LineReader
	{
		readonly Stream stream;
		readonly byte[] buffer = new byte[8192];
		int start, end;

		public LineReader(Stream stream) { this.stream = stream; }

		public string? ReadLine()
		{
			var line = new MemoryStream();
			while (true)
			{
				if (start == end)
				{
					start = 0;
					end = stream.Read(buffer, 0, buffer.Length);
					if (end <= 0)
					{
						end = 0;
						return null;
					}
				}
				int nl = Array.IndexOf(buffer, (byte)'\n', start, end - start);
				int stop = nl < 0 ? end : nl;
				line.Write(buffer, start, stop - start);
				if (line.Length > MaxLineBytes)
					throw new InvalidOperationException("Message too long");
				start = nl < 0 ? end : nl + 1;
				if (nl >= 0)
					return Encoding.UTF8.GetString(line.ToArray()).TrimEnd('\r');
			}
		}
	}
}
