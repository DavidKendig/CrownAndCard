// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;
import games.roulette.Roulette;
import art.FoyerArt;
import games.roulette.WheelMotion;

/** Layered artwork: fixed ball track, rotating numbered rotor, independent ball. */
class RouletteWheel extends h2d.Object {
	public final motion=new WheelMotion();
	final rotor:h2d.Object;
	final ball:h2d.Bitmap;
	final shadow:h2d.Graphics;
	public function new(parent:h2d.Object,palette:render.Palette) {
		super(parent);
		function art(name:String,size:Int,parent:h2d.Object):h2d.Bitmap {
			var tile=FoyerArt.surface("roulette/"+name+".png",palette,size,size,0,1,true).toColorTile(palette);
			tile.dx=-size/2;tile.dy=-size/2;return new h2d.Bitmap(tile,parent);
		}
		art("roulette-bowl",240,this);
		rotor=new h2d.Object(this);
		var ring=new h2d.Graphics(rotor),step=Math.PI*2/37;
		for(i in 0...37) {
			var n=WheelMotion.POCKETS[i],angle=i*step-Math.PI/2;
			ring.beginFill(n==0?0x176E49:Roulette.isRed(n)?0x8C2636:0x141923);
			ring.lineStyle(.6,0xBDA06C);
			for(j in 0...5) {
				var a=angle-step/2+step*j/4;
				if(j==0) ring.moveTo(Math.cos(a)*77,Math.sin(a)*77);else ring.lineTo(Math.cos(a)*77,Math.sin(a)*77);
			}
			for(j in 0...5) {var a=angle+step/2-step*j/4;ring.lineTo(Math.cos(a)*54,Math.sin(a)*54);}
			ring.endFill();
			var label=TableKit.text(rotor,0xEFE6D2);label.text=Std.string(n);label.setScale(.52);
			label.x=Math.cos(angle)*71-label.textWidth*.26;label.y=Math.sin(angle)*71-label.textHeight*.26;
		}
		art("roulette-rotor",110,rotor);
		shadow=new h2d.Graphics(this);shadow.beginFill(0x050709,.65);shadow.drawEllipse(0,0,4,2.6);shadow.endFill();
		ball=art("roulette-ball",12,this);
		pose();
	}
	public function update(dt:Float):Void {motion.update(dt);pose();}
	function pose():Void {
		rotor.rotation=motion.wheel;
		ball.x=Math.cos(motion.ball)*112*motion.radius;
		ball.y=Math.sin(motion.ball)*112*motion.radius-motion.bounce*40;
		shadow.x=ball.x+1;shadow.y=ball.y+2+motion.bounce*40;
	}
}
