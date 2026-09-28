// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

/** The Card Room's card table (Greybox): where the player sits down to play. */
class CardRoom {
	public static final TABLE = {x0: 11.8, y0: 35.4, x1: 14.2, y1: 36.6};

	/** How far from the table's edge the player can reach it, in meters. **/
	static inline var REACH = 1.0;

	/**
		True when the player stands at the table on the guests' side (the dealer
		works the north side) and faces it.
	**/
	public static function atTable(x:Float, y:Float, yaw:Float):Bool {
		var t = TABLE;
		if (y > t.y1) return false;
		var dx = Math.max(t.x0 - x, Math.max(0, x - t.x1));
		var dy = Math.max(t.y0 - y, Math.max(0, y - t.y1));
		if (dx * dx + dy * dy > REACH * REACH) return false;
		// Facing the table's center, within about 55 degrees.
		var cx = (t.x0 + t.x1) / 2, cy = (t.y0 + t.y1) / 2;
		var tx = cx - x, ty = cy - y, len = Math.sqrt(tx * tx + ty * ty);
		if (len < 1e-6) return true;
		return (Math.cos(yaw) * tx + Math.sin(yaw) * ty) / len > 0.57;
	}
}
