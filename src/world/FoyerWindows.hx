// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

typedef FoyerWindow = {x0:Float, x1:Float, y:Float, bottom:Float, top:Float};

/** South-facing entrance windows. Rendering opens the wall; collision stays solid. */
class FoyerWindows {
	public static function layout(map:GridMap, x:Float, y:Float):Array<FoyerWindow> {
		var result:Array<FoyerWindow> = [];
		// Only an exterior south facade can overlook the courtyard.
		if (y != 1 || x != Math.floor(x)) return result;
		for (offset in [-7, -4, 4, 7]) {
			var left = x + offset - 1;
			var valid = true;
			for (cx in Std.int(left)...Std.int(left + 2)) {
				var s = map.sectorAt(cx, 1);
				if (s == null || s.floorZ != 0 || s.ceilZ < 6 || map.sectorAt(cx, 0) != null) valid = false;
			}
			if (valid) result.push({x0:left, x1:left+2, y:y, bottom:1.15, top:5.7});
		}
		return result;
	}
}
