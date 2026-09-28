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

	[STAThread]
	static void Main(string[] args)
	{
		Paths.Ensure();
		if (Array.IndexOf(args, "--check-audio") >= 0)
		{
			Environment.ExitCode = CheckAudio();
			return;
		}
		using var mutex = new Mutex(true, @"Local\CrownAndCardLauncher", out bool firstInstance);
		if (!firstInstance)
		{
			// Ask the open launcher to come to the front instead of starting a second one.
			if (EventWaitHandle.TryOpenExisting(ShowSignalName, out var signal))
				using (signal)
					signal.Set();
			else
				MessageBox.Show("The Crown & Card launcher is already open.", "Crown & Card", MessageBoxButtons.OK, MessageBoxIcon.Information);
			return;
		}
		using var showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, ShowSignalName);
		Application.EnableVisualStyles();
		Application.SetCompatibleTextRenderingDefault(false);
		Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
		Application.ThreadException += (_, e) => ReportFatal(e.Exception);
		AppDomain.CurrentDomain.UnhandledException += (_, e) => ReportFatal(e.ExceptionObject as Exception);
		SessionRecorder.RecoverAbandoned();
		var form = new LauncherForm();
		new Thread(() =>
		{
			while (showSignal.WaitOne())
			{
				try { form.BeginInvoke(new Action(form.ShowFromAnotherLaunch)); }
				catch (InvalidOperationException) { return; } // the form is gone
			}
		}) { IsBackground = true, Name = "ShowSignal" }.Start();
		Application.Run(form);
	}

	/** Signalled by a second launch (for example the Start menu clicked twice). **/
	const string ShowSignalName = @"Local\CrownAndCardLauncher.Show";

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
