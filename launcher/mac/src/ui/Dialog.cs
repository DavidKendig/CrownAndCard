// SPDX-License-Identifier: AGPL-3.0-or-later
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;

namespace CrownAndCard.Launcher.UI;

/** A small message box in the launcher's colors (Avalonia has none of its own). **/
static class Dialog
{
	public enum Kind { Info, Warning, Error }

	/** Shows a message with OK. **/
	public static Task Show(Window? owner, string message, Kind kind = Kind.Info) => Ask(owner, message, kind, null);

	/** Shows a message with `yes` and Cancel; true when the player picks `yes`. **/
	public static async Task<bool> Confirm(Window? owner, string message, string yes, Kind kind = Kind.Warning) =>
		await Ask(owner, message, kind, yes);

	static async Task<bool> Ask(Window? owner, string message, Kind kind, string? yes)
	{
		var accent = kind switch { Kind.Error => UiTheme.Red, Kind.Warning => UiTheme.Amber, _ => UiTheme.Gold };
		var window = new Window
		{
			Title = "Crown & Card",
			Width = 460,
			SizeToContent = SizeToContent.Height,
			CanResize = false,
			WindowStartupLocation = owner != null ? WindowStartupLocation.CenterOwner : WindowStartupLocation.CenterScreen,
			Background = UiTheme.Brush(UiTheme.Background),
			ShowInTaskbar = false,
		};
		bool result = false;
		var ok = UiTheme.Button(yes ?? "OK", primary: true, size: UiTheme.Body);
		ok.MinWidth = 90;
		ok.IsDefault = true;
		ok.Click += (_, _) => { result = true; window.Close(); };
		var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Spacing = 8, Margin = new Thickness(0, 18, 0, 0) };
		if (yes != null)
		{
			var cancel = UiTheme.Button("Cancel", size: UiTheme.Body);
			cancel.MinWidth = 90;
			cancel.IsCancel = true;
			cancel.Click += (_, _) => window.Close();
			buttons.Children.Add(cancel);
		}
		buttons.Children.Add(ok);
		var text = UiTheme.Label(message, UiTheme.Body, UiTheme.Cream);
		window.Content = new Border
		{
			BorderBrush = UiTheme.Brush(accent),
			BorderThickness = new Thickness(3, 0, 0, 0),
			Margin = new Thickness(20),
			Padding = new Thickness(16, 4, 0, 4),
			Child = new StackPanel { Children = { text, buttons } },
		};
		if (owner != null && owner.IsVisible)
			await window.ShowDialog(owner);
		else
		{
			var closed = new TaskCompletionSource();
			window.Closed += (_, _) => closed.TrySetResult();
			window.Show();
			await closed.Task;
		}
		return result;
	}
}
