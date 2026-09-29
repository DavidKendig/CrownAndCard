// SPDX-License-Identifier: AGPL-3.0-or-later
package art;

import render.IndexCanvas;
import render.Palette;
import render.BuildShader;
import render.MeshBuilder;
import h3d.col.Point;
import h3d.prim.UV;

class FoyerArt {
	/** Full-bleed surface imports have no transparent sprite gutters. */
	public static function surface(path:String, palette:Palette, w:Int, h:Int, fromY:Float=0, toY:Float=1, transparent:Bool=false):IndexCanvas {
		var source = hxd.Res.load(path).toImage().getPixels();
		var result = new IndexCanvas(w,h);
		for (y in 0...h) for (x in 0...w) {
			var c = source.getPixel(Std.int((x+.5)*source.width/w),Std.int((fromY+(y+.5)/h*(toY-fromY))*source.height));
			if(transparent && (c >>> 24)<128) continue;
			result.set(x,y,palette.nearestRgb(c));
		}
		return result;
	}

	/** Authored art as a 2D tile, `w` × `h` grid units, drawn at the render resolution (render.Resolution). **/
	public static function surfaceTile(path:String, palette:Palette, w:Int, h:Int, fromY:Float = 0, toY:Float = 1, transparent:Bool = false):h2d.Tile
		return render.Resolution.tile(w, h, (pw, ph) -> surface(path, palette, pw, ph, fromY, toY, transparent).toColorPixels(palette));

	/** Authored art as a world texture: `w` × `h` texels at 480 lines, twice that at 720 (render.Resolution). **/
	public static function texture(transparentZero:Bool, repeat:Bool, path:String, palette:Palette, w:Int, h:Int, fromY:Float = 0, toY:Float = 1,
			transparent:Bool = false):h3d.mat.Texture
		return render.Resolution.texture(w, h, repeat, (pw, ph) -> surface(path, palette, pw, ph, fromY, toY, transparent).toIndexPixels(transparentZero));

	public static function material(ramp:Int, step:Int):IndexCanvas {
		var result = new IndexCanvas(64,64);
		for (y in 0...64) for (x in 0...64)
			result.set(x,y,Palette.index(ramp,step + ((x*13+y*7)%31==0 ? 1 : 0)));
		return result;
	}

	/** A fixed world plane (door and desk artwork never rotate toward the camera), parallel to the X axis at `y`. */
	public static function panel(path:String, w:Int, h:Int, x0:Float, x1:Float, y:Float, z0:Float, z1:Float, facesNorth:Bool,
			palette:Palette, lut:h3d.mat.Texture, parent:h3d.scene.Object):BuildShader {
		var mb = new MeshBuilder();
		var a = facesNorth ? x1 : x0, b = facesNorth ? x0 : x1;
		mb.quad(new Point(a,y,z1),new Point(b,y,z1),new Point(b,y,z0),new Point(a,y,z0),
			new UV(0,0),new UV(1,0),new UV(1,1),new UV(0,1),new Point(0,facesNorth?1:-1,0),4);
		var mat = h3d.mat.Material.create(); mat.mainPass.enableLights=false; mat.shadows=false; mat.mainPass.culling=None;
		var shader = new BuildShader(texture(false,false,path,palette,w,h),lut,false);
		mat.mainPass.addShader(shader); new h3d.scene.Mesh(mb.toPrimitive(),mat,parent);
		return shader;
	}
}
