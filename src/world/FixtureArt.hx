// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import art.FoyerArt;
import render.BuildShader;
import render.Palette;

/** The 3D art that goes with each fixture (see Fixtures for their collision), placed at its anchor. */
class FixtureArt {
	public static function build(level:Level, palette:Palette, lut:h3d.mat.Texture, parent:h3d.scene.Object):{shaders:Array<BuildShader>, water:Array<BuildShader>, animations:Array<Float->Void>} {
		var shaders:Array<BuildShader> = [], water:Array<BuildShader> = [];
		var animations:Array<Float->Void>=[];
		for (f in level.data.fixtures) switch f.type {
			case "frontDoors":
				shaders.push(FoyerArt.panel("foyer/grand-doors.png", 256, 384, f.x - 2.6, f.x + 2.6, f.y + .025, 0, 6.8, true, palette, lut, parent));
			case "frontDesk":
				shaders.push(FoyerArt.panel("foyer/welcome-desk.png", 256, 80, f.x - 2.2, f.x + 2.2, f.y - .615, .10, 1.08, false, palette, lut, parent));
			case "grandStairs":
				// The upper doorway is a visual destination for the future second floor.
				shaders.push(FoyerArt.panel("foyer/grand-doors.png", 192, 288, f.x - 1.5, f.x + 1.5, f.y + 6.475, 3.6, 7.8, false, palette, lut, parent));
			case "fountain":
				var built = Fountain.build(palette, lut, parent, f.x, f.y);
				shaders = shaders.concat(built.shaders);
				water = water.concat(built.water);
				animations.push(built.animate);
			case "cardTable":
				shaders = shaders.concat(BlackjackTable.build(palette, lut, parent, f.x, f.y));
			default:
		}
		return {shaders: shaders, water: water, animations:animations};
	}
}
