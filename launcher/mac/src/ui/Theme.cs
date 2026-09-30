// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Generic;
using System.Linq;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Presenters;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Styling;

namespace CrownAndCard.Launcher.UI;

/** Navy evening dress, burgundy damask, aged brass and ivory from the manor art (the Windows launcher's Theme, for Avalonia). **/
static class UiTheme
{
	public static readonly Color Background = Color.FromRgb(10, 13, 24);
	public static readonly Color Panel = Color.FromRgb(16, 21, 36);
	public static readonly Color Card = Color.FromRgb(23, 29, 46);
	public static readonly Color CardHover = Color.FromRgb(34, 42, 62);
	public static readonly Color Border = Color.FromRgb(73, 65, 53);
	public static readonly Color Burgundy = Color.FromRgb(66, 20, 33);
	public static readonly Color Gold = Color.FromRgb(200, 163, 94);
	public static readonly Color GoldBright = Color.FromRgb(244, 219, 165);
	public static readonly Color GoldDark = Color.FromRgb(115, 85, 43);
	public static readonly Color Cream = Color.FromRgb(239, 230, 210);
	public static readonly Color Muted = Color.FromRgb(164, 161, 154);
	public static readonly Color Ink = Color.FromRgb(24, 18, 8);
	public static readonly Color Red = Color.FromRgb(214, 92, 84);
	public static readonly Color Green = Color.FromRgb(120, 190, 120);
	public static readonly Color Amber = Color.FromRgb(226, 170, 80);
	public static readonly Color ErrorRow = Color.FromRgb(46, 22, 30);

	public static IBrush Brush(Color c) => new SolidColorBrush(c);

	public static readonly FontFamily Serif = new("Georgia, Times New Roman");
	public static readonly FontFamily Sans = FontFamily.Default;
	public static readonly FontFamily Mono = new("Menlo, Monaco, Courier New");

	// Point sizes from the Windows theme, in Avalonia's device-independent pixels (pt × 4/3).
	public const double Title = 40, Subtitle = 15, Heading = 20, CardTitle = 17, Tab = 14, Body = 13.5, Small = 12, Play = 22, MonoSize = 12;

	public static Color StatusColor(string status) => status switch
	{
		"ok" => Green,
		"running" => Gold,
		"errors" or "lost-contact" => Amber,
		"crashed" => Red,
		_ => Muted,
	};

	public static string StatusText(string status) => status switch
	{
		"ok" => "OK",
		"running" => "Playing",
		"errors" => "Errors reported",
		"crashed" => "Crashed",
		"lost-contact" => "Lost contact",
		_ => "Unknown",
	};

	public static TextBlock Label(string text, double size = Body, Color? color = null, FontFamily? family = null, FontWeight weight = FontWeight.Normal) => new()
	{
		Text = text,
		FontSize = size,
		FontFamily = family ?? Sans,
		FontWeight = weight,
		Foreground = Brush(color ?? Cream),
		TextWrapping = TextWrapping.Wrap,
	};

	/** A flat launcher button; `primary` is the gold PLAY style. **/
	public static Button Button(string text, bool primary = false, double size = Tab)
	{
		var b = new Button
		{
			Content = text,
			FontSize = size,
			FontWeight = primary ? FontWeight.Bold : FontWeight.SemiBold,
			FontFamily = primary ? Serif : Sans,
			Cursor = new Cursor(StandardCursorType.Hand),
			HorizontalContentAlignment = HorizontalAlignment.Center,
			VerticalContentAlignment = VerticalAlignment.Center,
			Padding = new Thickness(14, 6),
			CornerRadius = new CornerRadius(0),
			BorderThickness = new Thickness(1),
		};
		b.Classes.Add(primary ? "primary" : "flat");
		return b;
	}

