// SPDX-License-Identifier: AGPL-3.0-or-later
import games.roulette.BettingLayout;
import games.roulette.Roulette;
import games.roulette.WheelMotion;

/** Export the actual hit geometry and wheel order for the reusable tabletop PNG. */
class ExportRouletteArt {
 static function main() {
  var spots = [for (s in new BettingLayout().spots) {
   var b=s.bet;
   {label:s.label,x:s.x,y:s.y,w:s.w,h:s.h,small:s.small,
    number:b.kind==Straight && b.numbers[0]!=0,
    color:b.kind==Straight?(b.numbers[0]==0?"#176047":Roulette.isRed(b.numbers[0])?"#832735":"#111923"):b.kind==Red?"#832735":b.kind==Black?"#111923":"#123D2C"};
  }];
  sys.io.File.saveContent("art-source/roulette/layout.json",haxe.Json.stringify({spots:spots,pockets:WheelMotion.POCKETS,reds:[for(n in 1...37) if(Roulette.isRed(n)) n]},null,"  ")+"\n");
 }
}
