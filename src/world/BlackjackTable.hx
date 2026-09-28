// SPDX-License-Identifier: AGPL-3.0-or-later
package world;
import h3d.col.Point;
import h3d.prim.UV;
import render.Palette;
import render.MeshBuilder;
import render.BuildShader;

class BlackjackTable {
	public static function build(palette:Palette,lut:h3d.mat.Texture,parent:h3d.scene.Object):Array<BuildShader> {
		var shaders=[];
		function surface(texture:h3d.mat.Texture,x:Float,y:Float,w:Float,h:Float,z:Float,angle:Float=0,alpha:Bool=true) {
			function p(dx:Float,dy:Float):Point return new Point(x+dx*Math.cos(angle)-dy*Math.sin(angle),y+dx*Math.sin(angle)+dy*Math.cos(angle),z);
			var mb=new MeshBuilder();
			mb.quad(p(-w/2,h/2),p(w/2,h/2),p(w/2,-h/2),p(-w/2,-h/2),new UV(0,0),new UV(1,0),new UV(1,1),new UV(0,1),new Point(0,0,1),3);
			var mat=h3d.mat.Material.create(); mat.mainPass.enableLights=false; mat.shadows=false; mat.mainPass.culling=None;
			var shader=new BuildShader(texture,lut,alpha);mat.mainPass.addShader(shader);new h3d.scene.Mesh(mb.toPrimitive(),mat,parent);shaders.push(shader);
		}
		surface(art.FoyerArt.surface("materials/blackjack-table.png",palette,512,256).toIndexTexture(false,false),13,36,2.4,1.2,.907,0,false);
		// Illustrative deal: two standard-proportion player cards and a dealer hole card.
		surface(art.CardArt.texture(cards.Card.parse("As"),palette),12.70,35.66,.22,.308,.915,-.06);
		surface(art.CardArt.texture(cards.Card.parse("Kh"),palette),12.96,35.67,.22,.308,.919,.07);
		surface(art.CardArt.texture(cards.Card.parse("7c"),palette),12.84,36.34,.20,.28,.915);
		surface(art.CardArt.texture(null,palette),13.09,36.34,.20,.28,.915);
		surface(art.CardArt.texture(null,palette),13.93,36.32,.20,.28,.915);
		return shaders;
	}
}
