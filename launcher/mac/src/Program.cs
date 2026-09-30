// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Threading;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Styling;
using Avalonia.Themes.Fluent;
using CrownAndCard.Launcher.UI;

namespace CrownAndCard.Launcher;

static class Program
{
	/** 0.YY.BBB, from version.json (generated into BuildInfo by the project file). **/
	public const string Version = BuildInfo.Version;

	[STAThread]
	static int Main(string[] args)
	{
		Paths.Ensure();
		if (Array.IndexOf(args, "--check-audio") >= 0)
			return CheckAudio();
		AppDomain.CurrentDomain.UnhandledException += (_, e) => Log.Write("Unhandled launcher error: " + e.ExceptionObject);
		SessionRecorder.RecoverAbandoned();
		// One launcher at a time (Finder already keeps an app bundle to one; this covers the bare binary too).
		using var mutex = new Mutex(true, "CrownAndCardLauncher", out bool firstInstance);
		if (!firstInstance)
		{
			Console.Error.WriteLine("The Crown & Card launcher is already open.");
			return 0;
		}
		return AppBuilder.Configure<App>()
			.UsePlatformDetect()
			.With(new MacOSPlatformOptions { ShowInDock = true })
			.LogToTrace()
			.StartWithClassicDesktopLifetime(args);
	}

	/**
		`CrownAndCardLauncher --check-audio`: decodes the whole menu loop, briefly
		opens the audio device, and writes the result to the log (and the console).
	**/
	static int CheckAudio()
	{
		try
		{
			var (frames, channels, rate) = MusicPlayer.DecodeAll();
			Report($"Audio check: decoded {frames} frames ({frames / (double)rate:F3} s) at {rate} Hz, {channels} channel(s)");
			using var player = MusicPlayer.TryStart(0, false) ?? throw new InvalidOperationException("the player didn't start");
			Thread.Sleep(600);
			if (player.Error != null)
				throw new InvalidOperationException(player.Error);
			Report("Audio check: audio device opened and streaming OK");
			return 0;
		}
		catch (Exception e)
		{
			Report("Audio check failed: " + e.Message);
			return 1;
		}
	}

	static void Report(string message)
	{
		Log.Write(message);
		Console.WriteLine(message);
	}
}

sealed class App : Application
{
	public override void Initialize()
	{
		Name = "Crown & Card";
		RequestedThemeVariant = ThemeVariant.Dark;
		Styles.Add(new FluentTheme());
		Styles.Add(UiTheme.Styles());
	}

	public override void OnFrameworkInitializationCompleted()
	{
		if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
		{
			desktop.ShutdownMode = ShutdownMode.OnMainWindowClose;
			desktop.MainWindow = new LauncherWindow();
		}
		base.OnFrameworkInitializationCompleted();
	}
}
