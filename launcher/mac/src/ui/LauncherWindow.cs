// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Generic;
using System.Linq;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;

namespace CrownAndCard.Launcher.UI;

/** The launcher's main window (the Windows LauncherForm, for Avalonia on the Mac). **/
sealed class LauncherWindow : Window
{
	readonly LauncherSettings settings = LauncherSettings.Load();
	readonly LocalServer server = new();
	readonly NewsView news = new();
	readonly SettingsView settingsView;
	readonly ReportsView reports = new();
	readonly ContentControl content = new() { Padding = new Thickness(28, 18, 28, 10) };
	readonly ManorPanel manor = new() { Width = 338 };
	readonly Button play = UiTheme.Button("PLAY", primary: true, size: UiTheme.Play);
	readonly Button haxen = UiTheme.Button("HAXEN");
	readonly Button logButton = UiTheme.Button("LOG");
	readonly Button mapButton = UiTheme.Button("MAP");
	readonly MapStore maps = new(Paths.MapsDir);
	readonly TextBlock gameLabel = UiTheme.Label("", UiTheme.Body, UiTheme.Cream);
	readonly TextBlock sessionLabel = UiTheme.Label("", UiTheme.Small, UiTheme.Muted);
	readonly List<TabButton> tabs = [];
	readonly DispatcherTimer ticker = new() { Interval = TimeSpan.FromSeconds(1) };
	readonly MusicPlayer? music;
	readonly MusicToggle musicToggle = new();
	readonly TextBlock versionLabel = UiTheme.Label($"Launcher {Program.Version}", UiTheme.Small, UiTheme.Muted);
	readonly LinkText updateLink = new("", UiTheme.Small);
	readonly DispatcherTimer padTimer = new() { Interval = TimeSpan.FromMilliseconds(50) };
	readonly XInputPad controller = new();
	ReleaseInfo? pendingRelease;
	bool updating;
	bool isActive = true;
	bool closing;

	GameSession? session;
	GamePlan? plan;

