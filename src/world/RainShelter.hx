// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

/** Rain starts above the highest roof touching a sheet, including cell boundaries. */
class RainShelter {
 public static function base(map:GridMap,x:Float,y:Float):Float {
  var z=0.;
  for(dx in [-.01,.01]) for(dy in [-.01,.01]) {
   var room=map.sectorAtWorld(x+dx,y+dy);
   if(room!=null)z=Math.max(z,room.ceilZ+.2);
  }
  return z;
 }
}
