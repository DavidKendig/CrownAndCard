// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

/** Translucent departure confirmation, drawn over the paused world. */
class EntranceUI {
	public var open(default,null)=false;
	public var departed(default,null)=false;
	public var onLeave:Void->Void=()->{};
	public var onStay:Void->Void=()->{};
	/** Clicking the on-screen prompt does the same as pressing E / A. **/
	public var onPrompt:Void->Void=()->{};
	final root:h2d.Object;
	final shade:h2d.Graphics;
	final panel:h2d.Graphics;
	final heading:h2d.Text;
	final detail:h2d.Text;
	final stay:h2d.Text;
	final leave:h2d.Text;
	final stayHit:h2d.Interactive;
	final leaveHit:h2d.Interactive;
	final hint:h2d.Text;
	final hintHit:h2d.Interactive;
	final glyph:h2d.Bitmap;
	final blocker:h2d.Interactive;
	var selected=0;
	var message="";
	var messageSeconds=0.0;

	public function new(parent:h2d.Object) {
		hint=text(parent,0xF4DBA5);
		hintHit=new h2d.Interactive(300,24,hint); hintHit.onClick=_->onPrompt();
		glyph=new h2d.Bitmap(null,parent);
		root=new h2d.Object(parent); shade=new h2d.Graphics(root); panel=new h2d.Graphics(root);
		blocker=new h2d.Interactive(640,360,root);
		heading=text(root,0xF4DBA5); detail=text(root,0xEFE6D2);
		stay=text(root,0xF4DBA5); leave=text(root,0xF4DBA5);
		stayHit=new h2d.Interactive(130,30,root); leaveHit=new h2d.Interactive(130,30,root);
		stayHit.onClick=_->cancel(); leaveHit.onClick=_->confirm();
		stayHit.onOver=_->selected=0; leaveHit.onOver=_->selected=1;
		root.visible=false;
	}

	static function text(parent:h2d.Object,color:Int):h2d.Text {
		var t=new h2d.Text(hxd.res.DefaultFont.get(),parent); t.textColor=color;
		t.dropShadow={dx:1,dy:1,color:0x000000,alpha:1}; return t;
	}

	public function notify(value:String,seconds:Float=5):Void { message=value; messageSeconds=seconds; }
	public function show():Void { open=true; root.visible=true; selected=0; }
	function cancel():Void { if (!open || departed) return; open=false; root.visible=false; onStay(); }
	function confirm():Void { if (!open || departed) return; departed=true; onLeave(); }

	/** `actionable` prompts get the E key or the controller's A button in front of them. **/
	public function update(w:Int,dt:Float,pad:hxd.Pad,prompt:String,actionable:Bool=false):Void {
		messageSeconds-=dt;
		hint.text=open?"":messageSeconds>0?message:prompt;
		hint.maxWidth=w-32; hint.textAlign=Center; hint.x=16; hint.y=316;
		var showGlyph=!open && messageSeconds<=0 && actionable && prompt!="";
		hintHit.width=w-32; hintHit.visible=showGlyph;
		glyph.visible=showGlyph;
		if (showGlyph) {
			glyph.tile=ButtonGlyph.tile(Confirm,ButtonGlyph.InputMode.usingPad);
			// Center the glyph and the text together as one line.
			var lineW=glyph.tile.width+5+hint.textWidth;
			glyph.x=Math.round(w/2-lineW/2);
			glyph.y=Math.round(hint.y+(hint.textHeight-ButtonGlyph.HEIGHT)/2);
			hint.x=16+Math.round((glyph.tile.width+5)/2);
		}
		if (!open) return;
		blocker.width=w;
		if (!departed) {
			if (hxd.Key.isPressed(hxd.Key.ESCAPE) || (pad.connected && pad.isPressed(pad.config.B))) cancel();
			if (hxd.Key.isPressed(hxd.Key.LEFT) || hxd.Key.isPressed(hxd.Key.RIGHT) || hxd.Key.isPressed(hxd.Key.TAB)
				|| (pad.connected && (pad.isPressed(pad.config.dpadLeft)||pad.isPressed(pad.config.dpadRight)))) selected=1-selected;
			if (hxd.Key.isPressed(hxd.Key.ENTER) || (pad.connected && pad.isPressed(pad.config.A))) {
				if(selected==0) cancel(); else confirm();
			}
		}
		shade.clear(); shade.beginFill(0x080B16,.56); shade.drawRect(0,0,w,360); shade.endFill();
		var pw=Math.min(440,w-24), left=(w-pw)/2;
		panel.clear(); panel.beginFill(0x101524,.78); panel.lineStyle(1,0xC8A35E,.9); panel.drawRect(left,98,pw,160); panel.endFill();
		heading.text=departed?"UNTIL YOUR NEXT VISIT":"LEAVE DODRIEC MANOR?";
		heading.maxWidth=pw-24; heading.textAlign=Center; heading.x=left+12; heading.y=115;
		detail.text=departed?"Your visit has ended. You may close this tab.\nReturn through the launcher when you are ready.":"Leave the manor and quit the game?\nOnly your last check-in with Mr. Quill is saved.";
		detail.maxWidth=pw-32; detail.textAlign=Center; detail.x=left+16; detail.y=148;
		stay.visible=leave.visible=stayHit.visible=leaveHit.visible=!departed;
		stay.text=(selected==0?"> ":"")+"STAY"; leave.text=(selected==1?"> ":"")+"LEAVE";
		stay.x=w/2-115; leave.x=w/2+32; stay.y=leave.y=210;
		stayHit.setPosition(w/2-130,203); leaveHit.setPosition(w/2+16,203);
	}
}
