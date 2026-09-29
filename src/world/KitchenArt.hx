// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import art.FoyerArt;
import h3d.col.Point;
import h3d.prim.UV;
import render.BuildShader;
import render.MeshBuilder;
import render.Palette;

/** PNG surfaces follow their prop bounds, including maps edited in Haxen. */
class KitchenArt {
	public static function build(map:GridMap, palette:Palette, lut:h3d.mat.Texture, parent:h3d.scene.Object):Array<BuildShader> {
		var shaders:Array<BuildShader> = [];
		for (p in map.props) {
			var file = switch p.kind {
				case "kitchenCounter": "kitchen-counter-food";
				case "kitchenSink": "kitchen-sink";
				case "kitchenShelves": "kitchen-shelves";
				case "kitchenFreezer": "kitchen-freezer";
				default: continue;
			};
			var mesh = new MeshBuilder(), z = p.baseZ == null ? 0. : p.baseZ;
			var top = p.kind == "kitchenCounter" || p.kind == "kitchenSink";
			var points:Array<Point>;
			var normal:Point;
			if (top) {
				var h = p.height + .006;
				points = [new Point(p.x0,p.y1,h),new Point(p.x1,p.y1,h),new Point(p.x1,p.y0,h),new Point(p.x0,p.y0,h)];
				// The sink is approached from the north; its tap is against the south edge.
				if (p.kind == "kitchenSink") points = [points[2],points[3],points[0],points[1]];
				normal = new Point(0,0,1);
			} else if (p.kind == "kitchenFreezer") {
				var x = p.x1 + .006;
				points = [new Point(x,p.y1,p.height),new Point(x,p.y0,p.height),new Point(x,p.y0,z),new Point(x,p.y1,z)];
				normal = new Point(1,0,0);
			} else {
				var y = p.y0 - .006;
				points = [new Point(p.x0,y,p.height),new Point(p.x1,y,p.height),new Point(p.x1,y,z),new Point(p.x0,y,z)];
				normal = new Point(0,-1,0);
			}
			mesh.quad(points[0],points[1],points[2],points[3],new UV(0,0),new UV(1,0),new UV(1,1),new UV(0,1),normal,3);
			var material = h3d.mat.Material.create();
			material.mainPass.enableLights = false;
			material.shadows = false;
			material.mainPass.culling = None;
			var width = p.kind == "kitchenFreezer" ? 128 : 384;
			var height = top ? 128 : p.kind == "kitchenFreezer" ? 192 : 256;
			var shader = new BuildShader(FoyerArt.texture(false,false,'materials/$file.png',palette,width,height),lut,false);
			material.mainPass.addShader(shader);
			new h3d.scene.Mesh(mesh.toPrimitive(),material,parent);
			shaders.push(shader);
		}
		return shaders;
	}
}
