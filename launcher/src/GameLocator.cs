// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Generic;
using System.IO;
#if !MACOS
using Microsoft.Win32;
#endif

namespace CrownAndCard.Launcher;

enum GameKind
{
	/** A native desktop build (CrownAndCard.exe, or hl.exe + game.hl). **/
	Native,

	/** The WebGL build (index.html + game.js), served by the launcher. **/
	Web,
}

sealed class GamePlan
{
	public GameKind Kind;

	/** The executable for native builds, or the folder to serve for the web build. **/
	public string Path = "";

	/** HashLink bytecode file, when running through hl.exe. **/
	public string? Bytecode;

	/** Why this isn't the kind of build the player asked for, or null. **/
	public string? Fallback;

	public string Describe() => Kind switch
	{
		GameKind.Native when Bytecode != null => $"Native window (HashLink): {Bytecode}",
		GameKind.Native => $"Native window: {Path}",
		_ => $"Browser window: {Path}",
	} + (Fallback != null ? $"  ({Fallback})" : "");
}

/** Finds the game next to the launcher (or in the folder set in Settings) and a browser for the web build. **/
static class GameLocator
{
	/**
		The native build when `preferNative` and there is one, otherwise the web
		build, otherwise whichever exists. Native: CrownAndCard.exe, or HashLink
		bytecode (game.hl) with hl.exe beside it, in the folder or its native\
		subfolder; a developer's hl.exe on PATH also runs a bare native\game.hl.
	**/
	public static GamePlan? Find(string overridePath, bool preferNative)
	{
		GamePlan? native = null, web = null;
		foreach (var dir in CandidateDirs(overridePath))
		{
			native ??= FindNative(dir);
			web ??= FindWeb(dir);
		}
		var plan = preferNative ? native ?? web : web ?? native;
		if (plan != null && plan.Kind != (preferNative ? GameKind.Native : GameKind.Web))
			plan.Fallback = preferNative ? "no native build found" : "no web build found";
		return plan;
	}

	static GamePlan? FindNative(string dir)
	{
#if MACOS
		// The HL/C build for Apple Silicon (tools/build_mac.sh): native/mac/game, with libhl beside it.
		foreach (var d in new[] { Path.Combine(dir, "native", "mac"), Path.Combine(dir, "mac") })
		{
			var game = Path.Combine(d, "game");
			if (File.Exists(game) && File.Exists(Path.Combine(d, "libhl.dylib")))
				return new GamePlan { Kind = GameKind.Native, Path = Path.GetFullPath(game) };
		}
		return null;
#else
		var exe = Path.Combine(dir, "CrownAndCard.exe");
		if (File.Exists(exe))
			return new GamePlan { Kind = GameKind.Native, Path = exe };
		foreach (var d in new[] { dir, Path.Combine(dir, "native") })
		{
			var bytecode = Path.Combine(d, "game.hl");
			if (!File.Exists(bytecode))
				continue;
			var hl = Path.Combine(d, "hl.exe");
			if (!File.Exists(hl))
				hl = OnPath("hl.exe") ?? "";
			if (hl.Length > 0)
				return new GamePlan { Kind = GameKind.Native, Path = Path.GetFullPath(hl), Bytecode = Path.GetFullPath(bytecode) };
		}
		return null;
#endif
	}

	static GamePlan? FindWeb(string dir)
	{
		foreach (var web in new[] { Path.Combine(dir, "web"), dir })
			if (File.Exists(Path.Combine(web, "index.html")) && File.Exists(Path.Combine(web, "game.js")))
				return new GamePlan { Kind = GameKind.Web, Path = Path.GetFullPath(web) };
		return null;
	}

	static string? OnPath(string exe)
	{
		foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
		{
			try
			{
				var path = Path.Combine(dir.Trim().Trim('"'), exe);
				if (dir.Trim().Length > 0 && File.Exists(path))
					return path;
			}
			catch (ArgumentException)
			{
				// A malformed PATH entry.
			}
		}
		return null;
	}

	/** The web folder holding Haxen, the map editor (it ships beside the web build). **/
	public static string? FindHaxen(string overridePath)
	{
		foreach (var dir in CandidateDirs(overridePath))
			foreach (var web in new[] { Path.Combine(dir, "web"), dir })
				if (File.Exists(Path.Combine(web, "haxen.html")) && File.Exists(Path.Combine(web, "haxen.js")))
					return Path.GetFullPath(web);
		return null;
	}

	/** The override folder, then the launcher's folder and up to four parents (so a dev build finds the repo's web/). **/
	static IEnumerable<string> CandidateDirs(string overridePath)
	{
		if (!string.IsNullOrWhiteSpace(overridePath) && Directory.Exists(overridePath))
		{
			yield return Path.GetFullPath(overridePath);
			yield break;
		}
#if MACOS
		// A packaged app keeps the game in Contents/Resources/game.
		var resources = Path.GetFullPath(Path.Combine(Paths.ExeDir, "..", "Resources", "game"));
		if (Directory.Exists(resources))
			yield return resources;
#endif
		var d = new DirectoryInfo(Paths.ExeDir);
		for (int i = 0; i < 5 && d != null; i++, d = d.Parent)
		{
			yield return d.FullName;
			yield return Path.Combine(d.FullName, "game");
		}
	}

	/**
		Chrome if it's installed, otherwise Edge (on every Windows 10/11 PC), to
		open the web build as an app window. Chrome comes first because Edge's
		"browsing controls" turn the controller into a pointer and keep it from
		the game until the player picks "Use game controls" (§13.12).
	**/
	public static string? FindBrowser() => FindChrome() ?? FindEdge();

#if MACOS
	static string? FindChrome() => FindMacApp("Google Chrome");

	static string? FindEdge() => FindMacApp("Microsoft Edge");

	/** The executable inside /Applications/<name>.app (or ~/Applications). **/
	static string? FindMacApp(string name)
	{
		foreach (var apps in new[] { "/Applications", Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Applications") })
		{
			var path = Path.Combine(apps, name + ".app", "Contents", "MacOS", name);
			if (File.Exists(path))
				return path;
		}
		return null;
	}
#else

	static string? FindChrome() =>
		AppPath("chrome.exe") ?? FirstExisting(@"Google\Chrome\Application\chrome.exe",
			Environment.SpecialFolder.ProgramFiles, Environment.SpecialFolder.ProgramFilesX86, Environment.SpecialFolder.LocalApplicationData);

	static string? FindEdge() =>
		AppPath("msedge.exe") ?? FirstExisting(@"Microsoft\Edge\Application\msedge.exe",
			Environment.SpecialFolder.ProgramFilesX86, Environment.SpecialFolder.ProgramFiles);

	static string? FirstExisting(string relative, params Environment.SpecialFolder[] roots)
	{
		foreach (var root in roots)
		{
			var path = Path.Combine(Environment.GetFolderPath(root), relative);
			if (File.Exists(path))
				return path;
		}
		return null;
	}

	static string? AppPath(string exe)
	{
		foreach (var hive in new[] { Registry.CurrentUser, Registry.LocalMachine })
		{
			using var key = hive.OpenSubKey($@"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\{exe}");
			if (key?.GetValue("") is string path && File.Exists(path))
				return path;
		}
		return null;
	}
#endif
}
