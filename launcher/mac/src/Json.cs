// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Text.Json;

namespace CrownAndCard.Launcher;

/**
	The Mac build's JSON helpers: the same API as ../src/Json.cs, which sits on
	.NET Framework's JavaScriptSerializer (not in modern .NET). Parsed values
	have the same shapes it produces, so the shared code reads them alike:
	objects are Dictionary<string, object>, arrays are object[], whole numbers
	are int (or long, then decimal, when too big), other numbers decimal.
**/
static class Json
{
	static readonly JsonDocumentOptions Options = new() { MaxDepth = 64, AllowTrailingCommas = false, CommentHandling = JsonCommentHandling.Disallow };

	/** Throws ArgumentException on malformed JSON, as JavaScriptSerializer does. **/
	public static object? Parse(string text)
	{
		try
		{
			using var doc = JsonDocument.Parse(text, Options);
			return Convert(doc.RootElement);
		}
		catch (JsonException e)
		{
			throw new ArgumentException("Invalid JSON: " + e.Message, e);
		}
	}

	static object? Convert(JsonElement e)
	{
		switch (e.ValueKind)
		{
			case JsonValueKind.Object:
				var d = new Dictionary<string, object>();
				foreach (var p in e.EnumerateObject())
					d[p.Name] = Convert(p.Value)!;
				return d;
			case JsonValueKind.Array:
				var list = new List<object>();
				foreach (var item in e.EnumerateArray())
					list.Add(Convert(item)!);
				return list.ToArray();
			case JsonValueKind.String:
				return e.GetString();
			case JsonValueKind.Number:
				if (e.TryGetInt32(out var i)) return i;
				if (e.TryGetInt64(out var l)) return l;
				if (e.TryGetDecimal(out var m)) return m;
				return e.GetDouble();
			case JsonValueKind.True:
				return true;
			case JsonValueKind.False:
				return false;
			default:
				return null;
		}
	}

	public static string Write(object? value, bool indent = true)
	{
		var sb = new StringBuilder();
		WriteValue(sb, value, 0);
		var compact = sb.ToString();
		return indent ? Indent(compact) : compact;
	}

	static void WriteValue(StringBuilder sb, object? value, int depth)
	{
		if (depth > 64)
			throw new InvalidOperationException("JSON nesting is too deep");
		switch (value)
		{
			case null:
				sb.Append("null");
				break;
			case string s:
				WriteString(sb, s);
				break;
			case bool b:
				sb.Append(b ? "true" : "false");
				break;
			case char c:
				WriteString(sb, c.ToString());
				break;
			case int or long or short or byte or sbyte or uint or ulong or ushort:
				sb.Append(System.Convert.ToString(value, CultureInfo.InvariantCulture));
				break;
			case decimal m:
				sb.Append(m.ToString(CultureInfo.InvariantCulture));
				break;
			case double d:
				sb.Append(double.IsFinite(d) ? d.ToString("R", CultureInfo.InvariantCulture) : "null");
				break;
			case float f:
				sb.Append(float.IsFinite(f) ? f.ToString("R", CultureInfo.InvariantCulture) : "null");
				break;
			case DateTime t:
				WriteString(sb, t.ToString("o", CultureInfo.InvariantCulture));
				break;
			case Enum en:
				sb.Append(System.Convert.ToInt64(en, CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture));
				break;
			case IDictionary dict:
				sb.Append('{');
				bool first = true;
				foreach (DictionaryEntry kv in dict)
				{
					if (!first) sb.Append(',');
					first = false;
					WriteString(sb, System.Convert.ToString(kv.Key, CultureInfo.InvariantCulture) ?? "");
					sb.Append(':');
					WriteValue(sb, kv.Value, depth + 1);
				}
				sb.Append('}');
				break;
			case IEnumerable items:
				sb.Append('[');
				bool firstItem = true;
				foreach (var item in items)
				{
					if (!firstItem) sb.Append(',');
					firstItem = false;
					WriteValue(sb, item, depth + 1);
				}
				sb.Append(']');
				break;
			default:
				WriteString(sb, System.Convert.ToString(value, CultureInfo.InvariantCulture) ?? "");
				break;
		}
	}

	static void WriteString(StringBuilder sb, string s)
	{
		sb.Append('"');
		foreach (var c in s)
		{
			switch (c)
			{
				case '"': sb.Append("\\\""); break;
				case '\\': sb.Append("\\\\"); break;
				case '\n': sb.Append("\\n"); break;
				case '\r': sb.Append("\\r"); break;
				case '\t': sb.Append("\\t"); break;
				case '\b': sb.Append("\\b"); break;
				case '\f': sb.Append("\\f"); break;
				// Like JavaScriptSerializer: safe to drop into HTML.
				case '<' or '>' or '&' or '\'':
					sb.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
					break;
				default:
					if (c < ' ')
						sb.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
					else
						sb.Append(c);
					break;
			}
		}
		sb.Append('"');
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
		return v == null ? null : System.Convert.ToString(v, CultureInfo.InvariantCulture);
	}

	public static int Int(object? value, int fallback, params string[] path)
	{
		var v = Get(value, path);
		try
		{
			return v == null ? fallback : System.Convert.ToInt32(v, CultureInfo.InvariantCulture);
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
