// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Linq;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform.Storage;

namespace CrownAndCard.Launcher.UI;

/**
	Graphics and audio options passed through to the game, plus a few
	launcher options. Changes save immediately.
**/
sealed class SettingsView : UserControl
{
	/** Raised with the name of what changed: "gamePath" (also the game window choice), "newsCategory", "playerName" or "game". **/
	public event Action<string>? Changed;

	readonly LauncherSettings s;
	bool loading;

	readonly Choice gameWindow = new(("native", "Its own window (best for controllers)"), ("browser", "A browser window (web build)"));
	readonly Choice displayMode = new(("windowed", "Windowed"), ("fullscreen", "Fullscreen"));
	readonly Choice windowSize = new(LauncherSettings.WindowSizes.Select(w => ($"{w.W}x{w.H}", $"{w.W} × {w.H}")).ToArray());
	readonly Choice scaling = new(("integer", "Whole-number (sharpest pixels)"), ("fit", "Fill the window"));
	readonly Choice renderHeight = new(("480", "480 lines"), ("720", "720 lines (sharpest)"));
	readonly GoldSlider fov = new() { Minimum = 70, Maximum = 110, Suffix = "°" };
	readonly GoldSlider headBob = new();
	readonly Choice lookStyle = new(("shear", "Classic (Build-style shear)"), ("perspective", "Modern (true perspective)"));
	readonly TickBox showFps = new("Show frame rate");
	readonly GoldSlider mouseSensitivity = new() { Minimum = 25, Maximum = 300 };

	readonly GoldSlider master = new();
	readonly GoldSlider music = new();
	readonly GoldSlider effects = new();
	readonly GoldSlider voices = new();
	readonly TickBox muteInBackground = new("Mute when the game is in the background");

	readonly Choice newsCategory = new(("all", "All posts"), ("news", "News"), ("games", "Games"));
	readonly TickBox minimize = new("Minimize the launcher while playing");
	readonly TickBox showGameLog = new("Open the game log beside the game");
	readonly TickBox autoUpdate = new("Check GitHub for updates when the launcher starts");
	readonly TextBox gamePath = new() { Width = 250, FontSize = UiTheme.Body };
	readonly Button browse = UiTheme.Button("Browse…", size: UiTheme.Body);
	readonly TextBox playerName = new() { Width = 250, MaxLength = 20, FontSize = UiTheme.Body };

	public SettingsView(LauncherSettings settings)
	{
		s = settings;

		var pathRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Children = { gamePath, browse } };

		var graphics = Group("GRAPHICS",
			("Run the game in", gameWindow),
			("Display", displayMode),
			("Window size", windowSize),
			("Pixel scaling", scaling),
			("Render resolution", renderHeight),
			("Field of view", fov),
			("Head bob and sway", headBob),
			("Looking up and down", lookStyle),
			("Mouse sensitivity", mouseSensitivity),
			("", showFps));
		var audio = Group("AUDIO",
			("Master", master),
			("Music", music),
			("Effects", effects),
			("Voices", voices),
			("", muteInBackground));
		var audioNote = UiTheme.Label("The game has no sound yet. These are passed through now and will drive the mixer once audio lands.", UiTheme.Small, UiTheme.Muted);
		audioNote.MaxWidth = 420;
		audioNote.Margin = new Thickness(3, -6, 3, 16);
		var launcher = Group("LAUNCHER",
			("News category", newsCategory),
			("", minimize),
			("", showGameLog),
			("", autoUpdate),
			("Game folder", pathRow),
			("Name at multiplayer tables", playerName));
		var pathHint = UiTheme.Label("Leave empty to find the game next to the launcher (native/mac/game, or web/index.html).", UiTheme.Small, UiTheme.Muted);
		pathHint.MaxWidth = 440;
		pathHint.Margin = new Thickness(3, 0, 3, 0);

		var right = new StackPanel { Children = { audio, audioNote, launcher, pathHint } };

