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

	/** The storey it's on (see Layer); absent means the ground floor. **/
	@:optional var level:Int;
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

	/** In a map file, the floor it stands on (its heights are measured from that floor). The built level's props are in world heights. **/
	@:optional var floor:Int;
}

/**
	One storey of the grid: the ground floor is level 0, floors above count up
	and basements count down. Its sectors carry world heights.
**/
typedef Layer = {
	var level:Int;

	/** Where the storey starts, in meters: it owns the heights from here up to the next storey's. **/
	var elevation:Float;

	/** Each cell's sector; null for solid cells and cells open to the storey below. **/
	var cells:Array<Null<Sector>>;

	/** Cells with no floor of their own, open to the storey below ("."). **/
	var open:Array<Bool>;
}

/**
	A grid of 1 m cells (§13.6). Each open cell belongs to a sector; `#` is
	solid. The first text row is the north edge (+Y), so the map reads like a
	floor plan.

	A map can stack any number of storeys over the same grid, above and below
	the ground floor. Asked with a height (the feet of whoever is asking), a
	cell is the room on the storey that holds that height, so the same cell
	can be a cellar, a hall and a bedroom. Asked without one, it's the ground
	floor's, as it always was.
**/
class GridMap {
	/** How far up a step can be and still be walked onto (see canStep). **/
	static inline var STEP = 0.26;

	public final width:Int;
	public final height:Int;
	public final props:Array<Prop> = [];
	public final windows:Array<FoyerWindows.FoyerWindow> = [];
	public final plants:Array<Conservatory.PlantPlacement> = [];

	/** Every storey, lowest first. The ground floor is always there. **/
	public final layers:Array<Layer> = [];

	final ground:Layer;
	final cells:Array<Null<Sector>>;

	public function new(rows:Array<String>, sectors:Map<String, Sector>) {
		height = rows.length;
		width = rows[0].length;
		ground = layer(0, 0, rows, sectors);
		cells = ground.cells;
		layers.push(ground);
	}

	/** Adds a storey above or below the ground floor, with its sectors in world heights. **/
	public function addFloor(level:Int, elevation:Float, rows:Array<String>, sectors:Map<String, Sector>):Void {
		for (l in layers) if (l.level == level) throw 'Two floors are level $level';
		layers.push(layer(level, elevation, rows, sectors));
		layers.sort((a, b) -> a.level - b.level);
	}

	function layer(level:Int, elevation:Float, rows:Array<String>, sectors:Map<String, Sector>):Layer {
		if (rows.length != height)
			throw 'Floor $level is ${rows.length} rows, expected $height';
		var l:Layer = {level: level, elevation: elevation, cells: [for (_ in 0...width * height) null], open: [for (_ in 0...width * height) false]};
		for (row in 0...height) {
			if (rows[row].length != width)
				throw 'Map row $row is ${rows[row].length} wide, expected $width';
			for (cx in 0...width) {
				var ch = rows[row].charAt(cx);
				var i = (height - 1 - row) * width + cx;
				if (ch == "#")
					continue;
				if (ch == ".") {
					l.open[i] = true;
					continue;
				}
				var sector = sectors.get(ch);
				if (sector == null)
					throw 'Map uses unknown sector "$ch"';
				l.cells[i] = sector;
			}
		}
		return l;
	}

	/**
		The sector of a cell, or null for solid cells and anything outside the
		map. With `z` (feet height) on a map with several storeys, it's the room
		holding that height (see resolve); without, the ground floor's.
	**/
	public function sectorAt(cx:Int, cy:Int, ?z:Float):Null<Sector> {
		if (cx < 0 || cy < 0 || cx >= width || cy >= height)
			return null;
		if (z == null || layers.length == 1)
			return cells[cy * width + cx];
		return resolve(cy * width + cx, z);
	}

	public function sectorAtWorld(x:Float, y:Float, ?z:Float):Null<Sector> {
		return sectorAt(Math.floor(x), Math.floor(y), z);
	}

