// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

namespace CrownAndCard.Launcher;

/** One row in the Reports list. **/
sealed class SessionSummary
{
	public string Dir = "";
	public DateTime Started;
	public TimeSpan? Length;
	public string Status = "unknown";
	public string LastRoom = "";
	public int Errors;
	public string Build = "";
}

/**
	Records one play session for error tracking (§13.12), in
	%LOCALAPPDATA%\CrownAndCard\sessions\<start time>\:

	- session.json        launcher, system, settings, result and the latest summary
	- state.json          the game's most recent state heartbeat
	- state-history.json  the last 120 heartbeats (about 10 minutes)
	- events.jsonl        start, error and quit events, one per line
	- game-output.log     console output from native builds
	- notes.log           the launcher's own observations (hangs, lost contact)

	Nothing here is uploaded anywhere.
**/
sealed class SessionRecorder
{
	const int MaxHistory = 120;
	const int KeepSessions = 30;

	public string Dir { get; }
	public DateTime StartedAt { get; } = DateTime.Now;
	public DateTime LastContact { get; private set; }
	public int Heartbeats { get; private set; }
	public int Errors { get; private set; }
	public string LastRoom { get; private set; } = "";
	public DateTime? QuitAt { get; private set; }
	public bool Ended { get; private set; }

	/** Raised on whichever thread recorded something. **/
	public event Action? Changed;

	readonly object gate = new();
	readonly Dictionary<string, object?> info = new();
	readonly Queue<object> history = new();

	SessionRecorder(GamePlan plan, LauncherSettings settings)
	{
		var id = StartedAt.ToString("yyyy-MM-dd_HH-mm-ss", CultureInfo.InvariantCulture);
		Dir = Path.Combine(Paths.SessionsDir, id);
		for (int n = 2; Directory.Exists(Dir); n++)
			Dir = Path.Combine(Paths.SessionsDir, $"{id}_{n}");
		Directory.CreateDirectory(Dir);

		info["status"] = "running";
		info["startedAt"] = Iso(StartedAt);
		info["launcherVersion"] = Program.Version;
		info["game"] = plan.Describe();
		info["gameKind"] = plan.Kind.ToString();
		info["system"] = new Dictionary<string, object>
		{
			["os"] = Environment.OSVersion.VersionString,
			["is64BitOS"] = Environment.Is64BitOperatingSystem,
			["processors"] = Environment.ProcessorCount,
			["clr"] = Environment.Version.ToString(),
			["screen"] = $"{System.Windows.Forms.Screen.PrimaryScreen.Bounds.Width}x{System.Windows.Forms.Screen.PrimaryScreen.Bounds.Height}",
		};
		info["launcherSettings"] = settings.ToReport();
	}

	public static SessionRecorder Begin(GamePlan plan, LauncherSettings settings)
	{
		var recorder = new SessionRecorder(plan, settings);
		recorder.WriteInfo();
		Prune();
		return recorder;
	}

	public void SetLaunchCommand(string command)
	{
		lock (gate)
		{
			info["launchCommand"] = command;
			WriteInfo();
		}
	}

	/** Handles a heartbeat or event posted by the game. The body is untrusted data. **/
	public void OnPost(string endpoint, string body)
	{
		object? parsed;
		try
		{
			parsed = Json.Parse(body);
		}
		catch
		{
			parsed = null;
		}
		lock (gate)
		{
			if (parsed == null)
			{
				Append("notes.log", $"{Now()}  Ignored a malformed {endpoint} report ({body.Length} bytes)");
				return;
			}
			LastContact = DateTime.Now;
			if (endpoint == "state")
			{
				Heartbeats++;
				history.Enqueue(parsed);
				while (history.Count > MaxHistory)
					history.Dequeue();
				LastRoom = Json.Str(parsed, "state", "room") ?? LastRoom;
				info["build"] = Json.Str(parsed, "build") ?? info.GetValueOr("build");
				info["lastState"] = Json.Get(parsed, "state");
				info["lastHeartbeatAt"] = Iso(LastContact);
				info["heartbeats"] = Heartbeats;
				Write("state.json", Json.Write(parsed));
				Write("state-history.json", Json.Write(history.ToArray()));
			}
			else
			{
				var kind = Json.Str(parsed, "kind") ?? "event";
				Append("events.jsonl", Json.Write(parsed, indent: false));
				switch (kind)
				{
					case "start":
						QuitAt = null; // a page reload sends quit, then start again
						info["platform"] = Json.Get(parsed, "extra", "platform");
						info["gameSettings"] = Json.Get(parsed, "extra", "settings");
						break;
					case "error":
						Errors++;
						info["errors"] = Errors;
						info["lastError"] = Json.Str(parsed, "message");
						break;
					case "quit":
						QuitAt = DateTime.Now;
						break;
				}
				var room = Json.Str(parsed, "state", "room");
				if (room != null)
					LastRoom = room;
			}
			info["lastRoom"] = LastRoom;
			WriteInfo();
		}
		Changed?.Invoke();
	}

	public void OnOutput(string? line)
	{
		if (line == null)
			return;
		lock (gate)
			Append("game-output.log", line);
	}

	public void Note(string text)
	{
		lock (gate)
			Append("notes.log", $"{Now()}  {text}");
		Changed?.Invoke();
	}

