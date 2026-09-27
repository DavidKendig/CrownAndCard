// SPDX-License-Identifier: AGPL-3.0-or-later
package rng;

/**
	Derives every value type from `nextU32()` without bias (§7.5).
	Subclasses only provide the raw 32-bit generator.
**/
abstract class RngBase implements IRng {
	/** 2^26, used to build 53-bit floats from two draws. **/
	static inline var TWO_POW_26 = 67108864.0;

	/** 2^53. **/
	static inline var TWO_POW_53 = 9007199254740992.0;

	function new() {}

	public abstract function nextU32():Int;

	public function below(bound:Int):Int {
		if (bound <= 0)
			throw 'below(): bound must be positive, got $bound';
		// Bitmask with rejection: unbiased and needs no 64-bit math.
		// Never use `nextU32() % bound`, which is biased.
		var mask = bound - 1;
		mask |= mask >>> 1;
		mask |= mask >>> 2;
		mask |= mask >>> 4;
		mask |= mask >>> 8;
		mask |= mask >>> 16;
		var x:Int;
		do
			x = nextU32() & mask
		while (x >= bound);
		return x;
	}

	public function between(lo:Int, hi:Int):Int {
		if (hi < lo)
			throw 'between(): hi ($hi) < lo ($lo)';
		var span = hi - lo + 1;
		if (span <= 0)
			throw 'between(): range too large ($lo..$hi)';
		return lo + below(span);
	}

	public function nextFloat():Float {
		var a = nextU32() >>> 5; // 27 bits
		var b = nextU32() >>> 6; // 26 bits
		return (a * TWO_POW_26 + b) / TWO_POW_53;
	}

	public function chance(p:Float):Bool {
		return nextFloat() < p;
	}

	public function shuffle<T>(items:Array<T>):Void {
		var i = items.length;
		while (i > 1) {
			var j = below(i);
			i--;
			var t = items[i];
			items[i] = items[j];
			items[j] = t;
		}
	}

	public function pickWeighted<T>(items:Array<T>, weights:Array<Int>):T {
		if (items.length == 0 || items.length != weights.length)
			throw 'pickWeighted(): need matching, non-empty items and weights';
		var total = 0;
		for (w in weights) {
			if (w < 0)
				throw 'pickWeighted(): negative weight $w';
			total += w;
			if (total < 0)
				throw 'pickWeighted(): total weight overflows';
		}
		if (total == 0)
			throw 'pickWeighted(): all weights are zero';
		var r = below(total);
		for (i in 0...items.length) {
			r -= weights[i];
			if (r < 0)
				return items[i];
		}
		throw 'unreachable';
	}
}
