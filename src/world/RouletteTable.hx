// SPDX-License-Identifier: AGPL-3.0-or-later
package world;
import h3d.col.Point;
import h3d.prim.UV;
import render.BuildShader;
import render.MeshBuilder;
import render.Palette;

/** The same complete tabletop used by the seated game, including its resting wheel. */
class RouletteTable {
 public static function build(palette:Palette,lut:h3d.mat.Texture,parent:h3d.scene.Object,cx:Float,cy:Float):Array<BuildShader> {
  var mb=new MeshBuilder();
  mb.quad(new Point(cx-1.2,cy+.675,.907),new Point(cx+1.2,cy+.675,.907),
   new Point(cx+1.2,cy-.675,.907),new Point(cx-1.2,cy-.675,.907),
   new UV(0,0),new UV(1,0),new UV(1,1),new UV(0,1),new Point(0,0,1),3);
  var texture=art.FoyerArt.surface("tabletops/roulette.png",palette,640,360).toIndexTexture(false,false);
  var shader=new BuildShader(texture,lut,false),mat=h3d.mat.Material.create();
  mat.mainPass.enableLights=false;mat.shadows=false;mat.mainPass.culling=None;
  mat.mainPass.addShader(shader);new h3d.scene.Mesh(mb.toPrimitive(),mat,parent);
  return [shader];
 }
}
