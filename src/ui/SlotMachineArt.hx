// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;
import art.FoyerArt;
import games.slots.LeverPhysics;
import games.slots.Slots.Symbol;

class SlotMachineArt extends h2d.Object {
	public final lever=new LeverPhysics();
	public var onPull:Void->Void=()->{};
	public var canPull:Void->Bool=()->true;
	public var spinning(default,null)=false;
	final shaft:h2d.Graphics;
	final grip:h2d.Bitmap;
	final hit:h2d.Interactive;
	final tiles:Array<h2d.Tile>;
	final symbols:Array<Array<h2d.Bitmap>>=[];
	final positions=[0.,1.,2.];
	var starts=[0.,0.,0.];
	var stops=[0.,0.,0.];
	var age=0.;
	static final NAMES:Array<Symbol>=[Crown,Seven,Bell,Bar,Club,Diamond,Heart,Spade,Cherry,Blank];

	public function new(parent:h2d.Object,palette:render.Palette) {
		super(parent);
		var tile=FoyerArt.surface("slots/cabinet.png",palette,250,250,0,1,true).toColorTile(palette);
		var cabinet=new h2d.Bitmap(tile,this);cabinet.x=-125;
		var sheet=FoyerArt.surface("slots/symbols.png",palette,168,168,0,1,true).toColorTile(palette);
		tiles=[for(i in 0...9) sheet.sub(i%3*56,Std.int(i/3)*56,56,56)];
		for(i in 0...3) {
			var mask=new h2d.Mask(44,48,this);mask.x=-70+i*48;mask.y=96;
			var bg=new h2d.Graphics(mask);bg.beginFill(0xDDD4B8);bg.drawRect(0,0,44,48);bg.endFill();
			symbols.push([for(j in 0...3) {var b=new h2d.Bitmap(tiles[0],mask);b.setScale(40/56);b.x=2;b;}]);
			var shade=new h2d.Graphics(mask);
			for(j in 0...7) {shade.beginFill(0x17131A,(7-j)*.045);shade.drawRect(0,j,44,1);shade.drawRect(0,47-j,44,1);shade.endFill();}
		}
		shaft=new h2d.Graphics(this);
		var knob=FoyerArt.surface("slots/lever-grip.png",palette,28,28,0,1,true).toColorTile(palette);knob.dx=-14;knob.dy=-14;
		grip=new h2d.Bitmap(knob,this);
		hit=new h2d.Interactive(115,185,this);hit.x=108;hit.y=40;hit.cursor=Button;
		hit.onPush=e->{
			if(!canPull() || spinning || lever.latched || lever.held) return;
			var dx=e.relX+hit.x-grip.x,dy=e.relY+hit.y-grip.y;
			if(dx*dx+dy*dy>22*22) return;
			lever.grab();
			hit.startCapture(event->{
				if(event.kind==EMove) {
					var desiredY=event.relY+hit.y-dy;
					lever.drag(Math.acos(Math.max(-1,Math.min(1,(147-desiredY)/80))));
				}
				if(event.kind==ERelease || event.kind==EReleaseOutside || event.kind==EFocusLost) cancelDrag();
			},()->lever.release(),e.touchId);
		};
		hxd.Window.getInstance().addEventTarget(onWindowEvent);
		update(0);
	}
	function onWindowEvent(e:hxd.Event):Void {if(e.kind==EFocusLost && lever.held) cancelDrag();}
	public function cancelDrag():Void {if(lever.held) {lever.release();hit.stopCapture();}}
	public function reset():Void {cancelDrag();lever.reset();}
	public function pull():Void {if(canPull() && !spinning) lever.pull();}
	public function startSpin(result:Array<Symbol>):Void {
		age=0;spinning=true;starts=positions.copy();
		stops=[for(i in 0...3) {var base=Math.ceil(starts[i])+40+i*10; base+(NAMES.indexOf(result[i])-base%10+10)%10;}];
	}
	/** True only on the frame the final reel stops. */
	public function update(dt:Float):Bool {
		if(lever.update(dt) && !spinning && canPull()) onPull();
		var finished=false;
		if(spinning) {
			age+=Math.max(0,dt);
			for(i in 0...3) {var t=Math.min(1,age/(2.4+i*.7));positions[i]=starts[i]+(stops[i]-starts[i])*(1-Math.pow(1-t,3));}
			if(age>=3.8) {spinning=false;finished=true;}
		}
		for(i in 0...3) for(j in 0...3) {
			var phase=positions[i],whole=Math.floor(phase),n=((whole+j-1)%10+10)%10,b=symbols[i][j];
			b.visible=n<9;if(n<9) b.tile=tiles[n];b.y=4+(j-1-(phase-whole))*44;
		}
		var x=130+Math.sin(lever.angle)*80,y=147-Math.cos(lever.angle)*80;
		shaft.clear();shaft.lineStyle(9,0x332418);shaft.moveTo(130,147);shaft.lineTo(x,y);
		shaft.lineStyle(6,0xBDA16B);shaft.moveTo(130,147);shaft.lineTo(x,y);
		shaft.lineStyle(2,0xF1DCA6);shaft.moveTo(128,146);shaft.lineTo(x-2,y-1);shaft.lineStyle();
		shaft.beginFill(0xBDA16B);shaft.drawCircle(130,147,10);shaft.endFill();
		shaft.beginFill(0x514333);shaft.drawCircle(130,147,5);shaft.endFill();
		grip.x=x;grip.y=y;
		return finished;
	}
	override public function onRemove():Void {
		cancelDrag();hxd.Window.getInstance().removeEventTarget(onWindowEvent);super.onRemove();
	}
}
