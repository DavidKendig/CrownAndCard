// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.IO;
using System.Net;
using CrownAndCard.Launcher;

/** Checks the launcher's local API: the Guest Register (saves) and custom maps (Haxen). */
static class VerifyLocalApi
{
	static void Main(string[] args)
	{
		var path=Path.Combine(Path.GetFullPath(args[0]), "register-test-"+Guid.NewGuid().ToString("N")+".json");
		var store=new GuestRegisterStore(path);
		if(store.Read()!="null") throw new Exception("New page was not empty");
		const string first="{\"version\":1,\"checkIns\":1,\"rooms\":[\"Entrance Hall\"]}";
		const string second="{\"version\":1,\"checkIns\":2,\"rooms\":[\"Entrance Hall\",\"Rotunda\"],\"sovereigns\":1185,\"marker\":0}";
		store.Write(first);
		var reopened=new GuestRegisterStore(path);
		if(reopened.Read()!=first) throw new Exception("Save did not survive reopening");
		reopened.Write(second);
		if(reopened.Read()!=second || File.ReadAllText(path+".bak")!=first) throw new Exception("Atomic replacement/backup failed");
		foreach(var invalid in new[]{"null","{}","[]","{\"version\":2,\"checkIns\":0,\"rooms\":[]}","{\"version\":1,\"checkIns\":1,\"rooms\":[4]}","{\"version\":1,\"checkIns\":1,\"rooms\":[],\"sovereigns\":-1}"})
		{
			bool rejected=false;
			try { reopened.Write(invalid); } catch(ArgumentException) { rejected=true; }
			if(!rejected || reopened.Read()!=second) throw new Exception("Invalid save replaced good checkpoint");
		}
		Console.WriteLine("Guest Register: persistence across instances, atomic replacement, backup and invalid-page preservation PASS");
		// Start on two different random ports: the page must survive a launcher restart.
		string oldOrigin;
		using(var server=new LocalServer(reopened))
		using(var client=new WebClient())
		{
			oldOrigin=server.BaseUrl;
			if(client.DownloadString(server.ApiUrl+"/save")!=second) throw new Exception("HTTP load failed");
			client.Headers[HttpRequestHeader.ContentType]="application/json";
			client.UploadString(server.ApiUrl+"/save","POST",first);
			if(reopened.Read()!=first) throw new Exception("HTTP save acknowledged without persisting");
			try { client.DownloadString("http://127.0.0.1:"+server.Port+"/api/save"); throw new Exception("Missing token accepted"); }
			catch(WebException e) { if(((HttpWebResponse)e.Response!).StatusCode!=HttpStatusCode.NotFound) throw; }
		}
		using(var server=new LocalServer(new GuestRegisterStore(path)))
		using(var client=new WebClient())
		{
			if(server.BaseUrl==oldOrigin || client.DownloadString(server.ApiUrl+"/save")!=first) throw new Exception("Restart lost save");
		}
		Console.WriteLine("Local save API: GET/POST, token isolation and persistence across server restarts PASS");
		VerifyMaps(Path.GetFullPath(args[0]), path);
	}

	static int Status(Action call)
	{
		try { call(); return 200; }
		catch (WebException e) { return (int)((HttpWebResponse)e.Response!).StatusCode; }
	}

