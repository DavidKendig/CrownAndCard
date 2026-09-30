// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.IO;
#if !MACOS
using System.Windows.Forms;
#endif

namespace CrownAndCard.Launcher;

/** Where the launcher keeps its files: %LOCALAPPDATA%\CrownAndCard (on a Mac, ~/Library/Application Support/CrownAndCard). **/
static class Paths
{
	public static string DataDir { get; } =
		Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CrownAndCard");

	public static string SettingsFile => Path.Combine(DataDir, "launcher-settings.json");
	public static string NewsCache => Path.Combine(DataDir, "news-cache.json");
	public static string SessionsDir => Path.Combine(DataDir, "sessions");

	/**
		Data folder for the game's guest-mode browser window, so it runs as its own
		process, separate from the player's normal browser. Chrome and Edge each
		get their own: they can't share one.
	**/
	public static string BrowserProfileDir(string browser) => Path.Combine(DataDir, "game-window" + ProfileSuffix(browser));

	/** Haxen's own app-window data folder, so it can run beside the game window. **/
	public static string HaxenProfileDir(string browser) => Path.Combine(DataDir, "haxen-window" + ProfileSuffix(browser));

	static string ProfileSuffix(string browser) =>
		Path.GetFileName(browser).Equals("chrome.exe", StringComparison.OrdinalIgnoreCase)
		|| Path.GetFileName(browser).Equals("Google Chrome", StringComparison.Ordinal) ? "-chrome" : "";

	/** Custom maps made in Haxen (GAME_DESIGN.md §13.6). **/
	public static string MapsDir => Path.Combine(DataDir, "maps");

	public static string LauncherLog => Path.Combine(DataDir, "launcher.log");

#if MACOS
	/** The launcher's own folder (Contents/MacOS inside the app bundle). **/
	public static string ExeDir => AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
#else
	public static string ExeDir => Path.GetDirectoryName(Application.ExecutablePath) ?? ".";
#endif

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
