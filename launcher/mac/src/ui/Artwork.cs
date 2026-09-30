// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Globalization;
using System.IO;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using SkiaSharp;

namespace CrownAndCard.Launcher.UI;

/** The launcher's embedded PNG art (the same files the Windows launcher embeds). **/
static class Artwork
{
	public static Stream Open(string name) =>
		typeof(Artwork).Assembly.GetManifestResourceStream(name) ?? throw new InvalidOperationException("Missing launcher artwork: " + name);

	public static Bitmap Load(string name)
	{
		using var stream = Open(name);
		return new Bitmap(stream);
	}

	/** Loads a PNG without its transparent export margins, like the Windows header does. **/
	public static Bitmap LoadTrimmed(string name)
	{
		using var stream = Open(name);
		using var source = SKBitmap.Decode(stream) ?? throw new InvalidOperationException("Unreadable launcher artwork: " + name);
		int left = source.Width, top = source.Height, right = -1, bottom = -1;
		var pixels = source.Pixels;
		for (int y = 0; y < source.Height; y++)
		for (int x = 0; x < source.Width; x++)
		{
			if (pixels[y * source.Width + x].Alpha < 16) continue;
			left = Math.Min(left, x); top = Math.Min(top, y);
			right = Math.Max(right, x); bottom = Math.Max(bottom, y);
		}
		if (right < left) throw new InvalidOperationException("Empty launcher artwork: " + name);
		using var cropped = new SKBitmap();
		source.ExtractSubset(cropped, SKRectI.Create(left, top, right - left + 1, bottom - top + 1));
		using var image = SKImage.FromBitmap(cropped);
		using var png = image.Encode(SKEncodedImageFormat.Png, 100);
		using var ms = new MemoryStream(png.ToArray());
		return new Bitmap(ms);
	}

	/** Draws `bitmap` into `dest` with hard pixel edges. **/
	public static void DrawPixels(DrawingContext g, Bitmap bitmap, Rect dest)
	{
		using (g.PushRenderOptions(new RenderOptions { BitmapInterpolationMode = BitmapInterpolationMode.None }))
			g.DrawImage(bitmap, new Rect(bitmap.Size), dest);
	}

	public static FormattedText Text(string text, double size, Color color, FontFamily? family = null, FontWeight weight = FontWeight.Normal) =>
		new(text, CultureInfo.CurrentCulture, FlowDirection.LeftToRight, new Typeface(family ?? UiTheme.Sans, FontStyle.Normal, weight), size, UiTheme.Brush(color));
}

/** Title banner: a gradient, the crown, and the game's name. **/
sealed class HeaderArt : Control
{
	readonly Bitmap emblem = Artwork.LoadTrimmed("CrownAndCard.Emblem.png");
	readonly Bitmap logo = Artwork.LoadTrimmed("CrownAndCard.Logo.png");

	public HeaderArt()
	{
		IsHitTestVisible = false;
	}

	public override void Render(DrawingContext g)
	{
		var r = new Rect(Bounds.Size);
		var bg = new LinearGradientBrush
		{
			StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
			EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
			GradientStops = { new GradientStop(UiTheme.Panel, 0), new GradientStop(UiTheme.Background, 1) },
		};
		g.FillRectangle(bg, r);
		g.DrawLine(new Pen(UiTheme.Brush(UiTheme.GoldDark), 2), new Point(0, r.Height - 1), new Point(r.Width, r.Height - 1));
		double scale = r.Height / 118.0;
		double emblemHeight = 88 * scale;
		Artwork.DrawPixels(g, emblem, new Rect(26 * scale, 14 * scale, emblemHeight * emblem.Size.Width / emblem.Size.Height, emblemHeight));
		// The logo matches the crown's height; reserve room for the navigation at the minimum window width.
		double logoWidth = Math.Min(emblemHeight * logo.Size.Width / logo.Size.Height, Math.Max(180 * scale, r.Width - 480 * scale));
		double logoHeight = logoWidth * logo.Size.Height / logo.Size.Width;
		Artwork.DrawPixels(g, logo, new Rect(106 * scale, 14 * scale + (emblemHeight - logoHeight) / 2, logoWidth, logoHeight));
	}
}

/** Embedded static pixel artwork of the manor, with a caption at the foot. **/
sealed class ManorPanel : Control
{
	readonly Bitmap? artwork;

	public ManorPanel()
	{
		try
		{
			artwork = Artwork.Load("CrownAndCard.Manor.png");
		}
		catch (Exception e)
		{
			Log.Write("Manor artwork unavailable: " + e.Message);
		}
	}

	public override void Render(DrawingContext g)
	{
		double w = Bounds.Width, h = Bounds.Height;
		if (w < 2 || h < 2) return;
		g.FillRectangle(UiTheme.Brush(UiTheme.Panel), new Rect(Bounds.Size));
		if (artwork != null)
		{
			double scale = Math.Max(w / artwork.Size.Width, h / artwork.Size.Height);
			double aw = artwork.Size.Width * scale, ah = artwork.Size.Height * scale;
			using (g.PushClip(new Rect(Bounds.Size)))
				Artwork.DrawPixels(g, artwork, new Rect((w - aw) / 2, (h - ah) / 2, aw, ah));
		}
		var caption = new Rect(0, Math.Max(0, h - 200), w, Math.Min(200, h));
		var shade = new LinearGradientBrush
		{
			StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
			EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
			GradientStops = { new GradientStop(Color.FromArgb(0, UiTheme.Background.R, UiTheme.Background.G, UiTheme.Background.B), 0), new GradientStop(Color.FromArgb(250, UiTheme.Background.R, UiTheme.Background.G, UiTheme.Background.B), 1) },
		};
		g.FillRectangle(shade, caption);
		var border = new Pen(UiTheme.Brush(UiTheme.GoldDark), 1);
		g.DrawRectangle(border, new Rect(12.5, 12.5, w - 25, h - 25));
		g.DrawLine(border, new Point(w - 0.5, 0), new Point(w - 0.5, h));
		var bright = new Pen(UiTheme.Brush(UiTheme.Gold), 2);
		foreach (double x in new[] { 12.0, w - 13 })
		foreach (double y in new[] { 12.0, h - 13 })
		{
			g.DrawLine(bright, new Point(x, y), new Point(x + (x < w / 2 ? 22 : -22), y));
			g.DrawLine(bright, new Point(x, y), new Point(x, y + (y < h / 2 ? 22 : -22)));
		}
		Centered(g, Artwork.Text("THE ORDER AWAITS", UiTheme.Small, UiTheme.GoldBright), h - 142);
		var title = Artwork.Text("Dodriec Manor", 33, UiTheme.Cream, UiTheme.Serif);
		if (title.Width > w - 40)
			title = Artwork.Text("Dodriec Manor", Math.Max(8, 33 * (w - 40) / title.Width), UiTheme.Cream, UiTheme.Serif);
		Centered(g, title, h - 112);
		Centered(g, Artwork.Text("Fortune favors the bold.", UiTheme.Small, UiTheme.Muted), h - 57);
	}

	void Centered(DrawingContext g, FormattedText text, double y) =>
		g.DrawText(text, new Point((Bounds.Width - text.Width) / 2, y));
}
