// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Xml.Linq;

namespace CrownAndCard.Launcher;

sealed class NewsItem
{
	public string Title = "";
	public string Link = "";
	public string Excerpt = "";
	public DateTime Date;
}

sealed class NewsResult
{
	public List<NewsItem> Items = [];
	public DateTime FetchedAt;
	public bool FromCache;
	public string? Error;
}

/**
	Reads posts from davidkendig.info: the WordPress REST API first, the RSS
	feed as a fallback, and the last good copy on disk when offline.
**/
static class NewsService
{
	public const string Site = "https://davidkendig.info";
	const int PostCount = 10;

	static readonly HttpClient Http = CreateClient();

	static HttpClient CreateClient()
	{
		var http = new HttpClient { Timeout = TimeSpan.FromSeconds(12) };
		// An honest, identifiable user agent (the site rejects requests with none).
		http.DefaultRequestHeaders.UserAgent.ParseAdd($"CrownAndCardLauncher/{Program.Version} (+{Site})");
		http.DefaultRequestHeaders.Accept.ParseAdd("application/json, application/rss+xml;q=0.9, */*;q=0.5");
		return http;
	}

	/** `category` is a site category slug such as "news" or "games", or "all". **/
	public static async Task<NewsResult> FetchAsync(string category)
	{
		Exception? firstError = null;
		try
		{
			var items = await FetchRestAsync(category);
			SaveCache(items);
			return new NewsResult { Items = items, FetchedAt = DateTime.Now };
		}
		catch (Exception e)
		{
			firstError = e;
			Log.Write($"News (REST) failed: {e.Message}");
		}
		try
		{
			var items = await FetchRssAsync(category);
			SaveCache(items);
			return new NewsResult { Items = items, FetchedAt = DateTime.Now };
		}
		catch (Exception e)
		{
			Log.Write($"News (RSS) failed: {e.Message}");
		}
		var cached = LoadCache();
		if (cached != null)
		{
			cached.FromCache = true;
			cached.Error = firstError?.Message;
			return cached;
		}
		return new NewsResult { Error = firstError?.Message ?? "Unknown error" };
	}

	/** Only links on the site itself are ever opened. **/
	public static bool IsSiteLink(string? link)
	{
		if (!Uri.TryCreate(link, UriKind.Absolute, out var uri))
			return false;
		if (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp)
			return false;
		return uri.Host.Equals("davidkendig.info", StringComparison.OrdinalIgnoreCase)
			|| uri.Host.EndsWith(".davidkendig.info", StringComparison.OrdinalIgnoreCase);
	}

	static async Task<List<NewsItem>> FetchRestAsync(string category)
	{
		var url = $"{Site}/wp-json/wp/v2/posts?per_page={PostCount}&_fields=id,date,link,title,excerpt";
		if (category != "all")
		{
			var cats = Json.Parse(await Http.GetStringAsync($"{Site}/wp-json/wp/v2/categories?slug={Uri.EscapeDataString(category)}&_fields=id")) as object[];
			if (cats == null || cats.Length == 0)
				throw new InvalidDataException($"The site has no \"{category}\" category");
			url += "&categories=" + Json.Str(cats[0], "id");
		}
		if (Json.Parse(await Http.GetStringAsync(url)) is not object[] posts)
			throw new InvalidDataException("Unexpected response from the site");
		var items = new List<NewsItem>();
		foreach (var post in posts)
		{
			DateTime.TryParse(Json.Str(post, "date"), CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal, out var date);
			items.Add(new NewsItem
			{
				Title = Clean(Json.Str(post, "title", "rendered"), 140),
				Excerpt = Clean(Json.Str(post, "excerpt", "rendered"), 320),
				Link = Json.Str(post, "link") ?? Site,
				Date = date,
			});
		}
		return items;
	}

	static async Task<List<NewsItem>> FetchRssAsync(string category)
	{
		var url = category == "all" ? $"{Site}/feed/" : $"{Site}/category/{Uri.EscapeDataString(category)}/feed/";
		var doc = XDocument.Parse(await Http.GetStringAsync(url));
		return doc.Descendants("item").Take(PostCount).Select(item =>
		{
			DateTime.TryParse((string?)item.Element("pubDate"), CultureInfo.InvariantCulture, DateTimeStyles.None, out var date);
			return new NewsItem
			{
				Title = Clean((string?)item.Element("title"), 140),
				Excerpt = Clean((string?)item.Element("description"), 320),
				Link = (string?)item.Element("link") ?? Site,
				Date = date,
			};
		}).ToList();
	}

	/** Strips HTML, decodes entities and trims to a readable length. **/
	static string Clean(string? html, int maxLength)
	{
		if (string.IsNullOrEmpty(html))
			return "";
		var text = Regex.Replace(html, "<[^>]+>", " ");
		text = WebUtility.HtmlDecode(text);
		text = Regex.Replace(text, @"\s+", " ").Trim();
		text = text.Replace("[…]", "…").Replace("[...]", "…");
		if (text.Length > maxLength)
		{
			var cut = text.LastIndexOf(' ', maxLength);
			text = text.Substring(0, cut > maxLength / 2 ? cut : maxLength).TrimEnd(',', '.', ';', ':') + "…";
		}
		return text;
	}

	static void SaveCache(List<NewsItem> items)
	{
		try
		{
			var list = items.Select(i => new Dictionary<string, object>
			{
				["title"] = i.Title,
				["excerpt"] = i.Excerpt,
				["link"] = i.Link,
				["date"] = i.Date.ToString("o", CultureInfo.InvariantCulture),
			}).ToArray();
			var d = new Dictionary<string, object>
			{
				["fetchedAt"] = DateTime.Now.ToString("o", CultureInfo.InvariantCulture),
				["items"] = list,
			};
			File.WriteAllText(Paths.NewsCache, Json.Write(d));
		}
		catch (Exception e)
		{
			Log.Write("Couldn't cache news: " + e.Message);
		}
	}

	static NewsResult? LoadCache()
	{
		try
		{
			if (!File.Exists(Paths.NewsCache))
				return null;
			var d = Json.Parse(File.ReadAllText(Paths.NewsCache));
			DateTime.TryParse(Json.Str(d, "fetchedAt"), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var fetched);
			var result = new NewsResult { FetchedAt = fetched };
			if (Json.Get(d, "items") is object[] items)
				foreach (var i in items)
				{
					DateTime.TryParse(Json.Str(i, "date"), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var date);
					result.Items.Add(new NewsItem
					{
						Title = Json.Str(i, "title") ?? "",
						Excerpt = Json.Str(i, "excerpt") ?? "",
						Link = Json.Str(i, "link") ?? Site,
						Date = date,
					});
				}
			return result;
		}
		catch
		{
			return null;
		}
	}
}
