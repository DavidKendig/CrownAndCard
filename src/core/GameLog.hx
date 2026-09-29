// SPDX-License-Identifier: AGPL-3.0-or-later
package core;

/**
	The game's log (§13.12). The browser build had the developer console; the
	native window has none, so everything worth knowing comes through here:
	`trace`, window and controller changes (WindowWatch), and uncaught errors
	with their stack.

	- Each line reads `HH:MM:SS.mmm LEVEL [tag] message`; a stack follows on
	  indented lines. The launcher parses this format (GameLogParser.cs), so
	  keep the two in step.
	- Under the launcher it goes to standard output, which the launcher records
	  with the session and shows live in its game log window.
	- Run on its own, it also goes to %LOCALAPPDATA%\CrownAndCard\logs\game.log
	  (the previous run's is kept as game.prev.log).
	- In the browser it goes to the console.
	- Errors are handed to `onError` (Telemetry). An error that repeats every
	  frame is logged at most every few seconds, with a count.
**/
class GameLog {
	static inline var REPEAT_SECONDS = 5.0;

	/** Called for each error that gets logged (not for suppressed repeats). **/
	public static var onError:(message:String, stack:Null<String>) -> Void = (_, _) -> {};

	static var lastError = "";
	static var lastErrorAt = -1e9;
	static var repeats = 0;

	#if sys
	static var file:Null<sys.io.FileOutput>;
	#end

	/** Hooks `trace` and, on native builds, uncaught errors. Call first thing. **/
	public static function init(underLauncher:Bool):Void {
		#if sys
		if (!underLauncher) openFile();
		#end
		haxe.Log.trace = (v, ?pos) -> {
			var text = Std.string(v);
			if (pos != null && pos.customParams != null) text += " " + pos.customParams.join(" ");
			info(pos == null ? "trace" : haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(pos.fileName)), text);
		};
		#if hl
		var standard = hxd.System.reportError;
		hxd.System.reportError = e -> {
			var exc = Std.downcast(e, haxe.Exception);
			var stack = haxe.CallStack.toString(exc != null ? exc.stack : haxe.CallStack.exceptionStack());
			var message = try Std.string(e) catch (_:Dynamic) "(unprintable error)";
			error("uncaught", message, stack);
			// On its own, Heaps' Continue / Dismiss all / Exit box; under the launcher, its log window shows it instead.
			if (!underLauncher) standard(e);
		};
		#end
		info("log", 'Crown & Card ${Version.CURRENT}, ${target()} build' + (underLauncher ? ", started by the launcher" : ""));
	}

	public static function info(tag:String, message:String):Void
		write("INFO", tag, message);

	public static function warn(tag:String, message:String):Void
		write("WARN", tag, message);

	public static function error(tag:String, message:String, ?stack:String):Void {
		var now = haxe.Timer.stamp();
		if (message == lastError && now - lastErrorAt < REPEAT_SECONDS) {
			repeats++;
			return;
		}
		flushRepeats();
		lastError = message;
		lastErrorAt = now;
		write("ERROR", tag, message, stack);
		try onError(message, stack) catch (_:Dynamic) {}
	}

	/** Call once a frame: writes the count of a repeating error once it has had a few quiet seconds. **/
	public static function tick():Void {
		if (repeats > 0 && haxe.Timer.stamp() - lastErrorAt >= REPEAT_SECONDS) flushRepeats();
	}

	/** Writes anything held back (a repeat count). Call before the game exits. **/
	public static function flush():Void
		flushRepeats();

	static function flushRepeats():Void {
		if (repeats == 0) return;
		var n = repeats;
		repeats = 0;
		write("WARN", "log", '"$lastError" happened $n more time' + (n == 1 ? "" : "s"));
	}

	static function write(level:String, tag:String, message:String, ?stack:String):Void {
		var line = '${clock()} ${StringTools.rpad(level, " ", 5)} [$tag] ' + message.split("\r").join("").split("\n").join("\n    ");
		if (stack != null && StringTools.trim(stack) != "")
			for (frame in StringTools.trim(stack).split("\n")) line += "\n    " + StringTools.trim(frame);
		#if js
		switch (level) {
			case "ERROR": js.Browser.console.error(line);
			case "WARN": js.Browser.console.warn(line);
			default: js.Browser.console.log(line);
		}
		#elseif sys
		try {
			var out = Sys.stdout();
			out.writeString(line + "\n", UTF8);
			out.flush();
		} catch (_:Dynamic) {}
		if (file != null) try {
			file.writeString(line + "\n", UTF8);
			file.flush();
		} catch (_:Dynamic) file = null;
		#end
	}

	/** Local wall-clock time with milliseconds. **/
	static function clock():String {
		var ms = #if sys Sys.time() * 1000 #else Date.now().getTime() #end;
		var d = Date.fromTime(ms);
		inline function two(n:Int) return StringTools.lpad(Std.string(n), "0", 2);
		return '${two(d.getHours())}:${two(d.getMinutes())}:${two(d.getSeconds())}.' + StringTools.lpad(Std.string(Std.int(ms % 1000)), "0", 3);
	}

	static function target():String
		return #if hl "native (HashLink)" #elseif js "web" #else "unknown" #end;

	#if sys
	static function openFile():Void {
		try {
			var root = Sys.getEnv("LOCALAPPDATA");
			if (root == null) root = Sys.getEnv("HOME");
			if (root == null) return;
			var dir = haxe.io.Path.join([root, "CrownAndCard", "logs"]);
			sys.FileSystem.createDirectory(dir);
			var path = haxe.io.Path.join([dir, "game.log"]), previous = haxe.io.Path.join([dir, "game.prev.log"]);
			if (sys.FileSystem.exists(path)) {
				if (sys.FileSystem.exists(previous)) sys.FileSystem.deleteFile(previous);
				sys.FileSystem.rename(path, previous);
			}
			file = sys.io.File.write(path, false);
		} catch (_:Dynamic) {
			file = null;
		}
	}
	#end
}