	static void VerifyMaps(string root, string registerPath)
	{
		var maps = new MapStore(Path.Combine(root, "maps-" + Guid.NewGuid().ToString("N")));
		const string good = "{\"format\":\"crown-and-card-map\",\"version\":1,\"name\":\"Test Map\",\"rows\":[\"###\",\"#a#\",\"###\"]}";
		maps.Write("Test Map", good);
		if (maps.Read("Test Map") != good || !maps.List().Contains("Test Map")) throw new Exception("Map store round trip failed");
		foreach (var bad in new[] { "manor", "Manor", "../x", "a/b", "", " lead", "x:y" })
			if (MapStore.ValidName(bad)) throw new Exception("Accepted bad map name: " + bad);
		foreach (var notMap in new[] { "not json", "{}", "{\"format\":\"other\",\"rows\":[]}" })
		{
			bool rejected = false;
			try { maps.Write("Junk", notMap); } catch (ArgumentException) { rejected = true; }
			if (!rejected || maps.Read("Junk") != null) throw new Exception("Accepted something that isn't a map");
		}
		Console.WriteLine("Map store: round trip, name rules and rejecting non-maps PASS");

		using var server = new LocalServer(new GuestRegisterStore(registerPath), maps);
		using var client = new WebClient();
		string? requested = null;
		server.PlaytestRequested = name => { requested = name; return null; };
		var api = server.ApiUrl;
		if (!client.DownloadString(api + "/maps").Contains("Test Map")) throw new Exception("Map list missing");
		client.Headers[HttpRequestHeader.ContentType] = "application/json";
		client.UploadString(api + "/maps/Other%20Map", "PUT", good.Replace("Test Map", "Other Map"));
		if (maps.Read("Other Map") == null || !client.DownloadString(api + "/maps/Other%20Map").Contains("Other Map")) throw new Exception("PUT/GET failed");
		if (Status(() => client.UploadString(api + "/maps/Bad", "PUT", "{}")) != 400) throw new Exception("PUT of a non-map not rejected");
		if (Status(() => client.UploadString(api + "/maps/manor", "PUT", good)) != 400) throw new Exception("Reserved name not rejected");
		if (Status(() => client.UploadString(api + "/maps/Other%20Map", "DELETE", "")) != 200 || maps.Read("Other Map") != null) throw new Exception("DELETE failed");
		if (Status(() => client.DownloadString(api + "/maps/Other%20Map")) != 404) throw new Exception("Deleted map still served");
		if (Status(() => client.DownloadString("http://127.0.0.1:" + server.Port + "/api/maps")) != 404) throw new Exception("Maps served without the token");
		Console.WriteLine("Maps API: list, save, load, delete, validation and token isolation PASS");

		if (Status(() => client.UploadString(api + "/playtest?map=Test%20Map", "POST", "")) != 200 || requested != "Test Map") throw new Exception("Play test not requested");
		server.PlaytestRequested = _ => "busy";
		if (Status(() => client.UploadString(api + "/playtest?map=Test%20Map", "POST", "")) != 409) throw new Exception("Busy launcher not reported");
		if (Status(() => client.UploadString(api + "/playtest?map=Nope", "POST", "")) != 404) throw new Exception("Missing map not reported");
		Console.WriteLine("Play test API: starts the named map, reports a running game and missing maps PASS");

		// The controller stream: an event-stream that starts with the current pad state.
		using (var tcp = new System.Net.Sockets.TcpClient("127.0.0.1", server.Port))
		{
			var net = tcp.GetStream();
			net.ReadTimeout = 5000;
			var request = System.Text.Encoding.ASCII.GetBytes($"GET {server.BasePath}api/pad HTTP/1.1{Crlf}Host: 127.0.0.1{Crlf}{Crlf}");
			net.Write(request, 0, request.Length);
			var buffer = new byte[4096];
			var text = "";
			while (!text.Contains("data: {"))
			{
				int n = net.Read(buffer, 0, buffer.Length);
				if (n <= 0) break;
				text += System.Text.Encoding.ASCII.GetString(buffer, 0, n);
			}
			if (!text.Contains("text/event-stream") || !text.Contains("data: {\"c\":")) throw new Exception("Pad stream didn't start: " + text);
			Console.WriteLine("Pad stream: event-stream of controller state (" + (text.Contains("\"c\":1") ? "controller connected" : "no controller") + ") PASS");
		}
		VerifyNet(registerPath, maps);
	}

