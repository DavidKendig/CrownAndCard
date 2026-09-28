// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Generic;
using System.IO;
using Microsoft.Win32;

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

	public string Describe() => Kind switch
	{
		GameKind.Native when Bytecode != null => $"HashLink build: {Bytecode}",
		GameKind.Native => $"Desktop build: {Path}",
		_ => $"Web build: {Path}",
	};
}

/** Finds the game next to the launcher (or in the folder set in Settings) and a browser for the web build. **/
static class GameLocator
{
	public static GamePlan? Find(string overridePath)
	{
		foreach (var dir in CandidateDirs(overridePath))
		{
			var exe = Path.Combine(dir, "CrownAndCard.exe");
			if (File.Exists(exe))
				return new GamePlan { Kind = GameKind.Native, Path = exe };
			var hl = Path.Combine(dir, "hl.exe");
			var bytecode = Path.Combine(dir, "game.hl");
			if (File.Exists(hl) && File.Exists(bytecode))
				return new GamePlan { Kind = GameKind.Native, Path = hl, Bytecode = bytecode };
			foreach (var web in new[] { Path.Combine(dir, "web"), dir })
				if (File.Exists(Path.Combine(web, "index.html")) && File.Exists(Path.Combine(web, "game.js")))
					return new GamePlan { Kind = GameKind.Web, Path = Path.GetFullPath(web) };
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
		var d = new DirectoryInfo(Paths.ExeDir);
		for (int i = 0; i < 5 && d != null; i++, d = d.Parent)
		{
			yield return d.FullName;
			yield return Path.Combine(d.FullName, "game");
		}
	}

	/** Edge (on every Windows 10/11 PC) or Chrome, to open the web build as an app window. **/
	public static string? FindBrowser()
	{
		foreach (var exe in new[] { "msedge.exe", "chrome.exe" })
		{
			var registered = AppPath(exe);
			if (registered != null)
				return registered;
		}
		foreach (var root in new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) })
		{
			var edge = Path.Combine(root, @"Microsoft\Edge\Application\msedge.exe");
			if (File.Exists(edge))
				return edge;
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
}
