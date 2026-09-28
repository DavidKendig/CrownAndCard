// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.IO;
using System.Net;
using CrownAndCard.Launcher;

static class VerifyGuestRegister
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
	}
}
