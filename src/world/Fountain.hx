// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import h3d.col.Point;
import h3d.prim.UV;
import render.MeshBuilder;
import render.BuildShader;
import render.Palette;
import render.IndexCanvas;

/** Solid lathed architecture with water surfaces and animated falling ribbons. */
class Fountain {
	static inline var SEGMENTS=40;
	public static function build(palette:Palette,lut:h3d.mat.Texture,parent:h3d.scene.Object):{shaders:Array<BuildShader>,water:Array<BuildShader>} {
		var stone=new MeshBuilder(), brass=new MeshBuilder(), pool=new MeshBuilder(), falls=new MeshBuilder();
		// Every profile is revolved around Z: the fountain holds its shape from every side.
		lathe(stone,[{r:0.,z:0.},{r:1.62,z:0.},{r:1.72,z:.18},{r:1.66,z:.56},{r:1.5,z:.62},{r:1.46,z:.22}]);
		lathe(brass,[{r:1.72,z:.15},{r:1.72,z:.21},{r:1.65,z:.23}]);
		lathe(brass,[{r:1.67,z:.54},{r:1.7,z:.59},{r:1.5,z:.63},{r:1.48,z:.59}]);
		lathe(pool,[{r:0.,z:.48},{r:1.48,z:.48}]);
		lathe(stone,[{r:.4,z:.2},{r:.35,z:.7},{r:.20,z:1.35},{r:.44,z:1.45},{r:.95,z:1.65},{r:1.02,z:1.82},{r:.9,z:1.87}]);
		lathe(brass,[{r:1.02,z:1.78},{r:1.03,z:1.84},{r:.90,z:1.88}]);
		lathe(pool,[{r:0.,z:1.84},{r:.94,z:1.84}]);
		lathe(stone,[{r:.20,z:1.8},{r:.16,z:2.35},{r:.3,z:2.43},{r:.55,z:2.60},{r:.60,z:2.72},{r:.50,z:2.77}]);
		lathe(brass,[{r:.6,z:2.69},{r:.62,z:2.74},{r:.50,z:2.78}]);
		lathe(pool,[{r:0.,z:2.74},{r:.54,z:2.74}]);
		lathe(brass,[{r:.12,z:2.74},{r:.16,z:2.94},{r:.08,z:3.08},{r:0.,z:3.24}]);
		for(i in 0...12) {
			var a=i*Math.PI*2/12;
			stream(falls,a,1.00,1.84,1.35,.49);
			if(i%2==0) stream(falls,a,.56,2.74,.82,1.85);
		}
		var stoneTex=art.FoyerArt.surface("materials/ivory-marble.png",palette,128,128).toIndexTexture(false,true);
		var brassTex=art.FoyerArt.material(Palette.GOLD,9).toIndexTexture(false,true);
		var water=new IndexCanvas(64,64);
		for(y in 0...64) for(x in 0...64) {
			var ripple=Math.sin(x*.45+Math.sin(y*.3)*2)+Math.cos(y*.7+x*.11);
			water.set(x,y,Palette.index(Palette.TEAL,Std.int(8+ripple*2)));
			if((x*7+y*13)%43==0) water.set(x,y,Palette.index(Palette.IVORY,14));
		}
		var waterTex=water.toIndexTexture(false,true), shaders=[], moving=[];
		for(item in [{mesh:stone,tex:stoneTex},{mesh:brass,tex:brassTex},{mesh:pool,tex:waterTex},{mesh:falls,tex:waterTex}]) {
			var mat=h3d.mat.Material.create(); mat.mainPass.enableLights=false; mat.shadows=false; mat.mainPass.culling=None;
			var shader=new BuildShader(item.tex,lut,false); mat.mainPass.addShader(shader);
			var mesh=new h3d.scene.Mesh(item.mesh.toPrimitive(),mat,parent); mesh.setPosition(Foyer.FOUNTAIN.x,Foyer.FOUNTAIN.y,0);
			shaders.push(shader); if(item.mesh==pool || item.mesh==falls) moving.push(shader);
		}
		return {shaders:shaders,water:moving};
	}

	static function lathe(m:MeshBuilder,rings:Array<{r:Float,z:Float}>):Void {
		for(j in 0...rings.length-1) for(i in 0...SEGMENTS) {
			var a=i*Math.PI*2/SEGMENTS,b=(i+1)*Math.PI*2/SEGMENTS,p=rings[j],q=rings[j+1];
			m.quad(new Point(Math.cos(a)*p.r,Math.sin(a)*p.r,p.z),new Point(Math.cos(b)*p.r,Math.sin(b)*p.r,p.z),
				new Point(Math.cos(b)*q.r,Math.sin(b)*q.r,q.z),new Point(Math.cos(a)*q.r,Math.sin(a)*q.r,q.z),
				new UV(i/10,p.z),new UV((i+1)/10,p.z),new UV((i+1)/10,q.z+.05),new UV(i/10,q.z+.05),new Point(Math.cos(a),Math.sin(a),.4),12+Math.cos(a)*4);
		}
	}

	static function stream(m:MeshBuilder,a:Float,r0:Float,z0:Float,r1:Float,z1:Float):Void {
		for(i in 0...8) {
			var t=i/8,u=(i+1)/8;
			function p(t:Float,side:Float):Point {
				var r=r0+(r1-r0)*Math.sqrt(t);
				return new Point(Math.cos(a)*r+Math.sin(a)*side,Math.sin(a)*r-Math.cos(a)*side,z0+(z1-z0)*t);
			}
			m.quad(p(t,-.032),p(t,.032),p(u,.032),p(u,-.032),new UV(0,t*3),new UV(.25,t*3),new UV(.25,u*3),new UV(0,u*3),new Point(Math.cos(a),Math.sin(a),0),0);
		}
	}
}