	public LauncherWindow()
	{
		Title = "Crown & Card";
		Width = 1180;
		Height = 760;
		MinWidth = 900;
		MinHeight = 620;
		WindowStartupLocation = WindowStartupLocation.CenterScreen;
		Background = UiTheme.Brush(UiTheme.Background);
		FontSize = UiTheme.Body;
		try { Icon = new WindowIcon(Artwork.Open("CrownAndCard.Emblem.png")); } catch { /* keep the default */ }

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

		// Header: the banner art, with the tabs and the music switch over it.
		var tabRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 28, 6) };
		foreach (var (name, view) in new (string, Control)[] { ("NEWS", news), ("SETTINGS", settingsView), ("REPORTS", reports) })
		{
			var tab = new TabButton(name, view);
			tab.Click += () => ShowView(tab.View);
			tabs.Add(tab);
			tabRow.Children.Add(tab);
		}
		musicToggle.HorizontalAlignment = HorizontalAlignment.Right;
		musicToggle.VerticalAlignment = VerticalAlignment.Top;
		musicToggle.Margin = new Thickness(0, 12, 28, 0);
		musicToggle.Click += () =>
		{
			settings.LauncherMusic = !settings.LauncherMusic;
			settings.Save();
			UpdateMusic();
		};
		var header = new Panel { Height = 118, Children = { new HeaderArt(), tabRow, musicToggle } };

		// Footer: what's found and what happened last on the left; the buttons on the right.
		play.Width = 210;
		play.Height = 56;
		play.Click += (_, _) => Play();
		haxen.Click += (_, _) => OpenHaxen();
		logButton.Click += (_, _) => OpenGameLog();
		mapButton.Click += (_, _) => ShowMapMenu();
		mapButton.Width = 240;
		mapButton.HorizontalContentAlignment = HorizontalAlignment.Left;
		foreach (var b in new[] { haxen, logButton, mapButton })
			b.Height = 40;
		ToolTip.SetTip(logButton, "The game log: what the game window is doing, live, or the last session's");
		ToolTip.SetTip(haxen, "Haxen, the map editor: open the manor or make your own maps");
		var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 28, 0), Children = { logButton, mapButton, haxen } };
		play.Margin = new Thickness(4, 0, 0, 0);
		buttons.Children.Add(play);
		updateLink.Margin = new Thickness(10, 0, 0, 0);
		foreach (var t in new[] { gameLabel, sessionLabel })
		{
			t.TextWrapping = TextWrapping.NoWrap;
			t.TextTrimming = TextTrimming.CharacterEllipsis;
		}
		var info = new StackPanel
		{
			VerticalAlignment = VerticalAlignment.Center,
			Margin = new Thickness(28, 0, 16, 0),
			Spacing = 3,
			Children = { gameLabel, sessionLabel, new StackPanel { Orientation = Orientation.Horizontal, Children = { versionLabel, updateLink } } },
		};
		var footerGrid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto"), Children = { info, buttons } };
		Grid.SetColumn(buttons, 1);
		var footer = new Border
		{
			Height = 92,
			Background = UiTheme.Brush(UiTheme.Panel),
			BorderBrush = UiTheme.Brush(UiTheme.GoldDark),
			BorderThickness = new Thickness(0, 1, 0, 0),
			Child = footerGrid,
		};

		// Multiplayer is started from the Private Party table in the game (§13.13); the launcher carries it.
		server.StartHost = advertise => NetSession.Host(settings.PlayerName, Program.Version, NetSession.DefaultPort, advertise);
		server.StartJoin = code => NetSession.Join(code, settings.PlayerName, Program.Version);
		// Settings changed in the game menu are kept for the next visit, and shown in Settings.
		server.SettingsPosted = changed => Dispatcher.UIThread.Post(() =>
		{
			settings.ReadGameOptions(changed);
			settings.Save();
			settingsView.Reload();
			session?.Recorder.Note("Saved the settings changed in the game menu");
		});
		server.PlaytestRequested = name => Dispatcher.UIThread.Invoke(() => StartPlaytest(name));
		UpdateMapButton();

		var dock = new DockPanel();
		DockPanel.SetDock(header, Dock.Top);
		DockPanel.SetDock(footer, Dock.Bottom);
		DockPanel.SetDock(manor, Dock.Left);
		dock.Children.Add(header);
		dock.Children.Add(footer);
		dock.Children.Add(manor);
		dock.Children.Add(content);
		Content = dock;

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

		Activated += (_, _) => { isActive = true; UpdateMusic(); };
		Deactivated += (_, _) => { isActive = false; UpdateMusic(); };
		PropertyChanged += (_, e) =>
		{
			if (e.Property == WindowStateProperty)
				UpdateMusic();
		};
		Opened += (_, _) =>
		{
			if (Screens.Primary is { } screen)
				MacPlatform.PrimaryScreen = $"{(int)(screen.Bounds.Width / screen.Scaling)}x{(int)(screen.Bounds.Height / screen.Scaling)}";
		};
		KeyDown += (_, e) =>
		{
			if (e.Key == Key.Enter && play.IsEnabled && FocusManager?.GetFocusedElement() is not TextBox)
				Play();
		};
		UpdateMusic();
	}

	/** Menu music plays while the launcher is open, not during a game, and (optionally) not in the background. **/
	void UpdateMusic()
	{
		musicToggle.Set(settings.LauncherMusic, music != null);
		if (music == null)
			return;
		bool inBackground = WindowState == WindowState.Minimized || (settings.MuteInBackground && !isActive);
		music.Volume = MusicVolume();
		music.Playing = settings.LauncherMusic && session == null && !inBackground;
	}

	/** Master × music, squared so the sliders feel even to the ear. **/
	float MusicVolume()
	{
		float v = settings.MasterVolume / 100f * (settings.MusicVolume / 100f);
		return v * v;
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
		play.IsEnabled = false;
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

	void SetUpdateStatus(string text, Action? action) => updateLink.Set(text, action);

	static void OpenUrl(string url)
	{
		if (url.StartsWith("https://github.com/", StringComparison.Ordinal))
			MacPlatform.Open(url);
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
		if ((controller.WasPressed(XInputPad.A) || controller.WasPressed(XInputPad.Start)) && play.IsEnabled)
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
		manor.IsVisible = view == news;
		foreach (var t in tabs)
			t.Active = t.View == view;
		if (content.Content == view)
			return;
		content.Content = view;
		if (view == reports)
			reports.Reload();
	}

	void DetectGame()
	{
		plan = GameLocator.Find(settings.GamePath, settings.PreferNative);
		gameLabel.Text = plan == null
			? "Game not found. Build it (sh tools/build_mac.sh) or set the game folder in Settings."
			: "Ready  ·  " + plan.Describe();
		gameLabel.Foreground = UiTheme.Brush(plan == null || plan.Fallback != null ? UiTheme.Amber : UiTheme.Cream);
		ToolTip.SetTip(gameLabel, gameLabel.Text);
		play.IsEnabled = plan != null && session == null && !updating;
	}

	/** Chooses which map PLAY starts: the manor, or a custom map saved from Haxen (§13.6). **/
	void ShowMapMenu()
	{
		var menu = new MenuFlyout { Placement = PlacementMode.BottomEdgeAlignedLeft };
		MenuItem Item(string text, bool isChecked, Action onClick)
		{
			var item = new MenuItem { Header = text, ToggleType = MenuItemToggleType.CheckBox, IsChecked = isChecked };
			item.Click += (_, _) => onClick();
			return item;
		}
		void Choose(string name)
		{
			settings.Map = name;
			settings.Save();
			UpdateMapButton();
		}
		menu.Items.Add(Item("Dodriec Manor (the game's map)", settings.Map.Length == 0, () => Choose("")));
		var custom = maps.List();
		if (custom.Count > 0)
			menu.Items.Add(new Separator());
		foreach (var name in custom)
			menu.Items.Add(Item(name, settings.Map == name, () => Choose(name)));
		menu.Items.Add(new Separator());
		var edit = new MenuItem { Header = "Make or edit maps in Haxen…" };
		edit.Click += (_, _) => OpenHaxen();
		menu.Items.Add(edit);
		var folder = new MenuItem { Header = "Open the maps folder" };
		folder.Click += (_, _) =>
		{
			System.IO.Directory.CreateDirectory(maps.Folder);
			MacPlatform.OpenFolder(maps.Folder);
		};
		menu.Items.Add(folder);
		menu.ShowAt(mapButton);
	}

	void UpdateMapButton()
	{
		// A chosen map that's since been deleted falls back to the manor.
		if (settings.Map.Length > 0 && maps.Read(settings.Map) == null)
		{
			settings.Map = "";
			settings.Save();
		}
		mapButton.Content = "MAP:  " + (settings.Map.Length == 0 ? "Dodriec Manor" : settings.Map) + "  ▾";
	}

	async void OpenHaxen()
	{
		var web = GameLocator.FindHaxen(settings.GamePath);
		if (web == null)
		{
			await Dialog.Show(this, "Haxen wasn't found next to the game (web/haxen.html). Build it with `haxe haxen.hxml`, or set the game folder in Settings.", Dialog.Kind.Warning);
			return;
		}
		try
		{
			HaxenWindow.Open(server, web);
		}
		catch (Exception e)
		{
			Log.Write("Couldn't open Haxen: " + e);
			await Dialog.Show(this, $"Haxen couldn't be opened:\n\n{e.Message}", Dialog.Kind.Error);
		}
	}

	/** The running session's log, live; otherwise the open log window, or the latest session's. **/
	async void OpenGameLog()
	{
		if (session != null)
		{
			GameLogWindow.ShowLive(session.Recorder);
			return;
		}
		if (GameLogWindow.Raise())
			return;
		var last = SessionRecorder.ListAll().FirstOrDefault();
		if (last == null)
		{
			await Dialog.Show(this, "No sessions yet. Press Play and the game log will appear here.");
			return;
		}
		GameLogWindow.ShowSaved(last.Dir);
	}

	/** Haxen's "Play test": start the game on that map (on the UI thread). **/
	string? StartPlaytest(string name)
	{
		if (session != null)
			return "busy";
		DetectGame();
		if (plan == null)
			return "no game";
		Play(name);
		return session == null ? "failed" : null;
	}

	void Play(string? mapOverride = null)
	{
		DetectGame();
		UpdateMapButton();
		if (plan == null || session != null)
			return;
		try
		{
			session = GameSession.Start(plan, settings, server, mapOverride);
		}
		catch (Exception e)
		{
			Log.Write("Launch failed: " + e);
			_ = Dialog.Show(this, $"The game couldn't be started:\n\n{e.Message}", Dialog.Kind.Error);
			return;
		}
		session.Ended += status => Dispatcher.UIThread.Post(() => OnSessionEnded(status));
		// The native window has no browser console; its log opens beside it (§13.12).
		if (plan.Kind == GameKind.Native && settings.ShowGameLog)
			GameLogWindow.ShowLive(session.Recorder, activate: false);
		play.Content = "PLAYING…";
		play.IsEnabled = false;
		UpdateMusic();
		var mapName = mapOverride ?? (settings.Map.Length == 0 ? null : settings.Map);
		sessionLabel.Text = (mapName == null ? "Starting the game…" : $"Starting the game on {mapName}…") + "  Recording to " + session.Recorder.Dir;
		// Minimize once the game reports in (TickSession), so the game's window opens in front.
		minimizePending = settings.MinimizeWhilePlaying;
	}

	/** Set on PLAY; the launcher minimizes when the game first reports in, or after a few seconds. **/
	bool minimizePending;

	void MinimizeOnceStarted(SessionRecorder r)
	{
		if (!minimizePending || (r.Heartbeats == 0 && (DateTime.Now - r.StartedAt).TotalSeconds < 8))
			return;
		minimizePending = false;
		WindowState = WindowState.Minimized;
	}

	void TickSession()
	{
		if (session == null)
			return;
		session.Tick();
		var r = session.Recorder;
		if (r.Ended)
			return;
		MinimizeOnceStarted(r);
		var room = r.LastRoom.Length > 0 ? r.LastRoom : "starting up";
		var contact = r.Heartbeats == 0 ? "waiting for the game to report in" : $"last report {(int)(DateTime.Now - r.LastContact).TotalSeconds} s ago";
		sessionLabel.Text = $"Playing  ·  {room}  ·  {contact}" + (r.Errors > 0 ? $"  ·  {r.Errors} error(s) recorded" : "");
	}

	async void OnSessionEnded(string status)
	{
		if (closing)
			return;
		session = null;
		minimizePending = false;
		// A multiplayer session belongs to the game that started it.
		server.Net?.Dispose();
		server.Net = null;
		play.Content = "PLAY";
		DetectGame();
		UpdateMusic();
		if (pendingRelease is { } release && Updater.CannotUpdateReason() == null)
			SetUpdateStatus($"Version {release.Version} is available  ·  install", () => _ = InstallUpdate(release));
		if (WindowState == WindowState.Minimized)
			WindowState = WindowState.Normal;
		Activate();
		ShowLastSession();
		if (status is "crashed" or "errors" or "lost-contact")
		{
			ShowView(reports);
			await Dialog.Show(this, $"The last session ended with a problem ({UiTheme.StatusText(status).ToLowerInvariant()}). A report was saved; see the Reports tab.", Dialog.Kind.Warning);
		}
		else if (content.Content == reports)
			reports.Reload();
	}

	void ShowLastSession()
	{
		var all = SessionRecorder.ListAll();
		if (all.Count == 0)
		{
			sessionLabel.Text = "No sessions recorded yet.";
			sessionLabel.Foreground = UiTheme.Brush(UiTheme.Muted);
			return;
		}
		var last = all[0];
		sessionLabel.Text = $"Last session: {UiTheme.StatusText(last.Status)}  ·  {last.Started:MMM d, h:mm tt}"
			+ (last.LastRoom.Length > 0 ? $"  ·  last seen in the {last.LastRoom}" : "");
		sessionLabel.Foreground = UiTheme.Brush(last.Status == "ok" ? UiTheme.Muted : UiTheme.StatusColor(last.Status));
	}

	protected override void OnClosing(WindowClosingEventArgs e)
	{
		closing = true;
		session?.LauncherClosing();
		server.Net?.Dispose();
		ticker.Stop();
		padTimer.Stop();
		music?.Dispose();
		server.Dispose();
		base.OnClosing(e);
	}

	/** Header switch for the menu music. **/
	sealed class MusicToggle : TextBlock
	{
		bool on = true, available = true, hover;
		public event Action? Click;

		public MusicToggle()
		{
			FontSize = UiTheme.Small;
			Cursor = new Cursor(StandardCursorType.Hand);
			PointerEntered += (_, _) => { hover = true; Refresh(); };
			PointerExited += (_, _) => { hover = false; Refresh(); };
			PointerPressed += (_, e) =>
			{
				if (available && e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
					Click?.Invoke();
			};
			Refresh();
		}

		/** `available` is false when this Mac can't play the music (no audio device, or the decoder is missing). **/
		public void Set(bool on, bool available)
		{
			this.on = on;
			this.available = available;
			Refresh();
		}

		void Refresh()
		{
			Text = !available ? "♪  NO AUDIO" : on ? "♪  MUSIC ON" : "♪  MUSIC OFF";
			Foreground = UiTheme.Brush(!available ? UiTheme.Border : on ? (hover ? UiTheme.GoldBright : UiTheme.Gold) : (hover ? UiTheme.Cream : UiTheme.Muted));
		}
	}

	/** A text tab with a gold underline when active. **/
	sealed class TabButton : Border
	{
		public Control View { get; }
		public event Action? Click;
		readonly TextBlock label;
		readonly Border underline = new() { Height = 3, Margin = new Thickness(10, 0), VerticalAlignment = VerticalAlignment.Bottom };
		bool active, hover;

		public TabButton(string text, Control view)
		{
			View = view;
			label = new TextBlock { Text = text, FontSize = UiTheme.Tab, FontWeight = FontWeight.SemiBold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 0, 4) };
			Height = 36;
			Padding = new Thickness(14, 0);
			Cursor = new Cursor(StandardCursorType.Hand);
			var inner = new Panel { Children = { label } };
			Child = new Panel { Children = { inner, underline } };
			PointerEntered += (_, _) => { hover = true; Refresh(); };
			PointerExited += (_, _) => { hover = false; Refresh(); };
			PointerPressed += (_, e) =>
			{
				if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
					Click?.Invoke();
			};
			Refresh();
		}

		public bool Active
		{
			get => active;
			set { active = value; Refresh(); }
		}

		void Refresh()
		{
			label.Foreground = UiTheme.Brush(active ? UiTheme.GoldBright : hover ? UiTheme.Cream : UiTheme.Muted);
			Background = active ? UiTheme.Brush(UiTheme.Burgundy) : hover ? UiTheme.Brush(UiTheme.Card) : Brushes.Transparent;
			underline.Background = active ? UiTheme.Brush(UiTheme.Gold) : Brushes.Transparent;
		}
	}
}
