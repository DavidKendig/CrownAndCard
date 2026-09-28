// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace CrownAndCard.Launcher.UI;

sealed class LauncherForm : Form
{
	readonly LauncherSettings settings = LauncherSettings.Load();
	readonly LocalServer server = new();
	readonly NewsView news = new();
	readonly SettingsView settingsView;
	readonly ReportsView reports = new();
	readonly Panel content = new() { Dock = DockStyle.Fill, Padding = new Padding(28, 18, 28, 10), BackColor = Theme.Background };
	readonly ManorPanel manor = new() { Dock = DockStyle.Left, Width = 338 };
	readonly Button play = new() { Text = "PLAY", Size = new Size(210, 56), Font = Theme.Play };
	readonly Label gameLabel = Theme.Label("", Theme.Body, Theme.Cream);
	readonly Label sessionLabel = Theme.Label("", Theme.Small, Theme.Muted);
	readonly List<TabButton> tabs = [];
	readonly Timer ticker = new() { Interval = 1000 };
	readonly MusicPlayer? music;
	readonly MusicToggle musicToggle = new();
	readonly Label versionLabel = Theme.Label($"Launcher {Program.Version}", Theme.Small, Theme.Muted);
	readonly LinkLabel updateLink = new()
	{
		AutoSize = true,
		Font = Theme.Small,
		LinkColor = Theme.Gold,
		ActiveLinkColor = Theme.GoldBright,
		LinkBehavior = LinkBehavior.HoverUnderline,
		BackColor = Color.Transparent,
		ForeColor = Theme.Muted,
	};
	readonly Timer padTimer = new() { Interval = 50 };
	readonly XInputPad controller = new();
	Action? updateAction;
	ReleaseInfo? pendingRelease;
	bool updating;
	bool isActive = true;

	GameSession? session;
	GamePlan? plan;

	public LauncherForm()
	{
		Text = "Crown & Card";
		AutoScaleDimensions = new SizeF(96f, 96f);
		AutoScaleMode = AutoScaleMode.Dpi;
		ClientSize = new Size(1180, 760);
		MinimumSize = new Size(900, 620);
		StartPosition = FormStartPosition.CenterScreen;
		BackColor = Theme.Background;
		ForeColor = Theme.Cream;
		Font = Theme.Body;
		DoubleBuffered = true;
		try
		{
			Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
		}
		catch
		{
			// Keep the default icon.
		}

		settingsView = new SettingsView(settings);
		settingsView.Changed += what =>
		{
			if (what == "gamePath")
				DetectGame();
			else if (what == "newsCategory")
				news.LoadNews(settings.NewsCategory);
			UpdateMusic();
		};
		music = MusicPlayer.TryStart(MusicVolume(), false);

		var header = new HeaderPanel { Dock = DockStyle.Top, Height = 118 };
		foreach (var (name, view) in new (string, Control)[] { ("NEWS", news), ("SETTINGS", settingsView), ("REPORTS", reports) })
		{
			var tab = new TabButton(name, view);
			tab.Click += (_, _) => ShowView(tab.View);
			tabs.Add(tab);
			header.Controls.Add(tab);
		}
		header.Controls.Add(musicToggle);
		musicToggle.Click += (_, _) =>
		{
			settings.LauncherMusic = !settings.LauncherMusic;
			settings.Save();
			UpdateMusic();
		};
		header.Resize += (_, _) =>
		{
			musicToggle.Location = new Point(header.Width - musicToggle.Width - 28, 12);
			int x = header.Width - 28;
			for (int i = tabs.Count - 1; i >= 0; i--)
			{
				x -= tabs[i].Width;
				tabs[i].Location = new Point(x, header.Height - tabs[i].Height - 6);
				x -= 6;
			}
		};

		var footer = new FooterPanel { Dock = DockStyle.Bottom, Height = 92 };
		Theme.StyleButton(play, primary: true);
		play.Click += (_, _) => Play();
		gameLabel.Location = new Point(28, 20);
		sessionLabel.Location = new Point(28, 48);
		versionLabel.Location = new Point(28, 68);
		versionLabel.SizeChanged += (_, _) => updateLink.Left = versionLabel.Right + 10;
		updateLink.Location = new Point(versionLabel.Right + 10, 68);
		updateLink.LinkClicked += (_, _) => updateAction?.Invoke();
		footer.Controls.AddRange([gameLabel, sessionLabel, versionLabel, updateLink, play]);
		footer.Resize += (_, _) =>
		{
			play.Location = new Point(footer.Width - play.Width - 28, (footer.Height - play.Height) / 2 + 2);
			gameLabel.MaximumSize = sessionLabel.MaximumSize = new Size(Math.Max(200, play.Left - 56), 0);
		};

		var body = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Background };
		body.Controls.Add(content);
		body.Controls.Add(manor);
		Controls.Add(body);
		Controls.Add(footer);
		Controls.Add(header);

