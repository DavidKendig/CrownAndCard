// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Web.Script.Serialization;

namespace CrownAndCard.Launcher;

/**
	Small JSON helpers over .NET Framework's JavaScriptSerializer. Parsed
	objects are Dictionary<string, object>, arrays are object[].
**/
static class Json
{
	static readonly JavaScriptSerializer Serializer = new() { MaxJsonLength = 16 * 1024 * 1024, RecursionLimit = 64 };

	public static object? Parse(string text) => Serializer.DeserializeObject(text);

	public static string Write(object? value, bool indent = true)
	{
		var compact = Serializer.Serialize(value);
		return indent ? Indent(compact) : compact;
	}

	public static Dictionary<string, object>? Obj(object? value) => value as Dictionary<string, object>;

	/** Follows a path of keys through nested objects. **/
	public static object? Get(object? value, params string[] path)
	{
		foreach (var key in path)
		{
			if (value is not Dictionary<string, object> d || !d.TryGetValue(key, out value))
				return null;
		}
		return value;
	}

	public static string? Str(object? value, params string[] path)
	{
		var v = Get(value, path);
		return v == null ? null : Convert.ToString(v, CultureInfo.InvariantCulture);
	}

	public static int Int(object? value, int fallback, params string[] path)
	{
		var v = Get(value, path);
		try
		{
			return v == null ? fallback : Convert.ToInt32(v, CultureInfo.InvariantCulture);
		}
		catch
		{
			return fallback;
		}
	}

	/** Re-indents compact JSON for human-readable report files. **/
	static string Indent(string json)
	{
		var sb = new StringBuilder(json.Length * 2);
		int depth = 0;
		bool inString = false, escaped = false;
		for (int i = 0; i < json.Length; i++)
		{
			char c = json[i];
			if (inString)
			{
				sb.Append(c);
				if (escaped) escaped = false;
				else if (c == '\\') escaped = true;
				else if (c == '"') inString = false;
				continue;
			}
			switch (c)
			{
				case '"':
					inString = true;
					sb.Append(c);
					break;
				case '{':
				case '[':
					char close = c == '{' ? '}' : ']';
					if (i + 1 < json.Length && json[i + 1] == close)
					{
						sb.Append(c).Append(close);
						i++;
						break;
					}
					sb.Append(c).Append('\n').Append(' ', ++depth * 2);
					break;
				case '}':
				case ']':
					sb.Append('\n').Append(' ', --depth * 2).Append(c);
					break;
				case ',':
					sb.Append(c).Append('\n').Append(' ', depth * 2);
					break;
				case ':':
					sb.Append(": ");
					break;
				default:
					sb.Append(c);
					break;
			}
		}
		return sb.ToString();
	}
}
