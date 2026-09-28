// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import cards.Card;
import games.poker.HandEval;
import games.poker.PokerAi;
import games.poker.PokerTable;
import rng.ChaChaRng;
import utest.Assert;

class PokerTest extends utest.Test {
	static function h(codes:String):Array<Card> return [for (c in codes.split(" ")) Card.parse(c)];

	static function cat(codes:String):Int return HandEval.category(HandEval.score(h(codes)));

	function testCategories() {
		Assert.equals(HandEval.STRAIGHT_FLUSH, cat("9h Th Jh Qh Kh"));
		Assert.equals(HandEval.QUADS, cat("9h 9s 9d 9c 2h"));
		Assert.equals(HandEval.FULL_HOUSE, cat("9h 9s 9d 2c 2h"));
		Assert.equals(HandEval.FLUSH, cat("2h 7h 9h Jh Kh"));
		Assert.equals(HandEval.STRAIGHT, cat("9h Ts Jd Qc Kh"));
		Assert.equals(HandEval.STRAIGHT, cat("Ah 2s 3d 4c 5h")); // the wheel
		Assert.equals(HandEval.TRIPS, cat("9h 9s 9d 2c 3h"));
		Assert.equals(HandEval.TWO_PAIR, cat("9h 9s 2d 2c 3h"));
		Assert.equals(HandEval.PAIR, cat("9h 9s 2d 4c 3h"));
		Assert.equals(HandEval.HIGH_CARD, cat("9h Js 2d 4c 3h"));
	}

	function testKickersAndBestOfSeven() {
		// Same pair, better kicker.
		Assert.isTrue(HandEval.score(h("Ah As Kd 4c 3h")) > HandEval.score(h("Ah As Qd Jc Th")));
		// Wheel loses to a six-high straight.
		Assert.isTrue(HandEval.score(h("2h 3s 4d 5c 6h")) > HandEval.score(h("Ah 2s 3d 4c 5h")));
		// Seven cards: flush and full house available, full house wins; two trips make a full house.
		Assert.equals(HandEval.FULL_HOUSE, cat("Kh Ks Kd 2h 2s 7h 9h"));
		Assert.equals(HandEval.FULL_HOUSE, cat("Kh Ks Kd 2h 2s 2d 9h"));
		Assert.equals("Kings full of 2s", HandEval.describe(HandEval.score(h("Kh Ks Kd 2h 2s 2d 9h"))));
		// Split pots: the board plays.
		Assert.equals(HandEval.score(h("2c 3d Ah Kh Qh Jh Th")), HandEval.score(h("4c 5d Ah Kh Qh Jh Th")));
	}

	function table(stacks:Array<Int>, variant = Holdem):PokerTable {
		return new PokerTable(variant, [for (i in 0...stacks.length) 'P$i'], stacks, 1, 2, 1);
	}

	function testBlindsAndPreflopOrder() {
		var t = table([100, 100, 100, 100]);
		t.startHand(rng("blinds"));
		Assert.equals(0, t.button);
		Assert.equals(99, t.seats[1].stack); // small blind
		Assert.equals(98, t.seats[2].stack); // big blind
		Assert.equals(3, t.toAct); // under the gun
		for (s in t.seats) Assert.equals(2, s.cards.length);
		// Everyone calls, the big blind checks: on to the flop.
		t.act(3, Call);
		t.act(0, Call);
		t.act(1, Call);
		Assert.equals(2, t.toAct);
		t.act(2, Check);
		Assert.equals(3, t.board.length);
		Assert.equals(1, t.toAct); // first live seat after the button
		Assert.equals(8, t.pot);
	}

	function testFoldToARaiseWinsUncontested() {
		var t = table([100, 100, 100]);
		t.startHand(rng("fold"));
		// Button 0 raises to 6, both blinds fold.
		t.act(0, RaiseTo(6));
		t.act(1, Fold);
		t.act(2, Fold);
		Assert.equals(HandOver, t.phase);
		Assert.isFalse(t.showdown);
		Assert.equals(103, t.seats[0].stack);
		Assert.equals(300, t.seats[0].stack + t.seats[1].stack + t.seats[2].stack);
	}