		ShowView(news);
		news.LoadNews(settings.NewsCategory);
		DetectGame();
		ShowLastSession();
		ticker.Tick += (_, _) => TickSession();
		ticker.Start();
		padTimer.Tick += (_, _) => PollController();
		padTimer.Start();
		if (settings.AutoUpdate)
			CheckForUpdates();
		else
			SetUpdateStatus("Check for updates", CheckForUpdates);
		AcceptButton = play;
		UpdateMusic();
	}

	/** Menu music plays while the launcher is open, not during a game, and (optionally) not in the background. **/
	void UpdateMusic()
	{
		musicToggle.On = settings.LauncherMusic;
		musicToggle.Available = music != null;
		if (music == null)
			return;
		bool inBackground = WindowState == FormWindowState.Minimized || (settings.MuteInBackground && !isActive);
		music.Volume = MusicVolume();
		music.Playing = settings.LauncherMusic && session == null && !inBackground;
	}

	/** Master × music, squared so the sliders feel even to the ear. **/
	float MusicVolume()
	{
		float v = settings.MasterVolume / 100f * (settings.MusicVolume / 100f);
		return v * v;
	}

	protected override void OnActivated(EventArgs e)
	{
		isActive = true;
		UpdateMusic();
		base.OnActivated(e);
	}

	protected override void OnDeactivate(EventArgs e)
	{
		isActive = false;
		UpdateMusic();
		base.OnDeactivate(e);
	}

	protected override void OnResize(EventArgs e)
	{
		base.OnResize(e);
		if (music != null)
			UpdateMusic();
	}

	/** Checks GitHub for a newer release and offers it (§13.12). Installing always needs the player's click. **/
	async void CheckForUpdates()
	{
		if (updating)
			return;
		SetUpdateStatus("Checking for updates…", null);
		try
		{
			var release = await Updater.CheckAsync();
			if (release == null || !Updater.IsNewer(release.Version, Program.Version))
			{
				pendingRelease = null;
				SetUpdateStatus("Up to date  ·  check again", CheckForUpdates);
				return;
			}
			pendingRelease = release;
			var reason = Updater.CannotUpdateReason();
			if (reason != null)
			{
				Log.Write($"Version {release.Version} is on GitHub; not offering to install it: {reason}");
				SetUpdateStatus($"Version {release.Version} is on GitHub  ·  view release", () => OpenUrl(release.PageUrl));
				return;
			}
			SetUpdateStatus($"Version {release.Version} is available  ·  install", () => _ = InstallUpdate(release));
		}
		catch (Exception e)
		{
			Log.Write("Update check failed: " + e.Message);
			SetUpdateStatus("Couldn't check for updates  ·  retry", CheckForUpdates);
		}
	}

	async System.Threading.Tasks.Task InstallUpdate(ReleaseInfo release)
	{
		if (session != null)
		{
			SetUpdateStatus($"Finish playing first, then install {release.Version}", () => _ = InstallUpdate(release));
			return;
		}
		updating = true;
		play.Enabled = false;
		try
		{
			await Updater.DownloadAndRunSetupAsync(release, new Progress<string>(text => SetUpdateStatus(text, null)));
			Log.Write($"Started the {release.Version} installer; closing so it can update the launcher");
			Close();
		}
		catch (Exception e)
		{
			updating = false;
			DetectGame();
			Log.Write("Update failed: " + e);
			SetUpdateStatus($"Update to {release.Version} failed  ·  retry", () => _ = InstallUpdate(release));
		}
	}

	void SetUpdateStatus(string text, Action? action)
	{
		updateAction = action;
		updateLink.Text = text;
		updateLink.LinkArea = action == null ? new LinkArea(0, 0) : new LinkArea(0, text.Length);
	}

	static void OpenUrl(string url)
	{
		if (url.StartsWith("https://github.com/", StringComparison.Ordinal))
			System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true });
	}

	/** Controller in the launcher: A or Start plays, LB/RB switch tabs, Y toggles the music. **/
	void PollController()
	{
		bool wasConnected = controller.Connected;
		controller.Poll();
		if (controller.Connected != wasConnected)
			versionLabel.Text = $"Launcher {Program.Version}" + (controller.Connected ? "  ·  Controller: A play, LB/RB tabs, Y music" : "");
		if (!isActive || !controller.Connected || controller.Pressed == 0)
			return;
		if ((controller.WasPressed(XInputPad.A) || controller.WasPressed(XInputPad.Start)) && play.Enabled)
			Play();
		if (controller.WasPressed(XInputPad.RB) || controller.WasPressed(XInputPad.LB))
		{
			int current = tabs.FindIndex(t => t.Active);
			int next = (current + (controller.WasPressed(XInputPad.RB) ? 1 : tabs.Count - 1)) % tabs.Count;
			ShowView(tabs[next].View);
		}
		if (controller.WasPressed(XInputPad.Y) && music != null)
		{
			settings.LauncherMusic = !settings.LauncherMusic;
			settings.Save();
			UpdateMusic();
		}
	}

	void ShowView(Control view)
	{
		manor.Visible = view == news;
		if (content.Controls.Count == 1 && content.Controls[0] == view)
			return;
		content.Controls.Clear();
		view.Dock = DockStyle.Fill;
		content.Controls.Add(view);
		foreach (var t in tabs)
			t.Active = t.View == view;
		if (view == reports)
			reports.Reload();
	}

	void DetectGame()
	{
		plan = GameLocator.Find(settings.GamePath);
		gameLabel.Text = plan == null
			? "Game not found. Set the game folder in Settings."
			: "Ready  ·  " + plan.Describe();
		gameLabel.ForeColor = plan == null ? Theme.Amber : Theme.Cream;
		play.Enabled = plan != null && session == null && !updating;
	}

	void Play()
	{
		DetectGame();
		if (plan == null || session != null)
			return;
		try
		{
			session = GameSession.Start(plan, settings, server);
		}
		catch (Exception e)
		{
			Log.Write("Launch failed: " + e);
			MessageBox.Show(this, $"The game couldn't be started:\n\n{e.Message}", "Crown & Card", MessageBoxButtons.OK, MessageBoxIcon.Error);
			return;
		}
		session.Ended += status => BeginInvoke(new Action(() => OnSessionEnded(status)));
		play.Text = "PLAYING…";
		play.Enabled = false;
		UpdateMusic();
		sessionLabel.Text = "Starting the game…  Recording to " + session.Recorder.Dir;
		if (settings.MinimizeWhilePlaying)
			WindowState = FormWindowState.Minimized;
	}

	void TickSession()
	{
		if (session == null)
			return;
		session.Tick();
		var r = session.Recorder;
		if (r.Ended)
			return;
		var room = r.LastRoom.Length > 0 ? r.LastRoom : "starting up";
		var contact = r.Heartbeats == 0 ? "waiting for the game to report in" : $"last report {(int)(DateTime.Now - r.LastContact).TotalSeconds} s ago";
		sessionLabel.Text = $"Playing  ·  {room}  ·  {contact}" + (r.Errors > 0 ? $"  ·  {r.Errors} error(s) recorded" : "");
	}

	void OnSessionEnded(string status)
	{
		session = null;
		play.Text = "PLAY";
		DetectGame();
		UpdateMusic();
		if (pendingRelease is { } release && Updater.CannotUpdateReason() == null)
			SetUpdateStatus($"Version {release.Version} is available  ·  install", () => _ = InstallUpdate(release));
		if (WindowState == FormWindowState.Minimized)
			WindowState = FormWindowState.Normal;
		Activate();
		ShowLastSession();
		if (status is "crashed" or "errors" or "lost-contact")
		{
			ShowView(reports);
			MessageBox.Show(this, $"The last session ended with a problem ({Theme.StatusText(status).ToLowerInvariant()}). A report was saved; see the Reports tab.",
				"Crown & Card", MessageBoxButtons.OK, MessageBoxIcon.Warning);
		}
		else if (content.Controls.Count == 1 && content.Controls[0] == reports)
			reports.Reload();
	}

	void ShowLastSession()
	{
		var all = SessionRecorder.ListAll();
		if (all.Count == 0)
		{
			sessionLabel.Text = "No sessions recorded yet.";
			sessionLabel.ForeColor = Theme.Muted;
			return;
		}
		var last = all[0];
		sessionLabel.Text = $"Last session: {Theme.StatusText(last.Status)}  ·  {last.Started:MMM d, h:mm tt}"
			+ (last.LastRoom.Length > 0 ? $"  ·  last seen in the {last.LastRoom}" : "");
		sessionLabel.ForeColor = last.Status == "ok" ? Theme.Muted : Theme.StatusColor(last.Status);
	}

	protected override void OnFormClosing(FormClosingEventArgs e)
	{
		session?.LauncherClosing();
		ticker.Stop();
		padTimer.Stop();
		music?.Dispose();
		server.Dispose();
		base.OnFormClosing(e);
	}

	/** Title banner: a gradient, the crown, and the game's name. **/
	sealed class HeaderPanel : Panel
	{
		readonly Bitmap emblem = LoadArtwork("CrownAndCard.Emblem.png");
		readonly Bitmap logo = LoadArtwork("CrownAndCard.Logo.png");

		public HeaderPanel()
		{
			DoubleBuffered = true;
			ResizeRedraw = true;
			BackColor = Theme.Panel;
			AccessibleName = "Crown & Card";
		}

		static Bitmap LoadArtwork(string name)
		{
			using var stream = typeof(LauncherForm).Assembly.GetManifestResourceStream(name)
				?? throw new InvalidOperationException("Missing launcher artwork: " + name);
			using var source = new Bitmap(stream);
			// Ignore transparent export margins while retaining the original PNG masters.
			int left = source.Width, top = source.Height, right = -1, bottom = -1;
			for (int y = 0; y < source.Height; y++)
			for (int x = 0; x < source.Width; x++)
			{
				if (source.GetPixel(x, y).A < 16) continue;
				left = Math.Min(left, x); top = Math.Min(top, y);
				right = Math.Max(right, x); bottom = Math.Max(bottom, y);
			}
			if (right < left) throw new InvalidOperationException("Empty launcher artwork: " + name);
			return source.Clone(Rectangle.FromLTRB(left, top, right + 1, bottom + 1), System.Drawing.Imaging.PixelFormat.Format32bppArgb);
		}

		protected override void OnPaint(PaintEventArgs e)
		{
			var g = e.Graphics;
			using (var bg = new LinearGradientBrush(ClientRectangle, Theme.Panel, Theme.Background, LinearGradientMode.Vertical))
				g.FillRectangle(bg, ClientRectangle);
			using (var line = new Pen(Theme.GoldDark, 2))
				g.DrawLine(line, 0, Height - 1, Width, Height - 1);
			float scale = Height / 118f;
			g.InterpolationMode = InterpolationMode.NearestNeighbor;
			g.PixelOffsetMode = PixelOffsetMode.Half;
			float emblemHeight = 88 * scale;
			g.DrawImage(emblem, new RectangleF(26 * scale, 14 * scale, emblemHeight * emblem.Width / emblem.Height, emblemHeight));
			// The logo matches the crown's height; reserve room for the navigation at the
			// minimum window width and at high DPI, shrinking it about the crown's centre line.
			float logoWidth = Math.Min(emblemHeight * logo.Width / logo.Height, Math.Max(180 * scale, Width - 480 * scale));
			float logoHeight = logoWidth * logo.Height / logo.Width;
			g.DrawImage(logo, new RectangleF(106 * scale, 14 * scale + (emblemHeight - logoHeight) / 2, logoWidth, logoHeight));
		}

		protected override void Dispose(bool disposing)
		{
			if (disposing) { emblem.Dispose(); logo.Dispose(); }
			base.Dispose(disposing);
		}
	}

	sealed class FooterPanel : Panel
	{
		public FooterPanel()
		{
			DoubleBuffered = true;
			ResizeRedraw = true;
			BackColor = Theme.Panel;
		}

		protected override void OnPaint(PaintEventArgs e)
		{
			base.OnPaint(e);
			using var line = new Pen(Theme.GoldDark, 1);
			e.Graphics.DrawLine(line, 0, 0, Width, 0);
		}
	}

	/** Header switch for the menu music. **/
	sealed class MusicToggle : Control
	{
		bool on = true;
		bool available = true;
		bool hover;

		public MusicToggle()
		{
			Font = Theme.Small;
			Cursor = Cursors.Hand;
			SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true);
			BackColor = Color.Transparent;
			Size = new Size(TextRenderer.MeasureText("♪  MUSIC OFF", Theme.Small).Width + 16, 24);
		}

		public bool On
		{
			get => on;
			set { on = value; Invalidate(); }
		}

		/** False when this PC can't play the music (no audio device, or a 32-bit system). **/
		public bool Available
		{
			get => available;
			set { available = value; Enabled = value; Invalidate(); }
		}

		protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }

		protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }

		protected override void OnPaint(PaintEventArgs e)
		{
			var text = !available ? "♪  NO AUDIO" : on ? "♪  MUSIC ON" : "♪  MUSIC OFF";
			var color = !available ? Theme.Border : on ? (hover ? Theme.GoldBright : Theme.Gold) : (hover ? Theme.Cream : Theme.Muted);
			TextRenderer.DrawText(e.Graphics, text, Font, ClientRectangle, color, TextFormatFlags.Right | TextFormatFlags.VerticalCenter);
		}
	}

	/** A text tab with a gold underline when active. **/
	sealed class TabButton : Control
	{
		public Control View { get; }
		bool active;
		bool hover;

		public TabButton(string text, Control view)
		{
			Text = text;
			View = view;
			Font = Theme.Tab;
			Cursor = Cursors.Hand;
			SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true);
			BackColor = Color.Transparent;
			Size = new Size(TextRenderer.MeasureText(text, Theme.Tab).Width + 28, 36);
		}

		public bool Active
		{
			get => active;
			set
			{
				active = value;
				Invalidate();
			}
		}

		protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }

		protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }

		protected override void OnPaint(PaintEventArgs e)
		{
			var color = active ? Theme.GoldBright : hover ? Theme.Cream : Theme.Muted;
			if (active || hover)
			{
				using var fill = new SolidBrush(active ? Theme.Burgundy : Theme.Card);
				e.Graphics.FillRectangle(fill, 0, 0, Width, Height - 4);
			}
			TextRenderer.DrawText(e.Graphics, Text, Font, new Rectangle(0, 0, Width, Height - 4), color,
				TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
			if (active)
			{
				using var underline = new SolidBrush(Theme.Gold);
				e.Graphics.FillRectangle(underline, 10, Height - 4, Width - 20, 3);
			}
		}
	}
}
