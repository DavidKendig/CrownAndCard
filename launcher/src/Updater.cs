// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using System.Threading.Tasks;

namespace CrownAndCard.Launcher;

/** The newest release on GitHub. **/
sealed class ReleaseInfo
{
	public string Version = "";
	public string PageUrl = "";
	public string AssetName = "";
	public string AssetUrl = "";
	public long AssetSize;
	public string? Sha256;
}

/**
	Keeps the local copy in step with https://github.com/DavidKendig/CrownAndCard (§13.12).

	- Releases are tagged `v0.YY.BBB` and carry `CrownAndCard-0.YY.BBB-win64.zip`
	  (built by `launcher\build.ps1 -Package`).
	- A newer release is downloaded, checked against the SHA-256 digest GitHub
	  publishes for the asset, unpacked, and swapped in with a rollback copy.
	  Then the new launcher starts and the old one exits.
	- A development copy (inside a git checkout) is never overwritten; it's only
	  told that a newer release exists.
**/
static class Updater
{
	public const string Repo = "DavidKendig/CrownAndCard";
	const string ExeName = "CrownAndCardLauncher.exe";

	/** Overridden only by `--update-feed=http://127.0.0.1:…` for testing the updater locally. **/
	public static string FeedUrl = $"https://api.github.com/repos/{Repo}/releases/latest";

	static readonly HttpClient Http = CreateClient();

	static HttpClient CreateClient()
	{
		var http = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
		http.DefaultRequestHeaders.UserAgent.ParseAdd($"CrownAndCardLauncher/{Program.Version} (+https://github.com/{Repo})");
		return http;
	}

