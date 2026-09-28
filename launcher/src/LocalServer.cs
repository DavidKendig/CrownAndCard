// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace CrownAndCard.Launcher;

/**
	A tiny HTTP server on 127.0.0.1 (never reachable from other machines).

	- Serves the web build of the game from `WebRoot`.
	- Receives the game's state heartbeats and events at `api/state` and `api/event`.

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

	public int Port { get; }
	public string BasePath => $"/s/{token}/";
	public string BaseUrl => $"http://127.0.0.1:{Port}{BasePath}";
	public string ApiUrl => BaseUrl + "api";

	/** Folder served to the game window. Null serves nothing. **/
	public volatile string? WebRoot;

	/** Raised on a worker thread with the endpoint ("state" or "event") and the raw JSON body. **/
	public event Action<string, string>? Posted;

	public LocalServer(GuestRegisterStore? register = null)
	{
		this.register = register ?? new GuestRegisterStore(Path.Combine(Paths.DataDir, "saves", "guest-register.json"));
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
			}
		}
		catch (Exception e)
		{
			Log.Write("Local server: " + e.Message);
		}
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

	static string Reason(int code) => code switch
	{
		200 => "OK",
		204 => "No Content",
		400 => "Bad Request",
		403 => "Forbidden",
		404 => "Not Found",
		405 => "Method Not Allowed",
		413 => "Payload Too Large",
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
