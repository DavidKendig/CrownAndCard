// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace CrownAndCard.Launcher.UI;

/**
	Graphics and audio options passed through to the game, plus a few
	launcher options. Changes save immediately.
**/
sealed class SettingsView : UserControl
{
	/** Raised with the name of what changed: "gamePath", "newsCategory" or "game". **/
	public event Action<string>? Changed;

	readonly LauncherSettings s;
	bool loading;

	readonly Choice displayMode = new(("windowed", "Windowed"), ("fullscreen", "Fullscreen"));
	readonly Choice windowSize = new(LauncherSettings.WindowSizes.Select(w => ($"{w.W}x{w.H}", $"{w.W} × {w.H}")).ToArray());
	readonly Choice scaling = new(("integer", "Whole-number (sharpest pixels)"), ("fit", "Fill the window"));
	readonly Slider fov = new() { Minimum = 70, Maximum = 110, Suffix = "°" };
	readonly Slider headBob = new();
	readonly Choice lookStyle = new(("shear", "Classic (Build-style shear)"), ("perspective", "Modern (true perspective)"));
	readonly CheckBox showFps = Check("Show frame rate");

	readonly Slider master = new();
	readonly Slider music = new();
	readonly Slider effects = new();
	readonly Slider voices = new();
	readonly CheckBox muteInBackground = Check("Mute when the game is in the background");

	readonly Choice newsCategory = new(("all", "All posts"), ("news", "News"), ("games", "Games"));
	readonly CheckBox minimize = Check("Minimize the launcher while playing");
	readonly CheckBox autoUpdate = Check("Check GitHub for updates when the launcher starts");
	readonly TextBox gamePath = new() { Width = 240, BackColor = Theme.Card, ForeColor = Theme.Cream, BorderStyle = BorderStyle.FixedSingle, Font = Theme.Body };
	readonly Button browse = new() { Text = "Browse…", AutoSize = true };
	readonly TextBox playerName = new() { Width = 240, MaxLength = 20, BackColor = Theme.Card, ForeColor = Theme.Cream, BorderStyle = BorderStyle.FixedSingle, Font = Theme.Body, Margin = new Padding(0, 4, 0, 0) };

