// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import h3d.col.Point;
import h3d.prim.UV;
import render.MeshBuilder;
import render.BuildShader;
import render.Palette;

/** Marble architecture, translucent pools and gravity-driven streams and spray. */
class Fountain {
	static inline var SEGMENTS=40;
	public static function build(palette:Palette,lut:h3d.mat.Texture,parent:h3d.scene.Object,x:Float,y:Float):{shaders:Array<BuildShader>,water:Array<BuildShader>,animate:Float->Void} {
		var stone=new MeshBuilder(), brass=new MeshBuilder(), falls=new MeshBuilder(), spray=new MeshBuilder();
		// Every profile is revolved around Z: the fountain holds its shape from every side.
		lathe(stone,[{r:0.,z:0.},{r:1.62,z:0.},{r:1.72,z:.18},{r:1.66,z:.56},{r:1.5,z:.62},{r:1.46,z:.22}]);
		lathe(brass,[{r:1.72,z:.15},{r:1.72,z:.21},{r:1.65,z:.23}]);
		lathe(brass,[{r:1.67,z:.54},{r:1.7,z:.59},{r:1.5,z:.63},{r:1.48,z:.59}]);
		disc(stone,1.46,.23,5);
		lathe(stone,[{r:.4,z:.2},{r:.35,z:.7},{r:.20,z:1.35},{r:.44,z:1.45},{r:.95,z:1.65},{r:1.02,z:1.82},{r:.9,z:1.87}]);
		lathe(brass,[{r:1.02,z:1.78},{r:1.03,z:1.84},{r:.90,z:1.88}]);
		disc(stone,.94,1.72,5);
		lathe(stone,[{r:.20,z:1.8},{r:.16,z:2.35},{r:.3,z:2.43},{r:.55,z:2.60},{r:.60,z:2.72},{r:.50,z:2.77}]);
		lathe(brass,[{r:.6,z:2.69},{r:.62,z:2.74},{r:.50,z:2.78}]);
		disc(stone,.54,2.65,5);
		lathe(brass,[{r:.12,z:2.74},{r:.16,z:2.94},{r:.08,z:3.08},{r:0.,z:3.24}]);
		for(i in 0...12) {
			var a=i*Math.PI*2/12;
			stream(falls,a,1.00,1.84,1.30,.48);
			splash(spray,a,1.30,.49,i);
			if(i%2==0) {
				stream(falls,a,.56,2.74,.79,1.84);
				splash(spray,a,.79,1.85,i);
			}
		}
		var stoneTex=art.FoyerArt.surface("materials/fountain-marble.png",palette,256,256).toIndexTexture(false,true);
		var brassTex=art.FoyerArt.material(Palette.GOLD,9).toIndexTexture(false,true);
		var waterTex=art.FoyerArt.surface("materials/fountain-water.png",palette,256,256).toIndexTexture(false,true);
		var shaders:Array<BuildShader>=[], moving:Array<BuildShader>=[];
		function mesh(b:MeshBuilder,tex:h3d.mat.Texture,opacity:Float=1):h3d.scene.Mesh {
			var mat=h3d.mat.Material.create(); mat.mainPass.enableLights=false; mat.shadows=false; mat.mainPass.culling=None;
			if(opacity<1) {mat.blendMode=Alpha; mat.mainPass.depthWrite=false;}
			var shader=new BuildShader(tex,lut,false); shader.opacity=opacity; mat.mainPass.addShader(shader);
			var mesh=new h3d.scene.Mesh(b.toPrimitive(),mat,parent); mesh.setPosition(x,y,0);
			shaders.push(shader); return mesh;
		}
		mesh(stone,stoneTex); mesh(brass,brassTex);
		for(tier in [{r:1.46,z:.48,impact:1.30,count:12},{r:.94,z:1.84,impact:.79,count:6},{r:.54,z:2.74,impact:0.,count:0}]) {
			var pool=new MeshBuilder(); disc(pool,tier.r,tier.z,2);
			var sh=mesh(pool,waterTex,.78).material.mainPass.getShader(BuildShader);
			sh.waterSurface=true;
			for(i in 0...tier.count) {
				var a=i*Math.PI*2/tier.count;
				sh.waterImpacts[i].set(Math.cos(a)*tier.impact,Math.sin(a)*tier.impact,i*.71,1);
			}
			moving.push(sh);
		}
		var streamShader=mesh(falls,waterTex,.48).material.mainPass.getShader(BuildShader);
		streamShader.waterStream=true; moving.push(streamShader);
		var droplets=mesh(spray,art.FoyerArt.material(Palette.IVORY,13).toIndexTexture(false,true),.72);
		var motion=new render.FountainSplash(); droplets.material.mainPass.addShader(motion);
		return {shaders:shaders,water:moving,animate:t -> motion.time=t};
	}

