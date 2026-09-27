// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management;
using System.Threading;

namespace CrownAndCard.Launcher;

/**
	Starts the game with the player's settings, then watches it until it ends.

	- Native builds get `--key=value` arguments and are tracked by process.
	- The web build is served by LocalServer and opened as an Edge/Chrome app
	  window in guest mode with its own data folder: guest windows can't sign
	  in to an account or sync browsing data, and the separate folder makes the
	  window its own process. Without Edge or Chrome it opens in the default
	  browser, and the session ends when the heartbeats stop.
**/
sealed class GameSession
{
	const int HangSeconds = 20;
	const int LostSeconds = 30;
	const int NeverStartedSeconds = 60;
	const int QuitGraceSeconds = 8;

	public SessionRecorder Recorder { get; }

	/** Raised once, on any thread, with the final status. **/
	public event Action<string>? Ended;

	readonly LocalServer server;
	readonly GameKind kind;

	/** The process being watched. For the web build this can change once, when the browser hands off. **/
	volatile Process? process;
	int endedFlag;
	bool hangNoted;

	/** False when there's no process to watch, so the session is tracked by heartbeat alone. **/
	volatile bool processTracked;

	GameSession(GamePlan plan, LauncherSettings settings, LocalServer server)
	{
		this.server = server;
		kind = plan.Kind;
		// Start recording before the game starts, so its first reports aren't missed.
		Recorder = SessionRecorder.Begin(plan, settings);
		server.Posted += Recorder.OnPost;
		Process? started;
		try
		{
			started = plan.Kind == GameKind.Web ? StartWeb(plan, settings) : StartNative(plan, settings);
		}
		catch
		{
			server.Posted -= Recorder.OnPost;
			Recorder.End(null, "failed to start");
			throw;
		}
		if (started != null)
			Watch(started);
	}

	void Watch(Process p)
	{
		process = p;
		processTracked = true;
		p.EnableRaisingEvents = true;
		p.Exited += (_, _) => OnProcessExited(p);
		if (p.HasExited)
			OnProcessExited(p);
	}

	void OnProcessExited(Process p)
	{
		if (p != process)
			return;
		var code = SafeExitCode(p);
		if (kind == GameKind.Web && code == 0 && (DateTime.Now - Recorder.StartedAt).TotalSeconds < 10)
		{
			// Edge and Chrome often relaunch themselves: the process we started quits straight
			// away and another one opens the window. Find that one and watch it instead.
			processTracked = false;
			ThreadPool.QueueUserWorkItem(_ => AdoptBrowserProcess());
			return;
		}
		Finish(code, "game process exited");
	}

	void AdoptBrowserProcess()
	{
		for (int attempt = 0; attempt < 10 && !Recorder.Ended; attempt++)
		{
			var found = FindBrowserProcess(Paths.BrowserProfileDir);
			if (found != null)
			{
				Recorder.Note($"The browser relaunched itself; now watching process {found.Id}.");
				Watch(found);
				return;
			}
			Thread.Sleep(500);
		}
		Recorder.Note("The browser relaunched itself and its new process wasn't found; tracking by heartbeat instead.");
	}

	/** The main browser process (not a renderer or helper) using the given data folder. **/
	static Process? FindBrowserProcess(string dataDir)
	{
		try
		{
			using var search = new ManagementObjectSearcher("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name = 'msedge.exe' OR Name = 'chrome.exe'");
			foreach (var item in search.Get())
			{
				using var mo = (ManagementObject)item;
				var cmd = mo["CommandLine"] as string;
				if (cmd == null || cmd.IndexOf(dataDir, StringComparison.OrdinalIgnoreCase) < 0 || cmd.Contains("--type="))
					continue;
				try
				{
					return Process.GetProcessById(Convert.ToInt32(mo["ProcessId"]));
				}
				catch
				{
					// It exited between the query and now.
				}
			}
		}
		catch (Exception e)
		{
			Log.Write("Process search failed: " + e.Message);
		}
		return null;
	}

	public static GameSession Start(GamePlan plan, LauncherSettings settings, LocalServer server) => new(plan, settings, server);

