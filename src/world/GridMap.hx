// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

/** One area of the manor with Build-style sector properties (§5.4, §13.6). **/
typedef Sector = {
	/** Room name, for error reports and debugging. **/
	var name:String;

	var floorZ:Float;
	var ceilZ:Float;
	var floorTex:String;
	var ceilTex:String;

	/** Lower 3 m of walls (wainscot, paper, crown molding). **/
	var wallTex:String;

	/** Walls above 3 m, and the step between a high and a low ceiling. **/
	var upperTex:String;

	/** Base shade level: 0 is brightest, 31 is black. **/
	var shade:Float;
}

/** A solid box standing on the floor: tables, desks. **/
typedef Prop = {
	var x0:Float;
	var y0:Float;
	var x1:Float;
	var y1:Float;
	var height:Float;
	var topTex:String;
	var sideTex:String;
	@:optional var baseZ:Float;
	@:optional var solid:Bool;
	@:optional var walkable:Bool;
	@:optional var hidden:Bool;
	@:optional var kind:String;
	@:optional var collisionRadius:Float;
}

/**
	A grid of 1 m cells (§13.6). Each open cell belongs to a sector; `#` is
	solid. The first text row is the north edge (+Y), so the map reads like a
	floor plan.
**/
class GridMap {
	public final width:Int;
	public final height:Int;
	public final props:Array<Prop> = [];

	final cells:Array<Null<Sector>>;

	public function new(rows:Array<String>, sectors:Map<String, Sector>) {
		height = rows.length;
		width = rows[0].length;
		cells = [for (_ in 0...width * height) null];
		for (row in 0...height) {
			if (rows[row].length != width)
				throw 'Map row $row is ${rows[row].length} wide, expected $width';
			for (cx in 0...width) {
				var ch = rows[row].charAt(cx);
				if (ch == "#")
					continue;
				var sector = sectors.get(ch);
				if (sector == null)
					throw 'Map uses unknown sector "$ch"';
				cells[(height - 1 - row) * width + cx] = sector;
			}
		}
	}

	/** The sector of a cell, or null for solid cells and anything outside the map. **/
	public function sectorAt(cx:Int, cy:Int):Null<Sector> {
		if (cx < 0 || cy < 0 || cx >= width || cy >= height)
			return null;
		return cells[cy * width + cx];
	}

	public function sectorAtWorld(x:Float, y:Float):Null<Sector> {
		return sectorAt(Math.floor(x), Math.floor(y));
	}

	/** Whether a circle at (x, y) overlaps a solid cell or a prop. **/
	public function blocked(x:Float, y:Float, radius:Float):Bool {
		for (cy in Math.floor(y - radius)...Math.floor(y + radius) + 1)
			for (cx in Math.floor(x - radius)...Math.floor(x + radius) + 1)
				if (sectorAt(cx, cy) == null && circleHitsBox(x, y, radius, cx, cy, cx + 1, cy + 1))
					return true;
		for (p in props)
			if (p.solid != false && p.walkable != true && propOverlap(x,y,radius,p)>0)
				return true;
		return false;
	}

	/**
		Moves a circle by (dx, dy), one axis at a time so it slides along walls.
		A step is allowed when it doesn't push the circle any deeper into
		geometry, so a circle that starts overlapping a wall can always walk
		out instead of getting stuck.
	**/
	public function slide(x:Float, y:Float, dx:Float, dy:Float, radius:Float):{x:Float, y:Float} {
		// Substeps prevent a slow frame from tunnelling through ropes or stair risers.
		var count = Std.int(Math.ceil(Math.max(Math.abs(dx), Math.abs(dy)) / 0.1));
		if (count > 1) {
			for (_ in 0...count) {
				var p = slide(x, y, dx / count, dy / count, radius);
				x = p.x; y = p.y;
			}
			return {x: x, y: y};
		}
		if (dx != 0 && canStep(x, y, x + dx, y, radius))
			x += dx;
		if (dy != 0 && canStep(x, y, x, y + dy, radius))
			y += dy;
		return {x: x, y: y};
	}

	/** How far a circle at (x, y) overlaps solid cells and props, in meters (0 when clear). **/
	public function penetration(x:Float, y:Float, radius:Float):Float {
		var deepest = 0.0;
		for (cy in Math.floor(y - radius)...Math.floor(y + radius) + 1)
			for (cx in Math.floor(x - radius)...Math.floor(x + radius) + 1)
				if (sectorAt(cx, cy) == null)
					deepest = Math.max(deepest, overlap(x, y, radius, cx, cy, cx + 1, cy + 1));
		for (p in props)
			if (p.solid != false && p.walkable != true)
				deepest = Math.max(deepest, propOverlap(x,y,radius,p));
		return deepest;
	}

	function canStep(x0:Float, y0:Float, x1:Float, y1:Float, radius:Float):Bool {
		if (Math.abs(floorAt(x1, y1) - floorAt(x0, y0)) > 0.26) return false;
		return !blocked(x1, y1, radius) || penetration(x1, y1, radius) <= penetration(x0, y0, radius);
	}

	static function propOverlap(x:Float,y:Float,r:Float,p:Prop):Float {
		if(p.collisionRadius!=null) {
			var dx=x-(p.x0+p.x1)/2,dy=y-(p.y0+p.y1)/2;
			return Math.max(0,r+p.collisionRadius-Math.sqrt(dx*dx+dy*dy));
		}
		return overlap(x,y,r,p.x0,p.y0,p.x1,p.y1);
	}

	/** Stair treads share their rendered heights with movement; ropes are separate. */
	public function floorAt(x:Float, y:Float):Float {
		var sector = sectorAtWorld(x, y);
		var z = sector == null ? 0.0 : sector.floorZ;
		for (p in props)
			if (p.walkable == true && x >= p.x0 && x < p.x1 && y >= p.y0 && y < p.y1)
				z = Math.max(z, p.height);
		return z;
	}

	static function circleHitsBox(x:Float, y:Float, r:Float, x0:Float, y0:Float, x1:Float, y1:Float):Bool {
		var nx = Math.max(x0, Math.min(x, x1));
		var ny = Math.max(y0, Math.min(y, y1));
		var dx = x - nx, dy = y - ny;
		return dx * dx + dy * dy < r * r;
	}

	/** Overlap depth of a circle with a box: radius minus the distance to the box (0 if apart). **/
	static function overlap(x:Float, y:Float, r:Float, x0:Float, y0:Float, x1:Float, y1:Float):Float {
		var nx = Math.max(x0, Math.min(x, x1));
		var ny = Math.max(y0, Math.min(y, y1));
		var d = Math.sqrt((x - nx) * (x - nx) + (y - ny) * (y - ny));
		return d < r ? r - d : 0;
	}
}