	static function lathe(m:MeshBuilder,rings:Array<{r:Float,z:Float}>):Void {
		var distance=0.0;
		for(j in 0...rings.length-1) {
			var p=rings[j],q=rings[j+1];
			var next=distance+Math.sqrt((q.r-p.r)*(q.r-p.r)+(q.z-p.z)*(q.z-p.z));
			for(i in 0...SEGMENTS) {
			var a=i*Math.PI*2/SEGMENTS,b=(i+1)*Math.PI*2/SEGMENTS,p=rings[j],q=rings[j+1];
			m.quad(new Point(Math.cos(a)*p.r,Math.sin(a)*p.r,p.z),new Point(Math.cos(b)*p.r,Math.sin(b)*p.r,p.z),
				new Point(Math.cos(b)*q.r,Math.sin(b)*q.r,q.z),new Point(Math.cos(a)*q.r,Math.sin(a)*q.r,q.z),
				new UV(i/10,distance),new UV((i+1)/10,distance),new UV((i+1)/10,next),new UV(i/10,next),new Point(Math.cos(a),Math.sin(a),.4),6+Math.cos(a)*3);
			}
			distance=next;
		}
	}

	/** Planar UVs retain ripple detail across the entire pool; rings allow surface displacement. */
	static function disc(m:MeshBuilder,radius:Float,z:Float,shade:Float):Void {
		for(ring in 0...12) for(i in 0...SEGMENTS) {
			var a=i*Math.PI*2/SEGMENTS,b=(i+1)*Math.PI*2/SEGMENTS;
			var inner=radius*ring/12,outer=radius*(ring+1)/12;
			var p=new Point(Math.cos(a)*inner,Math.sin(a)*inner,z),q=new Point(Math.cos(b)*inner,Math.sin(b)*inner,z);
			var r=new Point(Math.cos(b)*outer,Math.sin(b)*outer,z),s=new Point(Math.cos(a)*outer,Math.sin(a)*outer,z);
			m.quad(p,q,r,s,new UV(p.x*.65,p.y*.65),new UV(q.x*.65,q.y*.65),new UV(r.x*.65,r.y*.65),new UV(s.x*.65,s.y*.65),new Point(0,0,1),shade);
		}
	}

	static function stream(m:MeshBuilder,a:Float,r0:Float,z0:Float,r1:Float,z1:Float):Void {
		var duration=FountainFlow.flightTime(z0,z1), speed=(r1-r0)/duration;
		for(i in 0...18) for(side in 0...6) {
			var t=i*duration/18,u=(i+1)*duration/18;
			function p(time:Float,edge:Int):Point {
				var pos=FountainFlow.position(r0,z0,r1,z1,time),angle=edge*Math.PI/3;
				var width=FountainFlow.width(speed,time);
				// Cross-section perpendicular to the tangent of the ballistic arc.
				var vz=FountainFlow.GRAVITY*time,len=Math.sqrt(speed*speed+vz*vz);
				var radial=pos.r+Math.sin(angle)*width*vz/len, tangent=Math.cos(angle)*width;
				return new Point(Math.cos(a)*radial-Math.sin(a)*tangent,Math.sin(a)*radial+Math.cos(a)*tangent,pos.z+Math.sin(angle)*width*speed/len);
			}
			m.quad(p(t,side),p(t,side+1),p(u,side+1),p(u,side),new UV(side/6,t*2.8),new UV((side+1)/6,t*2.8),new UV((side+1)/6,u*2.8),new UV(side/6,u*2.8),new Point(Math.cos(a),Math.sin(a),0),0);
		}
	}

	static function splash(m:MeshBuilder,a:Float,r:Float,z:Float,seed:Int):Void {
		for(i in 0...5) {
			var direction=a+i*Math.PI*2/5, speed=.24+(i%3)*.08,up=.75+(i%3)*.22;
			var velocity=new Point(Math.cos(direction)*speed,Math.sin(direction)*speed,up);
			var x=Math.cos(a)*r,y=Math.sin(a)*r,phase=(seed*.17+i*.21)%1,size=.011;
			// Crossed quads retain a droplet silhouette from all viewing directions.
			for(axis in 0...2) {
				var dx=axis==0?size:0.,dy=axis==1?size:0.;
				m.quad(new Point(x-dx,y-dy,z-size),new Point(x+dx,y+dy,z-size),new Point(x+dx,y+dy,z+size),new Point(x-dx,y-dy,z+size),
					new UV(phase,0),new UV(phase,0),new UV(phase,0),new UV(phase,0),velocity,0);
			}
		}
	}
}
