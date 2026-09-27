// SPDX-License-Identifier: AGPL-3.0-or-later
package cards;

class Deck {
	/** A fresh 52-card deck in index order (unshuffled). **/
	public static function standard():Array<Card> {
		return [for (i in 0...Card.COUNT) Card.fromIndex(i)];
	}

	/** The 24-card euchre deck: 9 through ace in each suit. **/
	public static function euchre():Array<Card> {
		return [for (c in standard()) if (c.rank >= 9) c];
	}
}
