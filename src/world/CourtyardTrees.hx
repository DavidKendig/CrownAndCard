// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

/** One cosmetic easter egg and fixed per-tree flips per launch, separate from game RNGs. */
class CourtyardTrees {
	public static inline var ROW_COUNT = 36;
	public static inline var TOTAL = ROW_COUNT * 2;
	public static final SPECIALS = ["tall-cedar-alien", "tall-cedar-fbi", "tall-cedar-sniper", "tall-cedar-alex-jones", "tall-cedar-ghost"];
	static final launchTrees = choose(rng.ChaChaRng.fromEntropy());

	public static function textureName(index:Int):String return launchTrees[index].texture;
	public static function flipped(index:Int):Bool return launchTrees[index].flipped;

	/** One uniform location, one uniform variant, and an independent coin flip per tree. */
	public static function choose(source:rng.IRng):Array<{texture:String, flipped:Bool}> {
		var slot = source.below(TOTAL), special = SPECIALS[source.below(SPECIALS.length)];
		return [for (i in 0...TOTAL) {
			var texture = i == slot ? special : i % 2 == 0 ? "tall-cedar" : "tall-cypress";
			var mirror = source.below(2) == 1;
			{texture: texture, flipped: texture != "tall-cedar-fbi" && mirror};
		}];
	}
}
