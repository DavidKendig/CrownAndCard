// SPDX-License-Identifier: AGPL-3.0-or-later
package render;

import h3d.col.Point;
import h3d.prim.UV;

/**
	Collects quads for one texture and turns them into a Heaps primitive.
	Each vertex carries its area's base shade in the color channel (read by
	BuildShader as `input.color.x`).
**/
class MeshBuilder {
	final points:Array<Point> = [];
	final normals:Array<Point> = [];
	final uvs:Array<UV> = [];
	final colors:Array<Point> = [];

	public function new() {}

	public var isEmpty(get, never):Bool;

	inline function get_isEmpty():Bool {
		return points.length == 0;
	}

	/**
		Adds a quad from four corners in order (a, b, c, d) with matching UVs.
		Winding doesn't matter: world materials draw both sides.
	**/
	public function quad(a:Point, b:Point, c:Point, d:Point, ua:UV, ub:UV, uc:UV, ud:UV, normal:Point, shade:Float):Void {
		vertex(a, ua, normal, shade);
		vertex(b, ub, normal, shade);
		vertex(c, uc, normal, shade);
		vertex(a, ua, normal, shade);
		vertex(c, uc, normal, shade);
		vertex(d, ud, normal, shade);
	}

	inline function vertex(p:Point, uv:UV, normal:Point, shade:Float):Void {
		points.push(p.clone());
		uvs.push(uv);
		normals.push(normal);
		colors.push(new Point(shade, 0, 0));
	}

	/** An axis-aligned box (tables, desks). `top` and `side` builders may be the same. **/
	public static function box(top:MeshBuilder, side:MeshBuilder, x0:Float, y0:Float, z0:Float, x1:Float, y1:Float, z1:Float, shade:Float):Void {
		inline function p(x, y, z)
			return new Point(x, y, z);
		inline function uv(u, v)
			return new UV(u, v);
		top.quad(p(x0, y0, z1), p(x1, y0, z1), p(x1, y1, z1), p(x0, y1, z1), uv(x0, -y0), uv(x1, -y0), uv(x1, -y1), uv(x0, -y1), p(0, 0, 1), shade);
		var h = z1 - z0;
		side.quad(p(x0, y0, z1), p(x1, y0, z1), p(x1, y0, z0), p(x0, y0, z0), uv(0, 0), uv(x1 - x0, 0), uv(x1 - x0, h), uv(0, h), p(0, -1, 0), shade);
		side.quad(p(x1, y1, z1), p(x0, y1, z1), p(x0, y1, z0), p(x1, y1, z0), uv(0, 0), uv(x1 - x0, 0), uv(x1 - x0, h), uv(0, h), p(0, 1, 0), shade);
		side.quad(p(x0, y1, z1), p(x0, y0, z1), p(x0, y0, z0), p(x0, y1, z0), uv(0, 0), uv(y1 - y0, 0), uv(y1 - y0, h), uv(0, h), p(-1, 0, 0), shade);
		side.quad(p(x1, y0, z1), p(x1, y1, z1), p(x1, y1, z0), p(x1, y0, z0), uv(0, 0), uv(y1 - y0, 0), uv(y1 - y0, h), uv(0, h), p(1, 0, 0), shade);
	}

	public function toPrimitive():h3d.prim.Polygon {
		var poly = new h3d.prim.Polygon(points);
		poly.normals = normals;
		poly.uvs = uvs;
		poly.colors = colors;
		return poly;
	}
}
