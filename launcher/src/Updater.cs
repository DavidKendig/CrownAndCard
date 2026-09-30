// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Diagnostics;
using System.IO;
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
	public string SetupName = "";
	public string SetupUrl = "";
	public long SetupSize;
	public string? Sha256;
}

/**
	Keeps the local copy in step with https://github.com/DavidKendig/CrownAndCard (§13.12).

	- Releases are tagged `v0.YY.BBB` and carry `CrownAndCard-Setup-0.YY.BBB.exe`
	  (the Inno Setup installer built by `launcher\build.ps1 -Package`).
	- When a newer release exists, the player chooses to install it. The launcher
	  downloads the setup, checks it against the SHA-256 digest GitHub publishes,
	  runs it and exits; the installer replaces the files and restarts the
	  launcher. The launcher never rewrites or relaunches its own exe, which
	  behavior-based antivirus treats as suspicious.
	- A development copy (inside a git checkout) only reports the new version.
**/
static class Updater
{
	public const string Repo = "DavidKendig/CrownAndCard";
	const string FeedUrl = $"https://api.github.com/repos/{Repo}/releases/latest";

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
		var setup = assets.FirstOrDefault(a =>
		{
			var name = Json.Str(a, "name") ?? "";
			return name.StartsWith("CrownAndCard-Setup-", StringComparison.OrdinalIgnoreCase) && name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase);
		});
		if (setup != null)
		{
			info.SetupName = Json.Str(setup, "name") ?? "";
			info.SetupUrl = Json.Str(setup, "browser_download_url") ?? "";
			info.SetupSize = long.TryParse(Json.Str(setup, "size"), out var size) ? size : 0;
			var digest = Json.Str(setup, "digest");
			if (digest != null && digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase))
				info.Sha256 = digest.Substring(7).ToLowerInvariant();
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

	/** Why this copy shouldn't be updated by the installer (null if it can). **/
	public static string? CannotUpdateReason()
	{
		for (var d = new DirectoryInfo(Paths.ExeDir); d != null; d = d.Parent)
			if (Directory.Exists(Path.Combine(d.FullName, ".git")))
				return "this is a development copy inside a git checkout (use git pull)";
#if MACOS
		return "releases carry a Windows installer only; update the Mac copy by hand";
#else
		return null;
#endif
	}

	/**
		Downloads and verifies the release's installer, then starts it. The caller
		should exit straight after, so the installer can replace the launcher.
	**/
	public static async Task DownloadAndRunSetupAsync(ReleaseInfo release, IProgress<string> progress)
	{
		if (release.SetupUrl.Length == 0)
			throw new InvalidDataException($"Release {release.Version} has no installer");
		if (release.Sha256 == null)
			throw new InvalidDataException($"Release {release.Version} has no SHA-256 digest, so it can't be verified");
		if (!Uri.TryCreate(release.SetupUrl, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps
			|| !uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase))
			throw new InvalidDataException("Refusing to download from " + release.SetupUrl);

		var folder = Path.Combine(Paths.DataDir, "updates");
		Directory.CreateDirectory(folder);
		var path = Path.Combine(folder, release.SetupName);
		progress.Report($"Downloading {release.Version}…");
		using (var response = await Http.GetAsync(release.SetupUrl, HttpCompletionOption.ResponseHeadersRead))
		{
			response.EnsureSuccessStatusCode();
			using var file = File.Create(path);
			await response.Content.CopyToAsync(file);
		}
		progress.Report("Verifying…");
		if (release.SetupSize > 0 && new FileInfo(path).Length != release.SetupSize)
			throw new InvalidDataException("The download is the wrong size");
		if (Sha256Of(path) != release.Sha256)
		{
			File.Delete(path);
			throw new InvalidDataException("The download doesn't match its published SHA-256 digest");
		}
		progress.Report($"Starting the {release.Version} installer…");
		// The installer shows its own window, closes nothing by force, and restarts the launcher when done.
		Process.Start(new ProcessStartInfo(path, $"/DIR=\"{Paths.ExeDir}\"") { UseShellExecute = true });
	}

	static string Sha256Of(string path)
	{
		using var sha = SHA256.Create();
		using var file = File.OpenRead(path);
		return BitConverter.ToString(sha.ComputeHash(file)).Replace("-", "").ToLowerInvariant();
	}
}
