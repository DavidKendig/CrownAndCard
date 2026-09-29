// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

/** Analytic, frame-rate-independent water motion, in metres and seconds. */
class FountainFlow {
	public static inline var GRAVITY = 9.81;
	public static function flightTime(top:Float, bottom:Float):Float
		return Math.sqrt(2 * Math.max(0,top-bottom) / GRAVITY);
	public static function position(r0:Float, top:Float, r1:Float, bottom:Float, time:Float):{r:Float,z:Float} {
		var duration=flightTime(top,bottom), t=Math.max(0,Math.min(duration,time));
		return {r:duration==0?r0:r0+(r1-r0)*t/duration, z:top-.5*GRAVITY*t*t};
	}
	/** Conservation of volume: an accelerating stream becomes narrower. */
	public static function width(speed:Float,time:Float):Float
		return .03 * Math.sqrt(speed / Math.sqrt(speed*speed+GRAVITY*GRAVITY*time*time));
	public static function splashHeight(upSpeed:Float,time:Float):Float
		return Math.max(0,upSpeed*time-.5*GRAVITY*time*time);
}
