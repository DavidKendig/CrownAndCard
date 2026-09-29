// SPDX-License-Identifier: AGPL-3.0-or-later
/** CPU preview of the exact palette/alpha import used by the game. */
class PreviewPrivateParty {
 static function main() {
  hxd.Res.initEmbed();
  var palette=new render.Palette(),px=hxd.Pixels.alloc(640,440,RGBA);
  px.clear(0xFF26352F);
  function draw(sheet:render.IndexCanvas,dx:Int,dy:Int) {
   for(y in 0...sheet.height) for(x in 0...sheet.width) {
    var i=sheet.get(x,y);
    if(i!=0)px.setPixel(dx+x,dy+y,0xFF000000|palette.colors[i]);
   }
  }
  draw(art.SpriteArt.characterSheet("security_black",palette),0,0);
  draw(art.SpriteArt.characterSheet("security_white",palette),320,0);
  draw(art.SpriteArt.characterSheet("party_chair",palette),80,276);
  var rgba=haxe.io.Bytes.alloc(640*440*4);
  for(y in 0...440) for(x in 0...640) {
   var c=px.getPixel(x,y),p=(y*640+x)*4;
   rgba.set(p,(c>>16)&255);rgba.set(p+1,(c>>8)&255);rgba.set(p+2,c&255);rgba.set(p+3,255);
  }
  var encoded=haxe.crypto.Base64.encode(rgba);
  js.Syntax.code("require('sharp')(Buffer.from({0},'base64'),{raw:{width:640,height:440,channels:4}}).png().toFile('art-source/private-party/import-preview.png').then(()=>process.exit(0))",encoded);
 }
}
