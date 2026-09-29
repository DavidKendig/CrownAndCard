// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.RegularExpressions;

namespace CrownAndCard.Launcher;

enum LogLevel
{
	Info,
	Warn,
	Error,
}

enum LogSource
{
	/** The game's own log (its standard output and error). **/
	Game,

	/** An event the game reported to the launcher's API (start, error, quit, room changes). **/
	Event,

	/** The launcher's own observations. **/
	Launcher,
}

/** One line in a session's log (session.log, and the game log window). **/
sealed class LogEntry
{
	public DateTime Time;
	public LogLevel Level;
	public LogSource Source;
	public string Tag = "";
	public string Message = "";

	/** An indented line that belongs to the entry above it (a stack frame). **/
	public bool Continuation;

	public string LevelName => Level switch { LogLevel.Error => "ERROR", LogLevel.Warn => "WARN", _ => "INFO" };

	public string SourceName => Source switch { LogSource.Game => "game", LogSource.Event => "event", _ => "launcher" };

	/** The session.log line; GameLogParser.ParseSessionLine reads it back. **/
	public string ToLine() => Continuation
		? "    " + Message
		: $"{Time.ToString("HH:mm:ss.fff", CultureInfo.InvariantCulture)} {LevelName,-5} [{SourceName}{(Tag.Length > 0 ? ":" + Tag : "")}] {Message}";
}

/**
	Reads the game's log lines (src/core/GameLog.hx writes them):
	`HH:MM:SS.mmm LEVEL [tag] message`, with a stack on indented lines after it.
	Anything else on standard output is plain output; on standard error it's a
	warning, or an error when it looks like one (HashLink prints crashes there).
**/
sealed class GameLogParser
{
	static readonly Regex GameLine = new(@"^(\d\d):(\d\d):(\d\d)\.(\d{3}) (INFO|WARN|ERROR)\s+\[([^\]]*)\] ?(.*)$", RegexOptions.CultureInvariant);
	static readonly Regex SessionLine = new(@"^(\d\d):(\d\d):(\d\d)\.(\d{3}) (INFO|WARN|ERROR)\s+\[(game|event|launcher)(?::([^\]]*))?\] ?(.*)$", RegexOptions.CultureInvariant);
	static readonly Regex LooksLikeError = new(@"error|exception|fatal|crash|access violation|failed", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

	LogEntry? previous;

	/** One line of the game's output, as it arrives. **/
	public LogEntry Parse(string line, bool stderr, DateTime now)
	{
		if (line.Length > 0 && char.IsWhiteSpace(line[0]) && previous != null)
			return Follow(previous, line.Trim());
		var m = GameLine.Match(line);
		LogEntry entry;
		if (m.Success)
			entry = new LogEntry
			{
				Time = TimeOn(now, m),
				Level = ParseLevel(m.Groups[5].Value),
				Source = LogSource.Game,
				Tag = m.Groups[6].Value,
				Message = m.Groups[7].Value,
			};
		else
			entry = new LogEntry
			{
				Time = now,
				Level = !stderr ? LogLevel.Info : LooksLikeError.IsMatch(line) ? LogLevel.Error : LogLevel.Warn,
				Source = LogSource.Game,
				Tag = stderr ? "stderr" : "output",
				Message = line,
			};
		previous = entry;
		return entry;
	}

	static LogEntry Follow(LogEntry head, string text) => new()
	{
		Time = head.Time,
		Level = head.Level,
		Source = head.Source,
		Tag = head.Tag,
		Message = text,
		Continuation = true,
	};

	/** A session's whole log: session.log, or for sessions recorded before it existed, the old files. **/
	public static List<LogEntry> Load(string dir)
	{
		var list = new List<LogEntry>();
		var day = Directory.GetCreationTime(dir).Date;
		var sessionLog = Path.Combine(dir, "session.log");
		if (File.Exists(sessionLog))
		{
			LogEntry? head = null;
			foreach (var line in ReadLines(sessionLog))
			{
				if (line.StartsWith("    ", StringComparison.Ordinal) && head != null)
				{
					list.Add(Follow(head, line.Substring(4)));
					continue;
				}
				var m = SessionLine.Match(line);
				if (!m.Success)
					continue;
				head = new LogEntry
				{
					Time = TimeOn(day, m),
					Level = ParseLevel(m.Groups[5].Value),
					Source = m.Groups[6].Value switch { "game" => LogSource.Game, "event" => LogSource.Event, _ => LogSource.Launcher },
					Tag = m.Groups[7].Value,
					Message = m.Groups[8].Value,
				};
				list.Add(head);
			}
			return list;
		}
		var parser = new GameLogParser();
		foreach (var line in ReadLines(Path.Combine(dir, "game-output.log")))
		{
			var stderr = line.StartsWith("[stderr] ", StringComparison.Ordinal);
			list.Add(parser.Parse(stderr ? line.Substring(9) : line, stderr, day));
		}
		foreach (var line in ReadLines(Path.Combine(dir, "notes.log")))
			list.Add(new LogEntry { Time = day, Level = LogLevel.Info, Source = LogSource.Launcher, Message = line });
		return list;
	}

	static IEnumerable<string> ReadLines(string path)
	{
		if (!File.Exists(path))
			return [];
		try
		{
			// The recorder may still be appending; share the file rather than lock it.
			using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
			using var reader = new StreamReader(stream);
			return reader.ReadToEnd().Replace("\r\n", "\n").Split(['\n'], StringSplitOptions.RemoveEmptyEntries);
		}
		catch (IOException)
		{
			return [];
		}
	}

	static LogLevel ParseLevel(string s) => s switch { "ERROR" => LogLevel.Error, "WARN" => LogLevel.Warn, _ => LogLevel.Info };

	/** The game prints the time of day only; put it on `now`'s date, or the day before if that would be in the future (a session past midnight). **/
	static DateTime TimeOn(DateTime now, Match m)
	{
		var t = now.Date + new TimeSpan(0, int.Parse(m.Groups[1].Value), int.Parse(m.Groups[2].Value), int.Parse(m.Groups[3].Value), int.Parse(m.Groups[4].Value));
		return t > now.AddMinutes(1) && now.TimeOfDay != TimeSpan.Zero ? t.AddDays(-1) : t;
	}
}
