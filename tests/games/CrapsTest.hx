// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import games.craps.Craps;
import utest.Assert;

/** Feeds `roll()` a scripted sequence of dice, two `between()` calls per roll. **/
private class StackedRng implements rng.IRng {
	final queue:Array<Int>;
	var pos = 0;

	public function new(queue:Array<Int>) this.queue = queue;

	function next():Int {
		if (pos >= queue.length) throw "StackedRng ran out of values";
		return queue[pos++];
	}

	public function nextU32():Int throw "not used by Craps";
	public function below(bound:Int):Int return next();
	public function between(lo:Int, hi:Int):Int return next();
	public function nextFloat():Float throw "not used by Craps";
	public function chance(p:Float):Bool throw "not used by Craps";
	public function shuffle<T>(items:Array<T>):Void throw "not used by Craps";
	public function pickWeighted<T>(items:Array<T>, weights:Array<Int>):T throw "not used by Craps";
}

class CrapsTest extends utest.Test {
	function table(dice:Array<Int>, purse = 1000):Craps return new Craps(new StackedRng(dice), purse);

	function testPassLineWinsSevenOnComeOut() {
		var g = table([3, 4]); // 7
		g.betPassLine(10);
		var r = g.roll();
		Assert.equals(7, r.total);
		Assert.isNull(g.point);
		Assert.equals(0, g.passLine);
		Assert.equals(1010, g.purse);
	}

	function testPassLineLosesCrapsOnComeOut() {
		var g = table([1, 1]); // 2
		g.betPassLine(10);
		g.betDontPass(10);
		g.roll();
		Assert.equals(0, g.passLine);
		Assert.equals(0, g.dontPass);
		// Pass loses its 10; Don't Pass wins its 10 back plus 10 profit.
		Assert.equals(1000, g.purse);
	}

	function testDontPassPushesOnBarTwelve() {
		var g = table([6, 6]); // 12
		g.betPassLine(10);
		g.betDontPass(10);
		g.roll();
		// Pass loses its 10; Don't Pass just gets its 10 back.
		Assert.equals(990, g.purse);
	}

	function testPointMadeWithOdds() {
		var g = table([2, 3, 1, 4]); // point 5, then made on 5 again
		g.betPassLine(10);
		g.roll();
		Assert.equals(5, g.point);
		g.betPassOdds(40); // 4x on a 5, the cap
		Assert.raises(() -> g.betPassOdds(1));
		g.roll();
		Assert.isNull(g.point);
		Assert.equals(0, g.passLine);
		Assert.equals(0, g.passOdds);
		// 1000 - 10 - 40 + (20 line return) + (40 + 60 odds return) = 1070.
		Assert.equals(1070, g.purse);
	}

	function testSevenOutPaysDontPassOdds() {
		var g = table([2, 4, 3, 4]); // point 6, then seven-out
		g.betDontPass(10);
		g.roll();
		Assert.equals(6, g.point);
		g.betDontPassOdds(30); // 5x on a 6, the cap
		g.roll();
		Assert.isNull(g.point);
		Assert.equals(0, g.dontPass);
		Assert.equals(0, g.dontPassOdds);
		// 1000 - 10 - 30 + (20 line return) + (30 + 25 odds return) = 1035.
		Assert.equals(1035, g.purse);
	}

	function testFieldPaysDoubleOnTwoAndTwelve() {
		var g = table([1, 1]); // 2
		g.betField(10);
		g.roll();
		Assert.equals(1020, g.purse); // 1000 - 10 + 30
	}

	function testFieldLosesOnSeven() {
		var g = table([3, 4]); // 7
		g.betField(10);
		g.roll();
		Assert.equals(990, g.purse);
	}

	function testPlaceBetPays() {
		var g = table([1, 3, 2, 4]); // point 4, then 6 (2+4)
		g.roll();
		g.betPlace(6, 30);
		g.roll();
		Assert.equals(4, g.point); // unaffected: 6 isn't the point or a seven
		Assert.equals(30, g.place.get(6)); // stays working
		// 1000 - 30 + (30 + 35 profit) = 1035.
		Assert.equals(1035, g.purse);
	}

	function testHardwayWinsOnThePair() {
		var g = table([2, 3, 3, 3]); // point 5, then hard 6
		g.roll();
		g.betHardway(6, 10);
		g.roll();
		Assert.equals(0, g.hardway.get(6));
		// 1000 - 10 + 100 (9:1 on hard 6) = 1090.
		Assert.equals(1090, g.purse);
	}

	function testHardwayLosesTheEasyWay() {
		var g = table([2, 3, 1, 3]); // point 5, then easy 4 (1+3)
		g.roll();
		g.betHardway(4, 10);
		g.roll();
		Assert.equals(0, g.hardway.get(4));
		Assert.equals(990, g.purse);
	}

	function testComeBetEstablishesAndWinsItsOwnPoint() {
		var g = table([2, 4, 2, 3, 2, 3]); // point 6, come point 5, come 5 hits again
		g.roll();
		Assert.equals(6, g.point);
		g.betCome(10);
		g.roll(); // 2+3 = 5, establishes the come point
		Assert.equals(1, g.come.length);
		Assert.equals(5, g.come[0].point);
		g.roll(); // 2+3 = 5 again, the come point hits
		Assert.equals(0, g.come.length);
		Assert.equals(1010, g.purse); // 1000 - 10 + 20
	}

	function testDontComeLosesWhenItsPointRepeats() {
		var g = table([2, 4, 3, 6, 3, 6]); // point 6, don't-come point 9, 9 repeats
		g.roll();
		g.betDontCome(10);
		g.roll(); // 3+6 = 9, establishes the don't-come point
		Assert.equals(9, g.dontCome[0].point);
		g.roll(); // 3+6 = 9 again: the don't-come bet loses
		Assert.equals(0, g.dontCome.length);
		Assert.equals(990, g.purse);
	}

	function testSevenOutClearsComeAndDontCome() {
		var g = table([2, 4, 2, 3, 3, 4]); // point 6, come point 5, seven-out
		g.roll();
		g.betCome(10);
		g.betDontCome(10);
		g.roll(); // 2+3 = 5, come point established; don't-come pending craps or point?
		g.roll(); // 3+4 = 7, seven-out
		Assert.equals(0, g.come.length);
		Assert.equals(0, g.dontCome.length);
		Assert.isNull(g.point);
	}

	function testAnySevenAnyCrapsYoAndHiLo() {
		var g = table([3, 4]); // 7
		g.betAnySeven(10);
		g.roll();
		Assert.equals(1040, g.purse); // 1000 - 10 + 50

		g = table([1, 2]); // 3
		g.betAnyCraps(10);
		g.roll();
		Assert.equals(1070, g.purse); // 1000 - 10 + 80

		g = table([5, 6]); // 11
		g.betYo(10);
		g.roll();
		Assert.equals(1150, g.purse); // 1000 - 10 + 160

		g = table([1, 1]); // 2
		g.betHiLo(10);
		g.roll();
		Assert.equals(1150, g.purse); // 1000 - 10 + 160
	}

	function testCanOnlyBetTheLineOnTheComeOut() {
		var g = table([2, 3]); // sets a point
		g.roll();
		Assert.raises(() -> g.betPassLine(10));
		Assert.raises(() -> g.betDontPass(10));
	}
}
