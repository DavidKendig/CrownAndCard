// SPDX-License-Identifier: AGPL-3.0-or-later
package games.slots;

/** Angular rigid lever with inertia, gravity, torsion spring, damping and hard stops. */
class LeverPhysics {
	public static inline var MAX_ANGLE=2.0;
	public static inline var TRIGGER_ANGLE=1.55;
	public var angle(default,null)=0.;
	public var velocity(default,null)=0.;
	public var held(default,null)=false;
	public var latched(default,null)=false;
	var target=0.;
	var assist=0.;
	var accumulator=0.;
	public function new() {}
	public function grab():Void {held=true;target=angle;assist=0;}
	public function drag(to:Float):Void {target=Math.max(0,Math.min(MAX_ANGLE,to));}
	public function release():Void {held=false;assist=0;}
	/** Keyboard/controller pulls apply the same hand spring as dragging. */
	public function pull():Void {if(latched || held) return;grab();target=MAX_ANGLE;assist=.65;}
	public function reset():Void {angle=velocity=target=assist=accumulator=0;held=latched=false;}
	/** Returns one trigger edge per full pull; no outcome randomness is consumed. */
	public function update(dt:Float):Bool {
		var fired=false,step=1/240;
		accumulator+=Math.max(0,Math.min(dt,.25));
		while(accumulator>=step) {
			accumulator-=step;
			if(assist>0) {assist-=step;if(assist<=0) held=false;}
			var torque=-16*angle-3.2*velocity+2*Math.sin(angle);
			if(held) torque+=190*(target-angle)-12*velocity;
			velocity+=torque/.65*step;angle+=velocity*step;
			if(angle<0) {angle=0;if(velocity<0) velocity*=-.22;}
			if(angle>MAX_ANGLE) {angle=MAX_ANGLE;if(velocity>0) velocity*=-.15;}
			if(!latched && angle>=TRIGGER_ANGLE) {latched=true;fired=true;}
			if(latched && !held && angle<.08 && Math.abs(velocity)<.6) latched=false;
			if(!held && angle<.001 && Math.abs(velocity)<.02) angle=velocity=0;
		}
		return fired;
	}
}
