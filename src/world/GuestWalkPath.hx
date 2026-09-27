// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

/** Short, collision-checked stroll for the sprite spike; not the NPC schedule. */
class GuestWalkPath {
	public var x(default, null):Float;
	public var y(default, null):Float;
	public var facing(default, null):Float;
	public var phase(default, null):Int = 0;
	final startX:Float;
	final startY:Float;
	final endX:Float;
	final endY:Float;
	var returning = false;
	var distance = 0.0;

	public function new(x:Float, y:Float, endX:Float, endY:Float) {
		this.x = startX = x;
		this.y = startY = y;
		this.endX = endX;
		this.endY = endY;
		facing = Math.atan2(endY - y, endX - x);
	}

	public function update(dt:Float, map:GridMap):Void {
		var dx = (returning ? startX : endX) - x;
		var dy = (returning ? startY : endY) - y;
		var remaining = Math.sqrt(dx * dx + dy * dy);
		if (remaining < 0.001) {
			returning = !returning;
			return;
		}
		var step = Math.min(remaining, Math.max(0, Math.min(dt, 0.1)) * 0.7);
		var nx = x + dx / remaining * step, ny = y + dy / remaining * step;
		if (map.blocked(nx, ny, 0.25)) return;
		x = nx;
		y = ny;
		facing = Math.atan2(dy, dx);
		distance += step;
		phase = Std.int(distance / 0.16) % 4;
	}
}
