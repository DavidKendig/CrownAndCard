// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace CrownAndCard.Launcher.UI;

/** Colors and fonts: felt green, gold and cream, matching the game's palette. **/
static class Theme
{
	public static readonly Color Background = Color.FromArgb(11, 19, 15);
	public static readonly Color Panel = Color.FromArgb(18, 31, 24);
	public static readonly Color Card = Color.FromArgb(25, 42, 33);
	public static readonly Color CardHover = Color.FromArgb(33, 54, 42);
	public static readonly Color Border = Color.FromArgb(56, 74, 50);
	public static readonly Color Gold = Color.FromArgb(212, 175, 55);
	public static readonly Color GoldBright = Color.FromArgb(240, 208, 96);
	public static readonly Color GoldDark = Color.FromArgb(120, 94, 26);
	public static readonly Color Cream = Color.FromArgb(237, 227, 200);
	public static readonly Color Muted = Color.FromArgb(150, 144, 124);
	public static readonly Color Ink = Color.FromArgb(24, 18, 8);
	public static readonly Color Red = Color.FromArgb(214, 92, 84);
	public static readonly Color Green = Color.FromArgb(120, 190, 120);
	public static readonly Color Amber = Color.FromArgb(226, 170, 80);

	static readonly string Serif = FontFamily.Families.Any(f => f.Name == "Georgia") ? "Georgia" : "Times New Roman";

	public static readonly Font Title = new(Serif, 30f, FontStyle.Bold);
	public static readonly Font Subtitle = new(Serif, 11f, FontStyle.Italic);
	public static readonly Font Heading = new(Serif, 15f, FontStyle.Bold);
	public static readonly Font CardTitle = new(Serif, 13f, FontStyle.Bold);
	public static readonly Font Tab = new("Segoe UI Semibold", 10.5f);
	public static readonly Font Body = new("Segoe UI", 10f);
	public static readonly Font Small = new("Segoe UI", 8.75f);
	public static readonly Font Play = new(Serif, 17f, FontStyle.Bold);
	public static readonly Font Mono = new("Consolas", 9f);

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

	[DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
	static extern int SetWindowTheme(IntPtr hWnd, string subAppName, string? subIdList);

	/** Dark scroll bars (Windows 10 1809 and later); older Windows keeps the light ones. **/
	public static void DarkScrollbars(Control c)
	{
		void Apply()
		{
			try
			{
				SetWindowTheme(c.Handle, "DarkMode_Explorer", null);
			}
			catch
			{
				// Cosmetic only.
			}
		}
		if (c.IsHandleCreated)
			Apply();
		else
			c.HandleCreated += (_, _) => Apply();
	}

	public static void StyleButton(Button b, bool primary = false)
	{
		b.FlatStyle = FlatStyle.Flat;
		b.UseVisualStyleBackColor = false;
		b.Cursor = Cursors.Hand;
		b.FlatAppearance.BorderSize = 1;
		b.FlatAppearance.BorderColor = primary ? GoldBright : Border;
		b.BackColor = primary ? Gold : Card;
		b.ForeColor = primary ? Ink : Cream;
		b.FlatAppearance.MouseOverBackColor = primary ? GoldBright : CardHover;
		b.FlatAppearance.MouseDownBackColor = primary ? GoldDark : Border;
	}

	public static Label Label(string text, Font? font = null, Color? color = null) => new()
	{
		Text = text,
		Font = font ?? Body,
		ForeColor = color ?? Cream,
		AutoSize = true,
		BackColor = Color.Transparent,
	};

	/** A gold crown, drawn rather than loaded so the launcher is a single file. **/
	public static void DrawCrown(Graphics g, RectangleF r)
	{
		g.SmoothingMode = SmoothingMode.AntiAlias;
		float w = r.Width, h = r.Height, x = r.X, y = r.Y;
		var points = new[]
		{
			new PointF(x, y + h * 0.35f), new PointF(x + w * 0.25f, y + h * 0.62f), new PointF(x + w * 0.5f, y + h * 0.15f),
			new PointF(x + w * 0.75f, y + h * 0.62f), new PointF(x + w, y + h * 0.35f), new PointF(x + w * 0.9f, y + h * 0.85f),
			new PointF(x + w * 0.1f, y + h * 0.85f),
		};
		using (var fill = new LinearGradientBrush(r, GoldBright, GoldDark, LinearGradientMode.Vertical))
			g.FillPolygon(fill, points);
		using (var pen = new Pen(GoldDark, 1.5f))
			g.DrawPolygon(pen, points);
		using var band = new SolidBrush(Gold);
		g.FillRectangle(band, x + w * 0.1f, y + h * 0.85f, w * 0.8f, h * 0.15f);
		using var jewel = new SolidBrush(Color.FromArgb(176, 32, 48));
		foreach (var p in new[] { points[0], points[2], points[4] })
			g.FillEllipse(jewel, p.X - w * 0.06f, p.Y - w * 0.06f, w * 0.12f, w * 0.12f);
	}
}

/** A flat horizontal slider in the launcher's colors, with the value shown on the right. **/
sealed class Slider : Control
{
	int value;
	public int Minimum { get; set; }
	public int Maximum { get; set; } = 100;
	public string Suffix { get; set; } = "%";

