// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import art.FoyerArt;
import h3d.col.Point;
import h3d.prim.UV;
import render.BuildShader;
import render.MeshBuilder;
import render.Palette;

/** Closed 3D beds, batched across the manor into two PNG-textured meshes.
	The atlas is a 4 x 4 sheet. UVs are local to each face, including the
	undersides: neither world tiling nor an untextured back face is used. */
class FourPosterBed {
	public static inline var ATLAS = "materials/bed-surface-atlas.png";
	public static inline var COVERLET = "materials/bed-coverlet-top.png";
	static inline var TICKING = 1;
	static inline var PILLOW = 2;
	static inline var CURTAIN = 3;
	static inline var HEADBOARD = 4;
	static inline var FOOTBOARD = 5;
	static inline var RAIL = 6;
	static inline var WOOD = 7;
	static inline var POST = 8;
	static inline var BRASS = 9;
	static inline var CANOPY = 10;
	static inline var SILK = 11;
	static inline var FASCIA = 12;
	static inline var ENDGRAIN = 13;
	static inline var HEM = 14;
	static inline var BACKING = 15;

	public static function build(level:Level, palette:Palette, lut:h3d.mat.Texture, parent:h3d.scene.Object):Array<BuildShader> {
		var surfaces = new MeshBuilder(), coverlets = new MeshBuilder();
		for (bed in level.fixtures("fourPosterBed")) {
			var sector = level.map.sectorOn(bed.floor == null ? 0 : bed.floor, bed.x, bed.y);
			var shade = sector == null ? 6. : sector.shade;
			add(surfaces, coverlets, bed.x, bed.y, shade, level.elevation(bed.floor));
		}
		if (surfaces.isEmpty) return [];
		var shaders = [];
		for (entry in [{mesh:surfaces, path:ATLAS, size:1024}, {mesh:coverlets, path:COVERLET, size:256}]) {
			var material = h3d.mat.Material.create();
			material.mainPass.enableLights = false;
			material.shadows = false;
			material.mainPass.culling = None;
			var shader = new BuildShader(FoyerArt.texture(false, false, entry.path, palette, entry.size, entry.size), lut, false);
			material.mainPass.addShader(shader);
			new h3d.scene.Mesh(entry.mesh.toPrimitive(), material, parent);
			shaders.push(shader);
		}
		return shaders;
	}

