// SPDX-License-Identifier: AGPL-3.0-or-later
package core;

/**
	Reads the options the launcher passes in: `--key=value` command-line
	arguments on native builds, or the page's URL query on the web build.
	Both use the same keys (see Settings and Telemetry).
**/
class LaunchOptions {
	public static function read():Map<String, String> {
		var out = new Map<String, String>();
		#if js
		var query = js.Browser.location.search;
		if (query.length > 1)
			for (pair in query.substr(1).split("&")) {
				var eq = pair.indexOf("=");
				var key = eq < 0 ? pair : pair.substr(0, eq);
				var value = eq < 0 ? "1" : pair.substr(eq + 1);
				out.set(StringTools.urlDecode(key), StringTools.urlDecode(value));
			}
		#elseif sys
		for (arg in Sys.args()) {
			if (!StringTools.startsWith(arg, "--"))
				continue;
			var eq = arg.indexOf("=");
			if (eq < 0)
				out.set(arg.substr(2), "1");
			else
				out.set(arg.substr(2, eq - 2), arg.substr(eq + 1));
		}
		#end
		return out;
	}
}
