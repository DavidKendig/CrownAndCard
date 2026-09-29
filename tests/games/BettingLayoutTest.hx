// SPDX-License-Identifier: AGPL-3.0-or-later
package games;
import games.roulette.BettingLayout;
import games.roulette.BettingTray;
import games.roulette.Roulette;
import utest.Assert;

class BettingLayoutTest extends utest.Test {
	function testAllNumberCentersAndOutsideBets() {
		var l=new BettingLayout(),seen=new Map<Int,Bool>();
		for(s in l.spots) if(!s.small) {
			var found=l.spots[l.hit(s.x+s.w/2,s.y+s.h/2)];
			Assert.equals(s.bet.kind,found.bet.kind);
			Assert.same(s.bet.numbers,found.bet.numbers);
			if(s.bet.kind==Straight)seen.set(s.bet.numbers[0],true);
		}
		for(n in 0...37)Assert.isTrue(seen.exists(n));
		Assert.equals(-1,l.hit(10,10));
	}
	function testIntersectionsSelectExactLegalCoverage() {
		var l=new BettingLayout();
		var split=l.spots[l.hit(231,104)].bet;Assert.equals(Split,split.kind);Assert.same([3,6],split.numbers);
		var corner=l.spots[l.hit(231,122)].bet;Assert.equals(Corner,corner.kind);Assert.same([2,3,5,6],corner.numbers);
		var street=l.spots[l.hit(217.5,199)].bet;Assert.equals(Street,street.kind);Assert.same([1,2,3],street.numbers);
		var six=l.spots[l.hit(231,199)].bet;Assert.equals(SixLine,six.kind);Assert.same([1,2,3,4,5,6],six.numbers);
		Assert.same([0,1,2,3],l.spots[l.hit(204,199)].bet.numbers);
		Assert.same([0,2],l.spots[l.hit(204,140)].bet.numbers);
		for(s in l.spots)if(s.small)Assert.same(s.bet.numbers,l.spots[l.hit(s.x+4,s.y+4)].bet.numbers);
	}
	function testBuildPlaceUndoAndClearReservations() {
		var l=new BettingLayout(),t=new BettingTray();
		Assert.isTrue(t.add(25,100));Assert.isTrue(t.add(25,100));Assert.isTrue(t.add(5,100));
		Assert.equals(55,t.inHand());Assert.equals(45,t.available(100));Assert.isFalse(t.add(50,100));
		Assert.isFalse(t.place(-1,l));Assert.equals(55,t.inHand());
		Assert.isTrue(t.place(1,l));Assert.equals(55,t.onMat());Assert.equals(0,t.inHand());
		Assert.isTrue(t.add(10,100));t.undo();Assert.equals(55,t.onMat());Assert.equals(0,t.inHand());
		t.undo();Assert.equals(100,t.available(100));
		t.add(100,100);t.place(0,l);t.clear();Assert.equals(100,t.available(100));
	}
	function testCannotSpinUnplacedChipsOrModifySpinningBets() {
		var l=new BettingLayout(),t=new BettingTray();
		Assert.equals(0,t.start(l).length);t.add(10,100);t.place(0,l);t.add(5,100);
		Assert.equals(0,t.start(l).length);Assert.isFalse(t.locked);t.undo();
		var bets=t.start(l);Assert.equals(1,bets.length);Assert.equals(10,bets[0].amount);Assert.same([0],bets[0].numbers);
		Assert.isTrue(t.locked);Assert.isFalse(t.add(1,100));Assert.isFalse(t.place(2,l));
		t.undo();t.clear();Assert.equals(10,t.onMat());Assert.equals(0,t.start(l).length);
		t.finish();Assert.isFalse(t.locked);Assert.equals(0,t.onMat());
	}
	function testRepeatedPlacementAndBalanceLimits() {
		var l=new BettingLayout(),t=new BettingTray();
		Assert.isFalse(t.add(0,100));Assert.isFalse(t.add(-1,100));Assert.isFalse(t.add(250,100));
		t.add(50,100);t.place(1,l);t.add(50,100);t.place(1,l);
		Assert.equals(0,t.available(100));Assert.isFalse(t.add(1,100));
		var bets=t.start(l);Assert.equals(2,bets.length);Assert.equals(100,bets[0].amount+bets[1].amount);
	}
}