	/**
		Styles for the stock controls (buttons, lists, drop-downs, text boxes,
		scroll bars) in the launcher's colors. Added once by the App.
	**/
	public static Styles Styles()
	{
		var styles = new Styles();
		void Add(Func<Selector?, Selector> selector, params (AvaloniaProperty Property, object Value)[] setters)
		{
			var style = new Style(selector);
			foreach (var (p, v) in setters)
				style.Setters.Add(new Setter(p, v));
			styles.Add(style);
		}
		Selector Presenter(Selector? s) => s!.Template().OfType<ContentPresenter>().Name("PART_ContentPresenter");

		// Flat buttons.
		Add(s => s.OfType<Button>().Class("flat"),
			(TemplatedControl.BackgroundProperty, Brush(Card)), (TemplatedControl.ForegroundProperty, Brush(Cream)), (TemplatedControl.BorderBrushProperty, Brush(Border)));
		Add(s => Presenter(s.OfType<Button>().Class("flat").Class(":pointerover")),
			(ContentPresenter.BackgroundProperty, Brush(CardHover)), (ContentPresenter.ForegroundProperty, Brush(GoldBright)), (ContentPresenter.BorderBrushProperty, Brush(Gold)));
		Add(s => Presenter(s.OfType<Button>().Class("flat").Class(":pressed")),
			(ContentPresenter.BackgroundProperty, Brush(Border)));
		Add(s => Presenter(s.OfType<Button>().Class("flat").Class(":disabled")),
			(ContentPresenter.BackgroundProperty, Brush(Panel)), (ContentPresenter.ForegroundProperty, Brush(Border)), (ContentPresenter.BorderBrushProperty, Brush(Border)));
		// PLAY.
		Add(s => s.OfType<Button>().Class("primary"),
			(TemplatedControl.BackgroundProperty, Brush(Gold)), (TemplatedControl.ForegroundProperty, Brush(Ink)), (TemplatedControl.BorderBrushProperty, Brush(GoldBright)));
		Add(s => Presenter(s.OfType<Button>().Class("primary").Class(":pointerover")),
			(ContentPresenter.BackgroundProperty, Brush(GoldBright)), (ContentPresenter.ForegroundProperty, Brush(Ink)), (ContentPresenter.BorderBrushProperty, Brush(GoldBright)));
		Add(s => Presenter(s.OfType<Button>().Class("primary").Class(":pressed")),
			(ContentPresenter.BackgroundProperty, Brush(GoldDark)));
		Add(s => Presenter(s.OfType<Button>().Class("primary").Class(":disabled")),
			(ContentPresenter.BackgroundProperty, Brush(GoldDark)), (ContentPresenter.ForegroundProperty, Brush(Ink)), (ContentPresenter.BorderBrushProperty, Brush(GoldDark)));

		// Text boxes and drop-downs.
		foreach (var type in new[] { typeof(TextBox), typeof(ComboBox) })
		{
			Add(s => s.OfType(type), (TemplatedControl.BackgroundProperty, Brush(Card)), (TemplatedControl.ForegroundProperty, Brush(Cream)),
				(TemplatedControl.BorderBrushProperty, Brush(Border)), (TemplatedControl.CornerRadiusProperty, new CornerRadius(0)));
		}
		Add(s => s.OfType<TextBox>().Class(":focus").Template().OfType<Border>().Name("PART_BorderElement"),
			(Avalonia.Controls.Border.BackgroundProperty, Brush(Card)), (Avalonia.Controls.Border.BorderBrushProperty, Brush(Gold)));
		Add(s => s.OfType<TextBox>().Class(":pointerover").Template().OfType<Border>().Name("PART_BorderElement"),
			(Avalonia.Controls.Border.BackgroundProperty, Brush(CardHover)), (Avalonia.Controls.Border.BorderBrushProperty, Brush(Gold)));
		Add(s => s.OfType<ComboBox>().Class(":pointerover").Template().OfType<Border>().Name("Background"),
			(Avalonia.Controls.Border.BackgroundProperty, Brush(CardHover)), (Avalonia.Controls.Border.BorderBrushProperty, Brush(Gold)));
		Add(s => s.OfType<ComboBoxItem>(), (TemplatedControl.ForegroundProperty, Brush(Cream)));
		Add(s => Presenter(s.OfType<ComboBoxItem>().Class(":pointerover")), (ContentPresenter.BackgroundProperty, Brush(CardHover)), (ContentPresenter.ForegroundProperty, Brush(GoldBright)));
		Add(s => Presenter(s.OfType<ComboBoxItem>().Class(":selected")), (ContentPresenter.BackgroundProperty, Brush(Burgundy)), (ContentPresenter.ForegroundProperty, Brush(GoldBright)));

		// Lists (Reports, game log): cards with a quiet highlight.
		Add(s => s.OfType<ListBox>(), (TemplatedControl.BackgroundProperty, Brush(Card)), (TemplatedControl.BorderThicknessProperty, new Thickness(0)));
		Add(s => s.OfType<ListBoxItem>(), (TemplatedControl.PaddingProperty, new Thickness(0)), (Layoutable.MinHeightProperty, 0.0));
		Add(s => Presenter(s.OfType<ListBoxItem>().Class(":pointerover")), (ContentPresenter.BackgroundProperty, Brush(Color.FromRgb(28, 35, 54))));
		Add(s => Presenter(s.OfType<ListBoxItem>().Class(":selected")), (ContentPresenter.BackgroundProperty, Brush(CardHover)));
		Add(s => Presenter(s.OfType<ListBoxItem>().Class(":selected").Class(":pointerover")), (ContentPresenter.BackgroundProperty, Brush(CardHover)));

		// Menus (the MAP button).
		Add(s => s.OfType<MenuFlyoutPresenter>(), (TemplatedControl.BackgroundProperty, Brush(Panel)), (TemplatedControl.BorderBrushProperty, Brush(GoldDark)));
		Add(s => s.OfType<MenuItem>(), (TemplatedControl.ForegroundProperty, Brush(Cream)));
		return styles;
	}
}

