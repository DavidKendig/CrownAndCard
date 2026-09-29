// SPDX-License-Identifier: AGPL-3.0-or-later
package games.roulette;

/** Cosmetic choreography only: the outcome stream is never read here. */
class WheelMotion {
	public static final POCKETS = [0,32,15,19,4,21,2,25,17,34,6,27,13,36,11,30,8,23,10,5,24,16,33,1,20,14,31,9,22,18,29,7,28,12,35,3,26];
	public static inline var DURATION = 8.0;
	public var active(default,null)=false;
	public var elapsed(default,null)=0.;
	public var wheel(default,null)=0.;
	public var ball(default,null)=-Math.PI/2;
	public var radius(default,null)=.755;
	public var bounce(default,null)=0.;
	var origin=0.;
	var target=0.;
	var offset=0.;
	static inline var TAU=6.283185307179586;

	public function new() {}
	public function start(pocket:Int):Void {
		var index=POCKETS.indexOf(pocket);
		if(index<0) throw "Invalid roulette pocket";
		origin=wheel%TAU;offset=index*TAU/37-Math.PI/2;
		elapsed=0;active=true;
		// Match the chosen pocket at capture, keeping the ball moving counterclockwise.
		var capture=wheelAt(7)+offset;
		var approach=orbit(5);
		target=capture-TAU*Math.ceil((capture-approach)/TAU)-TAU;
		sample();
	}
	public function update(dt:Float):Void {
		if(!active) return;
		elapsed=Math.min(DURATION,elapsed+Math.max(0,dt));sample();
		if(elapsed>=DURATION) active=false;
	}
	function wheelAt(t:Float):Float return origin+TAU*3*(1-Math.pow(1-t/DURATION,3));
	static function orbit(t:Float):Float return -Math.PI/2-TAU*(5*t-.35*t*t);
	function sample():Void {
		wheel=wheelAt(elapsed);bounce=0;
		if(elapsed<=5) {ball=orbit(elapsed);radius=.755;}
		else if(elapsed<7) {
			var t=(elapsed-5)/2,s=t*t*(3-2*t);
			// Hermite curve preserves the approach velocity and meets the moving pocket.
			var a=orbit(5),v0=-TAU*1.5*2,v1=TAU*9/8*Math.pow(1-7/8,2)*2;
			ball=(2*t*t*t-3*t*t+1)*a+(t*t*t-2*t*t+t)*v0+(-2*t*t*t+3*t*t)*target+(t*t*t-t*t)*v1;
			radius=.755-.205*s;
			bounce=Math.sin(Math.PI*t)*Math.abs(Math.sin(t*Math.PI*5))*.045;
			radius+=bounce;
		} else {ball=wheel+offset;radius=.55;}
	}
}
