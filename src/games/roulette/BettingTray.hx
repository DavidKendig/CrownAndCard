// SPDX-License-Identifier: AGPL-3.0-or-later
package games.roulette;
import games.roulette.Roulette;

typedef PlacedChips = {spot:Int, amount:Int};

/** Reservations stay local until Spin; locked layouts cannot be edited. */
class BettingTray {
	public static final DENOMINATIONS = [1,5,10,25,50,100,250];
	public final held:Array<Int> = [];
	public final placed:Array<PlacedChips> = [];
	public var locked(default,null)=false;
	public function new() {}
	public function inHand():Int {var sum=0;for(v in held)sum+=v;return sum;}
	public function onMat():Int {var sum=0;for(p in placed)sum+=p.amount;return sum;}
	public function available(purse:Int):Int return purse-inHand()-onMat();
	public function add(value:Int,purse:Int):Bool {
		if(locked || DENOMINATIONS.indexOf(value)<0 || value>available(purse))return false;
		held.push(value);return true;
	}
	public function place(spot:Int,layout:BettingLayout):Bool {
		if(locked || spot<0 || spot>=layout.spots.length || held.length==0)return false;
		placed.push({spot:spot,amount:inHand()});held.resize(0);return true;
	}
	public function undo():Void {if(locked)return;if(held.length>0)held.pop();else placed.pop();}
	public function clear():Void {if(locked)return;held.resize(0);placed.resize(0);}
	public function start(layout:BettingLayout):Array<Bet> {
		if(locked || placed.length==0 || held.length>0)return [];
		locked=true;
		return [for(p in placed) {var b=layout.spots[p.spot].bet;{kind:b.kind,numbers:b.numbers.copy(),group:b.group,amount:p.amount};}];
	}
	public function finish():Void {locked=false;clear();}
}
