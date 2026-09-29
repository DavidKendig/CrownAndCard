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
	- game-output.log     console output from native builds, exactly as printed
	- notes.log           the launcher's own observations (hangs, lost contact)
	- session.log         all of it as one timeline: the game's log lines, the
	                      events it reported and the launcher's notes (what the
	                      game log window shows)

	Nothing here is uploaded anywhere.
**/
sealed class SessionRecorder
{
	const int MaxHistory = 120;
	const int KeepSessions = 30;
	const int MaxEntries = 20000;

	public string Dir { get; }
	public DateTime StartedAt { get; } = DateTime.Now;
	public DateTime LastContact { get; private set; }
	public int Heartbeats { get; private set; }
	public int Errors { get; private set; }
	public string LastRoom { get; private set; } = "";
	public DateTime? QuitAt { get; private set; }
	public bool Ended { get; private set; }

	/** Warnings and errors in the game's own log (native builds), counted apart from reported errors. **/
	public int LogWarnings { get; private set; }
	public int LogErrors { get; private set; }

	/** The latest heartbeat's state (room, fps, controller...), or null before the first. **/
	public object? LastState { get; private set; }

	public string Status
	{
		get
		{
			lock (gate)
				return info["status"] as string ?? "unknown";
		}
	}

	/** Raised on whichever thread recorded something. **/
	public event Action? Changed;

	readonly object gate = new();
	readonly Dictionary<string, object?> info = new();
	readonly Queue<object> history = new();
	readonly List<LogEntry> entries = [];
	readonly List<Action<LogEntry>> listeners = [];
	readonly GameLogParser parser = new();

	/** Native builds log their own errors; their reported error events would show twice. **/
	readonly bool gameLogs;

	SessionRecorder(GamePlan plan, LauncherSettings settings)
	{
		gameLogs = plan.Kind == GameKind.Native;
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
		recorder.Note("Starting the game: " + plan.Describe());
		Prune();
		return recorder;
	}

	/**
		The log so far, and every entry after it as it's recorded (on the recording
		thread, so `listener` should hand off to its own). Call Unsubscribe to stop.
	**/
	public (LogEntry[] Past, Action Unsubscribe) Follow(Action<LogEntry> listener)
	{
		lock (gate)
		{
			listeners.Add(listener);
			return (entries.ToArray(), () =>
			{
				lock (gate)
					listeners.Remove(listener);
			});
		}
	}

	/** Records a log entry. Call with the gate held, so entries keep their order. **/
	void Add(LogEntry entry)
	{
		entries.Add(entry);
		if (entries.Count > MaxEntries)
			entries.RemoveRange(0, MaxEntries / 10);
		Append("session.log", entry.ToLine());
		if (entry.Source == LogSource.Game && !entry.Continuation)
		{
			if (entry.Level == LogLevel.Error)
				info["logErrors"] = ++LogErrors;
			else if (entry.Level == LogLevel.Warn)
				info["logWarnings"] = ++LogWarnings;
		}
		foreach (var listener in listeners.ToArray())
		{
			try
			{
				listener(entry);
			}
			catch (Exception e)
			{
				Log.Write("Log listener failed: " + e.Message);
			}
		}
	}

	/** Records a message (and any stack) as an entry plus indented continuation lines. **/
	void AddLines(LogSource source, LogLevel level, string tag, string message, string? more = null)
	{
		var now = DateTime.Now;
		var lines = message.Replace("\r\n", "\n").Split('\n');
		Add(new LogEntry { Time = now, Level = level, Source = source, Tag = tag, Message = lines[0] });
		var rest = lines.Skip(1).Concat(more == null ? [] : more.Replace("\r\n", "\n").Split('\n'));
		foreach (var line in rest.Select(l => l.Trim()).Where(l => l.Length > 0))
			Add(new LogEntry { Time = now, Level = level, Source = source, Tag = tag, Message = line, Continuation = true });
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
				var text = $"Ignored a malformed {endpoint} report ({body.Length} bytes)";
				Append("notes.log", $"{Now()}  {text}");
				AddLines(LogSource.Launcher, LogLevel.Warn, "", text);
				return;
			}
			var roomBefore = LastRoom;
			LastContact = DateTime.Now;
			if (endpoint == "state")
			{
				Heartbeats++;
				history.Enqueue(parsed);
				while (history.Count > MaxHistory)
					history.Dequeue();
				LastRoom = Json.Str(parsed, "state", "room") ?? LastRoom;
				info["build"] = Json.Str(parsed, "build") ?? info.GetValueOr("build");
				info["lastState"] = LastState = Json.Get(parsed, "state");
				info["lastHeartbeatAt"] = Iso(LastContact);
				info["heartbeats"] = Heartbeats;
				Write("state.json", Json.Write(parsed));
				Write("state-history.json", Json.Write(history.ToArray()));
			}
			else
			{
				var kind = Json.Str(parsed, "kind") ?? "event";
				Append("events.jsonl", Json.Write(parsed, indent: false));
				if (kind != "error" || !gameLogs)
					AddLines(LogSource.Event, kind == "error" ? LogLevel.Error : LogLevel.Info, kind,
						Json.Str(parsed, "message") ?? "(no message)", kind == "error" ? Json.Str(parsed, "stack") : null);
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
			if (LastRoom != roomBefore && LastRoom.Length > 0)
				AddLines(LogSource.Event, LogLevel.Info, "room", "Now in: " + LastRoom);
			WriteInfo();
		}
		Changed?.Invoke();
	}

	/** A line the game printed (native builds). **/
	public void OnOutput(string? line, bool stderr = false)
	{
		if (line == null)
			return;
		lock (gate)
		{
			Append("game-output.log", stderr ? "[stderr] " + line : line);
			int errors = LogErrors, warnings = LogWarnings;
			Add(parser.Parse(line, stderr, DateTime.Now));
			if (LogErrors != errors || LogWarnings != warnings)
				WriteInfo();
		}
		Changed?.Invoke();
	}

	public void Note(string text, LogLevel level = LogLevel.Info)
	{
		lock (gate)
		{
			Append("notes.log", $"{Now()}  {text}");
			AddLines(LogSource.Launcher, level, "", text);
		}
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
			AddLines(LogSource.Launcher, status switch { "crashed" => LogLevel.Error, "ok" => LogLevel.Info, _ => LogLevel.Warn }, "",
				$"Session ended: {reason}" + (exitCode != null ? $" (exit code {exitCode})" : "") + $". Result: {UI.Theme.StatusText(status)}.");
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
		// session.log has the notes and the game's output in one timeline; older sessions only have the separate files.
		var timeline = File.Exists(Path.Combine(dir, "session.log"));
		foreach (var (title, file, tail) in new[] { ("Session", "session.json", 0), ("Last game state", "state.json", 0), ("Events (latest last)", "events.jsonl", 25), ("Launcher notes", "notes.log", 25), ("Game output (latest last)", "game-output.log", 40), ("Log (latest last)", "session.log", 60) })
		{
			var path = Path.Combine(dir, file);
			if (!File.Exists(path) || (timeline && file is "notes.log" or "game-output.log"))
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