		var reset = UiTheme.Button("Reset graphics and audio", size: UiTheme.Body);
		reset.Click += (_, _) => ResetGraphicsAndAudio();
		var note = UiTheme.Label("Saved automatically. They're passed to the game each time you press Play.", UiTheme.Small, UiTheme.Muted);
		note.VerticalAlignment = VerticalAlignment.Center;
		note.Margin = new Thickness(12, 0, 3, 0);
		var footer = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 10, 0, 10), Children = { reset, note } };

		var layout = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,Auto"), RowDefinitions = new RowDefinitions("Auto,Auto") };
		layout.Children.Add(graphics);
		Grid.SetColumn(right, 1);
		layout.Children.Add(right);
		Grid.SetRow(footer, 1);
		Grid.SetColumnSpan(footer, 2);
		layout.Children.Add(footer);
		Content = new ScrollViewer { Content = layout, HorizontalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Auto };

		LoadValues();
		foreach (var choice in new[] { displayMode, windowSize, scaling, renderHeight, lookStyle })
			choice.SelectionChanged += (_, _) => Apply("game");
		foreach (var slider in new[] { fov, headBob, mouseSensitivity, master, music, effects, voices })
			slider.ValueChanged += (_, _) => Apply("game");
		foreach (var box in new[] { showFps, muteInBackground, minimize, showGameLog, autoUpdate })
			box.CheckedChanged += (_, _) => Apply("game");
		gameWindow.SelectionChanged += (_, _) => Apply("gamePath");
		newsCategory.SelectionChanged += (_, _) => Apply("newsCategory");
		gamePath.LostFocus += (_, _) => Apply("gamePath");
		gamePath.KeyDown += (_, e) =>
		{
			if (e.Key == Key.Enter)
				Apply("gamePath");
		};
		browse.Click += (_, _) => Browse();
		playerName.LostFocus += (_, _) => Apply("playerName");
		playerName.KeyDown += (_, e) =>
		{
			if (e.Key == Key.Enter)
				Apply("playerName");
		};
	}

	/** Shows the current values again (after the game menu changed them). **/
	public void Reload() => LoadValues();

	void LoadValues()
	{
		loading = true;
		gameWindow.Value = s.GameWindow;
		displayMode.Value = s.Fullscreen ? "fullscreen" : "windowed";
		windowSize.Value = $"{s.WindowWidth}x{s.WindowHeight}";
		scaling.Value = s.Scaling;
		renderHeight.Value = s.RenderHeight.ToString();
		fov.Value = s.Fov;
		headBob.Value = s.HeadBob;
		lookStyle.Value = s.LookStyle;
		showFps.Checked = s.ShowFps;
		mouseSensitivity.Value = s.MouseSensitivity;
		master.Value = s.MasterVolume;
		music.Value = s.MusicVolume;
		effects.Value = s.EffectsVolume;
		voices.Value = s.VoiceVolume;
		muteInBackground.Checked = s.MuteInBackground;
		newsCategory.Value = s.NewsCategory;
		minimize.Checked = s.MinimizeWhilePlaying;
		showGameLog.Checked = s.ShowGameLog;
		autoUpdate.Checked = s.AutoUpdate;
		gamePath.Text = s.GamePath;
		playerName.Text = s.PlayerName;
		loading = false;
	}

	void Apply(string what)
	{
		if (loading)
			return;
		s.GameWindow = gameWindow.Value;
		s.Fullscreen = displayMode.Value == "fullscreen";
		var size = windowSize.Value.Split('x');
		if (size.Length == 2 && int.TryParse(size[0], out var w) && int.TryParse(size[1], out var h))
		{
			s.WindowWidth = w;
			s.WindowHeight = h;
		}
		s.Scaling = scaling.Value;
		s.RenderHeight = renderHeight.Value == "720" ? 720 : 480;
		s.Fov = fov.Value;
		s.HeadBob = headBob.Value;
		s.LookStyle = lookStyle.Value;
		s.ShowFps = showFps.Checked;
		s.MouseSensitivity = mouseSensitivity.Value;
		s.MasterVolume = master.Value;
		s.MusicVolume = music.Value;
		s.EffectsVolume = effects.Value;
		s.VoiceVolume = voices.Value;
		s.MuteInBackground = muteInBackground.Checked;
		s.NewsCategory = newsCategory.Value;
		s.MinimizeWhilePlaying = minimize.Checked;
		s.ShowGameLog = showGameLog.Checked;
		s.AutoUpdate = autoUpdate.Checked;
		s.GamePath = (gamePath.Text ?? "").Trim();
		s.PlayerName = (playerName.Text ?? "").Trim();
		s.Save();
		if (what == "playerName")
			playerName.Text = s.PlayerName; // Save() fills in a default for an empty name
		Changed?.Invoke(what);
	}

	void ResetGraphicsAndAudio()
	{
		var d = new LauncherSettings();
		s.Fullscreen = d.Fullscreen;
		s.WindowWidth = d.WindowWidth;
		s.WindowHeight = d.WindowHeight;
		s.Scaling = d.Scaling;
		s.RenderHeight = d.RenderHeight;
		s.Fov = d.Fov;
		s.HeadBob = d.HeadBob;
		s.LookStyle = d.LookStyle;
		s.ShowFps = d.ShowFps;
		s.MouseSensitivity = d.MouseSensitivity;
		s.MasterVolume = d.MasterVolume;
		s.MusicVolume = d.MusicVolume;
		s.EffectsVolume = d.EffectsVolume;
		s.VoiceVolume = d.VoiceVolume;
		s.MuteInBackground = d.MuteInBackground;
		s.Save();
		LoadValues();
		Changed?.Invoke("game");
	}

	async void Browse()
	{
		var top = TopLevel.GetTopLevel(this);
		if (top == null)
			return;
		var picked = await top.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
		{
			Title = "Choose the folder that contains the game (native/mac/game, or web/index.html)",
			AllowMultiple = false,
		});
		var path = picked.Count > 0 ? picked[0].TryGetLocalPath() : null;
		if (path != null)
		{
			gamePath.Text = path;
			Apply("gamePath");
		}
	}

	static Grid Group(string title, params (string Label, Control Control)[] rows)
	{
		var t = new Grid { ColumnDefinitions = new ColumnDefinitions("170,Auto"), Margin = new Thickness(0, 0, 32, 12) };
		t.RowDefinitions.Add(new RowDefinition(GridLength.Auto));
		var heading = UiTheme.Label(title, UiTheme.Tab, UiTheme.Gold, weight: FontWeight.SemiBold);
		heading.Margin = new Thickness(3, 0, 3, 8);
		Grid.SetColumnSpan(heading, 2);
		t.Children.Add(heading);
		int row = 1;
		foreach (var (label, control) in rows)
		{
			t.RowDefinitions.Add(new RowDefinition(GridLength.Auto));
			var l = UiTheme.Label(label, UiTheme.Body, UiTheme.Muted);
			l.VerticalAlignment = VerticalAlignment.Center;
			l.Margin = new Thickness(3, 6, 8, 6);
			control.HorizontalAlignment = HorizontalAlignment.Left;
			control.VerticalAlignment = VerticalAlignment.Center;
			control.Margin = new Thickness(3);
			Grid.SetRow(l, row);
			Grid.SetRow(control, row);
			Grid.SetColumn(control, 1);
			t.Children.Add(l);
			t.Children.Add(control);
			row++;
		}
		return t;
	}
}
