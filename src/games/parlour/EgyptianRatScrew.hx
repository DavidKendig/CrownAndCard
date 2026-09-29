// SPDX-License-Identifier: AGPL-3.0-or-later
package games.parlour;

import games.PlayLog;
import cards.Card;
import cards.Deck;
import games.parlour.Slapjack.CenterCard;

/** An active run of face-card chances: `owner` takes the pile if `responder` can't beat it. **/
typedef Challenge = {owner:Int, responder:Int, remaining:Int};

enum ErsSlapResult {
	/** Nothing to slap. **/
	Empty;

	/** A valid slap: took the whole pile. **/
	Won(cards:Int, pattern:String);

	/** A false slap, with a card to burn to the bottom of the pile. **/
	Penalty;

	/** A false slap with no card left to pay. **/
	NothingToPay;
}

/**
	Egyptian Rat Screw (bicyclecards.com, with the common house additions
	noted below): the deck is dealt out evenly; in turn each player plays
	their top card face up onto the center pile.

	Playing a face card challenges the next player to beat it within a
	number of chances (ace 4, king 3, queen 2, jack 1): if they play a face
	card of their own within their chances, the challenge resets onto the
	player after them; if they run out of chances (or cards) first, the
	original player takes the whole pile.

	Any player may slap the pile at any time, cards left or not, for:
	doubles (top two cards match), a sandwich (top and third-from-top
	match), top-bottom (the pile's top card matches its very first card),
	or a marriage (king and queen on top, either order). A correct slap
	takes the whole pile; a wrong one burns a card to the bottom, win or
	lose. A player out of cards can still slap back in.

	Pure rules: which player slapped first is decided by the table screen's
	clock, not this class.
**/
class EgyptianRatScrew {
	public final piles:Array<Array<Card>>;
	public final center:Array<CenterCard> = [];
	public var turn(default, null) = 0;
	public var winner(default, null) = -1;
	public var challenge(default, null):Null<Challenge> = null;

	final rng:rng.IRng;
	final players:Int;

	public function new(players:Int, rng:rng.IRng) {
		this.rng = rng;
		this.players = players;
		piles = [for (_ in 0...players) []];
		var deck = Deck.standard();
		rng.shuffle(deck);
		for (i in 0...deck.length) piles[i % players].push(deck[i]);
	}

	/** Test hook: start from given piles (top first). **/
	public static function fromPiles(piles:Array<Array<Card>>, rng:rng.IRng):EgyptianRatScrew {
		var g = new EgyptianRatScrew(piles.length, rng);
		for (i in 0...piles.length) {
			g.piles[i].resize(0);
			for (c in piles[i]) g.piles[i].push(c);
		}
		return g;
	}

	public var top(get, never):Null<Card>;

	inline function get_top():Null<Card> return center.length > 0 ? center[center.length - 1].card : null;

	static function chancesFor(rank:Int):Int {
		return switch rank {
			case Card.ACE: 4;
			case Card.KING: 3;
			case Card.QUEEN: 2;
			case Card.JACK: 1;
			default: 0;
		}
	}

	/** The seat whose turn it is to play plays their top card onto the center. **/
	public function play():Card {
		if (winner >= 0) throw 'The game is over';
		if (piles[turn].length == 0) throw 'Seat $turn has no cards to play';
		var seat = turn;
		var card = piles[seat].shift();
		center.push({card: card, seat: seat});
		PlayLog.play(seat, "plays " + card.toString());
		var faceChances = chancesFor(card.rank);
		if (faceChances > 0) {
			var responder = nextWithCards(seat);
			// No one else has cards to respond: the pile is won outright.
			if (responder == seat) awardPile(seat) else {
				challenge = {owner: seat, responder: responder, remaining: faceChances};
				turn = responder;
			}
		} else if (challenge != null) {
			challenge.remaining--;
			if (challenge.remaining <= 0) {
				awardPile(challenge.owner);
				challenge = null;
			} else turn = challenge.responder;
		} else turn = nextWithCards(seat);
		// The responder ran out of cards mid-challenge: the owner wins outright.
		if (challenge != null && piles[challenge.responder].length == 0) {
			awardPile(challenge.owner);
			challenge = null;
		}
		checkWinner();
		return card;
	}

	function nextWithCards(from:Int):Int {
		for (k in 1...players + 1) {
			var i = (from + k) % players;
			if (piles[i].length > 0) return i;
		}
		return from;
	}

	function awardPile(seat:Int):Void {
		var won = [for (c in center) c.card];
		PlayLog.play(seat, 'takes the pile (${won.length} cards)');
		center.resize(0);
		for (c in won) piles[seat].push(c);
		turn = piles[seat].length > 0 ? seat : nextWithCards(seat);
	}

	/** What pattern (if any) is slappable right now. **/
	public function slappable():String {
		var n = center.length;
		if (n >= 2 && center[n - 1].card.rank == center[n - 2].card.rank) return "doubles";
		if (n >= 3 && center[n - 1].card.rank == center[n - 3].card.rank) return "sandwich";
		if (n >= 2 && center[n - 1].card.rank == center[0].card.rank) return "top-bottom";
		if (n >= 2 && isMarriage(center[n - 1].card.rank, center[n - 2].card.rank)) return "marriage";
		return "";
	}

	static function isMarriage(a:Int, b:Int):Bool {
		return (a == Card.KING && b == Card.QUEEN) || (a == Card.QUEEN && b == Card.KING);
	}

	public function slap(seat:Int):ErsSlapResult {
		if (winner >= 0) throw 'The game is over';
		if (center.length == 0) return Empty;
		var pattern = slappable();
		if (pattern != "") {
			PlayLog.play(seat, 'slaps the pile: $pattern');
			challenge = null;
			var count = center.length;
			awardPile(seat);
			checkWinner();
			return Won(count, pattern);
		}
		if (piles[seat].length == 0) return NothingToPay;
		PlayLog.play(seat, "slaps with nothing to slap and pays a card");
		center.insert(0, {card: piles[seat].shift(), seat: seat});
		if (piles[seat].length == 0 && challenge != null && challenge.responder == seat) {
			awardPile(challenge.owner);
			challenge = null;
			checkWinner();
		}
		return Penalty;
	}

	function checkWinner():Void {
		var holders = [for (i in 0...players) if (piles[i].length > 0) i];
		if (holders.length == 1 && center.length == 0) winner = holders[0];
	}

	public function count(seat:Int):Int return piles[seat].length;
}