	/**
		From the top storey down: the first room whose floor is at or just below
		`z` and whose ceiling is above it. A solid cell stops the search (null,
		a wall) when `z` is within its storey's heights; open cells, and rooms
		that don't hold `z`, let it carry on down.
	**/
	function resolve(i:Int, z:Float):Null<Sector> {
		var k = layers.length;
		while (k-- > 0) {
			var l = layers[k];
			var s = l.cells[i];
			if (s != null) {
				if (s.floorZ <= z + STEP && z < s.ceilZ)
					return s;
				continue;
			}
			if (l.open[i])
				continue;
			var top = k + 1 < layers.length ? layers[k + 1].elevation : Math.POSITIVE_INFINITY;
			if (z >= l.elevation && z < top)
				return null;
		}
		return null;
	}

	/** The storey numbered `level`, or null. **/
	public function floor(level:Int):Null<Layer> {
		for (l in layers) if (l.level == level) return l;
		return null;
	}

	/** The room painted at (x, y) on storey `level` itself (null for walls, open cells and missing floors). **/
	public function sectorOn(level:Int, x:Float, y:Float):Null<Sector> {
		var l = floor(level), cx = Math.floor(x), cy = Math.floor(y);
		if (l == null || cx < 0 || cy < 0 || cx >= width || cy >= height)
			return null;
		return l.cells[cy * width + cx];
	}

	/** The storey someone standing at (x, y) with their feet at `z` is on (0 when outside every room). **/
	public function levelAt(x:Float, y:Float, z:Float):Int {
		var s = sectorAtWorld(x, y, z);
		return s == null || s.level == null ? 0 : s.level;
	}

	/**
		What a wall of `s` on `from` looks across at, through the edge into cell
		(cx, cy): that cell on the same storey or, where the cell is open to the
		storey below, the first room below that rises past `s`'s floor. `level`
		is the storey the answer came from.
	**/
	public function across(from:Layer, s:Sector, cx:Int, cy:Int):{sector:Null<Sector>, level:Int} {
		if (cx < 0 || cy < 0 || cx >= width || cy >= height)
			return {sector: null, level: from.level};
		var i = cy * width + cx;
		if (!from.open[i])
			return {sector: from.cells[i], level: from.level};
		var k = layers.indexOf(from);
		while (k-- > 0) {
			var t = layers[k].cells[i];
			if (t != null)
				return t.ceilZ > s.floorZ ? {sector: t, level: layers[k].level} : {sector: null, level: from.level};
			if (!layers[k].open[i])
				break;
		}
		return {sector: null, level: from.level};
	}

	/**
		The height ranges of cell (cx, cy) that are open rooms on storeys other
		than `a` and `b`: where a wall between storeys has to leave a gap.
	**/
	public function openSpans(cx:Int, cy:Int, a:Int, b:Int):Array<{z0:Float, z1:Float}> {
		var out = [];
		if (layers.length == 1 || cx < 0 || cy < 0 || cx >= width || cy >= height)
			return out;
		var i = cy * width + cx;
		for (l in layers) {
			if (l.level == a || l.level == b)
				continue;
			var s = l.cells[i];
			if (s != null)
				out.push({z0: s.floorZ, z1: s.ceilZ});
		}
		return out;
	}

	/** Whether a circle at (x, y) overlaps a solid cell or a prop. **/
	public function blocked(x:Float, y:Float, radius:Float, ?feetZ:Float):Bool {
		for (cy in Math.floor(y - radius)...Math.floor(y + radius) + 1)
			for (cx in Math.floor(x - radius)...Math.floor(x + radius) + 1)
				if (sectorAt(cx, cy, feetZ) == null && circleHitsBox(x, y, radius, cx, cy, cx + 1, cy + 1))
					return true;
		for (p in props)
			if (blocksAtHeight(p,feetZ) && propOverlap(x,y,radius,p)>0)
				return true;
		return false;
	}

