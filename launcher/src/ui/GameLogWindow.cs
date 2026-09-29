// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows.Forms;

namespace CrownAndCard.Launcher.UI;

/**
	The game log window (§13.12): what the native game window is doing, live.
	The browser build had its developer console; this is the native window's.

	One timeline from three sources: the game's own log (GameLog.hx: traces,
	window and controller changes, hitches, uncaught errors with their stack),
	the events it reports (start, room changes, quit) and the launcher's notes
	(hangs, lost contact, how the session ended). Filter by level and source,
	search, copy lines, or follow along as they arrive.

	It follows the running session, or shows a saved one from Reports. It isn't
	owned by the launcher, so it stays up while the launcher is minimized.
**/
sealed class GameLogWindow : Form
{
	const int MaxEntries = 50000;

	static GameLogWindow? instance;

	readonly ListView list = new()
	{
		View = View.Details,
		VirtualMode = true,
		FullRowSelect = true,
		HideSelection = false,
		MultiSelect = true,
		BorderStyle = BorderStyle.None,
		BackColor = Theme.Card,
		ForeColor = Theme.Cream,
		Font = Theme.Mono,
		HeaderStyle = ColumnHeaderStyle.Nonclickable,
		OwnerDraw = true,
		Dock = DockStyle.Fill,
	};

	readonly Label status = Theme.Label("", Theme.Body, Theme.Cream);
	readonly Label counts = Theme.Label("", Theme.Small, Theme.Muted);
	readonly Choice levels = new(("all", "Everything"), ("warn", "Warnings and errors"), ("error", "Errors only")) { Width = 190 };
	readonly Choice sources = new(("all", "All sources"), ("game", "The game's log"), ("event", "Game events"), ("launcher", "Launcher notes"), ("play", "Plays at the tables")) { Width = 170 };
	readonly TextBox search = new() { Width = 200, BackColor = Theme.Card, ForeColor = Theme.Cream, BorderStyle = BorderStyle.FixedSingle, Font = Theme.Body };
	readonly TickBox follow = new("Follow") { Checked = true };
	readonly Button copy = new() { Text = "Copy", AutoSize = true };
	readonly Button folder = new() { Text = "Open folder", AutoSize = true };
	readonly Timer timer = new() { Interval = 150 };

	readonly List<LogEntry> all = [];
	List<LogEntry> shown = [];
	readonly ConcurrentQueue<LogEntry> incoming = new();
	int statusTicks;

	/** Whether the latest entry (not a stack line) passed the filters; its stack lines follow it. **/
	bool lastHeadShown;

	SessionRecorder? recorder;
	Action? unsubscribe;
	string dir = "";

	GameLogWindow()
	{
		Text = "Game log · Crown & Card";
		AutoScaleDimensions = new SizeF(96f, 96f);
		AutoScaleMode = AutoScaleMode.Dpi;
		ClientSize = new Size(900, 480);
		MinimumSize = new Size(560, 300);
		StartPosition = FormStartPosition.Manual;
		BackColor = Theme.Background;
		ForeColor = Theme.Cream;
		Font = Theme.Body;
		KeyPreview = true;
		try
		{
			Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
		}
		catch
		{
			// Keep the default icon.
		}
		// Bottom right of the screen, out of the way of a centered game window.
		var area = Screen.PrimaryScreen.WorkingArea;
		Location = new Point(Math.Max(area.Left, area.Right - Width - 12), Math.Max(area.Top, area.Bottom - Height - 12));

		foreach (var (name, width) in new[] { ("Time", 96), ("Level", 58), ("Source", 150), ("Message", 500) })
			list.Columns.Add(name, width);
		list.RetrieveVirtualItem += (_, e) => e.Item = ItemFor(e.ItemIndex);
		list.DrawColumnHeader += (_, e) =>
		{
			using (var bg = new SolidBrush(Theme.Panel))
				e.Graphics.FillRectangle(bg, e.Bounds);
			TextRenderer.DrawText(e.Graphics, e.Header?.Text, Theme.Small, Rectangle.Inflate(e.Bounds, -6, 0), Theme.Gold,
				TextFormatFlags.VerticalCenter | TextFormatFlags.Left);
		};
		list.DrawItem += (_, _) => { }; // drawn cell by cell below
		list.DrawSubItem += (_, e) => DrawCell(e);
		list.Resize += (_, _) => FillLastColumn();
		list.KeyDown += (_, e) =>
		{
			if (e.Control && e.KeyCode == Keys.A)
			{
				for (int i = 0; i < shown.Count; i++)
					list.SelectedIndices.Add(i);
				e.Handled = true;
			}
		};
		// Scrolling up to read stops following; End (or the box) turns it back on.
		list.MouseWheel += (_, e) =>
		{
			if (e.Delta > 0)
				follow.Checked = false;
		};
		Theme.DarkScrollbars(list);

		foreach (var b in new[] { copy, folder })
		{
			Theme.StyleButton(b);
			b.Margin = new Padding(8, 3, 0, 3);
			b.Padding = new Padding(6, 0, 6, 0);
		}
		copy.Click += (_, _) => CopyLines();
		folder.Click += (_, _) =>
		{
			if (Directory.Exists(dir))
				Process.Start(new ProcessStartInfo("explorer.exe", $"\"{dir}\"") { UseShellExecute = true });
		};
		levels.SelectedIndexChanged += (_, _) => Refilter();
		sources.SelectedIndexChanged += (_, _) => Refilter();
		search.TextChanged += (_, _) => Refilter();
		follow.CheckedChanged += (_, _) => { if (follow.Checked) ScrollToEnd(); };
		levels.Value = "all";
		sources.Value = "all";
		new ToolTip().SetToolTip(search, "Search the log (Ctrl+F). Esc clears it.");

		var searchLabel = Theme.Label("Search", Theme.Small, Theme.Muted);
		searchLabel.Margin = new Padding(12, 8, 4, 0);
		var bar = new FlowLayoutPanel { AutoSize = true, WrapContents = true, BackColor = Color.Transparent, Dock = DockStyle.Fill, Margin = new Padding(0, 4, 0, 6) };
		foreach (var c in new Control[] { levels, sources })
			c.Margin = new Padding(0, 3, 8, 3);
		search.Margin = new Padding(0, 4, 8, 3);
		follow.Margin = new Padding(4, 3, 0, 3);
		bar.Controls.AddRange([levels, sources, searchLabel, search, follow, copy, folder]);

		status.Margin = new Padding(3, 2, 3, 0);
		counts.Margin = new Padding(3, 2, 3, 2);
		var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4, BackColor = Color.Transparent, Padding = new Padding(12, 8, 12, 10) };
		layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
		layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
		layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
		layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
		layout.Controls.Add(status, 0, 0);
		layout.Controls.Add(counts, 0, 1);
		layout.Controls.Add(bar, 0, 2);
		layout.Controls.Add(list, 0, 3);
		Controls.Add(layout);