	public event EventHandler? ValueChanged;

	public Slider()
	{
		SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint
			| ControlStyles.ResizeRedraw | ControlStyles.Selectable | ControlStyles.SupportsTransparentBackColor, true);
		Height = 28;
		Width = 240;
		Cursor = Cursors.Hand;
		TabStop = true;
		BackColor = Color.Transparent;
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
			Invalidate();
			ValueChanged?.Invoke(this, EventArgs.Empty);
		}
	}

	Rectangle Track => new(8, Height / 2 - 3, Math.Max(10, Width - 70), 6);

	protected override void OnPaint(PaintEventArgs e)
	{
		var g = e.Graphics;
		g.SmoothingMode = SmoothingMode.AntiAlias;
		var track = Track;
		float t = Maximum == Minimum ? 0 : (value - Minimum) / (float)(Maximum - Minimum);
		int knobX = track.X + (int)(t * track.Width);
		using (var bg = new SolidBrush(Theme.Border))
			g.FillRectangle(bg, track);
		using (var fill = new SolidBrush(Theme.Gold))
			g.FillRectangle(fill, track.X, track.Y, knobX - track.X, track.Height);
		using (var knob = new SolidBrush(Focused ? Theme.GoldBright : Theme.Gold))
			g.FillEllipse(knob, knobX - 8, Height / 2 - 8, 16, 16);
		using (var ring = new Pen(Theme.GoldDark, 1.5f))
			g.DrawEllipse(ring, knobX - 8, Height / 2 - 8, 16, 16);
		TextRenderer.DrawText(g, value + Suffix, Theme.Body, new Rectangle(track.Right + 10, 0, Width - track.Right - 10, Height),
			Theme.Cream, TextFormatFlags.VerticalCenter | TextFormatFlags.Left);
	}

	protected override void OnMouseDown(MouseEventArgs e)
	{
		Focus();
		if (e.Button == MouseButtons.Left)
			SetFromX(e.X);
		base.OnMouseDown(e);
	}

	protected override void OnMouseMove(MouseEventArgs e)
	{
		if (e.Button == MouseButtons.Left)
			SetFromX(e.X);
		base.OnMouseMove(e);
	}

	void SetFromX(int x)
	{
		var track = Track;
		float t = (x - track.X) / (float)track.Width;
		Value = Minimum + (int)Math.Round(Math.Max(0, Math.Min(1, t)) * (Maximum - Minimum));
	}

	protected override bool IsInputKey(Keys keyData) => keyData is Keys.Left or Keys.Right or Keys.Up or Keys.Down || base.IsInputKey(keyData);

	protected override void OnKeyDown(KeyEventArgs e)
	{
		switch (e.KeyCode)
		{
			case Keys.Left or Keys.Down: Value -= 1; break;
			case Keys.Right or Keys.Up: Value += 1; break;
			case Keys.PageDown: Value -= 10; break;
			case Keys.PageUp: Value += 10; break;
			case Keys.Home: Value = Minimum; break;
			case Keys.End: Value = Maximum; break;
		}
		base.OnKeyDown(e);
	}

	protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }

	protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
}

