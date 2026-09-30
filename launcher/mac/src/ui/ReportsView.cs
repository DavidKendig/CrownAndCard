// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Generic;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Templates;
using Avalonia.Layout;
using Avalonia.Media;

namespace CrownAndCard.Launcher.UI;

/** Past play sessions with their error-tracking records, newest first. **/
sealed class ReportsView : UserControl
{
	static readonly (string Name, double Width)[] Columns = [("Started", 150), ("Length", 80), ("Result", 130), ("Last room", 170), ("Errors", 60), ("Build", 120)];

	readonly ListBox list = new() { SelectionMode = SelectionMode.Single };

	readonly TextBox details = new()
	{
		IsReadOnly = true,
		AcceptsReturn = true,
		TextWrapping = TextWrapping.NoWrap,
		FontFamily = UiTheme.Mono,
		FontSize = UiTheme.MonoSize,
		Background = UiTheme.Brush(UiTheme.Panel),
		BorderThickness = new Thickness(0),
		VerticalContentAlignment = VerticalAlignment.Top,
	};

	readonly Button openLog = UiTheme.Button("Open log", size: UiTheme.Body);
	readonly Button openFolder = UiTheme.Button("Show in Finder", size: UiTheme.Body);
	readonly Button copy = UiTheme.Button("Copy report", size: UiTheme.Body);
	readonly Button openAll = UiTheme.Button("Open reports folder", size: UiTheme.Body);
	readonly Button deleteAll = UiTheme.Button("Delete all reports…", size: UiTheme.Body);

	public ReportsView()
	{
		list.ItemTemplate = new FuncDataTemplate<SessionSummary>((s, _) => Row(s), true);
		list.SelectionChanged += (_, _) => ShowSelected();
		list.DoubleTapped += (_, _) => { if (SelectedDir != null) GameLogWindow.ShowSaved(SelectedDir); };
		ScrollViewer.SetHorizontalScrollBarVisibility(details, Avalonia.Controls.Primitives.ScrollBarVisibility.Auto);

		openLog.Click += (_, _) =>
		{
			if (SelectedDir != null)
				GameLogWindow.ShowSaved(SelectedDir);
		};
		openFolder.Click += (_, _) => MacPlatform.OpenFolder(SelectedDir);
		openAll.Click += (_, _) => MacPlatform.OpenFolder(Paths.SessionsDir);
		copy.Click += async (_, _) =>
		{
			if (SelectedDir != null && TopLevel.GetTopLevel(this)?.Clipboard is { } clipboard)
				await clipboard.SetTextAsync(SessionRecorder.BuildReport(SelectedDir));
		};
		deleteAll.Click += async (_, _) =>
		{
			if (await Dialog.Confirm(TopLevel.GetTopLevel(this) as Window, "Delete every saved session report?", "Delete"))
			{
				SessionRecorder.DeleteAll();
				Reload();
			}
		};

		var heading = UiTheme.Label("Session reports", UiTheme.Heading, UiTheme.Gold, UiTheme.Serif, FontWeight.Bold);
		var intro = UiTheme.Label("Each time you play, the launcher records the game's state every few seconds, any errors, and how the session ended. "
			+ "Reports stay on this computer; nothing is uploaded.", UiTheme.Small, UiTheme.Muted);
		intro.MaxWidth = 900;
		intro.HorizontalAlignment = HorizontalAlignment.Left;
		intro.Margin = new Thickness(0, 4, 0, 10);
		var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(0, 10, 0, 10), Children = { openLog, openFolder, copy, openAll, deleteAll } };

		var header = new Grid { Background = UiTheme.Brush(UiTheme.Panel), Height = 26 };
		header.ColumnDefinitions = ColumnDefs();
		for (int i = 0; i < Columns.Length; i++)
		{
			var h = UiTheme.Label(Columns[i].Name, UiTheme.Small, UiTheme.Gold);
			h.VerticalAlignment = VerticalAlignment.Center;
			h.Margin = new Thickness(6, 0);
			Grid.SetColumn(h, i);
			header.Children.Add(h);
		}
		var table = new DockPanel { Background = UiTheme.Brush(UiTheme.Card) };
		DockPanel.SetDock(header, Dock.Top);
		table.Children.Add(header);
		table.Children.Add(list);

		var layout = new Grid { RowDefinitions = new RowDefinitions("Auto,Auto,42*,Auto,58*") };
		foreach (var (c, row) in new (Control, int)[] { (heading, 0), (intro, 1), (table, 2), (buttons, 3), (details, 4) })
		{
			Grid.SetRow(c, row);
			layout.Children.Add(c);
		}
		Content = layout;
		UpdateButtons();
	}

	static ColumnDefinitions ColumnDefs()
	{
		var defs = new ColumnDefinitions();
		for (int i = 0; i < Columns.Length; i++)
			defs.Add(new ColumnDefinition(i == Columns.Length - 1 ? new GridLength(1, GridUnitType.Star) : new GridLength(Columns[i].Width)));
		return defs;
	}

	static Control Row(SessionSummary s)
	{
		var grid = new Grid { ColumnDefinitions = ColumnDefs(), Height = 26 };
		var cells = new[]
		{
			s.Started == default ? "?" : s.Started.ToString("MMM d  h:mm tt"),
			s.Length is TimeSpan t ? FormatLength(t) : "",
			UiTheme.StatusText(s.Status),
			s.LastRoom,
			s.Errors > 0 ? s.Errors.ToString() : "",
			s.Build,
		};
		for (int i = 0; i < cells.Length; i++)
		{
			var cell = UiTheme.Label(cells[i], UiTheme.Body, i == 2 ? UiTheme.StatusColor(s.Status) : UiTheme.Cream);
			cell.TextWrapping = TextWrapping.NoWrap;
			cell.TextTrimming = TextTrimming.CharacterEllipsis;
			cell.VerticalAlignment = VerticalAlignment.Center;
			cell.Margin = new Thickness(6, 0);
			Grid.SetColumn(cell, i);
			grid.Children.Add(cell);
		}
		return grid;
	}

	string? SelectedDir => (list.SelectedItem as SessionSummary)?.Dir;

	/** Reloads the list and selects the newest session. **/
	public void Reload()
	{
		List<SessionSummary> all = SessionRecorder.ListAll();
		list.ItemsSource = all;
		if (all.Count > 0)
			list.SelectedIndex = 0;
		else
			details.Text = "No sessions yet. Press Play and a report will appear here.";
		UpdateButtons();
	}

	void ShowSelected()
	{
		var dir = SelectedDir;
		details.Text = dir == null ? "" : SessionRecorder.BuildReport(dir);
		UpdateButtons();
	}

	void UpdateButtons()
	{
		openLog.IsEnabled = openFolder.IsEnabled = copy.IsEnabled = SelectedDir != null;
		deleteAll.IsEnabled = list.ItemCount > 0;
	}

	static string FormatLength(TimeSpan t) => t.TotalHours >= 1 ? $"{(int)t.TotalHours} h {t.Minutes} min" : t.TotalMinutes >= 1 ? $"{(int)t.TotalMinutes} min" : $"{t.Seconds} s";
}
