// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import art.FoyerArt;
import render.BuildShader;
import render.Palette;

/** Authored machinery faces on the basement's solid, textured props. */
class BasementArt {
	public static inline var BOILER = "materials/basement-boiler.png";

	public static function build(map:GridMap,palette:Palette,lut:h3d.mat.Texture,parent:h3d.scene.Object):Array<BuildShader> {
		var shaders:Array<BuildShader>=[];
		for(p in map.props) if(p.kind=="basementBoiler") {
			var z=p.baseZ==null?-3.6:p.baseZ;
			var shader=FoyerArt.panel(BOILER,512,512,p.x0,p.x1,p.y0-.006,z,p.height,false,palette,lut,parent);
			shader.shadeOffset=-2;
			shaders.push(shader);
		}
		return shaders;
	}
}