/** A check box drawn in the launcher's colors (the stock flat style shows no visible tick on dark backgrounds). **/
sealed class TickBox : CheckBox
{
	public TickBox(string text)
	{
		SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
		Text = text;
		Font = Theme.Body;
		ForeColor = Theme.Cream;
		Cursor = Cursors.Hand;
		AutoSize = false;
		Size = new Size(TextRenderer.MeasureText(text, Theme.Body).Width + 32, 26);
	}

	protected override void OnPaint(PaintEventArgs e)
	{
		var g = e.Graphics;
		using (var bg = new SolidBrush(Theme.Background))
			g.FillRectangle(bg, ClientRectangle);
		g.SmoothingMode = SmoothingMode.AntiAlias;
		var box = new Rectangle(1, (Height - 18) / 2, 18, 18);
		using (var fill = new SolidBrush(Checked ? Theme.GoldDark : Theme.Card))
			g.FillRectangle(fill, box);
		using (var border = new Pen(Focused ? Theme.GoldBright : Theme.Gold, 1.5f))
			g.DrawRectangle(border, box);
		if (Checked)
		{
			using var tick = new Pen(Theme.GoldBright, 2.4f) { StartCap = LineCap.Round, EndCap = LineCap.Round };
			g.DrawLines(tick, [new Point(box.X + 4, box.Y + 9), new Point(box.X + 8, box.Y + 13), new Point(box.X + 14, box.Y + 5)]);
		}
		TextRenderer.DrawText(g, Text, Font, new Rectangle(box.Right + 8, 0, Width - box.Right - 8, Height), ForeColor,
			TextFormatFlags.VerticalCenter | TextFormatFlags.Left);
	}
}

/** A drop-down list drawn in the launcher's colors. Items are (value, label) pairs. **/
sealed class Choice : ComboBox
{
	public Choice(params (string Value, string Label)[] options)
	{
		DropDownStyle = ComboBoxStyle.DropDownList;
		FlatStyle = FlatStyle.Flat;
		DrawMode = DrawMode.OwnerDrawFixed;
		BackColor = Theme.Card;
		ForeColor = Theme.Cream;
		Font = Theme.Body;
		Width = 240;
		ItemHeight = 22;
		foreach (var o in options)
			Items.Add(new Option(o.Value, o.Label));
	}

	public string Value
	{
		get => (SelectedItem as Option)?.Value ?? "";
		set
		{
			for (int i = 0; i < Items.Count; i++)
				if (((Option)Items[i]).Value == value)
				{
					SelectedIndex = i;
					return;
				}
			if (Items.Count > 0)
				SelectedIndex = 0;
		}
	}

	protected override void OnDrawItem(DrawItemEventArgs e)
	{
		if (e.Index < 0)
			return;
		bool selected = (e.State & DrawItemState.Selected) != 0 && (e.State & DrawItemState.ComboBoxEdit) == 0;
		using (var bg = new SolidBrush(selected ? Theme.CardHover : Theme.Card))
			e.Graphics.FillRectangle(bg, e.Bounds);
		TextRenderer.DrawText(e.Graphics, Items[e.Index].ToString(), Font, e.Bounds, selected ? Theme.GoldBright : Theme.Cream,
			TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
	}

	sealed class Option(string value, string label)
	{
		public string Value { get; } = value;
		public override string ToString() => label;
	}
}