	function testMinimumRaiseAndShortAllInDoesNotReopen() {
		var t = table([100, 100, 9, 100]);
		t.startHand(rng("short"));
		// UTG (3) raises to 6: the next full raise must be to at least 10.
		t.act(3, RaiseTo(6));
		Assert.equals(10, t.legal(0).minRaiseTo);
		Assert.raises(() -> t.act(0, RaiseTo(8)));
		t.act(0, Call);
		t.act(1, Call);
		// Big blind (9 chips total) shoves to 9: a short raise.
		t.act(2, RaiseTo(9));
		// UTG already acted and faces only a short raise: may call or fold, not re-raise.
		Assert.equals(3, t.toAct);
		Assert.isFalse(t.legal(3).canRaise);
	}

	function testSidePots() {
		// Seat 1 is all-in for 20; seats 0 and 2 keep betting.
		var t = table([100, 20, 100]);
		t.startHand(rng("side"));
		t.act(0, RaiseTo(20));
		t.act(1, Call);
		t.act(2, Call);
		// Flop onward: 0 bets 30, 2 calls; then check it down.
		while (t.phase == Betting) {
			var s = t.toAct;
			var l = t.legal(s);
			t.act(s, l.toCall > 0 ? Call : t.street == 1 && s == 2 ? RaiseTo(30) : Check);
		}
		Assert.equals(HandOver, t.phase);
		Assert.equals(220, t.seats[0].stack + t.seats[1].stack + t.seats[2].stack);
		// Seat 1 can never win more than the main pot of 60.
		Assert.isTrue(t.seats[1].stack <= 60);
	}

	function testDrawRoundThrowsInWhenEveryoneChecksAndCarriesThePot() {
		var t = table([50, 50, 50], Draw);
		t.startHand(rng("draw-check"));
		Assert.equals(3, t.pot); // antes
		for (_ in 0...3) t.act(t.toAct, Check);
		Assert.isTrue(t.thrownIn);
		Assert.equals(3, t.carried);
		t.startHand(rng("draw-check-2"));
		Assert.equals(6, t.pot);
	}

	function testDrawExchangeAndSecondRoundOpener() {
		var t = table([50, 50, 50], Draw);
		t.startHand(rng("draw"));
		// Seat 1 (left of the button) opens; the others call.
		t.act(1, RaiseTo(4));
		t.act(2, Call);
		t.act(0, Call);
		Assert.equals(Drawing, t.phase);
		Assert.equals(1, t.drawer);
		Assert.raises(() -> t.exchange(1, t.seats[1].cards.slice(0, 4)));
		t.exchange(1, t.seats[1].cards.slice(0, 3));
		t.exchange(2, []);
		t.exchange(0, t.seats[0].cards.slice(0, 1));
		for (s in t.seats) Assert.equals(5, s.cards.length);
		Assert.equals(Betting, t.phase);
		Assert.equals(1, t.toAct); // the opener starts the second round
	}

	/** AI-only sessions: every action is legal, chips are conserved, hands finish. **/
	function testAiSessionsConserveChips() {
		for (variant in [Holdem, Draw]) {
			var t = table([60, 60, 60, 60], variant);
			var r = rng('ai/$variant');
			var style = {looseness: .5, aggression: .5};
			var hands = 0;
			while (t.canStart() && hands < 25) {
				t.startHand(r);
				hands++;
				var guard = 0;
				while ((t.phase == Betting || t.phase == Drawing) && guard++ < 500) {
					if (t.phase == Drawing) t.exchange(t.drawer, PokerAi.discards(t.seats[t.drawer].cards));
					else t.act(t.toAct, PokerAi.decide(t, t.toAct, r, style, 20));
				}
				Assert.equals(HandOver, t.phase);
				var chips = t.carried;
				for (s in t.seats) chips += s.stack;
				Assert.equals(240, chips);
			}
		}
	}

	function testDrawDiscards() {
		Assert.equals(3, PokerAi.discards(h("9h 9s 2d 4c 7h")).length);
		Assert.equals(0, PokerAi.discards(h("9h Ts Jd Qc Kh")).length);
		Assert.equals(1, PokerAi.discards(h("2h 7h 9h Jh Kc")).length);
		Assert.equals(1, PokerAi.discards(h("9h 9s 2d 2c 7h")).length);
	}

	static function rng(label:String) return ChaChaRng.fromSeed(TestUtil.countingSeed()).fork('test-poker/$label');
}
