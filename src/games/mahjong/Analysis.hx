// SPDX-License-Identifier: AGPL-3.0-or-later
package games.mahjong;

/** A set inside a concealed hand: a pung (three alike) or a chow (a run starting at `kind`). **/
typedef HandSet = {kind:Int, chow:Bool};

/** One way to read a complete hand's concealed tiles: sets plus a pair. **/
typedef Decomposition = {pair:Int, sets:Array<HandSet>};

/**
	Hand reading shared by both rule sets: complete hands (four sets and a
	pair, seven pairs, thirteen orphans), waits and shanten (how many tile
	changes the hand is from ready; 0 is ready, -1 complete). All functions
	take counts per kind (Tiles.counts) and how many sets are already melded.
**/
class Analysis {
	static final ORPHANS = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33];

	/** Every way to split the concealed tiles into (4 - melds) sets and a pair. **/
	public static function decompositions(counts:Array<Int>, melds:Int):Array<Decomposition> {
		var out:Array<Decomposition> = [];
		var c = counts.copy();
		var total = 0;
		for (n in c) total += n;
		if (total != (4 - melds) * 3 + 2) return out;
		for (p in 0...Tiles.KINDS) if (c[p] >= 2) {
			c[p] -= 2;
			var sets:Array<HandSet> = [];
			collect(c, 0, sets, s -> out.push({pair: p, sets: s.copy()}));
			c[p] += 2;
		}
		return out;
	}

	static function collect(c:Array<Int>, from:Int, sets:Array<HandSet>, found:Array<HandSet>->Void):Void {
		var i = from;
		while (i < Tiles.KINDS && c[i] == 0) i++;
		if (i >= Tiles.KINDS) {
			found(sets);
			return;
		}
		if (c[i] >= 3) {
			c[i] -= 3;
			sets.push({kind: i, chow: false});
			collect(c, i, sets, found);
			sets.pop();
			c[i] += 3;
		}
		if (Tiles.isSuited(i) && Tiles.rank(i) <= 7 && c[i + 1] > 0 && c[i + 2] > 0) {
			c[i]--;
			c[i + 1]--;
			c[i + 2]--;
			sets.push({kind: i, chow: true});
			collect(c, i, sets, found);
			sets.pop();
			c[i]++;
			c[i + 1]++;
			c[i + 2]++;
		}
	}

	/** Seven different pairs (a closed hand only). **/
	public static function isSevenPairs(counts:Array<Int>, melds:Int):Bool {
		if (melds > 0) return false;
		var pairs = 0;
		for (n in counts) {
			if (n == 2) pairs++;
			else if (n != 0) return false;
		}
		return pairs == 7;
	}

	/** One of each terminal and honor, plus a second of any one of them. **/
	public static function isThirteenOrphans(counts:Array<Int>, melds:Int):Bool {
		if (melds > 0) return false;
		var pair = false;
		for (k in 0...Tiles.KINDS) {
			var orphan = ORPHANS.indexOf(k) >= 0;
			if (!orphan && counts[k] > 0) return false;
			if (orphan && counts[k] == 0) return false;
			if (counts[k] == 2) {
				if (pair) return false;
				pair = true;
			}
			if (counts[k] > 2) return false;
		}
		return pair;
	}

	public static function isComplete(counts:Array<Int>, melds:Int):Bool {
		return decompositions(counts, melds).length > 0 || isSevenPairs(counts, melds) || isThirteenOrphans(counts, melds);
	}

	/** Kinds that would complete a 13-tile (or 13 - 3n) hand. A kind already held four times can't be waited on. **/
	public static function waits(counts:Array<Int>, melds:Int):Array<Int> {
		var out = [];
		for (k in 0...Tiles.KINDS) {
			if (counts[k] >= 4) continue;
			counts[k]++;
			if (isComplete(counts, melds)) out.push(k);
			counts[k]--;
		}
		return out;
	}

	/** Tiles from ready: -1 complete, 0 ready (tenpai), and so on. **/
	public static function shanten(counts:Array<Int>, melds:Int):Int {
		var best = standardShanten(counts, melds);
		if (melds == 0) {
			best = Std.int(Math.min(best, sevenPairsShanten(counts)));
			best = Std.int(Math.min(best, orphansShanten(counts)));
		}
		return best;
	}

	public static function sevenPairsShanten(counts:Array<Int>):Int {
		var pairs = 0, kinds = 0;
		for (n in counts) if (n > 0) {
			kinds++;
			if (n >= 2) pairs++;
		}
		return 6 - pairs + Std.int(Math.max(0, 7 - kinds));
	}

	public static function orphansShanten(counts:Array<Int>):Int {
		var kinds = 0, pair = false;
		for (k in ORPHANS) if (counts[k] > 0) {
			kinds++;
			if (counts[k] >= 2) pair = true;
		}
		return 13 - kinds - (pair ? 1 : 0);
	}

	/** Four sets and a pair: 2 × (sets needed - sets) - partial sets - pair (-1 complete, 0 ready), with partials capped by the sets still needed. **/
	public static function standardShanten(counts:Array<Int>, melds:Int):Int {
		var c = counts.copy();
		var best = 8;
		var need = 4 - melds;
		function score(m:Int, t:Int, p:Int):Void {
			var partial = Std.int(Math.min(t, need - m));
			var s = 2 * (need - m) - partial - p;
			if (s < best) best = s;
		}
		function search(i:Int, m:Int, t:Int, p:Int):Void {
			while (i < Tiles.KINDS && c[i] == 0) i++;
			if (i >= Tiles.KINDS) {
				score(m, t, p);
				return;
			}
			if (m < need) {
				if (c[i] >= 3) {
					c[i] -= 3;
					search(i, m + 1, t, p);
					c[i] += 3;
				}
				if (Tiles.isSuited(i) && Tiles.rank(i) <= 7 && c[i + 1] > 0 && c[i + 2] > 0) {
					c[i]--;
					c[i + 1]--;
					c[i + 2]--;
					search(i, m + 1, t, p);
					c[i]++;
					c[i + 1]++;
					c[i + 2]++;
				}
			}
			if (c[i] >= 2) {
				c[i] -= 2;
				if (p == 0) search(i, m, t, 1);
				if (m + t < need) search(i, m, t + 1, p);
				c[i] += 2;
			}
			if (Tiles.isSuited(i) && m + t < need) {
				if (Tiles.rank(i) <= 8 && c[i + 1] > 0) {
					c[i]--;
					c[i + 1]--;
					search(i, m, t + 1, p);
					c[i]++;
					c[i + 1]++;
				}
				if (Tiles.rank(i) <= 7 && c[i + 2] > 0) {
					c[i]--;
					c[i + 2]--;
					search(i, m, t + 1, p);
					c[i]++;
					c[i + 2]++;
				}
			}
			// Leave this tile as a loose single.
			c[i]--;
			search(i, m, t, p);
			c[i]++;
		}
		search(0, 0, 0, 0);
		return best;
	}
}
