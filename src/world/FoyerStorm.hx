// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import art.FoyerArt;
import render.BuildShader;
import render.IndexCanvas;
import render.MeshBuilder;
import render.Palette;
import h3d.col.Point;
import h3d.prim.UV;

/** Palette-rendered courtyard, leaded clear glass and an independent cosmetic storm. */
class FoyerStorm {
	final exterior:Array<BuildShader> = [];
	final rain:Array<BuildShader> = [];
	final trees:Array<render.BuildSprite> = [];
	final interior:Array<BuildShader>;
	final fx = new rng.Xoshiro128ss(781, 2917, 513, 9001);
	final settings:core.Settings;
	var bolt:h3d.scene.Mesh;
	var rainSound:hxd.snd.Channel;
	var thunderSound:hxd.snd.Channel;
	var nextStrike = 9.0;
	var strikeAge = 100.0;
	var thunderDelay = -1.0;
	var elapsed = 0.0;
	var center:Float;
	var conservatory:Point;
	public final frames:Array<BuildShader> = [];

	public function new(map:GridMap, textures:Map<String,h3d.mat.Texture>, lut:h3d.mat.Texture,
		parent:h3d.scene.Object, interior:Array<BuildShader>, settings:core.Settings, palette:Palette) {
		this.interior = interior;
		this.settings = settings;
		hxd.Window.getInstance().addEventTarget(onWindowEvent);
		center = (map.windows[0].x0 + map.windows[map.windows.length-1].x1) / 2;
		function mesh(b:MeshBuilder, tex:h3d.mat.Texture, ?alpha:Float=1, cutout:Bool=false):h3d.scene.Mesh {
			var mat = h3d.mat.Material.create();
			mat.mainPass.enableLights = false; mat.shadows = false; mat.mainPass.culling = None;
			var sh = new BuildShader(tex,lut,cutout); sh.opacity = alpha;
			if (alpha < 1) { mat.blendMode = Alpha; mat.mainPass.depthWrite = false; }
			mat.mainPass.addShader(sh);
			return new h3d.scene.Mesh(b.toPrimitive(),mat,parent);
		}
		function finish(b:MeshBuilder, tex:h3d.mat.Texture, outside:Bool):BuildShader {
			var m=mesh(b,tex), sh=m.material.mainPass.getShader(BuildShader);
			if(outside) { sh.visibility=.12; exterior.push(sh); } else frames.push(sh);
			return sh;
		}
		function box(b:MeshBuilder,x0:Float,y0:Float,z0:Float,x1:Float,y1:Float,z1:Float,shade:Float=4):Void
			MeshBuilder.box(b,b,x0,y0,z0,x1,y1,z1,shade);
		var stone=new MeshBuilder(), brass=new MeshBuilder(), wood=new MeshBuilder(), glass=new MeshBuilder();
		for(w in map.windows) {
			// Deep marble reveals and projecting sill, with brass and mahogany inner moldings.
			for(x in [w.x0,w.x1]) {
				box(stone,x-.16,w.y-.2,w.bottom-.2,x+.16,w.y+.23,w.top+.2);
				box(wood,x-.075,w.y+.24,w.bottom,x+.075,w.y+.32,w.top);
			}
			for(z in [w.bottom,w.top]) {
				box(stone,w.x0-.24,w.y-.25,z-.13,w.x1+.24,w.y+.4,z+.13);
				box(brass,w.x0,w.y+.25,z-.035,w.x1,w.y+.34,z+.035);
			}
			// Stepped cornice and raised fillets catch the foyer's warm light.
			box(stone,w.x0-.3,w.y-.1,w.top+.2,w.x1+.3,w.y+.48,w.top+.34);
			for(x in [w.x0-.12,w.x1+.12]) box(brass,x-.018,w.y+.235,w.bottom+.16,x+.018,w.y+.27,w.top-.16);
			var mid=(w.x0+w.x1)/2;
			box(brass,mid-.045,w.y+.13,w.bottom,mid+.045,w.y+.23,w.top);
			for(z in [2.65,4.25]) box(brass,w.x0,w.y+.13,z-.045,w.x1,w.y+.23,z+.045);
			// Diamond leadwork in the transom echoes the manor's geometric brass inlay.
			for(x in [w.x0+.5,w.x0+1.5]) {
				line(brass,x-.44,w.y+.18,4.9,x,w.y+.18,5.55,.025);
				line(brass,x,w.y+.18,5.55,x+.44,w.y+.18,4.9,.025);
				line(brass,x+.44,w.y+.18,4.9,x,w.y+.18,4.3,.025);
				line(brass,x,w.y+.18,4.3,x-.44,w.y+.18,4.9,.025);
			}
			panel(glass,w.x0,w.x1,w.y+.08,w.bottom,w.top,0);
		}
		finish(stone,textures.get("ivory"),false);
		finish(brass,textures.get("brass"),false);
		finish(wood,textures.get("tableWood"),false);
		var glassMesh=mesh(glass,FoyerArt.material(Palette.NAVY,9).toIndexTexture(false,true),.075);
		glassMesh.material.mainPass.getShader(BuildShader).visibility=0;

		function texture(name:String):h3d.mat.Texture
			return FoyerArt.texture(false,true,"materials/courtyard-"+name+".png",palette,256,256);
		var ground=new MeshBuilder(), fence=new MeshBuilder();
		groundAround(map,ground,center-65,-70,center+65,map.height+40);
		finish(ground,texture("gravel"),true);
		// Wet slate paths and low hedges have real depth and parallax through every pane.
		var path=new MeshBuilder(), hedge=new MeshBuilder(), puddles=new MeshBuilder();
		box(path,center-2,-60,-.075,center+2,.8,-.045,5);
		box(path,center-45,-9,-.075,center+45,-6,-.045,5);
		for(side in [-1,1]) {
			var x=center+side*8;
			box(hedge,x-3,-6,.0,x+3,-3,.85,8);
			for(i in 0...8) box(puddles,x-2+i*.6,-7.9,-.04,x-1.7+i*.6,-6.4,-.025,4);
		}
		finish(path,texture("slate"),true);
		finish(hedge,texture("hedge"),true);
		finish(puddles,FoyerArt.material(Palette.NAVY,12).toIndexTexture(false,true),true);
		for(i in 0...57) {
			var x=center-42+i*1.5;
			box(fence,x-.045,-15,0,x+.045,-14.9,2.8,3);
			if(i%5==0) box(fence,x-.2,-15.2,0,x+.2,-14.7,3.15,4);
		}
		for(z in [.65,2.2]) box(fence,center-42,-15,z,center+42,-14.9,z+.07,3);
		finish(fence,texture("iron"),true);
		// Transparent trees share the game's palette and upright face-sprite rendering.
		var treeTextures=[for(name in ["tall-cedar","tall-cypress"].concat(CourtyardTrees.SPECIALS))
			name => FoyerArt.texture(true,false,"sprites/"+name+".png",palette,256,512,0,1,true)];
		for(i in 0...CourtyardTrees.ROW_COUNT) {
			// Staggered rows give the silhouettes real depth beyond each window.
			var x=center-48+(i%12)*8+fx.nextFloat()*3, y=-18-Std.int(i/12)*12-fx.nextFloat()*5;
			var height=12+fx.nextFloat()*7;
			var tree=new render.BuildSprite(treeTextures.get(CourtyardTrees.textureName(i)),lut,1,height*.5,height,parent);
			tree.mesh.scaleX = CourtyardTrees.flipped(i) ? -1 : 1;
			tree.setPosition(x,y,-.25); tree.shader.visibility=.16;
			exterior.push(tree.shader); trees.push(tree);
		}
		for(i in 0...CourtyardTrees.ROW_COUNT) {
			var east=i<24;
			var x=east?map.width+4+Std.int(i/12)*10+fx.nextFloat()*3:center-30+(i-24)*7;
			var y=east?-5+(i%12)*5:map.height+7+fx.nextFloat()*8;
			var height=12+fx.nextFloat()*7;
			var tree=new render.BuildSprite(treeTextures.get(CourtyardTrees.textureName(i+CourtyardTrees.ROW_COUNT)),lut,1,height*.5,height,parent);
			tree.mesh.scaleX = CourtyardTrees.flipped(i+CourtyardTrees.ROW_COUNT) ? -1 : 1;
			tree.setPosition(x,y,-.25); tree.shader.visibility=.12;
			exterior.push(tree.shader); trees.push(tree);
		}
		var sky=new MeshBuilder();
		var clouds=new IndexCanvas(128,128);
		for(y in 0...128) for(x in 0...128) {
			var band=Math.sin(x*.09+Math.sin(y*.08)*2)+Math.sin(y*.2+x*.035);
			clouds.set(x,y,Palette.index(Palette.NIGHT,band>1?6:band>-.4?5:4));
		}
		// A sky enclosure must not put an opaque front face across the windows.
		panel(sky,center-75,center+75,-75,-2,65,0);
		box(sky,center-76,-76,-2,center-75,map.height+50,65,0);
		box(sky,center+75,-76,-2,center+76,map.height+50,65,0);
		box(sky,center-75,-76,64,center+75,map.height+50,65,0);
		panel(sky,center-75,center+75,map.height+50,-2,65,0);
		var skyShader=finish(sky,clouds.toIndexTexture(false,true),true); skyShader.visibility=0;

		var drops=new IndexCanvas(128,128);
		for(i in 0...22) {
			var x=fx.below(128),y=fx.below(128);
			for(j in 0...3+fx.below(5)) drops.set((x+Std.int(j/3))%128,(y+j)%128,Palette.index(Palette.NAVY,10+j%3));
		}
		var rainTex=drops.toIndexTexture(true,true);
		// Clip sheets against every room, so later manor extensions remain indoors.
		function shelteredSheet(b:MeshBuilder,ax:Float,ay:Float,bx:Float,by:Float):Void {
			var length=Math.sqrt((bx-ax)*(bx-ax)+(by-ay)*(by-ay)),steps=Std.int(Math.ceil(length));
			for(j in 0...steps) {
				var t0=j/steps,t1=(j+1)/steps;
				var xa=ax+(bx-ax)*t0,ya=ay+(by-ay)*t0,xb=ax+(bx-ax)*t1,yb=ay+(by-ay)*t1;
				var base=RainShelter.base(map,(xa+xb)/2,(ya+yb)/2);
				b.quad(new Point(xa,ya,22),new Point(xb,yb,22),new Point(xb,yb,base),new Point(xa,ya,base),
					new UV(t0*7,0),new UV(t1*7,0),new UV(t1*7,(22-base)*5/22),new UV(t0*7,(22-base)*5/22),new Point(0,1,0),2);
			}
		}
		for(i in 0...10) {
			var b=new MeshBuilder(); panel(b,center-55,center+55,-.5-i*3,-2,24,2,22,5);
			var m=mesh(b,rainTex,1,true),sh=m.material.mainPass.getShader(BuildShader);
			sh.visibility=.15; rain.push(sh);
		}
		// Rain sheets sit outside glazed rooms, including above their roofs.
		var glazedRooms:Array<GridMap.Sector>=[];
		for(cy in 0...map.height) for(cx in 0...map.width) {
			var room=map.sectorAt(cx,cy);
			if(room!=null && room.wallTex=="glass" && glazedRooms.indexOf(room)<0) glazedRooms.push(room);
		}
		for(room in glazedRooms) {
			var x0=1e6,y0=1e6,x1=-1e6,y1=-1e6;
			for(cy in 0...map.height) for(cx in 0...map.width) if(map.sectorAt(cx,cy)==room) {
				x0=Math.min(x0,cx);y0=Math.min(y0,cy);x1=Math.max(x1,cx+1);y1=Math.max(y1,cy+1);
			}
			conservatory=new Point((x0+x1)/2,(y0+y1)/2,room.ceilZ);
			for(i in 0...6) {
				var b=new MeshBuilder(),gap=1+i*2;
				shelteredSheet(b,x0-6,y0-gap,x1+6,y0-gap);
				shelteredSheet(b,x0-6,y1+gap,x1+6,y1+gap);
				shelteredSheet(b,x1+gap,y0-6,x1+gap,y1+6);
				panel(b,x0,x1,y0+(y1-y0)*i/6,room.ceilZ+.2,24,2,4,4);
				var sh=mesh(b,rainTex,1,true).material.mainPass.getShader(BuildShader);
				sh.visibility=.1;rain.push(sh);
			}
		}
		var boltBuilder=new MeshBuilder();
		var bx=center+9.0, bz=26.0;
		for(i in 0...9) {
			var nx=bx+(fx.nextFloat()-.5)*3,nz=bz-2.5;
			line(boltBuilder,bx,-58,bz,nx,-58,nz,.07);
			if(i==3) line(boltBuilder,bx,-58,bz,bx-3,-58,bz-4,.035);
			bx=nx;bz=nz;
		}
		bolt=mesh(boltBuilder,FoyerArt.material(Palette.IVORY,15).toIndexTexture(false,true));
		bolt.material.mainPass.getShader(BuildShader).visibility=0; bolt.visible=false;
	}

