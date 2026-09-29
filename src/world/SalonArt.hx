// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import h3d.col.Point;
import h3d.prim.UV;
import render.MeshBuilder;
import render.BuildShader;
import render.Palette;
import art.FoyerArt;

/** Round cocktail tables: transparent authored tops, brass rims and pedestals. */
class SalonArt {
	public static function build(map:GridMap, palette:Palette, lut:h3d.mat.Texture, parent:h3d.scene.Object):Array<BuildShader> {
		var tables = [for (p in map.props) if (p.kind == "salonTable") p];
		if (tables.length == 0) return [];
		var tops = new MeshBuilder(), brass = new MeshBuilder();
		for (p in tables) {
			var x = (p.x0+p.x1)/2, y = (p.y0+p.y1)/2, z = p.height;
			tops.quad(new Point(p.x0,p.y1,z),new Point(p.x1,p.y1,z),new Point(p.x1,p.y0,z),new Point(p.x0,p.y0,z),
				new UV(0,0),new UV(1,0),new UV(1,1),new UV(0,1),new Point(0,0,1),5);
			cylinder(brass,x,y,(p.x1-p.x0)*.475,z-.055,z-.006);
			cylinder(brass,x,y,.065,.06,z-.055);
			cylinder(brass,x,y,.28,.015,.06);
		}
		var shaders:Array<BuildShader> = [];
		function finish(builder:MeshBuilder,texture:h3d.mat.Texture,alpha:Bool) {
			var mat = h3d.mat.Material.create(); mat.mainPass.enableLights=false; mat.shadows=false; mat.mainPass.culling=None;
			var shader = new BuildShader(texture,lut,alpha);
			mat.mainPass.addShader(shader); new h3d.scene.Mesh(builder.toPrimitive(),mat,parent); shaders.push(shader);
		}
		finish(brass,FoyerArt.material(Palette.GOLD,8).toIndexTexture(false,true),false);
		finish(tops,FoyerArt.texture(true,false,"tabletops/salon-round.png",palette,256,256,0,1,true),true);
		return shaders;
	}

	static function cylinder(b:MeshBuilder,x:Float,y:Float,r:Float,z0:Float,z1:Float):Void {
		for (i in 0...32) {
			var a=i*Math.PI/16, c=(i+1)*Math.PI/16;
			var p0=new Point(x+r*Math.cos(a),y+r*Math.sin(a),z1), p1=new Point(x+r*Math.cos(c),y+r*Math.sin(c),z1);
			b.quad(p0,p1,new Point(p1.x,p1.y,z0),new Point(p0.x,p0.y,z0),new UV(0,0),new UV(1,0),new UV(1,1),new UV(0,1),new Point(Math.cos(a),Math.sin(a),0),6);
			var center=new Point(x,y,z1);
			b.quad(center,p0,p1,center,new UV(0,0),new UV(1,0),new UV(1,1),new UV(0,0),new Point(0,0,1),5);
		}
	}
}
