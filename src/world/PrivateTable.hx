// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import h3d.col.Point;
import h3d.prim.UV;
import render.BuildShader;
import render.MeshBuilder;
import render.Palette;

/** Authored game spread over a cloth with a folded skirt on all four sides. */
class PrivateTable {
 public static function build(palette:Palette,lut:h3d.mat.Texture,parent:h3d.scene.Object,cx:Float,cy:Float):Array<BuildShader> {
  var shaders:Array<BuildShader>=[];
  function finish(builder:MeshBuilder,canvas:render.IndexCanvas,repeat:Bool) {
   var texture=canvas.toIndexTexture(false,repeat);
   var mat=h3d.mat.Material.create(),shader=new BuildShader(texture,lut,false);
   mat.mainPass.enableLights=false;mat.shadows=false;mat.mainPass.culling=None;
   mat.mainPass.addShader(shader);new h3d.scene.Mesh(builder.toPrimitive(),mat,parent);shaders.push(shader);
  }
  var top=new MeshBuilder(),x0=cx-3.035,x1=cx+3.035,y0=cy-.735,y1=cy+.735,z=.834;
  top.quad(new Point(x0,y1,z),new Point(x1,y1,z),new Point(x1,y0,z),new Point(x0,y0,z),
   new UV(0,0),new UV(1,0),new UV(1,1),new UV(0,1),new Point(0,0,1),3);
  finish(top,topCloth(palette),false);
  var skirt=new MeshBuilder();
  function edge(ax:Float,ay:Float,bx:Float,by:Float,nx:Float,ny:Float) {
   var length=Math.sqrt((bx-ax)*(bx-ax)+(by-ay)*(by-ay)),steps=Std.int(Math.ceil(length*24));
   var repeats=Math.max(1,Math.round(length/2));
   function p(t:Float,bottom:Bool):Point {
    // Fine pleats have actual depth; the gently scalloped hem clears the floor.
    var fold=Math.sin(t*repeats*Math.PI*12)*.018;
    // Spaces matter: `bottom?.028` parses as Haxe's `?.` safe-navigation operator.
    return new Point(ax+(bx-ax)*t+nx*(bottom ? .028+fold : 0),ay+(by-ay)*t+ny*(bottom ? .028+fold : 0),
     bottom ? .16+.045*(1-Math.cos(t*repeats*Math.PI*4)) : z);
   }
   for(i in 0...steps) {
    var a=i/steps,b=(i+1)/steps;
    skirt.quad(p(a,false),p(b,false),p(b,true),p(a,true),new UV(a*repeats,0),new UV(b*repeats,0),
     new UV(b*repeats,1),new UV(a*repeats,1),new Point(nx,ny,0),5);
   }
  }
  edge(x0,y0,x1,y0,0,-1);edge(x1,y1,x0,y1,0,1);
  edge(x0,y1,x0,y0,-1,0);edge(x1,y0,x1,y1,1,0);
  // The drape is authored 3:1, one repeat per 2 m of a long side.
  var drape="materials/private-table-drape.png";
  finish(skirt,hxd.Res.loader.exists(drape) ? art.FoyerArt.surface(drape,palette,384,128) : art.FoyerArt.material(Palette.TEAL,5),true);
  return shaders;
 }

 /**
  The game spread is authored about 3:1 and the top is about 4:1, so the art keeps its
  own proportions in the middle and plain cloth, drawn from the velvet just outside its
  gold frame, carries on to both ends.
 **/
 static function topCloth(palette:Palette):render.IndexCanvas {
  var path="materials/private-table-top.png",w=1024,h=248;
  if(!hxd.Res.loader.exists(path)) return art.FoyerArt.material(Palette.TEAL,7);
  var size=hxd.Res.load(path).toImage().getSize();
  var artW=Std.int(Math.min(w,Math.round(h*size.width/size.height)));
  var spread=art.FoyerArt.surface(path,palette,artW,h);
  var cloth=new render.IndexCanvas(w,h),left=Std.int((w-artW)/2);
  for(y in 0...h) for(x in 0...w) {
   var sx=x-left;
   if(sx>=0 && sx<artW) cloth.set(x,y,spread.get(sx,y));
   else {
    // Scatter the velvet's own pixels (its outermost two columns, nearby rows) so the ends read as the same cloth.
    var hash=(x*73856093)^(y*19349663);
    if(hash<0) hash=-hash;
    var sy=Std.int(Math.max(0,Math.min(h-1,y+hash%7-3)));
    cloth.set(x,y,spread.get(sx<0 ? (hash>>3)%2 : artW-1-(hash>>3)%2,sy));
   }
  }
  return cloth;
 }
}
