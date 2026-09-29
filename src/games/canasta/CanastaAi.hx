// SPDX-License-Identifier: AGPL-3.0-or-later
package games.canasta;

import cards.Card;

/** Simple heuristic Canasta: take a free meld off the discard pile, meld every rank it can, discard the costliest spare. **/
class CanastaAi {
	public static function takeTurn(game:Canasta, seat:Int):Void {
		if (game.canTakeDiscard()) game.takeDiscard() else game.drawFromStock();
		if (game.phase != Turn) return; // the stock ran out; the hand just ended

		var byRank = new Map<Int, Array<Card>>();
		for (c in game.hands[seat]) {
			if (Canasta.isWild(c)) continue;
			var list = byRank.exists(c.rank) ? byRank.get(c.rank) : [];
			list.push(c);
			byRank.set(c.rank, list);
		}
		for (rank in byRank.keys()) {
			var cards = byRank.get(rank);
			if (cards.length >= 3) game.meld(cards);
		}
		// Lay any spare wild cards onto an existing meld rather than get stuck holding them.
		var spareWild = [for (c in game.hands[seat]) if (Canasta.isWild(c)) c];
		for (c in spareWild) {
			if (game.melds[seat].length == 0) break;
			try game.layOn(0, [c]) catch (e:Dynamic) {}
		}

		var hand = game.hands[seat];
		if (hand.length == 0) return;
		var best:Null<Card> = null, bestValue = -1;
		for (c in hand) {
			if (Canasta.isWild(c)) continue;
			var v = Canasta.pointValue(c);
			if (v > bestValue) {
				bestValue = v;
				best = c;
			}
		}
		if (best != null) game.discard(best);
	}
}
