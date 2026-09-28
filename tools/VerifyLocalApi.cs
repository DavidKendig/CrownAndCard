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
	}

	static readonly string Crlf = "" + (char)13 + (char)10;
}
