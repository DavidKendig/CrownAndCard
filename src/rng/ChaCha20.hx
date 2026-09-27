// SPDX-License-Identifier: AGPL-3.0-or-later
package rng;

import haxe.ds.Vector;

/**
	The ChaCha20 block function from RFC 8439.

	It uses only 32-bit add, XOR and rotate, which behave identically on every
	Haxe target as long as additions are wrapped with `| 0` (JS numbers don't
	wrap on their own; §7.4).
**/
class ChaCha20 {
	public static inline var KEY_WORDS = 8;
	public static inline var NONCE_WORDS = 3;
	public static inline var BLOCK_WORDS = 16;

	/**
		Computes one 64-byte block into `out` (16 little-endian words).
		`key` has 8 words, `nonce` has 3 words.
	**/
	public static function block(key:Vector<Int>, counter:Int, nonce:Vector<Int>, out:Vector<Int>):Void {
		var s = out;
		s[0] = 0x61707865;
		s[1] = 0x3320646e;
		s[2] = 0x79622d32;
		s[3] = 0x6b206574;
		for (i in 0...KEY_WORDS)
			s[4 + i] = key[i];
		s[12] = counter;
		s[13] = nonce[0];
		s[14] = nonce[1];
		s[15] = nonce[2];

		var x0 = s[0], x1 = s[1], x2 = s[2], x3 = s[3];
		var x4 = s[4], x5 = s[5], x6 = s[6], x7 = s[7];
		var x8 = s[8], x9 = s[9], x10 = s[10], x11 = s[11];
		var x12 = s[12], x13 = s[13], x14 = s[14], x15 = s[15];

		for (_ in 0...10) {
			// Column rounds.
			x0 = add(x0, x4); x12 = rotl(x12 ^ x0, 16);
			x8 = add(x8, x12); x4 = rotl(x4 ^ x8, 12);
			x0 = add(x0, x4); x12 = rotl(x12 ^ x0, 8);
			x8 = add(x8, x12); x4 = rotl(x4 ^ x8, 7);

			x1 = add(x1, x5); x13 = rotl(x13 ^ x1, 16);
			x9 = add(x9, x13); x5 = rotl(x5 ^ x9, 12);
			x1 = add(x1, x5); x13 = rotl(x13 ^ x1, 8);
			x9 = add(x9, x13); x5 = rotl(x5 ^ x9, 7);

			x2 = add(x2, x6); x14 = rotl(x14 ^ x2, 16);
			x10 = add(x10, x14); x6 = rotl(x6 ^ x10, 12);
			x2 = add(x2, x6); x14 = rotl(x14 ^ x2, 8);
			x10 = add(x10, x14); x6 = rotl(x6 ^ x10, 7);

			x3 = add(x3, x7); x15 = rotl(x15 ^ x3, 16);
			x11 = add(x11, x15); x7 = rotl(x7 ^ x11, 12);
			x3 = add(x3, x7); x15 = rotl(x15 ^ x3, 8);
			x11 = add(x11, x15); x7 = rotl(x7 ^ x11, 7);

			// Diagonal rounds.
			x0 = add(x0, x5); x15 = rotl(x15 ^ x0, 16);
			x10 = add(x10, x15); x5 = rotl(x5 ^ x10, 12);
			x0 = add(x0, x5); x15 = rotl(x15 ^ x0, 8);
			x10 = add(x10, x15); x5 = rotl(x5 ^ x10, 7);

			x1 = add(x1, x6); x12 = rotl(x12 ^ x1, 16);
			x11 = add(x11, x12); x6 = rotl(x6 ^ x11, 12);
			x1 = add(x1, x6); x12 = rotl(x12 ^ x1, 8);
			x11 = add(x11, x12); x6 = rotl(x6 ^ x11, 7);

			x2 = add(x2, x7); x13 = rotl(x13 ^ x2, 16);
			x8 = add(x8, x13); x7 = rotl(x7 ^ x8, 12);
			x2 = add(x2, x7); x13 = rotl(x13 ^ x2, 8);
			x8 = add(x8, x13); x7 = rotl(x7 ^ x8, 7);

			x3 = add(x3, x4); x14 = rotl(x14 ^ x3, 16);
			x9 = add(x9, x14); x4 = rotl(x4 ^ x9, 12);
			x3 = add(x3, x4); x14 = rotl(x14 ^ x3, 8);
			x9 = add(x9, x14); x4 = rotl(x4 ^ x9, 7);
		}

		s[0] = add(x0, s[0]); s[1] = add(x1, s[1]); s[2] = add(x2, s[2]); s[3] = add(x3, s[3]);
		s[4] = add(x4, s[4]); s[5] = add(x5, s[5]); s[6] = add(x6, s[6]); s[7] = add(x7, s[7]);
		s[8] = add(x8, s[8]); s[9] = add(x9, s[9]); s[10] = add(x10, s[10]); s[11] = add(x11, s[11]);
		s[12] = add(x12, s[12]); s[13] = add(x13, s[13]); s[14] = add(x14, s[14]); s[15] = add(x15, s[15]);
	}

	/** One quarter round on four words of `s` (exposed for the RFC 8439 §2.1.1 test). **/
	public static function quarterRound(s:Vector<Int>, a:Int, b:Int, c:Int, d:Int):Void {
		s[a] = add(s[a], s[b]); s[d] = rotl(s[d] ^ s[a], 16);
		s[c] = add(s[c], s[d]); s[b] = rotl(s[b] ^ s[c], 12);
		s[a] = add(s[a], s[b]); s[d] = rotl(s[d] ^ s[a], 8);
		s[c] = add(s[c], s[d]); s[b] = rotl(s[b] ^ s[c], 7);
	}

	static inline function add(a:Int, b:Int):Int {
		return (a + b) | 0;
	}

	static inline function rotl(x:Int, n:Int):Int {
		return (x << n) | (x >>> (32 - n));
	}
}
