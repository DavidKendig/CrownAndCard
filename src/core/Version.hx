// SPDX-License-Identifier: AGPL-3.0-or-later
package core;

/**
	The build version, 0.YY.BBB (two-digit year, then build number), read from
	version.json at compile time so the game, launcher and releases agree.
	Bump it with `python tools/version.py bump`.
**/
class Version {
	#if !macro
	public static final CURRENT:String = read();
	#end

	static macro function read():haxe.macro.Expr {
		var file = "version.json";
		haxe.macro.Context.registerModuleDependency("core.Version", file);
		var version:String = haxe.Json.parse(sys.io.File.getContent(file)).version;
		return macro $v{version};
	}
}
