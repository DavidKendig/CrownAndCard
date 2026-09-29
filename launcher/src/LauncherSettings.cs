// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Generic;
using System.IO;

namespace CrownAndCard.Launcher;

/**
	Launcher options. The graphics and audio values are passed straight through
	to the game with the same keys the game reads (src/core/Settings.hx).
**/
sealed class LauncherSettings
{
	// Graphics
	public bool Fullscreen;
	public int WindowWidth = 1280;
	public int WindowHeight = 720;
	public string Scaling = "integer"; // integer | fit
	public int Fov = 90; // horizontal degrees at 16:9
	public int HeadBob = 100; // percent
	public string LookStyle = "shear"; // shear | perspective
	public bool ShowFps = true;

	// Audio
	public int MasterVolume = 80;
	public int MusicVolume = 70;
	public int EffectsVolume = 80;
	public int VoiceVolume = 80;
	public bool MuteInBackground = true;

	// Launcher
	public string NewsCategory = "all"; // "all" posts, or a davidkendig.info category slug
	public bool MinimizeWhilePlaying = true;
	public bool LauncherMusic = true; // the menu loop in the launcher
	public bool AutoUpdate = true; // check GitHub for a newer release at startup (installing always asks)
	public string GamePath = ""; // optional override; empty = auto-detect
	public string Map = ""; // a custom Haxen map to play; empty = Dodriec Manor
	public string PlayerName = DefaultName(); // shown at multiplayer tables

	public static readonly (int W, int H)[] WindowSizes = [(1280, 720), (1600, 900), (1920, 1080), (2560, 1440)];

	/** The options handed to the game, in the game's own key names. **/
	public List<KeyValuePair<string, string>> GameOptions()
	{
		List<KeyValuePair<string, string>> options =
		[
		new("fullscreen", Bool(Fullscreen)),
		new("windowWidth", WindowWidth.ToString()),
		new("windowHeight", WindowHeight.ToString()),
		new("scaling", Scaling),
		new("fov", Fov.ToString()),
		new("headBob", HeadBob.ToString()),
		new("lookStyle", LookStyle),
		new("showFps", Bool(ShowFps)),
		new("masterVolume", MasterVolume.ToString()),
		new("musicVolume", MusicVolume.ToString()),
		new("effectsVolume", EffectsVolume.ToString()),
		new("voiceVolume", VoiceVolume.ToString()),
		new("muteInBackground", Bool(MuteInBackground)),
		];
		if (Map.Length > 0)
			options.Add(new("map", Map));
		return options;
	}

	public Dictionary<string, object> ToReport()
	{
		var d = new Dictionary<string, object>();
		foreach (var kv in GameOptions())
			d[kv.Key] = kv.Value;
		return d;
	}

	public static LauncherSettings Load()
	{
		var s = new LauncherSettings();
		try
		{
			if (!File.Exists(Paths.SettingsFile))
				return s;
			var d = Json.Parse(File.ReadAllText(Paths.SettingsFile));
			s.Fullscreen = ReadBool(d, "fullscreen", s.Fullscreen);
			s.WindowWidth = Json.Int(d, s.WindowWidth, "windowWidth");
			s.WindowHeight = Json.Int(d, s.WindowHeight, "windowHeight");
			s.Scaling = Json.Str(d, "scaling") ?? s.Scaling;
			s.Fov = Json.Int(d, s.Fov, "fov");
			s.HeadBob = Json.Int(d, s.HeadBob, "headBob");
			s.LookStyle = Json.Str(d, "lookStyle") ?? s.LookStyle;
			s.ShowFps = ReadBool(d, "showFps", s.ShowFps);
			s.MasterVolume = Json.Int(d, s.MasterVolume, "masterVolume");
			s.MusicVolume = Json.Int(d, s.MusicVolume, "musicVolume");
			s.EffectsVolume = Json.Int(d, s.EffectsVolume, "effectsVolume");
			s.VoiceVolume = Json.Int(d, s.VoiceVolume, "voiceVolume");
			s.MuteInBackground = ReadBool(d, "muteInBackground", s.MuteInBackground);
			s.NewsCategory = Json.Str(d, "newsCategory") ?? s.NewsCategory;
			s.MinimizeWhilePlaying = ReadBool(d, "minimizeWhilePlaying", s.MinimizeWhilePlaying);
			s.LauncherMusic = ReadBool(d, "launcherMusic", s.LauncherMusic);
			s.AutoUpdate = ReadBool(d, "autoUpdate", s.AutoUpdate);
			s.GamePath = Json.Str(d, "gamePath") ?? s.GamePath;
			s.Map = Json.Str(d, "map") ?? s.Map;
			s.PlayerName = Json.Str(d, "playerName") ?? s.PlayerName;
		}
		catch (Exception e)
		{
			Log.Write("Couldn't read settings, using defaults: " + e.Message);
		}
		s.Clamp();
		return s;
	}

	public void Save()
	{
		Clamp();
		var d = ToReport();
		d["newsCategory"] = NewsCategory;
		d["minimizeWhilePlaying"] = Bool(MinimizeWhilePlaying);
		d["launcherMusic"] = Bool(LauncherMusic);
		d["autoUpdate"] = Bool(AutoUpdate);
		d["gamePath"] = GamePath;
		d["map"] = Map;
		d["playerName"] = PlayerName;
		try
		{
			File.WriteAllText(Paths.SettingsFile, Json.Write(d));
		}
		catch (Exception e)
		{
			Log.Write("Couldn't save settings: " + e.Message);
		}
	}

	/** Keeps every value inside the range the game accepts. **/
	public void Clamp()
	{
		WindowWidth = Clamp(WindowWidth, 640, 7680);
		WindowHeight = Clamp(WindowHeight, 360, 4320);
		Scaling = Scaling == "fit" ? "fit" : "integer";
		Fov = Clamp(Fov, 70, 110);
		HeadBob = Clamp(HeadBob, 0, 100);
		LookStyle = LookStyle == "perspective" ? "perspective" : "shear";
		MasterVolume = Clamp(MasterVolume, 0, 100);
		MusicVolume = Clamp(MusicVolume, 0, 100);
		EffectsVolume = Clamp(EffectsVolume, 0, 100);
		VoiceVolume = Clamp(VoiceVolume, 0, 100);
		if (string.IsNullOrWhiteSpace(NewsCategory))
			NewsCategory = "all";
		if (!MapStore.ValidName(Map))
			Map = "";
		PlayerName = (PlayerName ?? "").Trim();
		if (PlayerName.Length > 20)
			PlayerName = PlayerName.Substring(0, 20).Trim();
		if (PlayerName.Length == 0)
			PlayerName = DefaultName();
	}

	/** The Windows account's name to start with; the player can change it in the Multiplayer window. **/
	static string DefaultName()
	{
		var n = (Environment.UserName ?? "").Trim();
		return n.Length == 0 ? "Player" : n.Length > 20 ? n.Substring(0, 20) : n;
	}

	static int Clamp(int v, int min, int max) => v < min ? min : (v > max ? max : v);

	static string Bool(bool b) => b ? "1" : "0";

	static bool ReadBool(object? d, string key, bool fallback) => Json.Str(d, key) switch
	{
		"1" or "true" or "True" => true,
		"0" or "false" or "False" => false,
		_ => fallback,
	};
}