	/** Multiplayer (§13.13): join codes, the host/guest handshake, and relaying through each launcher's local API. **/
	static void VerifyNet(string registerPath, MapStore maps)
	{
		var address = IPAddress.Parse("192.168.1.23");
		var code = JoinCode.Encode(address, 47724, 0xDEADBEEF);
		if (code.Length != 19 || code[4] != '-') throw new Exception("Join code shape: " + code);
		if (!JoinCode.TryDecode(code.ToLowerInvariant().Replace("-", " "), out var ep, out var key) || !ep.Address.Equals(address) || ep.Port != 47724 || key != 0xDEADBEEF)
			throw new Exception("Join code round trip failed");
		foreach (var bad in new[] { "", "ABCD", code + "0", code.Replace(code[0], 'U') })
			if (JoinCode.TryDecode(bad, out _, out _)) throw new Exception("Accepted a bad join code: " + bad);
		Console.WriteLine("Join codes: round trip, forgiving input, bad codes refused PASS");

		using var host = NetSession.Host("Ada", "test-build", 0, IPAddress.Loopback);
		if (!JoinCode.TryDecode(host.JoinCode, out var hostEp, out var hostKey)) throw new Exception("Host code unreadable");
		Expect(() => NetSession.Join(JoinCode.Encode(IPAddress.Loopback, hostEp.Port, hostKey + 1), "Mallory", "test-build"), "isn't for this table");
		Expect(() => NetSession.Join(host.JoinCode!, "Old", "other-build"), "same version");
		using var bea = NetSession.Join(host.JoinCode!, "Bea", "test-build");
		using var cy = NetSession.Join(host.JoinCode!, "Bea", "test-build");
		WaitFor(() => host.Peers.Count == 3, "roster");
		if (bea.You != 1 || cy.You != 2 || host.Peers[2].Name != "Bea 2") throw new Exception("Ids or names wrong");
		Console.WriteLine("Sessions: key and build checks, ids, unique names PASS");

		using var hostServer = new LocalServer(new GuestRegisterStore(registerPath), maps) { Net = host };
		using var beaServer = new LocalServer(new GuestRegisterStore(registerPath), maps) { Net = bea };
		using var cyServer = new LocalServer(new GuestRegisterStore(registerPath), maps) { Net = cy };
		using var hostEvents = new EventReader(hostServer);
		using var beaEvents = new EventReader(beaServer);
		using var cyEvents = new EventReader(cyServer);
		hostEvents.WaitFor("\"type\":\"roster\"");
		beaEvents.WaitFor("\"you\":1");
		using var client = new WebClient();
		client.Headers[HttpRequestHeader.ContentType] = "application/json";
		client.UploadString(hostServer.ApiUrl + "/net/send", "POST", "{\"to\":1,\"body\":{\"t\":\"view\",\"n\":7}}");
		beaEvents.WaitFor("\"from\":0,\"body\":{\"t\":\"view\",\"n\":7}");
		// A guest can only reach the host, and can't pass itself off as anyone else.
		client.Headers[HttpRequestHeader.ContentType] = "application/json";
		client.UploadString(beaServer.ApiUrl + "/net/send", "POST", "{\"to\":2,\"from\":0,\"body\":{\"t\":\"act\",\"a\":\"fold\"}}");
		hostEvents.WaitFor("\"from\":1,\"body\":{\"t\":\"act\"");
		System.Threading.Thread.Sleep(300);
		if (cyEvents.Text.Contains("\"act\"")) throw new Exception("A guest's message reached another guest");
		if (cyEvents.Text.Contains("\"n\":7")) throw new Exception("A message for one guest reached another");
		client.Headers[HttpRequestHeader.ContentType] = "application/json";
		if (Status(() => client.UploadString(hostServer.ApiUrl + "/net/send", "POST", "not json")) != 400) throw new Exception("Bad send not refused");
		Console.WriteLine("Relay: host to one guest, guest to host only, sender stamped PASS");

		cy.Dispose();
		WaitFor(() => host.Peers.Count == 2, "leave");
		hostEvents.WaitFor("\"peers\":[{\"id\":0,\"name\":\"Ada\"},{\"id\":1,\"name\":\"Bea\"}]");
		host.Dispose();
		beaEvents.WaitFor("\"type\":\"closed\"");
		Console.WriteLine("Leaving: roster updates, and guests hear when the host ends the session PASS");

		// The game starts sessions itself, from the Private Party table, through the local API.
		using var a = new LocalServer(new GuestRegisterStore(registerPath), maps) { StartHost = _ => NetSession.Host("Ada", "test-build", 0, IPAddress.Loopback) };
		using var b = new LocalServer(new GuestRegisterStore(registerPath), maps) { StartJoin = c => NetSession.Join(c, "Bea", "test-build") };
		using var web = new WebClient();
		if (!web.DownloadString(a.ApiUrl + "/net/state").Contains("\"state\":\"none\"")) throw new Exception("State before hosting");
		if (Status(() => Post(web, a.ApiUrl + "/net/host", "{\"address\":\"not an address\"}")) != 400) throw new Exception("Bad address not refused");
		var hosted = Json.Obj(Json.Parse(Post(web, a.ApiUrl + "/net/host", "{}")));
		var joinCode = Json.Str(hosted, "code");
		if (Json.Str(hosted, "state") != "hosting" || string.IsNullOrEmpty(joinCode)) throw new Exception("Hosting didn't report a code");
		if (Status(() => Post(web, a.ApiUrl + "/net/host", "{}")) != 409) throw new Exception("Second session not refused");
		if (Status(() => Post(web, b.ApiUrl + "/net/join", "{\"code\":\"nonsense\"}")) != 400) throw new Exception("Bad code not refused");
		var joined = Post(web, b.ApiUrl + "/net/join", "{\"code\":\"" + joinCode + "\"}");
		if (!joined.Contains("\"state\":\"joined\"") || !joined.Contains("\"you\":1")) throw new Exception("Join through the API failed: " + joined);
		WaitFor(() => web.DownloadString(a.ApiUrl + "/net/state").Contains("\"name\":\"Bea\""), "the host to see the guest");
		Post(web, b.ApiUrl + "/net/leave", "");
		if (b.Net != null || !web.DownloadString(b.ApiUrl + "/net/state").Contains("\"state\":\"none\"")) throw new Exception("Leave didn't end the session");
		WaitFor(() => !web.DownloadString(a.ApiUrl + "/net/state").Contains("\"name\":\"Bea\""), "the host to see the guest leave");
		Post(web, a.ApiUrl + "/net/leave", "");
		Console.WriteLine("Session control API: host, join, state, leave, and refusals PASS");
	}

