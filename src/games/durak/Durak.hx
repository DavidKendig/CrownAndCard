// SPDX-License-Identifier: AGPL-3.0-or-later
package games.durak;

import games.PlayLog;
import cards.Card;
import cards.Suit;

enum abstract Phase(String) to String {
	/** The attacker may add a card, or has none left to add. **/
	var Attacking = "attacking";

	/** The defender must beat the open attack, or take the whole table. **/
	var Defending = "defending";

	var GameOver = "game over";
}

typedef TablePair = {attack:Card, defend:Null<Card>};

/**
	Two-player Durak ("Fool"), Podkidnoy rules: a 36-card deck (6 through
	ace), dealt 6 each. The last card cut is set face up under the stock to
	show trump; it's drawn last.

	The attacker plays a card; the defender beats it with a higher card of
	the same suit, or any trump if the attack card isn't trump, or takes the
	whole table. While the defender hasn't taken, the attacker may add more
	cards matching any rank already on the table, up to six cards or the
	defender's starting hand size, whichever is less. Once every attack card
	is beaten and the attacker has nothing left to add (or chooses to stop),
	the table goes to the discard, both hands refill to 6 from the stock
	(attacker first), and the roles swap. A defender who takes the table
	stays defender and the attacker keeps the lead next round.

	Once the stock is empty, hands stop refilling; the first player to empty
	their hand is safe, and the other is left the Durak. Both emptying at
	once is a draw.
**/
class Durak {
	public static inline var HAND_SIZE = 6;
	public static inline var MAX_ATTACK = 6;

	public var trumpSuit(default, null):Suit;
	public var trumpCard(default, null):Card;
	public final hands:Array<Array<Card>> = [[], []];
	public final stock:Array<Card> = [];
	public var discarded(default, null) = 0;
	public final table:Array<TablePair> = [];
	public var attacker(default, null) = 0;
	public var defender(default, null) = 1;
	public var phase(default, null):Phase = Attacking;
	public var durak(default, null) = -1;

	/** The defender's hand size when this round's attack began (caps how many cards can pile on). **/
	var roundCap = 0;

	public function new() {}

	/** Shuffles a fresh 36-card deck and deals it (§ new). **/
	public function dealFrom(rng:rng.IRng):Void {
		var deck:Array<Card> = [for (suit in Suit.ALL) for (rank in 6...Card.ACE + 1) Card.of(rank, suit)];
		rng.shuffle(deck);
		// The first card cut becomes trump, dealt last from the bottom of the stock.
		startDeal(deck.slice(1).concat([deck[0]]));
	}

	/** Test hook: deals from a known stock order; its last card is the trump, drawn last. **/
	public function startDeal(order:Array<Card>):Void {
		hands[0].resize(0);
		hands[1].resize(0);
		stock.resize(0);
		table.resize(0);
		var cards = order.copy();
		for (_ in 0...HAND_SIZE) {
			hands[0].push(cards.shift());
			hands[1].push(cards.shift());
		}
		trumpCard = cards[cards.length - 1];
		trumpSuit = trumpCard.suit;
		for (c in cards) stock.push(c);
		discarded = 0;
		attacker = 0;
		defender = 1;
		phase = Attacking;
		durak = -1;
		roundCap = hands[defender].length;
	}

	/** True if `card` beats `over` (both compared as the card the defender plays against the attack). **/
	public function beats(card:Card, over:Card):Bool {
		if (card.suit == over.suit) return card.rank > over.rank;
		return card.suit == trumpSuit && over.suit != trumpSuit;
	}

	/** Ranks currently on the table (attack or defense), for what the attacker may still add. **/
	function ranksOnTable():Array<Int> {
		var out = [];
		for (p in table) {
			if (out.indexOf(p.attack.rank) < 0) out.push(p.attack.rank);
			if (p.defend != null && out.indexOf(p.defend.rank) < 0) out.push(p.defend.rank);
		}
		return out;
	}

