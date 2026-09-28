// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Reflection;
using System.Windows.Forms;

namespace CrownAndCard.Launcher.UI;

/** Embedded static pixel artwork: no runtime download or external file dependency. */
sealed class ManorPanel : Panel
{
	readonly Bitmap? artwork;
	readonly Font manorTitle = new("Georgia", 25f, FontStyle.Regular);

	public ManorPanel()
	{
		DoubleBuffered = true;
		ResizeRedraw = true;
		BackColor = Theme.Panel;
		using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("CrownAndCard.Manor.png");
		if (stream != null)
		{
			using var source = new Bitmap(stream);
			artwork = new Bitmap(source);
		}
		AccessibleName = "Dodriec Manor: a candlelit masquerade";
	}

	protected override void OnPaint(PaintEventArgs e)
	{
		base.OnPaint(e);
		if (Width < 2 || Height < 2) return;
		var g = e.Graphics;
		if (artwork != null)
		{
			float scale = Math.Max(Width / (float)artwork.Width, Height / (float)artwork.Height);
			float w = artwork.Width * scale, h = artwork.Height * scale;
			g.InterpolationMode = InterpolationMode.NearestNeighbor;
			g.PixelOffsetMode = PixelOffsetMode.Half;
			g.DrawImage(artwork, new RectangleF((Width - w) / 2, (Height - h) / 2, w, h));
		}
		var caption = new Rectangle(0, Math.Max(0, Height - 200), Width, Math.Min(200, Height));
		using (var shade = new LinearGradientBrush(caption, Color.FromArgb(0, Theme.Background), Color.FromArgb(250, Theme.Background), LinearGradientMode.Vertical))
			g.FillRectangle(shade, caption);
		using (var border = new Pen(Theme.GoldDark))
		{
			g.DrawRectangle(border, 12, 12, Width - 25, Height - 25);
			g.DrawLine(border, Width - 1, 0, Width - 1, Height);
		}
		using (var bright = new Pen(Theme.Gold, 2))
		{
			foreach (int x in new[] { 12, Width - 13 })
			foreach (int y in new[] { 12, Height - 13 })
			{
				g.DrawLine(bright, x, y, x + (x < Width / 2 ? 22 : -22), y);
				g.DrawLine(bright, x, y, x, y + (y < Height / 2 ? 22 : -22));
			}
		}
		var flags = TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine;
		TextRenderer.DrawText(g, "THE ORDER AWAITS", Theme.Small, new Rectangle(20, Height - 142, Width - 40, 24), Theme.GoldBright, flags);
		TextRenderer.DrawText(g, "Dodriec Manor", manorTitle, new Rectangle(20, Height - 112, Width - 40, 48), Theme.Cream, flags);
		TextRenderer.DrawText(g, "Fortune favors the bold.", Theme.Small, new Rectangle(20, Height - 57, Width - 40, 24), Theme.Muted, flags);
	}

	protected override void Dispose(bool disposing)
	{
		if (disposing) { artwork?.Dispose(); manorTitle.Dispose(); }
		base.Dispose(disposing);
	}
}
