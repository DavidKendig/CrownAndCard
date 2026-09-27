// SPDX-License-Identifier: AGPL-3.0-or-later
package rng;

/**
	xoshiro128** 1.1 (Blackman & Vigna): tiny, fast and statistically strong.

	**FX tier only** (§7.2): particles, idle animations, bark variations.
	Its 128-bit state can't reach every deck order, so it must never shuffle
	cards or decide any outcome. Its state is not saved.
**/
class Xoshiro128ss extends RngBase {
	var s0:Int;
	var s1:Int;
	var s2:Int;
	var s3:Int;

	public function new(s0:Int, s1:Int, s2:Int, s3:Int) {
		super();
		if (s0 == 0 && s1 == 0 && s2 == 0 && s3 == 0)
			throw 'Xoshiro128ss state must not be all zero';
		this.s0 = s0;
		this.s1 = s1;
		this.s2 = s2;
		this.s3 = s3;
	}

	/** Seeds from another generator (normally a fork of the outcome RNG). **/
	public static function seededFrom(source:IRng):Xoshiro128ss {
		while (true) {
			var a = source.nextU32(), b = source.nextU32(), c = source.nextU32(), d = source.nextU32();
			if (a != 0 || b != 0 || c != 0 || d != 0)
				return new Xoshiro128ss(a, b, c, d);
		}
	}

	public function nextU32():Int {
		var result = mul(rotl(mul(s1, 5), 7), 9);
		var t = s1 << 9;
		s2 ^= s0;
		s3 ^= s1;
		s1 ^= s2;
		s0 ^= s3;
		s2 ^= t;
		s3 = rotl(s3, 11);
		return result;
	}

	/**
		32-bit wrapping multiply by a small constant. The exact product stays
		under 2^53, so `| 0` wraps it correctly on JS too.
	**/
	static inline function mul(a:Int, small:Int):Int {
		return (a * small) | 0;
	}

	static inline function rotl(x:Int, n:Int):Int {
		return (x << n) | (x >>> (32 - n));
	}
}
