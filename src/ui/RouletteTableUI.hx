// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import games.roulette.Roulette;
import games.roulette.BettingLayout;
import games.roulette.BettingTray;
import ui.ButtonGlyph;
import ui.TableKit;

/** Direct roulette betting: assemble Sovereign chips, place on felt, then spin. */
class RouletteTableUI extends h2d.Object {
 public var onLeave:Void->Void = () -> {};
 public var status(get,never):String;
 final wallet:core.Wallet;
 final game:Roulette;
 final layout = new BettingLayout();
 final tray = new BettingTray();
 final surface:TableSurface;
 final content:h2d.Object;
 final wheel:RouletteWheel;
 final board:h2d.Graphics;
 final marks:h2d.Graphics;
 final labels:Array<h2d.Text> = [];
 final chipTiles:Array<h2d.Tile> = [];
 final chips:Array<h2d.Bitmap> = [];
 final rackHits:Array<h2d.Interactive> = [];
 final boardHit:h2d.Interactive;
 final actions:ChoiceRow;
 final hints:HintBar;
 var usedLabels=0;
 var usedChips=0;
 var hovered = -1;
 var selected = 0;
 var focus = 0; // chips, layout, action row
 var chipIndex=2;
 var message="Click denominations to build a bet, then click the mat.";
 var result:Null<SpinResult>;
 var shownPurse=0;
 var spins=0;
 static final ACTIONS=["Spin", "Undo", "Clear", "Leave"];