	Process? StartWeb(GamePlan plan, LauncherSettings s)
	{
		server.WebRoot = plan.Path;
		var query = string.Join("&", s.GameOptions().Select(kv => kv.Key + "=" + Uri.EscapeDataString(kv.Value)));
		var url = $"{server.BaseUrl}index.html?{query}&telemetry={Uri.EscapeDataString(server.ApiUrl)}";
		var browser = GameLocator.FindBrowser();
		if (browser == null)
		{
			Recorder.SetLaunchCommand("default browser: " + url);
			Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
			Recorder.Note("No Edge or Chrome found; opened the default browser. The session ends when heartbeats stop.");
			return null;
		}
		Directory.CreateDirectory(Paths.BrowserProfileDir);
		var args = string.Join(" ",
			$"--app=\"{url}\"",
			$"--user-data-dir=\"{Paths.BrowserProfileDir}\"",
			"--guest",
			$"--window-size={s.WindowWidth},{s.WindowHeight}",
			"--no-first-run",
			"--no-default-browser-check",
			"--disable-background-mode",
			"--autoplay-policy=no-user-gesture-required",
			s.Fullscreen ? "--start-fullscreen" : "");
		Recorder.SetLaunchCommand($"\"{browser}\" {args}");
		return Process.Start(new ProcessStartInfo(browser, args) { UseShellExecute = false });
	}

	Process StartNative(GamePlan plan, LauncherSettings s)
	{
		var options = s.GameOptions().Select(kv => Quote($"--{kv.Key}={kv.Value}")).ToList();
		options.Add(Quote("--telemetry=" + server.ApiUrl));
		if (plan.Bytecode != null)
			options.Insert(0, Quote(plan.Bytecode));
		var psi = new ProcessStartInfo(plan.Path, string.Join(" ", options))
		{
			UseShellExecute = false,
			WorkingDirectory = Path.GetDirectoryName(plan.Path) ?? Paths.ExeDir,
			RedirectStandardOutput = true,
			RedirectStandardError = true,
			CreateNoWindow = true,
		};
		Recorder.SetLaunchCommand($"\"{psi.FileName}\" {psi.Arguments}");
		var p = Process.Start(psi) ?? throw new InvalidOperationException("The game didn't start");
		p.OutputDataReceived += (_, e) => Recorder.OnOutput(e.Data);
		p.ErrorDataReceived += (_, e) => Recorder.OnOutput(e.Data == null ? null : "[stderr] " + e.Data);
		p.BeginOutputReadLine();
		p.BeginErrorReadLine();
		return p;
	}

	/** Called about once a second on the UI thread: watches for hangs, lost contact and closed windows. **/
	public void Tick()
	{
		if (Recorder.Ended)
			return;
		var now = DateTime.Now;
		var quitAt = Recorder.QuitAt;
		if (quitAt != null && (now - quitAt.Value).TotalSeconds > QuitGraceSeconds && Recorder.LastContact <= quitAt.Value)
		{
			// The game page closed and nothing came back (a reload would have sent "start").
			// An app window can linger as a background process; it's our own profile, so close it.
			var p = process;
			if (processTracked && p != null && kind == GameKind.Web && !p.HasExited)
			{
				try
				{
					p.Kill();
				}
				catch
				{
					// It may have exited in the meantime.
				}
			}
			Finish(null, "game window closed");
			return;
		}
		if (!processTracked)
		{
			if (Recorder.Heartbeats > 0 && (now - Recorder.LastContact).TotalSeconds > LostSeconds)
				Finish(null, $"lost contact (no heartbeat for {LostSeconds} s)");
			else if (Recorder.Heartbeats == 0 && (now - Recorder.StartedAt).TotalSeconds > NeverStartedSeconds)
				Finish(null, "lost contact (the game never reported in)");
			return;
		}
		if (!hangNoted && Recorder.Heartbeats > 0 && (now - Recorder.LastContact).TotalSeconds > HangSeconds)
		{
			hangNoted = true;
			Recorder.Note($"No heartbeat for {HangSeconds} s while the game is still running (possible hang)");
		}
	}

	/** The launcher is closing while the game still runs: record that, but leave the game alone. **/
	public void LauncherClosing() => Finish(null, "the launcher closed while the game was running");

	void Finish(int? exitCode, string reason)
	{
		if (Interlocked.Exchange(ref endedFlag, 1) == 1)
			return;
		server.Posted -= Recorder.OnPost;
		var status = Recorder.End(exitCode, reason);
		Ended?.Invoke(status);
	}

	static int? SafeExitCode(Process p)
	{
		try
		{
			return p.ExitCode;
		}
		catch
		{
			return null;
		}
	}

	static string Quote(string arg) => "\"" + arg.Replace("\"", "\\\"") + "\"";
}