		timer.Tick += (_, _) => Pump();
		timer.Start();
	}

	/**
		Shows the running session's log and follows it. Reuses the open window.
		Opened as the game starts, it mustn't take the focus: the game window is
		about to open and should come up in front.
	**/
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
		if (instance == null || instance.IsDisposed)
			return false;
		instance.Reveal(true);
		return true;
	}

	static GameLogWindow Open(bool activate)
	{
		if (instance == null || instance.IsDisposed)
		{
			instance = new GameLogWindow { activateOnShow = activate };
			instance.Show();
		}
		instance.Reveal(activate);
		return instance;
	}

	bool activateOnShow = true;

	protected override bool ShowWithoutActivation => !activateOnShow;

	void Reveal(bool activate)
	{
		if (WindowState == FormWindowState.Minimized)
			WindowState = FormWindowState.Normal;
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
		Text = $"Game log · {Path.GetFileName(sessionDir)} · Crown & Card";
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
			list.VirtualListSize = shown.Count;
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
		shown = next;
		list.SelectedIndices.Clear();
		list.VirtualListSize = shown.Count;
		list.Invalidate();
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
		var q = search.Text.Trim();
		return q.Length == 0 || e.Message.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0 || e.Tag.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0;
	}

	void ScrollToEnd()
	{
		if (shown.Count > 0)
			list.EnsureVisible(shown.Count - 1);
	}

	ListViewItem ItemFor(int index)
	{
		var e = index >= 0 && index < shown.Count ? shown[index] : null;
		if (e == null)
			return new ListViewItem(["", "", "", ""]);
		return e.Continuation
			? new ListViewItem(["", "", "", "    " + e.Message])
			: new ListViewItem([e.Time.ToString("HH:mm:ss.fff"), e.LevelName, e.SourceName + (e.Tag.Length > 0 ? " · " + e.Tag : ""), e.Message]);
	}

	void DrawCell(DrawListViewSubItemEventArgs e)
	{
		if (e.Item == null || e.SubItem == null || e.ItemIndex >= shown.Count)
			return;
		var entry = shown[e.ItemIndex];
		bool selected = list.SelectedIndices.Contains(e.ItemIndex);
		var back = selected ? Theme.CardHover : entry.Level == LogLevel.Error ? Color.FromArgb(46, 22, 30) : Theme.Card;
		using (var bg = new SolidBrush(back))
			e.Graphics.FillRectangle(bg, e.Bounds);
		var color = entry.Level switch
		{
			LogLevel.Error => Theme.Red,
			LogLevel.Warn => Theme.Amber,
			_ => e.ColumnIndex == 0 ? Theme.Muted
				: entry.Source == LogSource.Event ? Theme.Gold
				: entry.Source == LogSource.Launcher ? Theme.Muted
				: Theme.Cream,
		};
		if (entry.Continuation && entry.Level == LogLevel.Info)
			color = Theme.Muted;
		TextRenderer.DrawText(e.Graphics, e.SubItem.Text, list.Font, Rectangle.Inflate(e.Bounds, -4, 0), color,
			TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine);
	}

	void FillLastColumn()
	{
		int used = 0;
		for (int i = 0; i < list.Columns.Count - 1; i++)
			used += list.Columns[i].Width;
		list.Columns[list.Columns.Count - 1].Width = Math.Max(200, list.ClientSize.Width - used);
	}

	/** The selected lines, or every line shown when none are selected, as session.log text. **/
	void CopyLines()
	{
		var indices = list.SelectedIndices.Count > 0
			? list.SelectedIndices.Cast<int>().OrderBy(i => i)
			: Enumerable.Range(0, shown.Count);
		var text = new StringBuilder();
		foreach (var i in indices)
			text.AppendLine(shown[i].ToLine());
		if (text.Length > 0)
			Clipboard.SetText(text.ToString());
	}

	void UpdateCounts()
	{
		int errors = all.Count(e => !e.Continuation && e.Level == LogLevel.Error);
		int warnings = all.Count(e => !e.Continuation && e.Level == LogLevel.Warn);
		var lines = shown.Count == all.Count ? $"{all.Count} lines" : $"{shown.Count} of {all.Count} lines";
		counts.Text = $"{lines}  ·  {Plural(errors, "error")}  ·  {Plural(warnings, "warning")}  ·  {dir}";
		counts.ForeColor = errors > 0 ? Theme.Red : warnings > 0 ? Theme.Amber : Theme.Muted;
	}

	/** Where the session stands: playing (room, frame rate, controller, last report) or how it ended. **/
	void UpdateStatus()
	{
		var r = recorder;
		if (r == null)
		{
			status.Text = "Saved session";
			status.ForeColor = Theme.Cream;
			return;
		}
		if (r.Ended)
		{
			status.Text = "Session ended  ·  " + Theme.StatusText(r.Status);
			status.ForeColor = Theme.StatusColor(r.Status);
			return;
		}
		if (r.Heartbeats == 0)
		{
			status.Text = "● Starting  ·  waiting for the game to report in";
			status.ForeColor = Theme.Gold;
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
		status.ForeColor = ago > 10 ? Theme.Amber : Theme.Green;
	}

	static string Plural(int n, string word) => n == 1 ? $"1 {word}" : $"{n} {word}s";

	[System.Runtime.InteropServices.DllImport("user32.dll")]
	static extern uint GetDpiForWindow(IntPtr hwnd);

	protected override void OnLoad(EventArgs e)
	{
		base.OnLoad(e);
		FitToText();
	}

	/**
		Sizes from measured text rather than design pixels. WinForms can fail to
		scale a form's layout to the DPI its text really renders at (see
		ManorPanel.TitleFont); then 2x text lands in 1x columns and boxes.
		Measuring sidesteps that, and the window itself is corrected by the real
		DPI over the one WinForms scaled for (1 when it scaled properly).
	**/
	void FitToText()
	{
		int Measure(string text, Font font) => TextRenderer.MeasureText(text, font).Width;
		int line = TextRenderer.MeasureText("Ag", Theme.Body).Height;
		int pad = Measure("  ", Theme.Mono);
		list.Columns[0].Width = Measure("00:00:00.000", Theme.Mono) + pad;
		list.Columns[1].Width = Measure("ERROR", Theme.Mono) + pad;
		list.Columns[2].Width = Measure("launcher · window", Theme.Mono) + pad;
		foreach (var choice in new[] { levels, sources })
		{
			choice.ItemHeight = line + 4;
			choice.Width = choice.Items.Cast<object>().Max(o => Measure(o.ToString(), Theme.Body)) + line * 2;
		}
		search.Width = Measure("a search that fits", Theme.Body);
		follow.Size = new Size(follow.Width, Math.Max(follow.Height, line + 8));
		float fix = 1f;
		try
		{
			var real = GetDpiForWindow(Handle);
			if (real > 0 && DeviceDpi > 0)
				fix = Math.Max(1f, real / (float)DeviceDpi);
		}
		catch (EntryPointNotFoundException)
		{
			// Before Windows 10 1607; WinForms' own scaling will have to do.
		}
		if (fix > 1f)
		{
			var area = Screen.FromControl(this).WorkingArea;
			Size = new Size(Math.Min((int)(Width * fix), area.Width * 9 / 10), Math.Min((int)(Height * fix), area.Height * 9 / 10));
			Location = new Point(Math.Max(area.Left, area.Right - Width - 12), Math.Max(area.Top, area.Bottom - Height - 12));
		}
		FillLastColumn();
	}

	protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
	{
		switch (keyData)
		{
			case Keys.Control | Keys.F:
				search.Focus();
				search.SelectAll();
				return true;
			case Keys.Control | Keys.C when !search.Focused:
				CopyLines();
				return true;
			case Keys.Escape when search.Focused && search.Text.Length > 0:
				search.Clear();
				return true;
			case Keys.End when !search.Focused:
				follow.Checked = true;
				ScrollToEnd();
				return true;
		}
		return base.ProcessCmdKey(ref msg, keyData);
	}

	protected override void OnFormClosed(FormClosedEventArgs e)
	{
		timer.Stop();
		unsubscribe?.Invoke();
		unsubscribe = null;
		if (instance == this)
			instance = null;
		base.OnFormClosed(e);
	}
}
