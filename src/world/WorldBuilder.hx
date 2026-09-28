// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import h3d.col.Point;
import h3d.prim.UV;
import render.BuildShader;
import render.MeshBuilder;
import world.GridMap.Sector;

/**
	Bakes a GridMap into meshes (§13.6): floors, ceilings, walls, the steps
	between high and low ceilings, and props. One mesh per texture.
**/
class WorldBuilder {
	/** Height of the lower wall texture (wainscot to crown molding). **/
	static inline var WALL_TEX_HEIGHT = 3.0;

	/**
		Returns every shader it created so the caller can set lights and
		visibility on all of them.
	**/
	public static function build(map:GridMap, textures:Map<String, h3d.mat.Texture>, shadeLut:h3d.mat.Texture, parent:h3d.scene.Object):Array<BuildShader> {
		var builders = new Map<String, MeshBuilder>();
		function mb(key:String):MeshBuilder {
			var b = builders.get(key);
			if (b == null) {
				if (!textures.exists(key))
					throw 'No texture named "$key"';
				b = new MeshBuilder();
				builders.set(key, b);
			}
			return b;
		}

		for (cy in 0...map.height)
			for (cx in 0...map.width) {
				var s = map.sectorAt(cx, cy);
				if (s == null)
					continue;
				addFloorAndCeiling(mb, s, cx, cy);
				// East, west, north, south neighbors.
				addEdge(mb, s, map.sectorAt(cx + 1, cy), new Point(cx + 1, cy, 0), new Point(cx + 1, cy + 1, 0), cy, 1);
				addEdge(mb, s, map.sectorAt(cx - 1, cy), new Point(cx, cy + 1, 0), new Point(cx, cy, 0), cy, 1);
				addEdge(mb, s, map.sectorAt(cx, cy + 1), new Point(cx + 1, cy + 1, 0), new Point(cx, cy + 1, 0), cx, 0);
				addEdge(mb, s, map.sectorAt(cx, cy - 1), new Point(cx, cy, 0), new Point(cx + 1, cy, 0), cx, 0);
			}

		for (p in map.props) {
			if (p.hidden == true) continue;
			var s = map.sectorAtWorld((p.x0 + p.x1) / 2, (p.y0 + p.y1) / 2);
			var shade = s == null ? 8.0 : s.shade;
			MeshBuilder.box(mb(p.topTex), mb(p.sideTex), p.x0, p.y0, p.baseZ == null ? 0 : p.baseZ, p.x1, p.y1, p.height, shade);
		}

		var shaders = [];
		for (key => b in builders) {
			var mat = h3d.mat.Material.create();
			mat.mainPass.enableLights = false;
			mat.shadows = false;
			mat.mainPass.culling = None;
			var shader = new BuildShader(textures.get(key), shadeLut, false);
			mat.mainPass.addShader(shader);
			new h3d.scene.Mesh(b.toPrimitive(), mat, parent);
			shaders.push(shader);
		}
		return shaders;
	}

	static function addFloorAndCeiling(mb:String->MeshBuilder, s:Sector, cx:Int, cy:Int):Void {
		var x0 = cx, y0 = cy, x1 = cx + 1, y1 = cy + 1;
		inline function uv(x:Float, y:Float)
			return new UV(x, -y);
		mb(s.floorTex).quad(new Point(x0, y0, s.floorZ), new Point(x1, y0, s.floorZ), new Point(x1, y1, s.floorZ), new Point(x0, y1, s.floorZ),
			uv(x0, y0), uv(x1, y0), uv(x1, y1), uv(x0, y1), new Point(0, 0, 1), s.shade);
		// Ceilings sit a little darker than floors, like Build maps usually did.
		mb(s.ceilTex).quad(new Point(x0, y0, s.ceilZ), new Point(x1, y0, s.ceilZ), new Point(x1, y1, s.ceilZ), new Point(x0, y1, s.ceilZ),
			uv(x0, y0), uv(x1, y0), uv(x1, y1), uv(x0, y1), new Point(0, 0, -1), s.shade + 2);
	}

	/**
		Walls along one cell edge from `a` to `b` (as seen from inside the cell).
		`along` is the edge's starting coordinate, so textures line up across cells.
		`shadeBias` darkens east/west faces slightly to give rooms some form.
	**/
	static function addEdge(mb:String->MeshBuilder, s:Sector, n:Null<Sector>, a:Point, b:Point, along:Int, shadeBias:Float):Void {
		var shade = s.shade + shadeBias;
		// A generated damask panel spans three metres, avoiding compressed woodwork.
		var repeat = s.wallTex == "damask" ? 3.0 : 1.0;
		var u0 = along / repeat, u1 = (along + 1) / repeat;
		if (n == null) {
			var lowerTop = Math.min(s.ceilZ, s.floorZ + WALL_TEX_HEIGHT);
			wall(mb(s.wallTex), a, b, s.floorZ, lowerTop, u0, u1, (s.floorZ + WALL_TEX_HEIGHT - lowerTop) / WALL_TEX_HEIGHT, 1, shade);
			if (s.ceilZ > lowerTop)
				wall(mb(s.upperTex), a, b, lowerTop, s.ceilZ, u0, u1, 0, s.ceilZ - lowerTop, shade);
		} else if (n.ceilZ < s.ceilZ) {
			// Step up from a neighbor's lower ceiling to ours.
			wall(mb(s.upperTex), a, b, n.ceilZ, s.ceilZ, u0, u1, 0, s.ceilZ - n.ceilZ, shade);
		}
	}

	static function wall(builder:MeshBuilder, a:Point, b:Point, z0:Float, z1:Float, u0:Float, u1:Float, vTop:Float, vBottom:Float, shade:Float):Void {
		var normal = new Point(-(b.y - a.y), b.x - a.x, 0);
		builder.quad(new Point(a.x, a.y, z1), new Point(b.x, b.y, z1), new Point(b.x, b.y, z0), new Point(a.x, a.y, z0), new UV(u0, vTop),
			new UV(u1, vTop), new UV(u1, vBottom), new UV(u0, vBottom), normal, shade);
	}
}
