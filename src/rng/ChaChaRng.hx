// SPDX-License-Identifier: AGPL-3.0-or-later
package rng;

import haxe.crypto.Sha256;
import haxe.ds.Vector;
import haxe.io.Bytes;

/** Everything needed to resume a ChaChaRng exactly where it left off (saved at check-in). **/
typedef ChaChaState = {
	var key:Array<Int>;
	var nonce:Array<Int>;
	var counter:Int;
	var pos:Int;
	var exhausted:Bool;
}

/**
	Outcome-grade RNG (§7.2): the ChaCha20 keystream read as 32-bit words.

	- 256-bit key, so every one of the 52! deck orders is reachable.
	- Deterministic and serializable: the same key gives the same stream on every target.
	- `fork(label)` derives independent child streams (one per table, AI, etc.)
	  that don't depend on the order they were created in (§7.3).
**/
class ChaChaRng extends RngBase {
	/** Words per block; `pos == BLOCK` means the buffer is empty. **/
	static inline var BLOCK = ChaCha20.BLOCK_WORDS;

	final key:Vector<Int>;
	final nonce:Vector<Int>;
	final buf:Vector<Int>;
	var counter:Int;
	var pos:Int;
	var exhausted:Bool;

	public function new(key:Array<Int>, ?nonce:Array<Int>) {
		super();
		if (key.length != ChaCha20.KEY_WORDS)
			throw 'ChaChaRng needs a ${ChaCha20.KEY_WORDS}-word key, got ${key.length}';
		if (nonce != null && nonce.length != ChaCha20.NONCE_WORDS)
			throw 'ChaChaRng needs a ${ChaCha20.NONCE_WORDS}-word nonce, got ${nonce.length}';
		this.key = Vector.fromArrayCopy(key);
		this.nonce = nonce == null ? Vector.fromArrayCopy([0, 0, 0]) : Vector.fromArrayCopy(nonce);
		buf = new Vector(BLOCK);
		counter = 0;
		pos = BLOCK;
		exhausted = false;
	}

	/** Builds a generator from a 32-byte seed (little-endian key words). **/
	public static function fromSeed(seed:Bytes):ChaChaRng {
		if (seed.length != ChaCha20.KEY_WORDS * 4)
			throw 'ChaChaRng seed must be 32 bytes, got ${seed.length}';
		return new ChaChaRng([for (i in 0...ChaCha20.KEY_WORDS) seed.getInt32(i * 4)]);
	}

	/** A fresh, unpredictable generator seeded from the OS (§7.6). **/
	public static function fromEntropy():ChaChaRng {
		return fromSeed(Entropy.bytes(ChaCha20.KEY_WORDS * 4));
	}

	public static function fromState(state:ChaChaState):ChaChaRng {
		var rng = new ChaChaRng(state.key, state.nonce);
		rng.counter = state.counter;
		rng.exhausted = state.exhausted;
		if (state.pos < BLOCK) {
			// Regenerate the partially consumed block.
			ChaCha20.block(rng.key, (state.counter - 1) | 0, rng.nonce, rng.buf);
			rng.pos = state.pos;
		}
		return rng;
	}

	public function saveState():ChaChaState {
		return {
			key: key.toArray(),
			nonce: nonce.toArray(),
			counter: counter,
			pos: pos,
			exhausted: exhausted,
		};
	}

	public function nextU32():Int {
		if (pos == BLOCK)
			refill();
		return buf[pos++];
	}

	/**
		Derives an independent child stream named `label` (for example
		`"table/card-room/blackjack/shuffle"`). The child depends only on this
		generator's key and the label, never on how much of this stream has
		been used, so creation order doesn't matter.
	**/
	public function fork(label:String):ChaChaRng {
		var hash = Sha256.make(Bytes.ofString(label));
		var labelNonce = Vector.fromArrayCopy([for (i in 0...ChaCha20.NONCE_WORDS) hash.getInt32(i * 4)]);
		var out = new Vector<Int>(BLOCK);
		ChaCha20.block(key, 0, labelNonce, out);
		return new ChaChaRng([for (i in 0...ChaCha20.KEY_WORDS) out[i]]);
	}

	/** Short, non-reversible fingerprint of the key, for debug logs and bug reports. **/
	public function fingerprint():String {
		var bytes = Bytes.alloc(ChaCha20.KEY_WORDS * 4);
		for (i in 0...ChaCha20.KEY_WORDS)
			bytes.setInt32(i * 4, key[i]);
		return Sha256.make(bytes).toHex().substr(0, 12);
	}

	function refill():Void {
		if (exhausted)
			throw 'ChaChaRng stream exhausted (2^32 blocks); fork a new stream';
		ChaCha20.block(key, counter, nonce, buf);
		counter = (counter + 1) | 0;
		if (counter == 0)
			exhausted = true;
		pos = 0;
	}
}