	/**
		Moves a circle by (dx, dy), one axis at a time so it slides along walls.
		A step is allowed when it doesn't push the circle any deeper into
		geometry, so a circle that starts overlapping a wall can always walk
		out instead of getting stuck.
	**/
	public function slide(x:Float, y:Float, dx:Float, dy:Float, radius:Float, ?feetZ:Float):{x:Float, y:Float, z:Float} {
		var z=feetZ==null?floorAt(x,y):feetZ;
		// Substeps prevent a slow frame from tunnelling through ropes or stair risers.
		var count = Std.int(Math.ceil(Math.max(Math.abs(dx), Math.abs(dy)) / 0.1));
		if (count > 1) {
			for (_ in 0...count) {
				var p = slide(x, y, dx / count, dy / count, radius, feetZ==null?null:z);
				x = p.x; y = p.y; z=p.z;
			}
			return {x: x, y: y, z:z};
		}
		if (dx != 0 && canStep(x, y, x + dx, y, radius,feetZ==null?null:z))
			x += dx;
		z=floorAt(x,y,feetZ==null?null:z);
		if (dy != 0 && canStep(x, y, x, y + dy, radius,feetZ==null?null:z))
			y += dy;
		z=floorAt(x,y,feetZ==null?null:z);
		return {x: x, y: y, z:z};
	}

	/** How far a circle at (x, y) overlaps solid cells and props, in meters (0 when clear). **/
	public function penetration(x:Float, y:Float, radius:Float, ?feetZ:Float):Float {
		var deepest = 0.0;
		for (cy in Math.floor(y - radius)...Math.floor(y + radius) + 1)
			for (cx in Math.floor(x - radius)...Math.floor(x + radius) + 1)
				if (sectorAt(cx, cy, feetZ) == null)
					deepest = Math.max(deepest, overlap(x, y, radius, cx, cy, cx + 1, cy + 1));
		for (p in props)
			if (blocksAtHeight(p,feetZ))
				deepest = Math.max(deepest, propOverlap(x,y,radius,p));
		return deepest;
	}

	function canStep(x0:Float, y0:Float, x1:Float, y1:Float, radius:Float, ?feetZ:Float):Bool {
		var from=feetZ==null?floorAt(x0,y0):feetZ, to=floorAt(x1,y1,feetZ);
		if (Math.abs(to-from) > STEP) return false;
		var targetZ=feetZ==null?null:to;
		return !blocked(x1,y1,radius,targetZ) || penetration(x1,y1,radius,targetZ)<=penetration(x0,y0,radius,feetZ);
	}

	static function blocksAtHeight(p:Prop,feetZ:Null<Float>):Bool {
		if(p.solid==false) return false;
		if(feetZ==null) return p.walkable!=true;
		var base=p.baseZ==null?0.:p.baseZ;
		if(p.height<=feetZ+.01 || base>=feetZ+1.75) return false;
		return p.walkable!=true || p.height>feetZ+.26;
	}

	static function propOverlap(x:Float,y:Float,r:Float,p:Prop):Float {
		if(p.collisionRadius!=null) {
			var dx=x-(p.x0+p.x1)/2,dy=y-(p.y0+p.y1)/2;
			return Math.max(0,r+p.collisionRadius-Math.sqrt(dx*dx+dy*dy));
		}
		return overlap(x,y,r,p.x0,p.y0,p.x1,p.y1);
	}

	/** Stair treads share their rendered heights with movement; ropes are separate. */
	public function floorAt(x:Float, y:Float, ?feetZ:Float):Float {
		var sector = sectorAtWorld(x, y, feetZ);
		var z = sector == null ? 0.0 : sector.floorZ;
		for (p in props)
			if (p.walkable == true && (feetZ==null || p.height<=feetZ+.26) && x >= p.x0 && x < p.x1 && y >= p.y0 && y < p.y1)
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