	public SettingsView(LauncherSettings settings)
	{
		s = settings;
		BackColor = Theme.Background;
		AutoScroll = true;
		Theme.DarkScrollbars(this);
		Theme.StyleButton(browse);

		var pathRow = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0), BackColor = Color.Transparent };
		gamePath.Margin = new Padding(0, 4, 8, 0);
		pathRow.Controls.AddRange([gamePath, browse]);

		var graphics = Group("GRAPHICS",
			("Display", displayMode),
			("Window size", windowSize),
			("Pixel scaling", scaling),
			("Field of view", fov),
			("Head bob and sway", headBob),
			("Looking up and down", lookStyle),
			("", showFps));
		var audio = Group("AUDIO",
			("Master", master),
			("Music", music),
			("Effects", effects),
			("Voices", voices),
			("", muteInBackground));
		var audioNote = Theme.Label("The game has no sound yet. These are passed through now and will drive the mixer once audio lands.", Theme.Small, Theme.Muted);
		audioNote.MaximumSize = new Size(420, 0);
		audioNote.Margin = new Padding(3, 0, 3, 12);
		var launcher = Group("LAUNCHER",
			("News category", newsCategory),
			("", minimize),
			("", autoUpdate),
			("Game folder", pathRow),
			("Name at multiplayer tables", playerName));
		var pathHint = Theme.Label("Leave empty to find the game next to the launcher.", Theme.Small, Theme.Muted);

		var right = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false, BackColor = Color.Transparent };
		right.Controls.AddRange([audio, audioNote, launcher, pathHint]);

		var reset = new Button { Text = "Reset graphics and audio", AutoSize = true, Padding = new Padding(8, 2, 8, 2) };
		Theme.StyleButton(reset);
		reset.Click += (_, _) => ResetGraphicsAndAudio();
		var note = Theme.Label("Saved automatically. They're passed to the game each time you press Play.", Theme.Small, Theme.Muted);
		note.Margin = new Padding(12, 10, 3, 3);
		var footer = new FlowLayoutPanel { AutoSize = true, WrapContents = false, BackColor = Color.Transparent, Margin = new Padding(0, 6, 0, 0) };
		footer.Controls.AddRange([reset, note]);

		var layout = new TableLayoutPanel { ColumnCount = 2, RowCount = 2, AutoSize = true, Dock = DockStyle.Top, BackColor = Color.Transparent };
		layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
		layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
		layout.Controls.Add(graphics, 0, 0);
		layout.Controls.Add(right, 1, 0);
		layout.Controls.Add(footer, 0, 1);
		layout.SetColumnSpan(footer, 2);
		Controls.Add(layout);

		LoadValues();
		foreach (var choice in new[] { displayMode, windowSize, scaling, lookStyle })
			choice.SelectedIndexChanged += (_, _) => Apply("game");
		foreach (var slider in new[] { fov, headBob, master, music, effects, voices })
			slider.ValueChanged += (_, _) => Apply("game");
		foreach (var box in new[] { showFps, muteInBackground, minimize, autoUpdate })
			box.CheckedChanged += (_, _) => Apply("game");
		newsCategory.SelectedIndexChanged += (_, _) => Apply("newsCategory");
		gamePath.Leave += (_, _) => Apply("gamePath");
		gamePath.KeyDown += (_, e) =>
		{
			if (e.KeyCode == Keys.Enter)
				Apply("gamePath");
		};
		browse.Click += (_, _) => Browse();
		playerName.Leave += (_, _) => Apply("playerName");
		playerName.KeyDown += (_, e) =>
		{
			if (e.KeyCode == Keys.Enter)
				Apply("playerName");
		};
	}

	void LoadValues()
	{
		loading = true;
		displayMode.Value = s.Fullscreen ? "fullscreen" : "windowed";
		windowSize.Value = $"{s.WindowWidth}x{s.WindowHeight}";
		scaling.Value = s.Scaling;
		fov.Value = s.Fov;
		headBob.Value = s.HeadBob;
		lookStyle.Value = s.LookStyle;
		showFps.Checked = s.ShowFps;
		master.Value = s.MasterVolume;
		music.Value = s.MusicVolume;
		effects.Value = s.EffectsVolume;
		voices.Value = s.VoiceVolume;
		muteInBackground.Checked = s.MuteInBackground;
		newsCategory.Value = s.NewsCategory;
		minimize.Checked = s.MinimizeWhilePlaying;
		autoUpdate.Checked = s.AutoUpdate;
		gamePath.Text = s.GamePath;
		playerName.Text = s.PlayerName;
		loading = false;
	}

	void Apply(string what)
	{
		if (loading)
			return;
		s.Fullscreen = displayMode.Value == "fullscreen";
		var size = windowSize.Value.Split('x');
		if (size.Length == 2 && int.TryParse(size[0], out var w) && int.TryParse(size[1], out var h))
		{
			s.WindowWidth = w;
			s.WindowHeight = h;
		}
		s.Scaling = scaling.Value;
		s.Fov = fov.Value;
		s.HeadBob = headBob.Value;
		s.LookStyle = lookStyle.Value;
		s.ShowFps = showFps.Checked;
		s.MasterVolume = master.Value;
		s.MusicVolume = music.Value;
		s.EffectsVolume = effects.Value;
		s.VoiceVolume = voices.Value;
		s.MuteInBackground = muteInBackground.Checked;
		s.NewsCategory = newsCategory.Value;
		s.MinimizeWhilePlaying = minimize.Checked;
		s.AutoUpdate = autoUpdate.Checked;
		s.GamePath = gamePath.Text.Trim();
		s.PlayerName = playerName.Text.Trim();
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
		s.Fov = d.Fov;
		s.HeadBob = d.HeadBob;
		s.LookStyle = d.LookStyle;
		s.ShowFps = d.ShowFps;
		s.MasterVolume = d.MasterVolume;
		s.MusicVolume = d.MusicVolume;
		s.EffectsVolume = d.EffectsVolume;
		s.VoiceVolume = d.VoiceVolume;
		s.MuteInBackground = d.MuteInBackground;
		s.Save();
		LoadValues();
		Changed?.Invoke("game");
	}

	void Browse()
	{
		using var dialog = new FolderBrowserDialog { Description = "Choose the folder that contains the game (web\\index.html, CrownAndCard.exe, or hl.exe + game.hl)." };
		if (dialog.ShowDialog(this) == DialogResult.OK)
		{
			gamePath.Text = dialog.SelectedPath;
			Apply("gamePath");
		}
	}

	static TableLayoutPanel Group(string title, params (string Label, Control Control)[] rows)
	{
		var t = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, BackColor = Color.Transparent, Margin = new Padding(0, 0, 24, 4) };
		t.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 160));
		t.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
		var heading = Theme.Label(title, Theme.Tab, Theme.Gold);
		heading.Margin = new Padding(3, 0, 3, 6);
		t.Controls.Add(heading, 0, 0);
		t.SetColumnSpan(heading, 2);
		int row = 1;
		foreach (var (label, control) in rows)
		{
			var l = Theme.Label(label, Theme.Body, Theme.Muted);
			l.Anchor = AnchorStyles.Left;
			l.Margin = new Padding(3, 6, 3, 6);
			control.Anchor = AnchorStyles.Left;
			control.Margin = new Padding(3, 3, 3, 3);
			t.Controls.Add(l, 0, row);
			t.Controls.Add(control, 1, row);
			row++;
		}
		return t;
	}

	static CheckBox Check(string text) => new TickBox(text);
}