	static function panel(b:MeshBuilder,x0:Float,x1:Float,y:Float,z0:Float,z1:Float,shade:Float,u:Float=1,v:Float=1):Void {
		b.quad(new Point(x0,y,z1),new Point(x1,y,z1),new Point(x1,y,z0),new Point(x0,y,z0),
			new UV(0,0),new UV(u,0),new UV(u,v),new UV(0,v),new Point(0,1,0),shade);
	}
	static function line(b:MeshBuilder,x0:Float,y0:Float,z0:Float,x1:Float,y1:Float,z1:Float,r:Float):Void {
		b.quad(new Point(x0-r,y0,z0),new Point(x0+r,y0,z0),new Point(x1+r,y1,z1),new Point(x1-r,y1,z1),
			new UV(0,0),new UV(1,0),new UV(1,1),new UV(0,1),new Point(0,1,0),0);
	}

	public function update(dt:Float,x:Float,y:Float):Void {
		for(tree in trees) tree.update(x,y);
		elapsed+=dt; nextStrike-=dt; strikeAge+=dt;
		if(nextStrike<=0) {
			strikeAge=0; nextStrike=17+fx.nextFloat()*24; thunderDelay=1.3+fx.nextFloat()*2.7;
			bolt.x=(fx.nextFloat()-.5)*28;
		}
		var flash=strikeAge<.16 ? 1-strikeAge/.16 : strikeAge>.26 && strikeAge<.39 ? (.39-strikeAge)/.13*.55 : 0;
		bolt.visible=flash>.1;
		for(sh in exterior) sh.shadeOffset=-flash*12;
		for(sh in interior) {
			sh.stormLight.set(center,1,3,flash*9);
			if(conservatory!=null) sh.conservatoryStormLight.set(conservatory.x,conservatory.y,conservatory.z,flash*9);
		}
		for(i in 0...rain.length) rain[i].uvOffset.set(-elapsed*.12+i*.19,-elapsed*(1.15+i*.025));
		var gain=settings.masterVolume*settings.effectsVolume/10000;
		#if js
		if(settings.muteInBackground && !js.Browser.document.hasFocus()) gain=0;
		#else
		if(settings.muteInBackground && !hxd.Window.getInstance().isFocused) gain=0;
		#end
		var near=Math.max(.08,1-Math.sqrt((x-center)*(x-center)+(y-1)*(y-1))/32);
		if(conservatory!=null) near=Math.max(near,Math.max(.08,1-Math.sqrt((x-conservatory.x)*(x-conservatory.x)+(y-conservatory.y)*(y-conservatory.y))/32));
		if(rainSound==null && gain>0) rainSound=hxd.Res.load("audio/weather/rain.wav").toSound().play(true,0);
		if(rainSound!=null) rainSound.volume=gain*near*.38;
		if(thunderSound!=null) thunderSound.volume=gain*near*.8;
		if(thunderDelay>=0) {
			thunderDelay-=dt;
			if(thunderDelay<0 && gain>0) thunderSound=hxd.Res.load("audio/weather/thunder.wav").toSound().play(false,gain*near*.8);
		}
	}
	public function stop():Void {
		hxd.Window.getInstance().removeEventTarget(onWindowEvent);
		stopAudio();
	}
	function onWindowEvent(event:hxd.Event):Void {
		// Stop immediately even if the browser suspends the next animation frame.
		if(event.kind==EFocusLost && settings.muteInBackground) stopAudio();
	}
	function stopAudio():Void {
		if(rainSound!=null) rainSound.stop();
		if(thunderSound!=null) thunderSound.stop();
		rainSound=null; thunderSound=null;
	}