 public function new(parent:h2d.Object,wallet:core.Wallet,rng:rng.IRng,palette:render.Palette) {
  super(parent);
  this.wallet=wallet;
  game=new Roulette(rng,wallet.sovereigns);
  content=new h2d.Object(this);
  surface=new TableSurface("roulette",content);
  wheel=new RouletteWheel(content,palette);wheel.setScale(.65);wheel.x=90;wheel.y=169;
  board=new h2d.Graphics(content);
  marks=new h2d.Graphics(content);
  for(value in BettingTray.DENOMINATIONS)
   chipTiles.push(art.FoyerArt.surfaceTile('chips/$value.png',palette,32,32,0,1,true));
  boardHit=new h2d.Interactive(390,194,content);boardHit.x=174;boardHit.y=80;boardHit.cursor=Button;
  boardHit.onMove=e->{hovered=layout.hit(e.relX+boardHit.x,e.relY+boardHit.y);};
  boardHit.onOut=_->hovered=-1;
  boardHit.onClick=e->{var spot=layout.hit(e.relX+boardHit.x,e.relY+boardHit.y);if(spot>=0){selected=spot;focus=1;place(spot);}};
  for(i in 0...BettingTray.DENOMINATIONS.length) {
   var hit=new h2d.Interactive(46,32,content);hit.x=578;hit.y=67+i*33;hit.cursor=Button;
   hit.onClick=_-> {chipIndex=i;focus=0;addChip(i);};rackHits.push(hit);
  }
  actions=new ChoiceRow(content);actions.onChoose=choose;
  hints=new HintBar(content);
 }
 function get_status():String return 'roulette purse ${game.purse} reserved ${tray.onMat()} held ${tray.inHand()} spins $spins';
 public function sit():Void {
  game.seatPurse(wallet.sovereigns);tray.finish();result=null;hovered=-1;focus=0;
  message="Click denominations to build a bet, then click the mat.";
 }
 function addChip(i:Int):Void {
  if(tray.locked)return;
  if(!tray.add(BettingTray.DENOMINATIONS[i],game.purse))message="Not enough unreserved Sovereigns for that chip.";
  else message='In hand: ${tray.inHand()} Sov. Click a betting space to place.';
 }
 function place(i:Int):Void {
  if(tray.locked)return;
  var amount=tray.inHand();
  if(tray.place(i,layout))message='Placed $amount Sov. Add more bets or spin.';
  else message="First click chips on the right to build your bet.";
 }
 function choose(i:Int):Void {
  if(tray.locked)return;
  switch i {
   case 0: spin();
   case 1: tray.undo();message="Removed the last chip in hand, or last placement.";
   case 2: tray.clear();message="All chips returned to your purse.";
   case 3: tray.clear();onLeave();
  }
 }
 function spin():Void {
  if(tray.locked)return;
  if(tray.inHand()>0){message="Place the chips in your hand, or Undo them, before spinning.";return;}
  var bets=tray.start(layout);
  if(bets.length==0){message="Place a bet on the mat first.";return;}
  shownPurse=game.purse-tray.onMat();
  result=game.spin(bets);wallet.sovereigns=game.purse;spins++;
  wheel.motion.start(result.pocket);message="No more bets. The ball is running.";
 }
 public function update(w:Int,dt:Float,input:MenuInput):Void {
  var scale=Math.min(1,w/640);content.setScale(scale);content.x=Math.round((w-640*scale)/2);content.y=Math.round((360-360*scale)/2);
  wheel.update(dt);
  if(tray.locked && !wheel.motion.active) {
   var net=result.payout-tray.onMat();
   message='Landed ${result.pocket}. '+(net>0?'Won $net Sov.':net<0?'Lost ${-net} Sov.':"Push.");
   tray.finish();
  }
  if(!tray.locked) {
   if(input.back){choose(3);return;}
   if(input.alt){focus=(focus+1)%3;hovered=-1;}
   if(focus==0) {
    if(input.up || input.left)chipIndex=(chipIndex+6)%7;
    if(input.down || input.right)chipIndex=(chipIndex+1)%7;
    if(input.confirm)addChip(chipIndex);
   } else if(focus==1) {
    if(input.left || input.right || input.up || input.down) {
     selected=layout.neighbor(selected,input.left?-1:input.right?1:0,input.up?-1:input.down?1:0);hovered=-1;
    }
    if(input.confirm)place(selected);
   }
  }
  actions.set(ACTIONS,[!tray.locked && tray.onMat()>0 && tray.inHand()==0,!tray.locked && (tray.onMat()>0 || tray.inHand()>0),!tray.locked && (tray.onMat()>0 || tray.inHand()>0),!tray.locked]);
  actions.layout(320,310,68);
  if(!tray.locked && focus==2)actions.handle(input);
  boardHit.visible=!tray.locked;
  for(hit in rackHits)hit.visible=!tray.locked;
  drawTable();
  hints.show(tray.locked?[{glyph:null,label:"Bets locked until the ball lands"}]:[
   {glyph:Confirm,label:focus==0?"Add chip":focus==1?"Place bet":"Choose"},
   {glyph:null,label:InputMode.usingPad?"X: switch area":"Space: switch area"},
   {glyph:Back,label:"Leave"}],320,341);
 }
 function text(s:String,x:Float,y:Float,color=TableKit.CREAM,center=false):h2d.Text {
  var t=usedLabels<labels.length?labels[usedLabels]:{var n=TableKit.text(content);labels.push(n);n;};usedLabels++;
  t.visible=true;t.text=s;t.textColor=color;t.x=Math.round(center?x-t.textWidth/2:x);t.y=Math.round(y);return t;
 }
 function chip(i:Int,x:Float,y:Float,size=32):h2d.Bitmap {
  var b=usedChips<chips.length?chips[usedChips]:{var n=new h2d.Bitmap(null,content);chips.push(n);n;};usedChips++;
  b.tile=chipTiles[i];b.setScale(size/32);b.x=Math.round(x-size/2);b.y=Math.round(y-size/2);b.visible=true;b.alpha=1;return b;
 }
 function drawTable():Void {
  usedLabels=usedChips=0;board.clear();marks.clear();
  TableKit.panel(board,10,7,620,46,.82);
  text('Purse ${tray.locked?shownPurse:game.purse} Sov',18,12,TableKit.GOLD);
  text('ROULETTE  /  SINGLE ZERO',332,12,TableKit.GOLD,true);
  text(tray.locked?"BETS LOCKED":'Free ${tray.available(game.purse)} Sov',622,12,TableKit.GOLD).x=496;
  text(message,320,32,TableKit.CREAM,true);
  text('In hand: ${tray.inHand()} Sov',360,64,TableKit.GOLD,true);
  text("CHIPS",601,53,TableKit.GOLD,true);
  for(i in 0...layout.spots.length) {
   var s=layout.spots[i],b=s.bet;
   // Permanent markings live in the shared tabletop PNG; only feedback is dynamic.
   if(s.small)continue;
   if(result!=null && !tray.locked && b.kind==Straight && b.numbers[0]==result.pocket) {
    marks.lineStyle(2,TableKit.GOLD);marks.drawRect(s.x+2,s.y+2,s.w-4,s.h-4);marks.lineStyle();
   }
  }
  var active=hovered>=0?hovered:focus==1?selected:-1;
  if(active>=0 && !tray.locked) {
   var s=layout.spots[active];
   marks.lineStyle(2,TableKit.GOLD);marks.drawRect(s.x-1,s.y-1,s.w+2,s.h+2);marks.lineStyle();
  }
  var sums=new Map<Int,Int>();
  for(p in tray.placed)sums.set(p.spot,(sums.exists(p.spot)?sums.get(p.spot):0)+p.amount);
  for(spot=>amount in sums) {
   var s=layout.spots[spot],remaining=amount,stack=0;
   // Up to three visible chips; the hover line gives the exact combined stake.
   var i=6;while(i>=0 && stack<3){if(remaining>=BettingTray.DENOMINATIONS[i]){
    chip(i,s.x+s.w/2+stack,s.y+s.h/2+(s.bet.kind==Straight && s.bet.numbers[0]!=0?7:0)-stack*2,16);remaining-=BettingTray.DENOMINATIONS[i];stack++;
   }else i--;}
  }
  for(i in 0...7) {
   var y=83+i*33;
   if(focus==0 && i==chipIndex && !tray.locked){marks.lineStyle(1,TableKit.GOLD);marks.drawCircle(601,y,18);marks.lineStyle();}
   var b=chip(i,601,y);if(tray.locked || BettingTray.DENOMINATIONS[i]>tray.available(game.purse))b.alpha=.4;
  }
  TableKit.panel(board,12,258,157,43,.86);
  text('On mat: ${tray.onMat()} Sov',20,264,TableKit.GOLD);
  text("La Partage on 0",20,281,TableKit.CREAM);
  var detail=layout.description(active);
  if(active>=0 && sums.exists(active))detail+='  |  ${sums.get(active)} Sov placed';
  text(detail,374,287,TableKit.GOLD,true);
  if(result!=null && !tray.locked)text('LAST: ${result.pocket}',90,69,TableKit.GOLD,true);
  for(i in usedLabels...labels.length)labels[i].visible=false;
  for(i in usedChips...chips.length)chips[i].visible=false;
 }
}
