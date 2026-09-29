// SPDX-License-Identifier: AGPL-3.0-or-later
package net;

import haxe.crypto.Sha256;
import haxe.io.Bytes;
import rng.ChaChaRng;

/**
	Shared-seed dealing for multiplayer tables (§13.13): the host commits to
	a secret seed, every guest adds one of their own, and the deck comes from
	all of them. No single player can choose the shuffle.

	Seeds and commitments travel as lowercase hex (64 characters).
**/
class Fairness {
	public static inline var SEED_BYTES = 32;

	/** A fresh secret seed from the OS random source (§7.6). **/
	public static function newSeed():String return rng.Entropy.bytes(SEED_BYTES).toHex();

	/** What the host shows before the hand: SHA-256 of its seed. **/
	public static function commit(seed:String):String return Sha256.make(Bytes.ofHex(seed)).toHex();

	public static function validSeed(seed:Dynamic):Bool {
		if (!(seed is String)) return false;
		var s:String = seed;
		if (s.length != SEED_BYTES * 2) return false;
		for (i in 0...s.length) if ("0123456789abcdef".indexOf(s.charAt(i)) < 0) return false;
		return true;
	}

	/**
		The hand's seed: SHA-256 of the host seed followed by each guest seed in
		seat order. A guest who sent nothing (or garbage) adds nothing.
	**/
	public static function handSeed(hostSeed:String, guestSeeds:Array<String>):Bytes {
		var buf = new haxe.io.BytesBuffer();
		buf.add(Bytes.ofHex(hostSeed));
		for (g in guestSeeds) if (validSeed(g)) buf.add(Bytes.ofHex(g));
		return Sha256.make(buf.getBytes());
	}

	/** The deck's shuffle stream for a hand. **/
	public static function shuffleRng(handSeed:Bytes):ChaChaRng return ChaChaRng.fromSeed(handSeed);

	/** House players' decisions, derived from the same seed so guests can check them too. **/
	public static function houseRng(handSeed:Bytes):ChaChaRng return ChaChaRng.fromSeed(handSeed).fork("house");
}