	static string Post(WebClient web, string url, string body)
	{
		web.Headers[HttpRequestHeader.ContentType] = "application/json";
		return web.UploadString(url, "POST", body);
	}

	static void Expect(Action call, string reasonPart)
	{
		try { call(); }
		catch (IOException e) when (e.Message.Contains(reasonPart)) { return; }
		throw new Exception("Expected a refusal mentioning: " + reasonPart);
	}

	static void WaitFor(Func<bool> done, string what)
	{
		for (int i = 0; i < 100 && !done(); i++) System.Threading.Thread.Sleep(50);
		if (!done()) throw new Exception("Timed out waiting for " + what);
	}

	/** Reads a local server's `api/net/events` stream in the background. **/
	sealed class EventReader : IDisposable
	{
		readonly System.Net.Sockets.TcpClient tcp;
		readonly System.Text.StringBuilder text = new();
		public string Text { get { lock (text) return text.ToString(); } }

		public EventReader(LocalServer server)
		{
			tcp = new System.Net.Sockets.TcpClient("127.0.0.1", server.Port);
			var net = tcp.GetStream();
			var request = System.Text.Encoding.ASCII.GetBytes($"GET {server.BasePath}api/net/events HTTP/1.1{Crlf}Host: 127.0.0.1{Crlf}{Crlf}");
			net.Write(request, 0, request.Length);
			new System.Threading.Thread(() =>
			{
				var buffer = new byte[8192];
				try
				{
					int n;
					while ((n = net.Read(buffer, 0, buffer.Length)) > 0)
						lock (text) text.Append(System.Text.Encoding.UTF8.GetString(buffer, 0, n));
				}
				catch { }
			}) { IsBackground = true }.Start();
		}

		public void WaitFor(string fragment)
		{
			for (int i = 0; i < 100 && !Text.Contains(fragment); i++) System.Threading.Thread.Sleep(50);
			if (!Text.Contains(fragment)) throw new Exception("Never saw " + fragment + " in: " + Text);
		}

		public void Dispose() => tcp.Close();
	}

	static readonly string Crlf = "" + (char)13 + (char)10;
}
