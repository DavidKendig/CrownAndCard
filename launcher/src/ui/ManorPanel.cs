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
	Font? manorTitle;
	Size manorTitleFitBox = new(-1, -1);

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

	/**
		A point size is DPI-relative, but under Remote Desktop and similar .NET Framework
		WinForms can fail to scale a form's own layout to match the DPI its GDI text actually
		renders at; a fixed 25pt title then draws far larger than the box below expects (the
		box mismatch is unnoticeable at the same DPI, but blows up in proportion to how far it
		diverges). Measuring the live Graphics against the box it has to fit sidesteps the
		mismatch entirely, whatever caused it.
	**/
	Font TitleFont(Graphics g, Size box)
	{
		if (manorTitle != null && manorTitleFitBox == box)
			return manorTitle;
		const float DesignSize = 25f;
		using var probe = new Font("Georgia", DesignSize, FontStyle.Regular);
		var measured = TextRenderer.MeasureText(g, "Dodriec Manor", probe, new Size(int.MaxValue, int.MaxValue),
			TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
		float widthRatio = measured.Width > box.Width && measured.Width > 0 ? (float)box.Width / measured.Width : 1f;
		float heightRatio = measured.Height > box.Height && measured.Height > 0 ? (float)box.Height / measured.Height : 1f;
		float fitted = DesignSize * Math.Min(widthRatio, heightRatio);
		manorTitle?.Dispose();
		manorTitle = new Font("Georgia", Math.Max(6f, fitted), FontStyle.Regular);
		manorTitleFitBox = box;
		return manorTitle;
	}

	/**
		SingleLine text with no VerticalCenter flag draws from the top of its box, so a box
		shorter than the font's real line height (the same live-DPI mismatch TitleFont works
		around) clips the bottom of the glyphs rather than the top. Measuring first keeps the
		box tall enough regardless.
	**/
	static Rectangle FitLine(Graphics g, string text, Font font, int x, int y, int width)
	{
		var size = TextRenderer.MeasureText(g, text, font, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
		return new Rectangle(x, y, width, Math.Max(size.Height, 1));
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
		TextRenderer.DrawText(g, "THE ORDER AWAITS", Theme.Small, FitLine(g, "THE ORDER AWAITS", Theme.Small, 20, Height - 142, Width - 40), Theme.GoldBright, flags);
		TextRenderer.DrawText(g, "Dodriec Manor", TitleFont(g, new Size(Width - 40, 48)), new Rectangle(20, Height - 112, Width - 40, 48), Theme.Cream, flags);
		TextRenderer.DrawText(g, "Fortune favors the bold.", Theme.Small, FitLine(g, "Fortune favors the bold.", Theme.Small, 20, Height - 57, Width - 40), Theme.Muted, flags);
	}

	protected override void Dispose(bool disposing)
	{
		if (disposing) { artwork?.Dispose(); manorTitle?.Dispose(); }
		base.Dispose(disposing);
	}
}
