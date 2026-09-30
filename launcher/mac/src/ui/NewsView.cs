// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;

namespace CrownAndCard.Launcher.UI;

/** Posts from davidkendig.info as cards. Clicking one opens it in the browser. **/
sealed class NewsView : UserControl
{
	readonly StackPanel list = new() { Spacing = 10, Margin = new Thickness(0, 4, 14, 4) };
	readonly TextBlock status = UiTheme.Label("", UiTheme.Small, UiTheme.Muted);
	string category = "all";
	int requestId;

	public NewsView()
	{
		var title = UiTheme.Label("THE MANOR GAZETTE", UiTheme.Heading, UiTheme.Gold, UiTheme.Serif, FontWeight.Bold);
		var refresh = new LinkText("Refresh");
		refresh.Click += () => LoadNews(category);
		var top = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto"), RowDefinitions = new RowDefinitions("Auto,Auto"), Margin = new Thickness(0, 0, 14, 12) };
		top.Children.Add(title);
		Grid.SetColumn(refresh, 1);
		refresh.VerticalAlignment = VerticalAlignment.Center;
		top.Children.Add(refresh);
		Grid.SetRow(status, 1);
		status.Margin = new Thickness(0, 6, 0, 0);
		top.Children.Add(status);

		var scroll = new ScrollViewer { Content = list, HorizontalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Disabled };
		var dock = new DockPanel();
		DockPanel.SetDock(top, Dock.Top);
		dock.Children.Add(top);
		dock.Children.Add(scroll);
		Content = dock;
	}

	public async void LoadNews(string newCategory)
	{
		category = newCategory;
		var id = ++requestId;
		status.Text = "Loading…";
		ShowMessage("Loading news…");
		var result = await NewsService.FetchAsync(category);
		if (id != requestId)
			return;
		ShowResult(result);
	}

	void ShowResult(NewsResult r)
	{
		list.Children.Clear();
		if (r.Items.Count == 0)
			ShowMessage(r.Error != null ? $"Couldn't reach davidkendig.info.\n{r.Error}" : "No posts in this category yet.");
		foreach (var item in r.Items)
			list.Children.Add(MakeCard(item));
		status.Text = r.FromCache
			? $"Offline · showing news saved {r.FetchedAt:MMM d, h:mm tt}"
			: $"Updated {r.FetchedAt:h:mm tt}";
	}

	void ShowMessage(string text)
	{
		list.Children.Clear();
		var message = UiTheme.Label(text, UiTheme.Body, UiTheme.Muted);
		message.Margin = new Thickness(3, 12, 3, 3);
		list.Children.Add(message);
	}

	Control MakeCard(NewsItem item)
	{
		var title = UiTheme.Label(item.Title, UiTheme.CardTitle, UiTheme.Gold, UiTheme.Serif, FontWeight.Bold);
		title.Cursor = new Cursor(StandardCursorType.Hand);
		title.PointerPressed += (_, _) => Open(item.Link);
		var date = UiTheme.Label(item.Date == default ? "" : item.Date.ToString("MMMM d, yyyy"), UiTheme.Small, UiTheme.Muted);
		date.Margin = new Thickness(0, 2, 0, 0);
		var excerpt = UiTheme.Label(item.Excerpt, UiTheme.Body, UiTheme.Cream);
		excerpt.Margin = new Thickness(0, 8, 0, 4);
		var more = new LinkText("Read on davidkendig.info  →", UiTheme.Small);
		more.Click += () => Open(item.Link);
		// A gold accent down the left edge, inside a thin border.
		return new Border
		{
			Background = UiTheme.Brush(UiTheme.Card),
			BorderBrush = UiTheme.Brush(UiTheme.Border),
			BorderThickness = new Thickness(1),
			Child = new Border
			{
				BorderBrush = UiTheme.Brush(UiTheme.GoldDark),
				BorderThickness = new Thickness(3, 0, 0, 0),
				Padding = new Thickness(16, 12, 16, 12),
				Child = new StackPanel { Children = { title, date, excerpt, more } },
			},
		};
	}

	static void Open(string link)
	{
		if (NewsService.IsSiteLink(link))
			MacPlatform.Open(link);
	}
}
