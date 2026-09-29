// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import cards.Card;
import games.parlour.War;
import games.rummy.GinRummy;
import rng.ChaChaRng;
import utest.Assert;

/** The play log (§13.12): the models report each play, named by seat, and only what the table can see. **/
class PlayLogTest extends utest.Test {
	var lines:Array<String>;

	static function h(codes:String):Array<Card> return [for (c in codes.split(" ")) Card.parse(c)];

	function setup() {
		lines = [];
		PlayLog.sink = (table, text) -> lines.push('$table · $text');
	}

	function teardown() {
		PlayLog.sink = null;
		PlayLog.sitAt("", []);
	}

	function testPlaysAreNamedBySeatAtTheTable() {
		PlayLog.sitAt("War", ["You", "Sir Reggie"]);
		var g = War.fromStacks(h("Kc 2d"), h("Qh 3s"), ChaChaRng.fromSeed(TestUtil.countingSeed()).fork("test-playlog/war"));
		g.battle();
		Assert.same(["War · You K♣, Sir Reggie Q♥", "War · You: takes 2 cards"], lines);
	}

	function testStockDrawsStayHiddenButDiscardsShow() {
		PlayLog.sitAt("Gin Rummy", ["You", "The Deacon"]);
		var g = new GinRummy();
		g.startDeal(h("2c 2d 2h 2s 3c 3d 3h 3s 4c 4d 4h 4s 5c 5d 5h 5s 6c 6d 6h 6s 7c 7d 7h"));
		g.drawFromStock(0);
		Assert.equals("Gin Rummy · You: draws from the stock", lines[0]);
		var card = g.hands[0][0];
		g.discard(0, card);
		Assert.equals("Gin Rummy · You: discards " + card.toString(), lines[1]);
	}

	function testQuietlyRecordsNothing() {
		var g = War.fromStacks(h("Kc 2d"), h("Qh 3s"), ChaChaRng.fromSeed(TestUtil.countingSeed()).fork("test-playlog/quiet"));
		var result = PlayLog.quietly(() -> g.battle());
		Assert.equals(War.YOU, result.winner);
		Assert.equals(0, lines.length);
		// Recording resumes afterwards.
		g.battle();
		Assert.isTrue(lines.length > 0);
	}

	function testNothingIsRecordedWithoutASink() {
		PlayLog.sink = null;
		var g = War.fromStacks(h("Kc 2d"), h("Qh 3s"), ChaChaRng.fromSeed(TestUtil.countingSeed()).fork("test-playlog/none"));
		g.battle();
		Assert.equals(0, lines.length);
	}
}
