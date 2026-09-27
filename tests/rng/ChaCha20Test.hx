// SPDX-License-Identifier: AGPL-3.0-or-later
package rng;

import haxe.ds.Vector;
import utest.Assert;

/** Official test vectors from RFC 8439. **/
class ChaCha20Test extends utest.Test {
	function testQuarterRound_Section2_1_1() {
		var s = Vector.fromArrayCopy([0x11111111, 0x01020304, 0x9b8d6f43, 0x01234567]);
		ChaCha20.quarterRound(s, 0, 1, 2, 3);
		Assert.equals("ea2a92f4 cb1cf8ce 4581472e 5881c4bb", TestUtil.hexWords(s.toArray()));
	}

	function testBlock_Section2_3_2() {
		var key = [0x03020100, 0x07060504, 0x0b0a0908, 0x0f0e0d0c, 0x13121110, 0x17161514, 0x1b1a1918, 0x1f1e1d1c];
		var nonce = [0x09000000, 0x4a000000, 0x00000000];
		Assert.equals("e4e7f110 15593bd1 1fdd0f50 c47120a3 c7f4d1c7 0368c033 9aaa2204 4e6cd4c3 "
			+ "466482d2 09aa9f07 05d7c214 a2028bd9 d19c12b5 b94e16de e883d0cb 4e3c50a2",
			run(key, 1, nonce));
	}

	function testBlock_AppendixA1_Vector1() {
		Assert.equals("ade0b876 903df1a0 e56a5d40 28bd8653 b819d2bd 1aed8da0 ccef36a8 c70d778b "
			+ "7c5941da 8d485751 3fe02477 374ad8b8 f4b8436a 1ca11815 69b687c3 8665eeb2",
			run([0, 0, 0, 0, 0, 0, 0, 0], 0, [0, 0, 0]));
	}

	function testBlock_AppendixA1_Vector2() {
		Assert.equals("bee7079f 7a385155 7c97ba98 0d082d73 a0290fcb 6965e348 3e53c612 ed7aee32 "
			+ "7621b729 434ee69c b03371d5 d539d874 281fed31 45fb0a51 1f0ae1ac 6f4d794b",
			run([0, 0, 0, 0, 0, 0, 0, 0], 1, [0, 0, 0]));
	}

	function testBlock_AppendixA1_Vector3() {
		// Last key byte is 0x01, so the last little-endian key word is 0x01000000.
		Assert.equals("2452eb3a 9249f8ec 8d829d9b ddd4ceb1 e8252083 60818b01 f38422b8 5aaa49c9 "
			+ "bb00ca8e da3ba7b4 c4b592d1 fdf2732f 4436274e 2561b3c8 ebdd4aa6 a0136c00",
			run([0, 0, 0, 0, 0, 0, 0, 0x01000000], 1, [0, 0, 0]));
	}

	function testBlock_AppendixA1_Vector4() {
		// Key byte 1 is 0xff, so the first little-endian key word is 0x0000ff00.
		Assert.equals("fb4dd572 4bc42ef1 df922636 327f1394 a78dea8f 5e269039 a1bebbc1 caf09aae "
			+ "a25ab213 48a6b46c 1b9d9bcb 092c5be6 546ca624 1bec45d5 87f47473 96f0992e",
			run([0x0000ff00, 0, 0, 0, 0, 0, 0, 0], 2, [0, 0, 0]));
	}

	static function run(key:Array<Int>, counter:Int, nonce:Array<Int>):String {
		var out = new Vector<Int>(ChaCha20.BLOCK_WORDS);
		ChaCha20.block(Vector.fromArrayCopy(key), counter, Vector.fromArrayCopy(nonce), out);
		return TestUtil.hexWords(out.toArray());
	}
}
