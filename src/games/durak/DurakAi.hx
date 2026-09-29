// SPDX-License-Identifier: AGPL-3.0-or-later
package games.durak;

import cards.Card;

/** Simple heuristic Durak play: spend cheap, non-trump cards first and hold trump back. **/
class DurakAi {
	public static function chooseAttack(game:Durak):Null<Card> {
		var legal = game.legalAttacks();
		if (legal.length == 0) return null;
		legal.sort((a, b) -> weight(game, a) - weight(game, b));
		return legal[0];
	}

	/** Once the table's fully beaten, whether the attacker keeps piling cards on. **/
	public static function shouldKeepAttacking(game:Durak):Bool {
		if (game.table.length == 0) return true;
		if (game.legalAttacks().length == 0) return false;
		return game.table.length < 3;
	}

	/** Beats the sole open attack with the cheapest card that works, or null to take the table. **/
	public static function chooseDefend(game:Durak):Null<Card> {
		if (game.table.length == 0) return null;
		var legal = game.legalDefends(game.table.length - 1);
		if (legal.length == 0) return null;
		legal.sort((a, b) -> weight(game, a) - weight(game, b));
		return legal[0];
	}

	/** Trump cards sort after every non-trump card, so the AI spends them last. **/
	static function weight(game:Durak, c:Card):Int return (c.suit == game.trumpSuit ? 100 : 0) + c.rank;
}
