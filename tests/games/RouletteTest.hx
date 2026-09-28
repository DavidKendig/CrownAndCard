// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import games.roulette.Roulette;
import utest.Assert;

/** Always spins to the same pocket. **/
private class FixedRng implements rng.IRng {
	final pocket:Int;

	public function new(pocket:Int) this.pocket = pocket;

	public function nextU32():Int throw "not used by Roulette";
	public function below(bound:Int):Int return pocket;
	public function between(lo:Int, hi:Int):Int return pocket;
	public function nextFloat():Float throw "not used by Roulette";
	public function chance(p:Float):Bool throw "not used by Roulette";
	public function shuffle<T>(items:Array<T>):Void throw "not used by Roulette";
	public function pickWeighted<T>(items:Array<T>, weights:Array<Int>):T throw "not used by Roulette";
}

class RouletteTest extends utest.Test {
	function wheel(pocket:Int, purse = 1000):Roulette return new Roulette(new FixedRng(pocket), purse);

	function testStraightUpPaysThirtyFiveToOne() {
		var g = wheel(17);
		var r = g.spin([Roulette.straight(17, 10)]);
		Assert.equals(17, r.pocket);
		Assert.isTrue(r.results[0].won);
		Assert.equals(360, r.results[0].payout); // 10 + 10*35
		Assert.equals(1350, g.purse); // 1000 - 10 + 360
	}

	function testStraightUpLoses() {
		var g = wheel(5);
		var r = g.spin([Roulette.straight(17, 10)]);
		Assert.isFalse(r.results[0].won);
		Assert.equals(0, r.results[0].payout);
		Assert.equals(990, g.purse);
	}

	function testLaPartageReturnsHalfOnZero() {
		var g = wheel(0);
		var r = g.spin([Roulette.outside(Red, 10)]);
		Assert.isFalse(r.results[0].won);
		Assert.isTrue(r.results[0].partaged);
		Assert.equals(5, r.results[0].payout);
		Assert.equals(995, g.purse);
	}

	function testRedBlackOddEvenLowHigh() {
		var g = wheel(19); // red, odd, high
		Assert.isTrue(Roulette.isRed(19));
		var r = g.spin([Roulette.outside(Red, 10), Roulette.outside(Black, 10), Roulette.outside(Odd, 10), Roulette.outside(Even, 10),
			Roulette.outside(Low, 10), Roulette.outside(High, 10)]);
		Assert.isTrue(r.results[0].won); // Red
		Assert.isFalse(r.results[1].won); // Black
		Assert.isTrue(r.results[2].won); // Odd
		Assert.isFalse(r.results[3].won); // Even
		Assert.isFalse(r.results[4].won); // Low (1-18)
		Assert.isTrue(r.results[5].won); // High (19-36)
	}

	function testZeroWinsNoEvenMoneyBet() {
		var g = wheel(0);
		var r = g.spin([Roulette.outside(Red, 10), Roulette.outside(Black, 10), Roulette.outside(Odd, 10), Roulette.outside(Even, 10),
			Roulette.outside(Low, 10), Roulette.outside(High, 10)]);
		for (o in r.results) Assert.isFalse(o.won);
	}

	function testDozensAndColumns() {
		var g = wheel(5); // first dozen, second column
		var r = g.spin([Roulette.dozen(1, 10), Roulette.dozen(2, 10), Roulette.dozen(3, 10), Roulette.column(1, 10), Roulette.column(2, 10),
			Roulette.column(3, 10)]);
		Assert.isTrue(r.results[0].won); // 1st dozen
		Assert.isFalse(r.results[1].won);
		Assert.isFalse(r.results[2].won);
		Assert.isFalse(r.results[3].won); // column 1 is 1,4,7... 5 isn't in it
		Assert.isTrue(r.results[4].won); // column 2 is 2,5,8...
		Assert.isFalse(r.results[5].won);
	}

	function testSplitStreetCornerSixLineShapes() {
		Assert.same([1, 2], Roulette.split(1, 2, 5).numbers);
		Assert.same([4, 5, 6], Roulette.street(2, 5).numbers);
		Assert.same([1, 2, 4, 5], Roulette.corner(1, 5).numbers);
		Assert.same([0, 1, 2, 3], Roulette.basket(5).numbers);
		Assert.same([1, 2, 3, 4, 5, 6], Roulette.sixLine(1, 5).numbers);
	}

	function testInsideBetsPayByHowManyNumbersTheyCover() {
		var g = wheel(2);
		var r = g.spin([Roulette.split(1, 2, 10), Roulette.street(1, 10), Roulette.corner(1, 10), Roulette.sixLine(1, 10)]);
		for (o in r.results) Assert.isTrue(o.won);
		Assert.equals(10 + 10 * 17, r.results[0].payout);
		Assert.equals(10 + 10 * 11, r.results[1].payout);
		Assert.equals(10 + 10 * 8, r.results[2].payout);
		Assert.equals(10 + 10 * 5, r.results[3].payout);
	}

	function testCannotBetMoreThanThePurse() {
		var g = wheel(0, 5);
		Assert.raises(() -> g.spin([Roulette.straight(1, 10)]));
	}
}
