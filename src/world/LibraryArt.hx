// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import art.FoyerArt;
import h3d.col.Point;
import h3d.prim.UV;
import render.BuildShader;
import render.MeshBuilder;
import render.Palette;

/** One shared PNG on bookcase faces; map boxes provide wooden sides and collision. */
class LibraryArt {
	public static function build(map:GridMap,palette:Palette,lut:h3d.mat.Texture,parent:h3d.scene.Object):Array<BuildShader> {
		var mesh=new MeshBuilder();
		for(p in map.props) {
			if(p.kind!="libraryShelf" && p.kind!="libraryShelfDouble") continue;
			var base=p.baseZ==null?0.:p.baseZ;
			for(north in (p.kind=="libraryShelfDouble"?[false,true]:[false])) {
				var y=north?p.y1+.006:p.y0-.006;
				var a=north?p.x1:p.x0,b=north?p.x0:p.x1;
				mesh.quad(new Point(a,y,p.height),new Point(b,y,p.height),new Point(b,y,base),new Point(a,y,base),
					new UV(0,0),new UV(1,0),new UV(1,1),new UV(0,1),new Point(0,north?1:-1,0),6);
			}
		}
		if(mesh.isEmpty) return [];
		var mat=h3d.mat.Material.create();mat.mainPass.enableLights=false;mat.shadows=false;mat.mainPass.culling=None;
		var shader=new BuildShader(FoyerArt.surface("materials/library-bookshelf.png",palette,192,256).toIndexTexture(false,false),lut,false);
		mat.mainPass.addShader(shader);
		new h3d.scene.Mesh(mesh.toPrimitive(),mat,parent);
		return [shader];
	}
}