	/** Finishes the session and works out how it went. Safe to call more than once. **/
	public string End(int? exitCode, string reason)
	{
		string status;
		lock (gate)
		{
			if (Ended)
				return (string)info["status"]!;
			Ended = true;
			status = exitCode is int code && code != 0 ? "crashed"
				: Errors > 0 ? "errors"
				: reason.StartsWith("lost", StringComparison.Ordinal) ? "lost-contact"
				: reason.StartsWith("the launcher closed", StringComparison.Ordinal) ? "unknown" // the game's end wasn't seen
				: "ok";
			info["status"] = status;
			info["endedAt"] = Iso(DateTime.Now);
			info["endReason"] = reason;
			if (exitCode != null)
				info["exitCode"] = exitCode;
			WriteInfo();
		}
		Changed?.Invoke();
		return status;
	}

	/** Sessions left "running" (the launcher closed or crashed mid-game) are marked unknown at startup. **/
	public static void RecoverAbandoned()
	{
		foreach (var dir in SafeDirs())
		{
			var file = Path.Combine(dir, "session.json");
			try
			{
				if (Json.Parse(File.ReadAllText(file)) is Dictionary<string, object> d && Json.Str(d, "status") == "running")
				{
					d["status"] = "unknown";
					d["endReason"] = "The launcher closed before the game ended";
					File.WriteAllText(file, Json.Write(d));
				}
			}
			catch
			{
				// Unreadable sessions are shown as unknown in the list anyway.
			}
		}
	}

	public static List<SessionSummary> ListAll()
	{
		var list = new List<SessionSummary>();
		foreach (var dir in SafeDirs())
		{
			var s = new SessionSummary { Dir = dir };
			try
			{
				var d = Json.Parse(File.ReadAllText(Path.Combine(dir, "session.json")));
				DateTime.TryParse(Json.Str(d, "startedAt"), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out s.Started);
				if (DateTime.TryParse(Json.Str(d, "endedAt"), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var ended))
					s.Length = ended - s.Started;
				s.Status = Json.Str(d, "status") ?? "unknown";
				s.LastRoom = Json.Str(d, "lastRoom") ?? "";
				s.Errors = Json.Int(d, 0, "errors");
				s.Build = Json.Str(d, "build") ?? "";
			}
			catch
			{
				s.Started = Directory.GetCreationTime(dir);
			}
			list.Add(s);
		}
		return list.OrderByDescending(s => s.Started).ToList();
	}

	/** Plain-text report for the clipboard: the summary, the last state and the recent events. **/
	public static string BuildReport(string dir)
	{
		var sb = new StringBuilder();
		sb.AppendLine("Crown & Card session report");
		sb.AppendLine("Folder: " + dir);
		sb.AppendLine();
		foreach (var (title, file, tail) in new[] { ("Session", "session.json", 0), ("Last game state", "state.json", 0), ("Events (latest last)", "events.jsonl", 25), ("Launcher notes", "notes.log", 25), ("Game output (latest last)", "game-output.log", 40) })
		{
			var path = Path.Combine(dir, file);
			if (!File.Exists(path))
				continue;
			sb.AppendLine($"== {title} ==");
			try
			{
				var text = File.ReadAllText(path);
				if (tail > 0)
				{
					var lines = text.Split(['\n'], StringSplitOptions.RemoveEmptyEntries);
					text = string.Join("\n", lines.Skip(Math.Max(0, lines.Length - tail)));
				}
				sb.AppendLine(text.TrimEnd());
			}
			catch (Exception e)
			{
				sb.AppendLine("(unreadable: " + e.Message + ")");
			}
			sb.AppendLine();
		}
		return sb.ToString();
	}

	public static void DeleteAll()
	{
		foreach (var dir in SafeDirs())
		{
			try
			{
				Directory.Delete(dir, true);
			}
			catch (Exception e)
			{
				Log.Write($"Couldn't delete {dir}: {e.Message}");
			}
		}
	}

	static void Prune()
	{
		var old = SafeDirs().OrderByDescending(d => d, StringComparer.Ordinal).Skip(KeepSessions);
		foreach (var dir in old)
		{
			try
			{
				Directory.Delete(dir, true);
			}
			catch
			{
				// Try again next time.
			}
		}
	}

	static IEnumerable<string> SafeDirs()
	{
		try
		{
			return Directory.GetDirectories(Paths.SessionsDir);
		}
		catch
		{
			return [];
		}
	}

	void WriteInfo() => Write("session.json", Json.Write(info));

	void Write(string file, string text)
	{
		try
		{
			File.WriteAllText(Path.Combine(Dir, file), text);
		}
		catch (Exception e)
		{
			Log.Write($"Session write failed ({file}): {e.Message}");
		}
	}

	void Append(string file, string line)
	{
		try
		{
			File.AppendAllText(Path.Combine(Dir, file), line + Environment.NewLine);
		}
		catch (Exception e)
		{
			Log.Write($"Session append failed ({file}): {e.Message}");
		}
	}

	static string Iso(DateTime t) => t.ToString("o", CultureInfo.InvariantCulture);

	static string Now() => DateTime.Now.ToString("HH:mm:ss", CultureInfo.InvariantCulture);
}

static class DictionaryExtensions
{
	public static object? GetValueOr(this Dictionary<string, object?> d, string key) => d.TryGetValue(key, out var v) ? v : null;
}
