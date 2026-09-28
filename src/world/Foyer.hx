// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

/** Authored entrance layout. Stair collision is independent of the removable ropes. */
class Foyer {
	public static final START = {x: 13.0, y: 4.0, yaw: Math.PI / 2};
	public static final KEEPER = {x: 13.0, y: 7.8};
	public static final FOUNTAIN = {x: 13.0, y: 11.0};

	public static function atDoor(x:Float, y:Float):Bool {
		return x > 11 && x < 15 && y < 2.2 && y >= 1;
	}

	public static function atDesk(x:Float, y:Float, yaw:Float):Bool {
		return x > 10.8 && x < 15.2 && y >= 3.6 && y < 6.0 && Math.sin(yaw) > 0.55;
	}

	public static function furnish(map:GridMap):Void {
		function box(x0:Float, y0:Float, x1:Float, y1:Float, top:Float, tex:String, base:Float = 0, solid:Bool = true) {
			map.props.push({x0:x0, y0:y0, x1:x1, y1:y1, height:top, baseZ:base, topTex:tex, sideTex:tex, solid:solid});
		}
		// Broad desk, overhanging marble counter, brass plinth, and the Guest Register.
		box(10.8, 6.1, 15.2, 7.3, 1.08, "tableWood");
		box(10.65, 6.0, 15.35, 7.4, 1.16, "stone", 1.08);
		box(10.75, 6.05, 15.25, 7.35, 0.10, "brass");
		box(12.65, 6.45, 13.35, 6.9, 1.20, "ivory", 1.16, false);
		box(12.97, 6.44, 13.03, 6.91, 1.205, "brass", 1.2, false);
		for (x in [11.2, 14.8]) {
			box(x-.10, 6.6, x+.10, 6.8, 1.22, "brass", 1.16, false);
			box(x-.03, 6.67, x+.03, 6.73, 1.57, "ivory", 1.22, false);
			box(x-.025, 6.67, x+.025, 6.73, 1.65, "flame", 1.57, false);
		}
		// Circular collision follows the 3D fountain rim; the keeper also has a solid footprint.
		map.props.push({x0:11.4,y0:9.4,x1:14.6,y1:12.6,height:.5,topTex:"stone",sideTex:"stone",hidden:true,collisionRadius:1.72});
		map.props.push({x0:12.65,y0:7.45,x1:13.35,y1:8.15,height:2,topTex:"stone",sideTex:"stone",hidden:true});
		// Twenty true treads rise to a 3.6 m landing. Future access only needs rope removal.
		for (i in 0...20) {
			var y = 14.5 + i * .3, z = (i + 1) * .18;
			map.props.push({x0:9,y0:y,x1:17,y1:y+.3,height:z,topTex:"stone",sideTex:"stone",walkable:true,kind:"stair"});
			box(11.25, y, 14.75, y+.3, z+.008, "carpet", z, false);
			// Brass nosings make the individual risers legible from the entrance.
			box(9.05,y-.012,16.95,y+.035,z+.012,"brass",z-.025,false);
			for (x in [9.12,16.88]) {
				box(x-.07,y+.10,x+.07,y+.20,z+.9,"ivory",z,false);
				box(x-.11,y,x+.11,y+.3,z+1,"brass",z+.92,false);
			}
		}
		// Closed north wall marks the future upper-floor entrance.
		map.props.push({x0:9,y0:20.5,x1:17,y1:21,height:3.6,topTex:"stone",sideTex:"stone",walkable:true,kind:"landing"});
		box(11.25,20.5,14.75,20.98,3.608,"carpet",3.6,false);
		for (x in [9.1,16.9]) box(x-.25,14.3,x+.25,14.8,1.25,"ivory");
		rope(map, 8.6, 13.9, 17.4, 13.9);
		rope(map, 8.6, 13.9, 8.6, 20.8);
		rope(map, 17.4, 13.9, 17.4, 20.8);
		// Tall pilasters, capitals and gilded cornices articulate the double-height hall.
		for (x in [3.6,22.4]) for (y in [3.5,8.5,13.5,18.5]) {
			box(x-.4,y-.4,x+.4,y+.4,.32,"stone");
			box(x-.24,y-.24,x+.24,y+.24,6.9,"ivory",.32);
			box(x-.38,y-.38,x+.38,y+.38,7.1,"brass",6.9,false);
		}
		for (x in [3.05,22.65]) box(x,1,x+.3,21,7.35,"brass",7.18,false);
		// Burgundy runner from the grand doors to the desk.
		box(11.3,1.02,14.7,5.95,.012,"carpet",0,false);
	}

	static function rope(map:GridMap, x0:Float, y0:Float, x1:Float, y1:Float):Void {
		map.props.push({x0:x0-.09,y0:y0-.09,x1:x1+.09,y1:y1+.09,height:1,topTex:"brass",sideTex:"brass",hidden:true,kind:"rope"});
		var length = Math.sqrt((x1-x0)*(x1-x0)+(y1-y0)*(y1-y0));
		var spans = Std.int(Math.ceil(length / 2.2));
		for (i in 0...spans+1) {
			var x = x0+(x1-x0)*i/spans, y = y0+(y1-y0)*i/spans;
			map.props.push({x0:x-.07,y0:y-.07,x1:x+.07,y1:y+.07,height:1.05,topTex:"brass",sideTex:"brass",solid:false});
		}
		var pieces = spans*12;
		for (i in 0...pieces) {
			var a = i/pieces, b = (i+1)/pieces;
			var z = .92 - .23*Math.sin(Math.PI*((i%12)+.5)/12);
			map.props.push({x0:x0+(x1-x0)*a-.025,y0:y0+(y1-y0)*a-.025,x1:x0+(x1-x0)*b+.025,y1:y0+(y1-y0)*b+.025,
				height:z+.065,baseZ:z,topTex:"velvet",sideTex:"velvet",solid:false});
		}
	}
}
