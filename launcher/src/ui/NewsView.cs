// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;

namespace CrownAndCard.Launcher.UI;

/** Posts from davidkendig.info as cards. Clicking one opens it in the browser. **/
sealed class NewsView : UserControl
{
	readonly FlowLayoutPanel list;
	readonly Label status;
	readonly LinkLabel refresh;
	string category = "all";
	int requestId;

	public NewsView()
	{
		BackColor = Theme.Background;
		var top = new Panel { Dock = DockStyle.Top, Height = 46, BackColor = Theme.Background };
		var title = Theme.Label("News from davidkendig.info", Theme.Heading, Theme.Gold);
		title.Location = new Point(0, 6);
		status = Theme.Label("", Theme.Small, Theme.Muted);
		refresh = new LinkLabel
		{
			Text = "Refresh",
			AutoSize = true,
			Font = Theme.Body,
			LinkColor = Theme.Gold,
			ActiveLinkColor = Theme.GoldBright,
			LinkBehavior = LinkBehavior.HoverUnderline,
			BackColor = Color.Transparent,
		};
		refresh.LinkClicked += (_, _) => LoadNews(category);
		top.Controls.AddRange([title, status, refresh]);
		top.Resize += (_, _) =>
		{
			refresh.Location = new Point(top.Width - refresh.Width, 12);
			status.Location = new Point(refresh.Left - status.Width - 14, 14);
		};
		status.SizeChanged += (_, _) => status.Left = refresh.Left - status.Width - 14;

		list = new FlowLayoutPanel
		{
			Dock = DockStyle.Fill,
			AutoScroll = true,
			FlowDirection = FlowDirection.TopDown,
			WrapContents = false,
			BackColor = Theme.Background,
			Padding = new Padding(0, 4, 0, 4),
		};
		list.Resize += (_, _) => ResizeCards();
		Theme.DarkScrollbars(list);
		Controls.Add(list);
		Controls.Add(top);
	}

	public async void LoadNews(string newCategory)
	{
		category = newCategory;
		var id = ++requestId;
		status.Text = "Loading…";
		ShowMessage("Loading news…");
		var result = await NewsService.FetchAsync(category);
		if (id != requestId || IsDisposed)
			return;
		ShowResult(result);
	}

	void ShowResult(NewsResult r)
	{
		list.SuspendLayout();
		ClearList();
		if (r.Items.Count == 0)
			ShowMessage(r.Error != null ? $"Couldn't reach davidkendig.info.\n{r.Error}" : "No posts in this category yet.");
		foreach (var item in r.Items)
			list.Controls.Add(MakeCard(item));
		status.Text = r.FromCache
			? $"Offline · showing news saved {r.FetchedAt:MMM d, h:mm tt}"
			: $"Updated {r.FetchedAt:h:mm tt}";
		ResizeCards();
		list.ResumeLayout();
	}

	void ShowMessage(string text)
	{
		ClearList();
		var message = Theme.Label(text, Theme.Body, Theme.Muted);
		message.Margin = new Padding(3, 12, 3, 3);
		list.Controls.Add(message);
		ResizeCards();
	}

	void ClearList()
	{
		while (list.Controls.Count > 0)
		{
			var c = list.Controls[0];
			list.Controls.RemoveAt(0);
			c.Dispose();
		}
	}

	Control MakeCard(NewsItem item)
	{
		var card = new FlowLayoutPanel
		{
			FlowDirection = FlowDirection.TopDown,
			WrapContents = false,
			AutoSize = true,
			AutoSizeMode = AutoSizeMode.GrowAndShrink,
			BackColor = Theme.Card,
			Padding = new Padding(16, 12, 16, 12),
			Margin = new Padding(0, 0, 0, 10),
		};
		var title = Theme.Label(item.Title, Theme.CardTitle, Theme.Gold);
		title.Cursor = Cursors.Hand;
		title.Click += (_, _) => Open(item.Link);
		var date = Theme.Label(item.Date == default ? "" : item.Date.ToString("MMMM d, yyyy"), Theme.Small, Theme.Muted);
		var excerpt = Theme.Label(item.Excerpt, Theme.Body, Theme.Cream);
		excerpt.Margin = new Padding(3, 8, 3, 4);
		var more = new LinkLabel
		{
			Text = "Read on davidkendig.info  →",
			AutoSize = true,
			Font = Theme.Small,
			LinkColor = Theme.Gold,
			ActiveLinkColor = Theme.GoldBright,
			LinkBehavior = LinkBehavior.HoverUnderline,
			BackColor = Color.Transparent,
		};
		more.LinkClicked += (_, _) => Open(item.Link);
		card.Controls.AddRange([title, date, excerpt, more]);
		return card;
	}

	void ResizeCards()
	{
		var width = list.ClientSize.Width - list.Padding.Horizontal - SystemInformation.VerticalScrollBarWidth - 4;
		if (width < 200)
			return;
		foreach (Control c in list.Controls)
		{
			if (c is FlowLayoutPanel card)
			{
				card.MinimumSize = new Size(width, 0);
				card.MaximumSize = new Size(width, 0);
				foreach (Control child in card.Controls)
					child.MaximumSize = new Size(width - card.Padding.Horizontal - 6, 0);
			}
			else
				c.MaximumSize = new Size(width, 0);
		}
	}

	static void Open(string link)
	{
		if (!NewsService.IsSiteLink(link))
			return;
		try
		{
			Process.Start(new ProcessStartInfo(link) { UseShellExecute = true });
		}
		catch (Exception e)
		{
			Log.Write("Couldn't open link: " + e.Message);
		}
	}
}
