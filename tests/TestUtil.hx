// SPDX-License-Identifier: AGPL-3.0-or-later

import haxe.crypto.Sha256;
import haxe.io.Bytes;
import rng.IRng;

class TestUtil {
	/** Lowercase 8-digit hex words joined by spaces, matching the RFC and tools/rng_reference.py. **/
	public static function hexWords(words:Iterable<Int>):String {
		return [for (w in words) StringTools.hex(w, 8).toLowerCase()].join(" ");
	}

	/** SHA-256 over `count` words, each serialized little-endian. **/
	public static function streamDigest(rng:IRng, count:Int):String {
		var bytes = Bytes.alloc(count * 4);
		for (i in 0...count)
			bytes.setInt32(i * 4, rng.nextU32());
		return Sha256.make(bytes).toHex();
	}

	/** The 32-byte seed 00 01 02 ... 1f used across the reference vectors. **/
	public static function countingSeed():Bytes {
		var b = Bytes.alloc(32);
		for (i in 0...32)
			b.set(i, i);
		return b;
	}

	/** Pearson chi-square statistic for observed counts against a uniform expectation. **/
	public static function chiSquare(counts:Array<Int>, total:Int):Float {
		var expected = total / counts.length;
		var sum = 0.0;
		for (c in counts)
			sum += (c - expected) * (c - expected) / expected;
		return sum;
	}

	/**
		Upper critical value of chi-square at p = 0.0001 (z = 3.719),
		via the Wilson–Hilferty approximation.
	**/
	public static function chiSquareCritical(df:Int):Float {
		var z = 3.719;
		var k = 2 / (9 * df);
		var t = 1 - k + z * Math.sqrt(k);
		return df * t * t * t;
	}
}
