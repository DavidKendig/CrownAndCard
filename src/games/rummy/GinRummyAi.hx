// SPDX-License-Identifier: AGPL-3.0-or-later
package games.rummy;

import cards.Card;

/** Simple heuristic Gin Rummy: take the discard only when it visibly helps, then keep deadwood low. **/
class GinRummyAi {
	public static function shouldTakeDiscard(game:GinRummy, seat:Int):Bool {
		if (game.discardPile.length == 0) return false;
		var top = game.discardPile[game.discardPile.length - 1];
		var without = GinRummy.evaluate(game.hands[seat]).deadwoodPoints;
		var withIt = game.hands[seat].copy();
		withIt.push(top);
		return GinRummy.evaluate(withIt).deadwoodPoints < without + GinRummy.pointValue(top.rank);
	}

	/** The card whose discard leaves the least deadwood. **/
	public static function chooseDiscard(game:GinRummy, seat:Int):Card {
		var hand = game.hands[seat];
		var best = hand[0], bestValue = game.deadwoodIfDiscarding(seat, best);
		for (c in hand) {
			var v = game.deadwoodIfDiscarding(seat, c);
			if (v < bestValue) {
				bestValue = v;
				best = c;
			}
		}
		return best;
	}
}