	static function add(atlas:MeshBuilder, cover:MeshBuilder, ax:Float, ay:Float, shade:Float, az:Float = 0):Void {
		inline function p(x:Float, y:Float, z:Float) return new Point(ax+x, ay+y, az+z);
		function face(tile:Int, a:Point, b:Point, c:Point, d:Point, normal:Point, bias:Float=0) {
			// Inset inside each tile avoids sampling its neighbor at the seam.
			var u=(tile%4)/4.+.002, v=Std.int(tile/4)/4.+.002, span=.246;
			atlas.quad(a,b,c,d,new UV(u,v),new UV(u+span,v),new UV(u+span,v+span),new UV(u,v+span),normal,shade+bias);
		}
		function box(x0:Float,y0:Float,z0:Float,x1:Float,y1:Float,z1:Float,top:Int,side:Int,bottom:Int,
				front:Int=-1,back:Int=-1) {
			face(top,p(x0,y1,z1),p(x1,y1,z1),p(x1,y0,z1),p(x0,y0,z1),new Point(0,0,1));
			face(bottom,p(x0,y0,z0),p(x1,y0,z0),p(x1,y1,z0),p(x0,y1,z0),new Point(0,0,-1),2);
			face(front<0?side:front,p(x0,y0,z1),p(x1,y0,z1),p(x1,y0,z0),p(x0,y0,z0),new Point(0,-1,0),1);
			face(back<0?side:back,p(x1,y1,z1),p(x0,y1,z1),p(x0,y1,z0),p(x1,y1,z0),new Point(0,1,0),1);
			face(side,p(x0,y1,z1),p(x0,y0,z1),p(x0,y0,z0),p(x0,y1,z0),new Point(-1,0,0),2);
			face(side,p(x1,y0,z1),p(x1,y1,z1),p(x1,y1,z0),p(x1,y0,z0),new Point(1,0,0),2);
		}
		// Frame and king mattress (76 x 80 inches, rounded to 1.93 x 2.03 m).
		box(-1.08,-1.14,.28,1.08,1.14,.49,WOOD,RAIL,ENDGRAIN);
		box(-.965,-1.015,.49,.965,1.015,.79,TICKING,TICKING,BACKING);
		box(-.99,-1.04,.76,.99,.54,.83,0,HEM,BACKING);
		cover.quad(p(-.99,.54,.832),p(.99,.54,.832),p(.99,-1.04,.832),p(-.99,-1.04,.832),
			new UV(0,0),new UV(1,0),new UV(1,1),new UV(0,1),new Point(0,0,1),shade);
		box(-.97,.45,.83,.97,.57,.875,PILLOW,PILLOW,BACKING); // folded ivory sheet
		for (x in [-.48,.48]) {
			box(x-.415,.64,.80,x+.415,.97,.90,PILLOW,PILLOW,BACKING);
			box(x-.37,.67,.90,x+.37,.94,.96,PILLOW,PILLOW,PILLOW);
		}
		// Headboard and footboard: carved faces, wood edges and end-grain caps.
		box(-1.08,1.04,.43,1.08,1.18,1.63,ENDGRAIN,WOOD,WOOD,HEADBOARD,HEADBOARD);
		box(-.84,1.03,1.63,.84,1.19,1.79,WOOD,WOOD,WOOD,HEADBOARD,HEADBOARD);
		box(-1.08,-1.18,.40,1.08,-1.05,1.00,ENDGRAIN,WOOD,WOOD,FOOTBOARD,FOOTBOARD);
		box(-1.10,-1.20,1.00,1.10,-1.03,1.055,BRASS,BRASS,WOOD);
		// Four turned, eight-sided columns, with closed caps and actual finials.
		var profile = [
			{z:.16,r:.10},{z:.31,r:.10},{z:.36,r:.075},{z:.51,r:.065},
			{z:.57,r:.085},{z:.65,r:.085},{z:.72,r:.06},{z:2.20,r:.055},
			{z:2.28,r:.085},{z:2.35,r:.085},{z:2.40,r:.065},{z:2.65,r:.075},
			{z:2.70,r:.045},{z:2.77,r:.09},{z:2.84,r:.075},{z:2.94,r:0.}
		];
		for (x in [-1.10,1.10]) for (y in [-1.16,1.16]) {
			box(x-.11,y-.11,0,x+.11,y+.11,.16,ENDGRAIN,WOOD,ENDGRAIN);
			for (j in 0...profile.length-1) for (i in 0...8) {
				var a=i*Math.PI/4, b=(i+1)*Math.PI/4, lo=profile[j], hi=profile[j+1];
				face(j>=11?BRASS:POST,
					p(x+hi.r*Math.cos(a),y+hi.r*Math.sin(a),hi.z),
					p(x+hi.r*Math.cos(b),y+hi.r*Math.sin(b),hi.z),
					p(x+lo.r*Math.cos(b),y+lo.r*Math.sin(b),lo.z),
					p(x+lo.r*Math.cos(a),y+lo.r*Math.sin(a),lo.z),
					new Point(Math.cos((a+b)/2),Math.sin((a+b)/2),0),1);
			}
			// Gathered corner drapes leave the bed and approaches visible.
			var curtainX=x+(x < 0 ? .17 : -.17), curtainY=y+(y < 0 ? .08 : -.08);
			box(curtainX-.065,curtainY-.09,.50,curtainX+.065,curtainY+.09,2.48,CURTAIN,CURTAIN,BACKING);
			box(curtainX-.075,curtainY-.10,1.18,curtainX+.075,curtainY+.10,1.24,BRASS,BRASS,BRASS);
		}
		// Solid tester with independently authored top and underside artwork.
		box(-1.22,-1.28,2.52,1.22,1.28,2.65,CANOPY,FASCIA,SILK);
		box(-1.22,-1.28,2.39,1.22,-1.20,2.52,WOOD,FASCIA,WOOD);
		box(-1.22,1.20,2.39,1.22,1.28,2.52,WOOD,FASCIA,WOOD);
		for (x in [-1.22,1.14]) box(x,-1.20,2.39,x+.08,1.20,2.52,WOOD,FASCIA,WOOD);
	}
}
