// SPDX-License-Identifier: AGPL-3.0-or-later
package games.parlour;

import games.parlour.GoFish.AskResult;

/**
	Go Fish opponents with a memory (§9.1): they remember who asked for what
	(an asker must hold that rank) and who just received cards, and go after
	those first. Otherwise they ask for the rank they hold most of.
**/
class GoFishAi {
	/** known[seat] = ranks that seat is known to hold. **/
	final known:Array<Array<Int>>;

	final rng:rng.IRng;

	public function new(players:Int, rng:rng.IRng) {
		known = [for (_ in 0...players) []];
		this.rng = rng;
	}

	/** Everyone at the table hears every ask; call this after each one. **/
	public function observe(r:AskResult):Void {
		// The asker holds the rank (and now more of it, if they got some).
		if (known[r.asker].indexOf(r.rank) < 0) known[r.asker].push(r.rank);
		known[r.target].remove(r.rank);
		for (b in r.books) for (k in known) k.remove(b);
	}

	public function choose(game:GoFish, seat:Int):{target:Int, rank:Int} {
		var mine = game.ranksHeld(seat);
		var others = [for (i in 0...game.hands.length) if (i != seat && game.hands[i].length > 0) i];
		if (others.length == 0) others = [for (i in 0...game.hands.length) if (i != seat) i];
		// Someone is known to hold a rank we have: ask them.
		for (o in others) for (rank in known[o]) if (mine.indexOf(rank) >= 0) return {target: o, rank: rank};
		var bestRank = mine[0], bestCount = 0;
		for (rank in mine) {
			var n = 0;
			for (c in game.hands[seat]) if (c.rank == rank) n++;
			if (n > bestCount || (n == bestCount && rng.chance(0.5))) {
				bestRank = rank;
				bestCount = n;
			}
		}
		return {target: others[rng.below(others.length)], rank: bestRank};
	}
}
