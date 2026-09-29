// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace CrownAndCard.Launcher.UI;

/** Past play sessions with their error-tracking records, newest first. **/
sealed class ReportsView : UserControl
{
	readonly ListView list = new()
	{
		View = View.Details,
		FullRowSelect = true,
		HideSelection = false,
		MultiSelect = false,
		BorderStyle = BorderStyle.None,
		BackColor = Theme.Card,
		ForeColor = Theme.Cream,
		Font = Theme.Body,
		HeaderStyle = ColumnHeaderStyle.Nonclickable,
		OwnerDraw = true,
		Dock = DockStyle.Fill,
	};

	readonly TextBox details = new()
	{
		Multiline = true,
		ReadOnly = true,
		ScrollBars = ScrollBars.Both,
		WordWrap = false,
		BorderStyle = BorderStyle.None,
		BackColor = Theme.Panel,
		ForeColor = Theme.Cream,
		Font = Theme.Mono,
		Dock = DockStyle.Fill,
	};

	readonly Button openLog = new() { Text = "Open log", AutoSize = true };
	readonly Button openFolder = new() { Text = "Open session folder", AutoSize = true };
	readonly Button copy = new() { Text = "Copy report", AutoSize = true };
	readonly Button openAll = new() { Text = "Open reports folder", AutoSize = true };
	readonly Button deleteAll = new() { Text = "Delete all reports…", AutoSize = true };

