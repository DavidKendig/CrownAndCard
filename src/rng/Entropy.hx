// SPDX-License-Identifier: AGPL-3.0-or-later
package rng;

import haxe.crypto.Sha256;
import haxe.io.Bytes;

/**
	Unpredictable seed bytes from the operating system (§7.6).
**/
class Entropy {
	/**
		False if the platform had no OS random source and a timing-based
		fallback was used. Release builds must never ship with this false.
	**/
	public static var isStrong(default, null) = true;

	public static function bytes(count:Int):Bytes {
		#if js
		var data = new js.lib.Uint8Array(count);
		js.Syntax.code("globalThis.crypto.getRandomValues({0})", data);
		return Bytes.ofData(data.buffer);
		#elseif sys
		// TODO(hl): call BCryptGenRandom / getrandom / SecRandomCopyBytes through
		// a small HashLink native extension. Until then, native builds use this
		// weak fallback and report isStrong = false.
		isStrong = false;
		return timingFallback(count);
		#else
		#error "Entropy: no random source for this target"
		#end
	}

	#if sys
	/** Makes back-to-back fallback seeds differ even within the same timer tick. **/
	static var fallbackCalls = 0;

	static function timingFallback(count:Int):Bytes {
		var out = Bytes.alloc(count);
		var seed = '${fallbackCalls++}|${Sys.time()}|${Sys.cpuTime()}|${haxe.Timer.stamp()}|${Date.now().getTime()}';
		var filled = 0;
		var round = 0;
		while (filled < count) {
			var block = Sha256.make(Bytes.ofString('$seed|$round|${haxe.Timer.stamp()}'));
			var n = count - filled < block.length ? count - filled : block.length;
			out.blit(filled, block, 0, n);
			filled += n;
			round++;
		}
		return out;
	}
	#end
}