	/** Returns the latest release, or null when the repo has none yet. **/
	public static async Task<ReleaseInfo?> CheckAsync()
	{
		using var request = new HttpRequestMessage(HttpMethod.Get, FeedUrl);
		request.Headers.Accept.ParseAdd("application/vnd.github+json");
		using var response = await Http.SendAsync(request);
		if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
			return null;
		response.EnsureSuccessStatusCode();
		var release = Json.Parse(await response.Content.ReadAsStringAsync());
		var tag = Json.Str(release, "tag_name") ?? "";
		var info = new ReleaseInfo
		{
			Version = tag.TrimStart('v', 'V'),
			PageUrl = Json.Str(release, "html_url") ?? $"https://github.com/{Repo}/releases",
		};
		if (Parse(info.Version) == null)
			throw new InvalidDataException($"The latest release's tag \"{tag}\" isn't a 0.YY.BBB version");
		var assets = Json.Get(release, "assets") as object[] ?? [];
		var zip = assets.FirstOrDefault(a => (Json.Str(a, "name") ?? "").EndsWith("-win64.zip", StringComparison.OrdinalIgnoreCase));
		if (zip != null)
		{
			info.AssetName = Json.Str(zip, "name") ?? "";
			info.AssetUrl = Json.Str(zip, "browser_download_url") ?? "";
			info.AssetSize = long.TryParse(Json.Str(zip, "size"), out var size) ? size : 0;
			var digest = Json.Str(zip, "digest");
			if (digest != null && digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase))
				info.Sha256 = digest.Substring(7).ToLowerInvariant();
			// Older releases without a digest can carry "<zip>.sha256" instead.
			var sidecar = assets.FirstOrDefault(a => Json.Str(a, "name") == info.AssetName + ".sha256");
			if (info.Sha256 == null && sidecar != null)
				info.Sha256 = (await Http.GetStringAsync(Json.Str(sidecar, "browser_download_url"))).Trim().Split(' ')[0].ToLowerInvariant();
		}
		return info;
	}

	/** True when `remote` is a later 0.YY.BBB version than `local`. **/
	public static bool IsNewer(string remote, string local)
	{
		var r = Parse(remote);
		var l = Parse(local);
		if (r == null || l == null)
			return false;
		for (int i = 0; i < 3; i++)
			if (r[i] != l[i])
				return r[i] > l[i];
		return false;
	}

	static int[]? Parse(string version)
	{
		var parts = version.Split('.');
		if (parts.Length != 3)
			return null;
		var n = new int[3];
		for (int i = 0; i < 3; i++)
			if (!int.TryParse(parts[i], out n[i]) || n[i] < 0)
				return null;
		return n;
	}

	/** Why this copy can't update itself in place (null if it can). **/
	public static string? CannotSelfUpdateReason()
	{
		for (var d = new DirectoryInfo(Paths.ExeDir); d != null; d = d.Parent)
			if (Directory.Exists(Path.Combine(d.FullName, ".git")))
				return "this is a development copy inside a git checkout (use git pull)";
		if (!File.Exists(Path.Combine(Paths.ExeDir, "web", "index.html")) && !File.Exists(Path.Combine(Paths.ExeDir, "CrownAndCard.exe")))
			return "the launcher isn't in an installed game folder";
		return null;
	}

	/**
		Downloads, verifies and installs `release`, then starts the new launcher.
		The caller should exit right after this returns. Rolls back on failure.
	**/
	public static async Task InstallAsync(ReleaseInfo release, IProgress<string> progress)
	{
		if (release.AssetUrl.Length == 0)
			throw new InvalidDataException($"Release {release.Version} has no Windows download");
		if (release.Sha256 == null)
			throw new InvalidDataException($"Release {release.Version} has no SHA-256 digest, so it can't be verified");
		if (!IsAllowedDownload(release.AssetUrl))
			throw new InvalidDataException("Refusing to download from " + release.AssetUrl);

		var work = Path.Combine(Paths.DataDir, "updates", release.Version);
		if (Directory.Exists(work))
			Directory.Delete(work, true);
		Directory.CreateDirectory(work);
		var zipPath = Path.Combine(work, release.AssetName);

		progress.Report($"Downloading {release.Version}…");
		using (var response = await Http.GetAsync(release.AssetUrl, HttpCompletionOption.ResponseHeadersRead))
		{
			response.EnsureSuccessStatusCode();
			using var file = File.Create(zipPath);
			await response.Content.CopyToAsync(file);
		}
		if (release.AssetSize > 0 && new FileInfo(zipPath).Length != release.AssetSize)
			throw new InvalidDataException("The download is the wrong size");
		progress.Report("Verifying…");
		if (Sha256Of(zipPath) != release.Sha256)
			throw new InvalidDataException("The download doesn't match its published SHA-256 digest");

		progress.Report("Unpacking…");
		var staging = Path.Combine(work, "staging");
		Extract(zipPath, staging);
		if (!File.Exists(Path.Combine(staging, ExeName)))
			throw new InvalidDataException($"The release doesn't contain {ExeName}");

		progress.Report($"Installing {release.Version}…");
		Swap(staging, Paths.ExeDir, Path.Combine(work, "backup"));
		Process.Start(new ProcessStartInfo(Path.Combine(Paths.ExeDir, ExeName), $"--updated-from={Program.Version}")
		{
			UseShellExecute = false,
			WorkingDirectory = Paths.ExeDir,
		});
	}

	/** Deletes the previous launcher left behind by an update. **/
	public static void CleanUpAfterUpdate()
	{
		var old = Path.Combine(Paths.ExeDir, ExeName + ".old");
		for (int attempt = 0; attempt < 20 && File.Exists(old); attempt++)
		{
			try
			{
				File.Delete(old);
			}
			catch
			{
				System.Threading.Thread.Sleep(250); // the old launcher may still be closing
			}
		}
	}

	static bool IsAllowedDownload(string url)
	{
		if (!Uri.TryCreate(url, UriKind.Absolute, out var uri))
			return false;
		if (uri.Scheme == Uri.UriSchemeHttps && uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase))
			return true;
		// Local test feeds only (see FeedUrl).
		return uri.Scheme == Uri.UriSchemeHttp && uri.Host == "127.0.0.1" && FeedUrl.StartsWith("http://127.0.0.1:", StringComparison.Ordinal);
	}

	static void Extract(string zipPath, string destination)
	{
		var root = Path.GetFullPath(destination).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
		using var zip = ZipFile.OpenRead(zipPath);
		foreach (var entry in zip.Entries)
		{
			var target = Path.GetFullPath(Path.Combine(root, entry.FullName));
			if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase))
				throw new InvalidDataException("The release zip contains an unsafe path: " + entry.FullName);
			if (entry.FullName.EndsWith("/") || entry.FullName.EndsWith("\\"))
			{
				Directory.CreateDirectory(target);
				continue;
			}
			Directory.CreateDirectory(Path.GetDirectoryName(target)!);
			entry.ExtractToFile(target, true);
		}
	}

	/**
		Copies every staged file into the install folder. The running launcher
		can't be overwritten, but it can be renamed, so it moves aside to
		`.old` first. Everything replaced is backed up and restored on failure.
	**/
	static void Swap(string staging, string install, string backup)
	{
		var files = Directory.GetFiles(staging, "*", SearchOption.AllDirectories)
			.Select(f => f.Substring(staging.Length).TrimStart(Path.DirectorySeparatorChar)).ToList();
		var exe = Path.Combine(install, ExeName);
		var oldExe = exe + ".old";
		var replaced = new List<string>();
		var added = new List<string>();
		if (File.Exists(oldExe))
			File.Delete(oldExe);
		File.Move(exe, oldExe);
		try
		{
			foreach (var rel in files)
			{
				var target = Path.Combine(install, rel);
				if (rel.Equals(ExeName, StringComparison.OrdinalIgnoreCase))
				{
					File.Copy(Path.Combine(staging, rel), target);
					continue;
				}
				if (File.Exists(target))
				{
					var saved = Path.Combine(backup, rel);
					Directory.CreateDirectory(Path.GetDirectoryName(saved)!);
					File.Copy(target, saved, true);
					replaced.Add(rel);
				}
				else
					added.Add(rel);
				Directory.CreateDirectory(Path.GetDirectoryName(target)!);
				File.Copy(Path.Combine(staging, rel), target, true);
			}
		}
		catch
		{
			foreach (var rel in replaced)
				TryCopy(Path.Combine(backup, rel), Path.Combine(install, rel));
			foreach (var rel in added)
				TryDelete(Path.Combine(install, rel));
			TryDelete(exe);
			File.Move(oldExe, exe);
			throw;
		}
	}

	static void TryCopy(string from, string to)
	{
		try { File.Copy(from, to, true); } catch (Exception e) { Log.Write($"Rollback copy failed ({to}): {e.Message}"); }
	}

	static void TryDelete(string path)
	{
		try { if (File.Exists(path)) File.Delete(path); } catch (Exception e) { Log.Write($"Rollback delete failed ({path}): {e.Message}"); }
	}

	static string Sha256Of(string path)
	{
		using var sha = SHA256.Create();
		using var file = File.OpenRead(path);
		return BitConverter.ToString(sha.ComputeHash(file)).Replace("-", "").ToLowerInvariant();
	}
}
