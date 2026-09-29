// SPDX-License-Identifier: AGPL-3.0-or-later
package games.roulette;

import games.roulette.Roulette;

typedef BettingSpot = {
	var label:String;
	var bet:Bet;
	var x:Float;
	var y:Float;
	var w:Float;
	var h:Float;
	var small:Bool;
}

/** One geometry definition for painting, mouse hit-testing and keyboard navigation. */
class BettingLayout {
	public static inline var X = 204;
	public static inline var Y = 86;
	public static inline var CW = 27;
	public static inline var CH = 36;
	public final spots:Array<BettingSpot> = [];

	public function new() {
		add("0", Roulette.straight(0,1), X-26,Y,26,CH*3);
		for (col in 0...12) for (row in 0...3) {
			var n=col*3+3-row;
			add(Std.string(n),Roulette.straight(n,1),X+col*CW,Y+row*CH,CW,CH);
		}
		for (row in 0...3) add('2:1',Roulette.column(3-row,1),X+12*CW,Y+row*CH,28,CH);
		for (i in 0...3) add(['1st 12','2nd 12','3rd 12'][i],Roulette.dozen(i+1,1),X+i*CW*4,214,CW*4,25);
		var kinds:Array<BetKind>=[Low,Even,Red,Black,Odd,High];
		for (i in 0...6) add(['1-18','EVEN','RED','BLACK','ODD','19-36'][i],Roulette.outside(kinds[i],1),X+i*CW*2,244,CW*2,28);
		// Small targets are added last so intersections win over the surrounding cells.
		for (col in 0...12) for (row in 1...3) {
			var lower=col*3+3-row;
			point('Split $lower/${lower+1}',Roulette.split(lower,lower+1,1),X+(col+.5)*CW,Y+row*CH);
		}
		for (col in 1...12) for (row in 0...3) {
			var a=(col-1)*3+3-row;
			point('Split $a/${a+3}',Roulette.split(a,a+3,1),X+col*CW,Y+(row+.5)*CH);
		}
		for (col in 1...12) for (row in 1...3) {
			var a=(col-1)*3+3-row;
			point('Corner $a/${a+1}/${a+3}/${a+4}',Roulette.corner(a,1),X+col*CW,Y+row*CH);
		}
		for (row in 0...3) point('Split 0/${3-row}',Roulette.split(0,3-row,1),X,Y+(row+.5)*CH);
		for (col in 0...12) point('Street ${col*3+1}-${col*3+3}',Roulette.street(col+1,1),X+(col+.5)*CW,199);
		for (col in 1...12) point('Six line ${(col-1)*3+1}-${col*3+3}',Roulette.sixLine(col,1),X+col*CW,199);
		point('Basket 0/1/2/3',Roulette.basket(1),X,199);
	}
	function add(label:String,bet:Bet,x:Float,y:Float,w:Float,h:Float,small=false):Void
		spots.push({label:label,bet:bet,x:x,y:y,w:w,h:h,small:small});
	function point(label:String,bet:Bet,x:Float,y:Float):Void add(label,bet,x-4,y-4,8,8,true);
	public function hit(x:Float,y:Float):Int {
		var i=spots.length;
		while(i-->0) {var s=spots[i];if(x>=s.x && x<s.x+s.w && y>=s.y && y<s.y+s.h)return i;}
		return -1;
	}
	public function description(i:Int):String {
		if(i<0 || i>=spots.length)return "Choose chips, then click the mat.";
		var s=spots[i], b=s.bet;
		var name=b.kind==Straight?'Number ${b.numbers[0]}':b.kind==Column?'Column ${b.group}':s.label;
		return '$name - pays ${Roulette.odds(b.kind)} to 1';
	}
	public function neighbor(i:Int,dx:Int,dy:Int):Int {
		var s=spots[i],cx=s.x+s.w/2,cy=s.y+s.h/2,best=i,score=Math.POSITIVE_INFINITY;
		for(j in 0...spots.length) if(j!=i) {
			var t=spots[j],x=t.x+t.w/2-cx,y=t.y+t.h/2-cy;
			var forward=x*dx+y*dy,across=Math.abs(x*dy-y*dx);
			if(forward<=1)continue;
			var d=forward+across*4;
			if(d<score){score=d;best=j;}
		}
		return best;
	}
}