	/**
		The courtyard gravel: a slab just under ground level, out to the horizon.
		Under the manor itself it stops wherever any floor has a room below
		ground (a stairwell, a basement), so looking down the stairs or up in a
		cellar never meets it. Under the rest of the building only its top is
		laid, which the floors above hide anyway.
	**/
	static function groundAround(map:GridMap,b:MeshBuilder,x0:Float,y0:Float,x1:Float,y1:Float):Void {
		var z0=-.3, z1=-.08, shade=9.;
		function slab(ax:Float,ay:Float,bx:Float,by:Float) if(bx>ax && by>ay) MeshBuilder.box(b,b,ax,ay,z0,bx,by,z1,shade);
		var w=map.width, h=map.height;
		slab(x0,y0,x1,Math.min(0,y1));
		slab(x0,Math.max(h,y0),x1,y1);
		slab(x0,Math.max(0,y0),Math.min(0,x1),Math.min(h,y1));
		slab(Math.max(w,x0),Math.max(0,y0),x1,Math.min(h,y1));
		function sunken(cx:Int,cy:Int):Bool {
			for(l in map.layers) {
				var s=l.cells[cy*w+cx];
				if(s!=null && s.floorZ<-.01) return true;
			}
			return false;
		}
		for(cy in 0...h) {
			if(cy+1<=y0 || cy>=y1) continue;
			var run=-1;
			for(cx in 0...w+1) {
				var laid=cx<w && !sunken(cx,cy);
				if(laid && run<0) run=cx;
				if(!laid && run>=0) {
					var ax=Math.max(run,x0), bx=Math.min(cx,x1);
					if(bx>ax) b.quad(new h3d.col.Point(ax,cy,z1),new h3d.col.Point(bx,cy,z1),new h3d.col.Point(bx,cy+1,z1),new h3d.col.Point(ax,cy+1,z1),
						new h3d.prim.UV(ax,-cy),new h3d.prim.UV(bx,-cy),new h3d.prim.UV(bx,-cy-1),new h3d.prim.UV(ax,-cy-1),new h3d.col.Point(0,0,1),shade);
					run=-1;
				}
			}
		}
	}
}