/** A clickable line of text in gold, underlined on hover (the Windows LinkLabel). With no action it's plain muted text. **/
sealed class LinkText : TextBlock
{
	Action? action;

	public LinkText(string text = "", double size = UiTheme.Body)
	{
		Text = text;
		FontSize = size;
		Foreground = UiTheme.Brush(UiTheme.Gold);
		Cursor = new Cursor(StandardCursorType.Hand);
		PointerEntered += (_, _) => { if (action != null) TextDecorations = Avalonia.Media.TextDecorations.Underline; };
		PointerExited += (_, _) => TextDecorations = null;
		PointerPressed += (_, e) =>
		{
			if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed && action != null)
			{
				e.Handled = true;
				action();
			}
		};
	}

	/** Sets the text and what clicking it does (null: not a link). **/
	public void Set(string text, Action? onClick)
	{
		Text = text;
		action = onClick;
		Foreground = UiTheme.Brush(onClick != null ? UiTheme.Gold : UiTheme.Muted);
		Cursor = new Cursor(onClick != null ? StandardCursorType.Hand : StandardCursorType.Arrow);
		if (onClick == null)
			TextDecorations = null;
	}

	public event Action Click
	{
		add => action += value;
		remove => action -= value;
	}
}

/** A flat horizontal slider in the launcher's colors, with the value shown on the right. **/
sealed class GoldSlider : Control
{
	int value;
	public int Minimum { get; init; }
	public int Maximum { get; init; } = 100;
	public string Suffix { get; init; } = "%";

	public event EventHandler? ValueChanged;

	public GoldSlider()
	{
		Height = 28;
		Width = 290;
		Focusable = true;
		Cursor = new Cursor(StandardCursorType.Hand);
	}

	public int Value
	{
		get => value;
		set
		{
			var v = Math.Max(Minimum, Math.Min(Maximum, value));
			if (v == this.value)
				return;
			this.value = v;
			InvalidateVisual();
			ValueChanged?.Invoke(this, EventArgs.Empty);
		}
	}

	Rect Track => new(8, Bounds.Height / 2 - 3, Math.Max(10, Bounds.Width - 78), 6);

	public override void Render(DrawingContext g)
	{
		var track = Track;
		double t = Maximum == Minimum ? 0 : (value - Minimum) / (double)(Maximum - Minimum);
		double knobX = track.X + t * track.Width;
		g.FillRectangle(UiTheme.Brush(UiTheme.Border), track);
		g.FillRectangle(UiTheme.Brush(UiTheme.Gold), new Rect(track.X, track.Y, knobX - track.X, track.Height));
		var center = new Point(knobX, Bounds.Height / 2);
		g.DrawEllipse(UiTheme.Brush(IsFocused ? UiTheme.GoldBright : UiTheme.Gold), new Pen(UiTheme.Brush(UiTheme.GoldDark), 1.5), center, 8, 8);
		var text = new FormattedText(value + Suffix, System.Globalization.CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
			new Typeface(UiTheme.Sans), UiTheme.Body, UiTheme.Brush(UiTheme.Cream));
		g.DrawText(text, new Point(track.Right + 12, (Bounds.Height - text.Height) / 2));
	}

	protected override void OnPointerPressed(PointerPressedEventArgs e)
	{
		Focus();
		if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
		{
			e.Pointer.Capture(this);
			SetFromX(e.GetPosition(this).X);
		}
		base.OnPointerPressed(e);
	}

	protected override void OnPointerMoved(PointerEventArgs e)
	{
		if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
			SetFromX(e.GetPosition(this).X);
		base.OnPointerMoved(e);
	}

	protected override void OnPointerReleased(PointerReleasedEventArgs e)
	{
		e.Pointer.Capture(null);
		base.OnPointerReleased(e);
	}

	void SetFromX(double x)
	{
		var track = Track;
		double t = (x - track.X) / track.Width;
		Value = Minimum + (int)Math.Round(Math.Max(0, Math.Min(1, t)) * (Maximum - Minimum));
	}

