// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import art.FoyerArt;
import render.BuildShader;
import render.Palette;

/** Authored decorative CCTV and VHS panels on the room's physical equipment. */
class SecurityArt {
	public static function build(map:GridMap,palette:Palette,lut:h3d.mat.Texture,parent:h3d.scene.Object):Array<BuildShader> {
		var shaders:Array<BuildShader> = [];
		for(p in map.props) {
			var monitors=p.kind=="securityMonitors";
			if(!monitors && p.kind!="securityVhs") continue;
			var file=monitors?"security-monitors":"security-vhs";
			var shader=FoyerArt.panel('materials/$file.png',384,monitors?256:128,p.x0,p.x1,p.y0-.006,
				p.baseZ==null?0:p.baseZ,p.height,false,palette,lut,parent);
			if(monitors) {shader.shadeOffset=-4;shader.visibility=.02;}
			shaders.push(shader);
		}
		return shaders;
	}
}