	public ReportsView()
	{
		BackColor = Theme.Background;
		foreach (var (name, width) in new[] { ("Started", 150), ("Length", 80), ("Result", 130), ("Last room", 150), ("Errors", 60), ("Build", 110) })
			list.Columns.Add(name, width);
		list.DrawColumnHeader += (_, e) =>
		{
			using (var bg = new SolidBrush(Theme.Panel))
				e.Graphics.FillRectangle(bg, e.Bounds);
			TextRenderer.DrawText(e.Graphics, e.Header?.Text, Theme.Small, Rectangle.Inflate(e.Bounds, -6, 0), Theme.Gold,
				TextFormatFlags.VerticalCenter | TextFormatFlags.Left);
		};
		list.DrawItem += (_, _) => { }; // rows are drawn cell by cell below
		list.DrawSubItem += (_, e) =>
		{
			if (e.Item == null || e.SubItem == null)
				return;
			bool selected = e.Item.Selected;
			using (var bg = new SolidBrush(selected ? Theme.CardHover : Theme.Card))
				e.Graphics.FillRectangle(bg, e.Bounds);
			var color = e.ColumnIndex == 2 ? e.SubItem.ForeColor : selected ? Theme.GoldBright : Theme.Cream;
			TextRenderer.DrawText(e.Graphics, e.SubItem.Text, list.Font, Rectangle.Inflate(e.Bounds, -6, 0), color,
				TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
		};
		// Stretch the last column so the header has no unpainted strip on the right.
		list.Resize += (_, _) => FillLastColumn();
		list.SelectedIndexChanged += (_, _) => ShowSelected();
		Theme.DarkScrollbars(list);
		Theme.DarkScrollbars(details);

		foreach (var b in new[] { openLog, openFolder, copy, openAll, deleteAll })
		{
			Theme.StyleButton(b);
			b.Margin = new Padding(0, 0, 8, 0);
			b.Padding = new Padding(6, 1, 6, 1);
		}
		openLog.Click += (_, _) =>
		{
			if (SelectedDir != null)
				GameLogWindow.ShowSaved(SelectedDir);
		};
		openFolder.Click += (_, _) => OpenFolder(SelectedDir);
		openAll.Click += (_, _) => OpenFolder(Paths.SessionsDir);
		copy.Click += (_, _) =>
		{
			if (SelectedDir != null)
				Clipboard.SetText(SessionRecorder.BuildReport(SelectedDir));
		};
		deleteAll.Click += (_, _) =>
		{
			if (MessageBox.Show(this, "Delete every saved session report?", "Crown & Card", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes)
			{
				SessionRecorder.DeleteAll();
				Reload();
			}
		};

		var heading = Theme.Label("Session reports", Theme.Heading, Theme.Gold);
		var intro = Theme.Label("Each time you play, the launcher records the game's state every few seconds, any errors, and how the session ended. "
			+ "Reports stay on this computer; nothing is uploaded.", Theme.Small, Theme.Muted);
		intro.MaximumSize = new Size(900, 0);
		intro.Margin = new Padding(3, 4, 3, 10);
		var buttons = new FlowLayoutPanel { AutoSize = true, WrapContents = false, BackColor = Color.Transparent, Margin = new Padding(0, 10, 0, 10) };
		buttons.Controls.AddRange([openLog, openFolder, copy, openAll, deleteAll]);

		var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 5, BackColor = Color.Transparent };
		layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
		layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
		layout.RowStyles.Add(new RowStyle(SizeType.Percent, 42));
		layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
		layout.RowStyles.Add(new RowStyle(SizeType.Percent, 58));
		layout.Controls.Add(heading, 0, 0);
		layout.Controls.Add(intro, 0, 1);
		layout.Controls.Add(list, 0, 2);
		layout.Controls.Add(buttons, 0, 3);
		layout.Controls.Add(details, 0, 4);
		Controls.Add(layout);
		UpdateButtons();
	}

	string? SelectedDir => list.SelectedItems.Count > 0 ? list.SelectedItems[0].Tag as string : null;

	/** Reloads the list and selects the newest session. **/
	public void Reload()
	{
		list.BeginUpdate();
		list.Items.Clear();
		foreach (var s in SessionRecorder.ListAll())
		{
			var item = new ListViewItem(
			[
				s.Started == default ? "?" : s.Started.ToString("MMM d  h:mm tt"),
				s.Length is TimeSpan t ? FormatLength(t) : "",
				Theme.StatusText(s.Status),
				s.LastRoom,
				s.Errors > 0 ? s.Errors.ToString() : "",
				s.Build,
			])
			{
				Tag = s.Dir,
				UseItemStyleForSubItems = false,
			};
			foreach (ListViewItem.ListViewSubItem sub in item.SubItems)
			{
				sub.BackColor = Theme.Card;
				sub.ForeColor = Theme.Cream;
			}
			item.SubItems[2].ForeColor = Theme.StatusColor(s.Status);
			list.Items.Add(item);
		}
		list.EndUpdate();
		FillLastColumn();
		if (list.Items.Count > 0)
			list.Items[0].Selected = true;
		else
			details.Text = "No sessions yet. Press Play and a report will appear here.";
		UpdateButtons();
	}

	void FillLastColumn()
	{
		if (list.Columns.Count == 0)
			return;
		int used = 0;
		for (int i = 0; i < list.Columns.Count - 1; i++)
			used += list.Columns[i].Width;
		list.Columns[list.Columns.Count - 1].Width = Math.Max(80, list.ClientSize.Width - used);
	}

	void ShowSelected()
	{
		list.Invalidate(); // redraw the selection highlight
		var dir = SelectedDir;
		details.Text = dir == null ? "" : SessionRecorder.BuildReport(dir).Replace("\n", Environment.NewLine);
		UpdateButtons();
	}

	void UpdateButtons()
	{
		openLog.Enabled = openFolder.Enabled = copy.Enabled = SelectedDir != null;
		deleteAll.Enabled = list.Items.Count > 0;
	}

	static string FormatLength(TimeSpan t) => t.TotalHours >= 1 ? $"{(int)t.TotalHours} h {t.Minutes} min" : t.TotalMinutes >= 1 ? $"{(int)t.TotalMinutes} min" : $"{t.Seconds} s";

	static void OpenFolder(string? dir)
	{
		if (dir == null || !Directory.Exists(dir))
			return;
		Process.Start(new ProcessStartInfo("explorer.exe", $"\"{dir}\"") { UseShellExecute = true });
	}
}