	protected override void OnKeyDown(KeyEventArgs e)
	{
		switch (e.Key)
		{
			case Key.Left or Key.Down: Value -= 1; e.Handled = true; break;
			case Key.Right or Key.Up: Value += 1; e.Handled = true; break;
			case Key.PageDown: Value -= 10; e.Handled = true; break;
			case Key.PageUp: Value += 10; e.Handled = true; break;
			case Key.Home: Value = Minimum; e.Handled = true; break;
			case Key.End: Value = Maximum; e.Handled = true; break;
		}
		base.OnKeyDown(e);
	}

	protected override void OnGotFocus(GotFocusEventArgs e) { InvalidateVisual(); base.OnGotFocus(e); }

	protected override void OnLostFocus(Avalonia.Interactivity.RoutedEventArgs e) { InvalidateVisual(); base.OnLostFocus(e); }
}

/** A check box drawn in the launcher's colors. **/
sealed class TickBox : Control
{
	bool isChecked;
	readonly string text;

	public event EventHandler? CheckedChanged;

	public TickBox(string text)
	{
		this.text = text;
		Height = 26;
		Focusable = true;
		Cursor = new Cursor(StandardCursorType.Hand);
	}

	public bool Checked
	{
		get => isChecked;
		set
		{
			if (value == isChecked)
				return;
			isChecked = value;
			InvalidateVisual();
			CheckedChanged?.Invoke(this, EventArgs.Empty);
		}
	}

	FormattedText Text() => new(text, System.Globalization.CultureInfo.CurrentCulture, FlowDirection.LeftToRight, new Typeface(UiTheme.Sans), UiTheme.Body, UiTheme.Brush(UiTheme.Cream));

	protected override Size MeasureOverride(Size availableSize) => new(Text().Width + 30, 26);

	public override void Render(DrawingContext g)
	{
		g.FillRectangle(Brushes.Transparent, new Rect(Bounds.Size));
		var box = new Rect(1, (Bounds.Height - 18) / 2, 18, 18);
		g.DrawRectangle(UiTheme.Brush(isChecked ? UiTheme.GoldDark : UiTheme.Card), new Pen(UiTheme.Brush(IsFocused ? UiTheme.GoldBright : UiTheme.Gold), 1.5), box);
		if (isChecked)
		{
			var pen = new Pen(UiTheme.Brush(UiTheme.GoldBright), 2.4, lineCap: PenLineCap.Round);
			var geometry = new PolylineGeometry(new[] { new Point(box.X + 4, box.Y + 9), new Point(box.X + 8, box.Y + 13), new Point(box.X + 14, box.Y + 5) }, false);
			g.DrawGeometry(null, pen, geometry);
		}
		var t = Text();
		g.DrawText(t, new Point(box.Right + 9, (Bounds.Height - t.Height) / 2));
	}

	protected override void OnPointerReleased(PointerReleasedEventArgs e)
	{
		if (e.InitialPressMouseButton == MouseButton.Left && new Rect(Bounds.Size).Contains(e.GetPosition(this)))
		{
			Focus();
			Checked = !Checked;
		}
		base.OnPointerReleased(e);
	}

	protected override void OnKeyDown(KeyEventArgs e)
	{
		if (e.Key == Key.Space)
		{
			Checked = !Checked;
			e.Handled = true;
		}
		base.OnKeyDown(e);
	}

	protected override void OnGotFocus(GotFocusEventArgs e) { InvalidateVisual(); base.OnGotFocus(e); }

	protected override void OnLostFocus(Avalonia.Interactivity.RoutedEventArgs e) { InvalidateVisual(); base.OnLostFocus(e); }
}

/** A drop-down list in the launcher's colors. Items are (value, label) pairs. **/
sealed class Choice : ComboBox
{
	protected override Type StyleKeyOverride => typeof(ComboBox);

	readonly List<(string Value, string Label)> options;

	public Choice(params (string Value, string Label)[] options)
	{
		this.options = options.ToList();
		ItemsSource = options.Select(o => o.Label).ToList();
		Width = 290;
		FontSize = UiTheme.Body;
		SelectedIndex = options.Length > 0 ? 0 : -1;
	}

	public string Value
	{
		get => SelectedIndex >= 0 && SelectedIndex < options.Count ? options[SelectedIndex].Value : "";
		set
		{
			var i = options.FindIndex(o => o.Value == value);
			SelectedIndex = i >= 0 ? i : options.Count > 0 ? 0 : -1;
		}
	}

	public IEnumerable<string> Labels => options.Select(o => o.Label);
}

/**
	The one piece of the Windows UI's Theme that shared code uses
	(SessionRecorder's end-of-session note). The Mac UI's own palette is
	UiTheme: inside Avalonia controls, "Theme" names StyledElement.Theme.
**/
static class Theme
{
	public static string StatusText(string status) => UiTheme.StatusText(status);
}
