// SPDX-License-Identifier: AGPL-3.0-or-later
package render;

/** Batched ballistic droplets: normal stores launch velocity, uv.x stores phase. */
class FountainSplash extends hxsl.Shader {
	static var SRC = {
		@input var input:{var normal:Vec3; var uv:Vec2;};
		var relativePosition:Vec3;
		@param var time:Float;
		function vertex() {
			var life=2.*input.normal.z/9.81;
			var age=fract(time/life+input.uv.x)*life;
			relativePosition += input.normal*age-vec3(0.,0.,4.905*age*age);
		}
	};
	public function new() {super(); time=0;}
}
