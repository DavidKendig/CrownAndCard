// SPDX-License-Identifier: AGPL-3.0-or-later
package rng;

/**
	A source of random numbers. All gameplay randomness goes through this
	interface: never call `Std.random` or `Math.random` in game code (§7.2).
**/
interface IRng {
	/** 32 random bits, as a (possibly negative) Int. **/
	function nextU32():Int;

	/** Unbiased integer in `[0, bound)`. Requires `0 < bound <= 0x7FFFFFFF`. **/
	function below(bound:Int):Int;

	/** Unbiased integer in `[lo, hi]` (inclusive). **/
	function between(lo:Int, hi:Int):Int;

	/** Uniform float in `[0, 1)` with 53 bits of precision. **/
	function nextFloat():Float;

	/** True with probability `p`. **/
	function chance(p:Float):Bool;

	/** In-place Fisher–Yates (Durstenfeld) shuffle. **/
	function shuffle<T>(items:Array<T>):Void;

	/** Picks one item with probability proportional to its integer weight. **/
	function pickWeighted<T>(items:Array<T>, weights:Array<Int>):T;
}
