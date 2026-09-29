// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import art.SpriteArt;
import render.BuildSprite;
import render.IndexCanvas;
import render.Palette;

/** Directional plumbing art, paired with the map's hidden collision footprints. */
class BathroomArt {
	public static final ASSETS = ["bathroom-sink", "bathroom-toilet", "bathroom-roll-stand"];
	public static function sheet(name:String,palette:Palette):IndexCanvas {
		var image=SpriteArt.importSheet(hxd.Res.load('sprites/$name.png').toImage().getPixels(),palette,5,96,128);
		// Front three-quarter and profile face right in the source. Rear three-quarter
		// already faces the opposite way, as required by the five-angle convention.
		var original=image.copy();
		for(f in 1...3) for(y in 0...128) for(x in 0...96)
			image.set(f*96+x,y,original.get((f+1)*96-1-x,y));
		return image;
	}
	public static function build(map:GridMap,palette:Palette,lut:h3d.mat.Texture,parent:h3d.scene.Object):Array<BuildSprite> {
		var result:Array<BuildSprite>=[];
		var textures=new Map<String,h3d.mat.Texture>();
		for(p in map.props) {
			var name=switch p.kind {
				case "bathroomSink": ASSETS[0];
				case "bathroomToilet": ASSETS[1];
				case "bathroomRoll": ASSETS[2];
				default: continue;
			};
			if(!textures.exists(name)) textures.set(name,sheet(name,palette).toIndexTexture(true,false));
			var base=p.baseZ==null?0.:p.baseZ, height=p.height-base;
			var sprite=new BuildSprite(textures.get(name),lut,5,height*.75,height,parent);
			sprite.setPosition((p.x0+p.x1)/2,(p.y0+p.y1)/2,base);
			sprite.facing=-Math.PI/2;
			var sector=map.sectorAtWorld(sprite.mesh.x,sprite.mesh.y);
			sprite.shader.shadeOffset=sector==null?4:sector.shade;
			result.push(sprite);
		}
		return result;
	}
}