	public function canAttackWith(card:Card):Bool {
		if (phase != Attacking) return false;
		if (table.length >= MAX_ATTACK || table.length >= roundCap) return false;
		if (table.length == 0) return true;
		return ranksOnTable().indexOf(card.rank) >= 0;
	}

	public function legalAttacks():Array<Card> return [for (c in hands[attacker]) if (canAttackWith(c)) c];

	/** The attacker adds a card (or opens the round with the first one). **/
	public function attack(card:Card):Void {
		if (!canAttackWith(card)) throw 'Cannot attack with ${card.code}';
		hands[attacker].remove(card);
		table.push({attack: card, defend: null});
		PlayLog.play(attacker, "attacks with " + card.toString());
		phase = Defending;
	}

	public function legalDefends(index:Int):Array<Card> {
		if (phase != Defending || index < 0 || index >= table.length || table[index].defend != null) return [];
		var over = table[index].attack;
		return [for (c in hands[defender]) if (beats(c, over)) c];
	}

	/** The defender beats one open attack card. **/
	public function defend(index:Int, card:Card):Void {
		if (legalDefends(index).indexOf(card) < 0) throw 'Cannot defend table slot $index with ${card.code}';
		hands[defender].remove(card);
		table[index].defend = card;
		PlayLog.play(defender, 'beats ${table[index].attack.toString()} with ${card.toString()}');
		phase = allBeaten() ? Attacking : Defending;
	}

	function allBeaten():Bool {
		for (p in table) if (p.defend == null) return false;
		return true;
	}

	/** True once neither side has anything left to do but end the round. **/
	public var canFinish(get, never):Bool;

	inline function get_canFinish():Bool return table.length > 0 && allBeaten();

	/** The attacker has nothing left worth adding (an empty hand, or no matching ranks and the table's already open). **/
	public var attackerMustPass(get, never):Bool;

	inline function get_attackerMustPass():Bool return phase == Attacking && table.length > 0 && legalAttacks().length == 0;

	/** The defender takes the whole table: it goes to their hand, and the attacker keeps the lead. **/
	public function take():Void {
		if (phase != Defending && !canFinish) throw 'Nothing to take';
		var taken:Array<Card> = [];
		for (p in table) {
			taken.push(p.attack);
			if (p.defend != null) taken.push(p.defend);
		}
		PlayLog.play(defender, "takes the table: " + PlayLog.cards(taken));
		for (p in table) {
			hands[defender].push(p.attack);
			if (p.defend != null) hands[defender].push(p.defend);
		}
		table.resize(0);
		refill(defender);
		refill(attacker);
		checkGameOver();
		if (phase != GameOver) startRound(attacker, defender);
	}

	/** All attack cards were beaten and the attacker has nothing more to add: the table is cleared and roles swap. **/
	public function finish():Void {
		if (!canFinish) throw 'The table is not fully beaten yet';
		PlayLog.play(attacker, "ends the attack; the beaten cards are discarded");
		discarded += table.length * 2;
		table.resize(0);
		refill(attacker);
		refill(defender);
		checkGameOver();
		if (phase != GameOver) startRound(defender, attacker);
	}

	function refill(seat:Int):Void {
		while (hands[seat].length < HAND_SIZE && stock.length > 0) hands[seat].push(stock.shift());
	}

	function startRound(nextAttacker:Int, nextDefender:Int):Void {
		attacker = nextAttacker;
		defender = nextDefender;
		roundCap = hands[defender].length;
		phase = Attacking;
	}

	function checkGameOver():Void {
		if (stock.length > 0) return;
		var empty0 = hands[0].length == 0, empty1 = hands[1].length == 0;
		if (empty0 && empty1) {
			durak = -1;
			phase = GameOver;
		} else if (empty0) {
			durak = 1;
			phase = GameOver;
		} else if (empty1) {
			durak = 0;
			phase = GameOver;
		}
	}
}
