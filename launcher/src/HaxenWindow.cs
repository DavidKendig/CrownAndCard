// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Diagnostics;
using System.IO;

namespace CrownAndCard.Launcher;

/**
	Opens Haxen, the map editor, the same way as the web game: served by the
	launcher's LocalServer and shown as an Edge/Chrome app window with its own
	data folder, so it can sit beside the game window. Haxen saves maps and asks
	for play tests through the launcher's local API.
**/
static class HaxenWindow
{
	public static void Open(LocalServer server, string webDir)
	{
		server.WebRoot = webDir;
		var url = $"{server.BaseUrl}haxen.html?api={Uri.EscapeDataString(server.ApiUrl)}";
		var browser = GameLocator.FindBrowser();
		if (browser == null)
		{
			Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
			return;
		}
		Directory.CreateDirectory(Paths.HaxenProfileDir);
		var args = string.Join(" ",
			$"--app=\"{url}\"",
			$"--user-data-dir=\"{Paths.HaxenProfileDir}\"",
			"--guest",
			"--window-size=1440,900",
			"--no-first-run",
			"--no-default-browser-check",
			"--disable-background-mode");
		Log.Write("Opening Haxen");
		Process.Start(new ProcessStartInfo(browser, args) { UseShellExecute = false });
	}
}
