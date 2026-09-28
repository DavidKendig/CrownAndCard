// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.IO;
using System.Windows.Forms;

namespace CrownAndCard.Launcher;

/** Where the launcher keeps its files: %LOCALAPPDATA%\CrownAndCard. **/
static class Paths
{
	public static string DataDir { get; } =
		Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CrownAndCard");

	public static string SettingsFile => Path.Combine(DataDir, "launcher-settings.json");
	public static string NewsCache => Path.Combine(DataDir, "news-cache.json");
	public static string SessionsDir => Path.Combine(DataDir, "sessions");

	/**
		Data folder for the game's guest-mode browser window, so it runs as its own
		process, separate from the player's normal browser.
	**/
	public static string BrowserProfileDir => Path.Combine(DataDir, "game-window");

	/** Haxen's own app-window data folder, so it can run beside the game window. **/
	public static string HaxenProfileDir => Path.Combine(DataDir, "haxen-window");

	/** Custom maps made in Haxen (GAME_DESIGN.md §13.6). **/
	public static string MapsDir => Path.Combine(DataDir, "maps");

	public static string LauncherLog => Path.Combine(DataDir, "launcher.log");

	public static string ExeDir => Path.GetDirectoryName(Application.ExecutablePath) ?? ".";

	public static void Ensure()
	{
		Directory.CreateDirectory(DataDir);
		Directory.CreateDirectory(SessionsDir);
	}
}

/** Append-only launcher log for problems the launcher itself runs into. **/
static class Log
{
	static readonly object Gate = new();

	public static void Write(string message)
	{
		try
		{
			lock (Gate)
				File.AppendAllText(Paths.LauncherLog, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss}  {message}{Environment.NewLine}");
		}
		catch
		{
			// Logging must never take the launcher down.
		}
	}
}
