// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace CrownAndCard.Launcher;

/**
	Custom maps made in Haxen, one JSON file each in %LOCALAPPDATA%\CrownAndCard\maps
	(GAME_DESIGN.md §13.6). The file name is the map's name, so names are kept
	to letters, digits, spaces, dashes and underscores.
**/
sealed class MapStore
{
	public const int MaxBytes = 512 * 1024;
	static readonly Regex NamePattern = new("^[A-Za-z0-9 _-]{1,40}$");

	readonly string dir;
	readonly object gate = new();

	public MapStore(string dir) { this.dir = dir; }

	public string Folder => dir;

	/** "manor" is the built-in map's reserved name. **/
	public static bool ValidName(string? name) =>
		name != null && NamePattern.IsMatch(name) && name.Trim() == name && !name.Equals("manor", StringComparison.OrdinalIgnoreCase);

	public List<string> List()
	{
		lock (gate)
		{
			if (!Directory.Exists(dir)) return [];
			return Directory.GetFiles(dir, "*.json")
				.Select(Path.GetFileNameWithoutExtension)
				.Where(ValidName)
				.OrderBy(n => n, StringComparer.OrdinalIgnoreCase)
				.ToList();
		}
	}

	public string? Read(string name)
	{
		if (!ValidName(name)) return null;
		lock (gate)
		{
			var path = PathFor(name);
			return File.Exists(path) ? File.ReadAllText(path) : null;
		}
	}

	/** Saves a map file. Throws ArgumentException for a bad name or anything that isn't a map. **/
	public void Write(string name, string json)
	{
		if (!ValidName(name)) throw new ArgumentException("Invalid map name");
		if (Encoding.UTF8.GetByteCount(json) > MaxBytes) throw new ArgumentException("Map is too large");
		if (Json.Obj(Json.Parse(json)) is not { } map || Json.Str(map, "format") != "crown-and-card-map" || Json.Get(map, "rows") is not object[])
			throw new ArgumentException("Not a Crown & Card map");
		lock (gate)
		{
			Directory.CreateDirectory(dir);
			var path = PathFor(name);
			File.WriteAllText(path + ".tmp", json, new UTF8Encoding(false));
			if (File.Exists(path)) File.Replace(path + ".tmp", path, null);
			else File.Move(path + ".tmp", path);
		}
	}

	public bool Delete(string name)
	{
		if (!ValidName(name)) return false;
		lock (gate)
		{
			var path = PathFor(name);
			if (!File.Exists(path)) return false;
			File.Delete(path);
			return true;
		}
	}

	string PathFor(string name) => Path.Combine(dir, name + ".json");
}
