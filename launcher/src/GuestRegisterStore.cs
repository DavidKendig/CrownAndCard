// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace CrownAndCard.Launcher;

/** Stable, atomic checkpoint storage, independent of the local web server's port. */
sealed class GuestRegisterStore
{
	readonly string path;
	readonly object gate = new();
	public GuestRegisterStore(string path) { this.path = path; }
	public string Read() { lock (gate) return File.Exists(path) ? File.ReadAllText(path) : "null"; }
	public void Write(string json)
	{
		if (json.Length > 65536) throw new ArgumentException("Guest Register is too large");
		var value = Json.Parse(json) as Dictionary<string, object>;
		if (value == null || !value.TryGetValue("version", out var version) || !(version is int v) || v != 1
			|| !value.TryGetValue("checkIns", out var count) || !(count is int n) || n < 0
			|| !value.TryGetValue("rooms", out var rooms) || !(rooms is object[] list))
			throw new ArgumentException("Invalid Guest Register");
		foreach (var room in list) if (!(room is string)) throw new ArgumentException("Invalid room");
		// The purse and Pemberton's marker are optional (older pages don't have them).
		foreach (var field in new[] { "sovereigns", "marker" })
			if (value.TryGetValue(field, out var amount) && !(amount is int a && a >= 0))
				throw new ArgumentException("Invalid " + field);
		lock (gate)
		{
			Directory.CreateDirectory(Path.GetDirectoryName(path)!);
			File.WriteAllText(path + ".tmp", json, new UTF8Encoding(false));
			if (File.Exists(path)) File.Replace(path + ".tmp", path, path + ".bak", true);
			else File.Move(path + ".tmp", path);
		}
	}
}
