// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Templates;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;

namespace CrownAndCard.Launcher.UI;

/**
	The game log window (§13.12): what the native game window is doing, live.
	One timeline from the game's own log, the events it reports and the
	launcher's notes. Filter by level and source, search, copy lines, or follow
	along as they arrive. It follows the running session, or shows a saved one
	from Reports. (The Windows launcher's GameLogWindow, for Avalonia.)
**/
sealed class GameLogWindow : Window
{
	const int MaxEntries = 50000;

	static GameLogWindow? instance;

	readonly ListBox list = new() { SelectionMode = SelectionMode.Multiple, FontFamily = UiTheme.Mono, FontSize = UiTheme.MonoSize };
	readonly TextBlock status = UiTheme.Label("", UiTheme.Body, UiTheme.Cream);
	readonly TextBlock counts = UiTheme.Label("", UiTheme.Small, UiTheme.Muted);
	readonly Choice levels = new(("all", "Everything"), ("warn", "Warnings and errors"), ("error", "Errors only")) { Width = 190 };
	readonly Choice sources = new(("all", "All sources"), ("game", "The game's log"), ("event", "Game events"), ("launcher", "Launcher notes"), ("play", "Plays at the tables")) { Width = 180 };
	readonly TextBox search = new() { Width = 200, FontSize = UiTheme.Body, Watermark = "Search (⌘F)" };
	readonly TickBox follow = new("Follow") { Checked = true };
	readonly Button copy = UiTheme.Button("Copy", size: UiTheme.Body);
	readonly Button folder = UiTheme.Button("Show in Finder", size: UiTheme.Body);
	readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(150) };

	readonly List<LogEntry> all = [];
	ObservableCollection<LogEntry> shown = [];
	readonly ConcurrentQueue<LogEntry> incoming = new();
	int statusTicks;

	/** Whether the latest entry (not a stack line) passed the filters; its stack lines follow it. **/
	bool lastHeadShown;

	SessionRecorder? recorder;
	Action? unsubscribe;
	string dir = "";

	GameLogWindow()
	{
		Title = "Game log · Crown & Card";
		Width = 920;
		Height = 500;
		MinWidth = 560;
		MinHeight = 300;
		Background = UiTheme.Brush(UiTheme.Background);
		try { Icon = new WindowIcon(Artwork.Open("CrownAndCard.Emblem.png")); } catch { /* keep the default */ }

		list.ItemTemplate = new FuncDataTemplate<LogEntry>((e, _) => Row(e), true);
		// Scrolling up to read stops following; End (or the box) turns it back on.
		list.AddHandler(PointerWheelChangedEvent, (_, e) => { if (e.Delta.Y > 0) follow.Checked = false; }, RoutingStrategies.Tunnel);

		copy.Click += (_, _) => CopyLines();
		folder.Click += (_, _) => MacPlatform.OpenFolder(dir);
		levels.SelectionChanged += (_, _) => Refilter();
		sources.SelectionChanged += (_, _) => Refilter();
		search.TextChanged += (_, _) => Refilter();
		follow.CheckedChanged += (_, _) => { if (follow.Checked) ScrollToEnd(); };

		var bar = new WrapPanel { Margin = new Thickness(0, 6, 0, 8) };
		foreach (var c in new Control[] { levels, sources, search, follow, copy, folder })
		{
			c.Margin = new Thickness(0, 3, 8, 3);
			c.VerticalAlignment = VerticalAlignment.Center;
			bar.Children.Add(c);
		}
		follow.Margin = new Thickness(4, 3, 8, 3);

		var header = new Grid { ColumnDefinitions = ColumnDefs(), Background = UiTheme.Brush(UiTheme.Panel), Height = 24 };
		foreach (var (name, i) in new[] { ("Time", 0), ("Level", 1), ("Source", 2), ("Message", 3) })
		{
			var h = UiTheme.Label(name, UiTheme.Small, UiTheme.Gold);
			h.VerticalAlignment = VerticalAlignment.Center;
			h.Margin = new Thickness(4, 0);
			Grid.SetColumn(h, i);
			header.Children.Add(h);
		}
		var table = new DockPanel { Background = UiTheme.Brush(UiTheme.Card) };
		DockPanel.SetDock(header, Dock.Top);
		table.Children.Add(header);
		table.Children.Add(list);

		counts.Margin = new Thickness(0, 2, 0, 0);
		counts.TextWrapping = TextWrapping.NoWrap;
		counts.TextTrimming = TextTrimming.CharacterEllipsis;
		var layout = new DockPanel { Margin = new Thickness(12, 8, 12, 10) };
		foreach (var c in new Control[] { status, counts, bar })
		{
			DockPanel.SetDock(c, Dock.Top);
			layout.Children.Add(c);
		}
		layout.Children.Add(table);
		Content = layout;

		AddHandler(KeyDownEvent, OnKeys, RoutingStrategies.Tunnel);
		timer.Tick += (_, _) => Pump();
		timer.Start();
		Closed += (_, _) =>
		{
			timer.Stop();
			unsubscribe?.Invoke();
			unsubscribe = null;
			if (instance == this)
				instance = null;
		};
	}

	static ColumnDefinitions ColumnDefs() => new("100,56,160,*");

	/** Shows the running session's log and follows it. Reuses the open window. **/
	public static void ShowLive(SessionRecorder recorder, bool activate = true)
	{
		var w = Open(activate);
		w.Attach(recorder.Dir, recorder);
	}

	/** Shows a saved session's log (from Reports). Reuses the open window. **/
	public static void ShowSaved(string dir)
	{
		var w = Open(true);
		w.Attach(dir, null);
	}

	/** Brings the window up again if it's open, without changing what it shows. **/
	public static bool Raise()
	{
		if (instance == null)
			return false;
		instance.Reveal(true);
		return true;
	}

	static GameLogWindow Open(bool activate)
	{
		if (instance == null)
		{
			instance = new GameLogWindow { ShowActivated = activate };
			// Bottom right of the screen, out of the way of a centered game window.
			if (instance.Screens.Primary is { } screen)
			{
				var area = screen.WorkingArea;
				double scale = screen.Scaling;
				instance.WindowStartupLocation = WindowStartupLocation.Manual;
				instance.Position = new PixelPoint(
					Math.Max(area.X, area.Right - (int)(instance.Width * scale) - 12),
					Math.Max(area.Y, area.Bottom - (int)(instance.Height * scale) - 12));
			}
			instance.Show();
		}
		instance.Reveal(activate);
		return instance;
	}

	void Reveal(bool activate)
	{
		if (WindowState == WindowState.Minimized)
			WindowState = WindowState.Normal;
		if (activate)
			Activate();
	}

	void Attach(string sessionDir, SessionRecorder? live)
	{
		unsubscribe?.Invoke();
		unsubscribe = null;
		while (incoming.TryDequeue(out _)) { }
		recorder = live;
		dir = sessionDir;
		all.Clear();
		if (live != null)
		{
			var (past, stop) = live.Follow(entry => incoming.Enqueue(entry));
			unsubscribe = stop;
			all.AddRange(past);
		}
		else
			all.AddRange(GameLogParser.Load(sessionDir));
		Title = $"Game log · {Path.GetFileName(sessionDir)} · Crown & Card";
		follow.Checked = true;
		Refilter();
		UpdateStatus();
	}

	/** Moves newly recorded lines in, a batch at a time, and keeps the status line current. **/
	void Pump()
	{
		bool added = false;
		while (incoming.TryDequeue(out var entry))
		{
			all.Add(entry);
			if (!entry.Continuation)
				lastHeadShown = Passes(entry);
			if (lastHeadShown)
				shown.Add(entry);
			added = true;
		}
		if (all.Count > MaxEntries)
		{
			all.RemoveRange(0, MaxEntries / 10);
			Refilter();
		}
		else if (added)
		{
			if (follow.Checked)
				ScrollToEnd();
			UpdateCounts();
		}
		if (++statusTicks % 4 == 0)
			UpdateStatus();
	}

	void Refilter()
	{
		// A stack's lines show with the entry they belong to.
		var next = new List<LogEntry>(all.Count);
		lastHeadShown = false;
		foreach (var e in all)
		{
			if (!e.Continuation)
				lastHeadShown = Passes(e);
			if (lastHeadShown)
				next.Add(e);
		}
		shown = new ObservableCollection<LogEntry>(next);
		list.ItemsSource = shown;
		if (follow.Checked)
			ScrollToEnd();
		UpdateCounts();
	}

	/** Whether an entry passes the level, source and search filters. **/
	bool Passes(LogEntry e)
	{
		var level = levels.Value;
		if (level == "warn" && e.Level == LogLevel.Info || level == "error" && e.Level != LogLevel.Error)
			return false;
		var source = sources.Value;
		// "Plays" are the game's own log lines tagged play (games/PlayLog.hx): every move at the tables.
		if (source == "play" ? !(e.Source == LogSource.Game && e.Tag == "play") : source != "all" && source != e.SourceName)
			return false;
		var q = (search.Text ?? "").Trim();
		return q.Length == 0 || e.Message.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0 || e.Tag.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0;
	}

	void ScrollToEnd()
	{
		if (shown.Count > 0)
			Dispatcher.UIThread.Post(() => { if (shown.Count > 0) list.ScrollIntoView(shown.Count - 1); }, DispatcherPriority.Background);
	}

	static Control Row(LogEntry entry)
	{
		var grid = new Grid { ColumnDefinitions = ColumnDefs(), Height = 20 };
		if (entry.Level == LogLevel.Error)
			grid.Background = UiTheme.Brush(UiTheme.ErrorRow);
		var cells = entry.Continuation
			? new[] { "", "", "", "    " + entry.Message }
			: new[] { entry.Time.ToString("HH:mm:ss.fff"), entry.LevelName, entry.SourceName + (entry.Tag.Length > 0 ? " · " + entry.Tag : ""), entry.Message };
		for (int i = 0; i < cells.Length; i++)
		{
			var color = entry.Level switch
			{
				LogLevel.Error => UiTheme.Red,
				LogLevel.Warn => UiTheme.Amber,
				_ => i == 0 ? UiTheme.Muted
					: entry.Source == LogSource.Event ? UiTheme.Gold
					: entry.Source == LogSource.Launcher ? UiTheme.Muted
					: UiTheme.Cream,
			};
			if (entry.Continuation && entry.Level == LogLevel.Info)
				color = UiTheme.Muted;
			var cell = new TextBlock
			{
				Text = cells[i],
				Foreground = UiTheme.Brush(color),
				FontFamily = UiTheme.Mono,
				FontSize = UiTheme.MonoSize,
				TextWrapping = TextWrapping.NoWrap,
				TextTrimming = TextTrimming.CharacterEllipsis,
				VerticalAlignment = VerticalAlignment.Center,
				Margin = new Thickness(4, 0),
			};
			if (i == 3)
				ToolTip.SetTip(cell, entry.Message.Length > 100 ? entry.Message : null);
			Grid.SetColumn(cell, i);
			grid.Children.Add(cell);
		}
		return grid;
	}

	/** The selected lines, or every line shown when none are selected, as session.log text. **/
	async void CopyLines()
	{
		var selected = list.SelectedItems?.OfType<LogEntry>().ToHashSet() ?? [];
		var lines = selected.Count > 0 ? shown.Where(selected.Contains) : shown;
		var text = new StringBuilder();
		foreach (var e in lines)
			text.AppendLine(e.ToLine());
		if (text.Length > 0 && Clipboard is { } clipboard)
			await clipboard.SetTextAsync(text.ToString());
	}

	void UpdateCounts()
	{
		int errors = all.Count(e => !e.Continuation && e.Level == LogLevel.Error);
		int warnings = all.Count(e => !e.Continuation && e.Level == LogLevel.Warn);
		var lines = shown.Count == all.Count ? $"{all.Count} lines" : $"{shown.Count} of {all.Count} lines";
		counts.Text = $"{lines}  ·  {Plural(errors, "error")}  ·  {Plural(warnings, "warning")}  ·  {dir}";
		counts.Foreground = UiTheme.Brush(errors > 0 ? UiTheme.Red : warnings > 0 ? UiTheme.Amber : UiTheme.Muted);
	}

	/** Where the session stands: playing (room, frame rate, controller, last report) or how it ended. **/
	void UpdateStatus()
	{
		var r = recorder;
		if (r == null)
		{
			status.Text = "Saved session";
			status.Foreground = UiTheme.Brush(UiTheme.Cream);
			return;
		}
		if (r.Ended)
		{
			status.Text = "Session ended  ·  " + UiTheme.StatusText(r.Status);
			status.Foreground = UiTheme.Brush(UiTheme.StatusColor(r.Status));
			return;
		}
		if (r.Heartbeats == 0)
		{
			status.Text = "● Starting  ·  waiting for the game to report in";
			status.Foreground = UiTheme.Brush(UiTheme.Gold);
			return;
		}
		var s = r.LastState;
		var parts = new List<string> { "● Playing" };
		var room = Json.Str(s, "room");
		if (!string.IsNullOrEmpty(room))
			parts.Add(room!);
		var fps = Json.Int(s, -1, "fps");
		if (fps >= 0)
			parts.Add($"{fps} fps");
		var controller = Json.Str(s, "controller");
		if (!string.IsNullOrEmpty(controller))
			parts.Add("controller: " + controller);
		var ago = (int)(DateTime.Now - r.LastContact).TotalSeconds;
		parts.Add(ago <= 1 ? "reporting" : $"last report {ago} s ago");
		status.Text = string.Join("  ·  ", parts);
		status.Foreground = UiTheme.Brush(ago > 10 ? UiTheme.Amber : UiTheme.Green);
	}

	static string Plural(int n, string word) => n == 1 ? $"1 {word}" : $"{n} {word}s";

	void OnKeys(object? sender, KeyEventArgs e)
	{
		bool command = e.KeyModifiers.HasFlag(KeyModifiers.Meta);
		switch (e.Key)
		{
			case Key.F when command:
				search.Focus();
				search.SelectAll();
				e.Handled = true;
				break;
			case Key.C when command && !search.IsFocused:
				CopyLines();
				e.Handled = true;
				break;
			case Key.A when command && !search.IsFocused:
				list.SelectAll();
				e.Handled = true;
				break;
			case Key.Escape when search.IsFocused && (search.Text ?? "").Length > 0:
				search.Text = "";
				e.Handled = true;
				break;
			case Key.End when !search.IsFocused:
				follow.Checked = true;
				ScrollToEnd();
				e.Handled = true;
				break;
		}
	}
}
