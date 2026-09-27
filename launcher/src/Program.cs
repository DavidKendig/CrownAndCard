// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Threading;
using System.Windows.Forms;
using CrownAndCard.Launcher.UI;

namespace CrownAndCard.Launcher;

static class Program
{
	/** 0.YY.BBB, from version.json (generated into BuildInfo by build.ps1). **/
	public const string Version = BuildInfo.Version;

	/** Set when this launcher was just started by an update from that version. **/
	public static string? UpdatedFrom;

	[STAThread]
	static void Main(string[] args)
	{
		Paths.Ensure();
		if (Array.IndexOf(args, "--check-audio") >= 0)
		{
			Environment.ExitCode = CheckAudio();
			return;
		}
		foreach (var arg in args)
		{
			if (arg.StartsWith("--updated-from=", StringComparison.Ordinal))
			{
				UpdatedFrom = arg.Substring("--updated-from=".Length);
				Log.Write($"Updated from {UpdatedFrom} to {Version}");
				Updater.CleanUpAfterUpdate();
			}
			// Test hook: only local feeds are accepted, so this can't redirect real updates.
			else if (arg.StartsWith("--update-feed=http://127.0.0.1:", StringComparison.Ordinal))
				Updater.FeedUrl = arg.Substring("--update-feed=".Length);
		}
		using var mutex = new Mutex(true, @"Local\CrownAndCardLauncher", out bool firstInstance);
		if (!firstInstance && UpdatedFrom != null)
		{
			// Just updated: the old launcher is still closing, so wait for it.
			try
			{
				firstInstance = mutex.WaitOne(TimeSpan.FromSeconds(15));
			}
			catch (AbandonedMutexException)
			{
				firstInstance = true;
			}
		}
		if (!firstInstance)
		{
			MessageBox.Show("The Crown & Card launcher is already open.", "Crown & Card", MessageBoxButtons.OK, MessageBoxIcon.Information);
			return;
		}
		Application.EnableVisualStyles();
		Application.SetCompatibleTextRenderingDefault(false);
		Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
		Application.ThreadException += (_, e) => ReportFatal(e.Exception);
		AppDomain.CurrentDomain.UnhandledException += (_, e) => ReportFatal(e.ExceptionObject as Exception);
		SessionRecorder.RecoverAbandoned();
		Application.Run(new LauncherForm());
	}

	/**
		`CrownAndCardLauncher.exe --check-audio`: decodes the whole embedded menu
		loop, briefly opens the audio device, and writes the result to the log.
	**/
	static int CheckAudio()
	{
		try
		{
			var (frames, channels, rate) = MusicPlayer.DecodeAll();
			Log.Write($"Audio check: decoded {frames} frames ({frames / (double)rate:F3} s) at {rate} Hz, {channels} channel(s)");
			using var player = MusicPlayer.TryStart(0, false) ?? throw new InvalidOperationException("the player didn't start");
			Thread.Sleep(600);
			if (player.Error != null)
				throw new InvalidOperationException(player.Error);
			Log.Write("Audio check: audio device opened and streaming OK");
			return 0;
		}
		catch (Exception e)
		{
			Log.Write("Audio check failed: " + e.Message);
			return 1;
		}
	}

	static void ReportFatal(Exception? e)
	{
		Log.Write("Unhandled launcher error: " + e);
		MessageBox.Show($"Something went wrong in the launcher:\n\n{e?.Message}\n\nDetails were written to {Paths.LauncherLog}",
			"Crown & Card", MessageBoxButtons.OK, MessageBoxIcon.Error);
	}
}
