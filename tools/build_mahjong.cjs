// SPDX-License-Identifier: AGPL-3.0-or-later
// Exact symbols/counts over generated enamel and botanical art. Requires sharp.
const fs = require('node:fs/promises');
const path = require('node:path');
const assert = require('node:assert/strict');
const sharp = require('sharp');
const root = path.resolve(__dirname, '../res/mahjong');
const W = 144, H = 192;
const red = '#9b2839', green = '#216044', navy = '#182b45';
const svg = body => Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}">${body}</svg>`);
const text = (s,x,y,size,color=navy,font='SimSun') => `<text x="${x}" y="${y}" text-anchor="middle" font-family="${font}" font-size="${size}" font-weight="bold" fill="${color}" stroke="${color}" stroke-width="1.2" paint-order="stroke">${s}</text>`;
function points(n) {
  if(n===1)return [[72,96]];
  if(n===2)return [[72,66],[72,130]];
  if(n===3)return [[42,58],[72,98],[102,138]];
  const four=[[42,58],[102,58],[42,138],[102,138]];
  if(n===4)return four;
  if(n===5)return [...four,[72,98]];
  if(n===6)return [42,102].flatMap(x=>[58,98,138].map(y=>[x,y]));
  if(n===7)return [[42,52],[72,52],[102,52],[42,100],[102,100],[42,140],[102,140]];
  if(n===8)return [42,102].flatMap(x=>[48,80,112,144].map(y=>[x,y]));
  return [42,72,102].flatMap(x=>[58,98,138].map(y=>[x,y]));
}
function dot(x,y,color,large=false) {
 const r=large?32:11;
 return `<circle cx="${x}" cy="${y}" r="${r}" fill="none" stroke="${color}" stroke-width="5"/><circle cx="${x}" cy="${y}" r="${r*.55}" fill="none" stroke="${color}" stroke-width="2"/><circle cx="${x}" cy="${y}" r="${large?6:3}" fill="${color}"/>`;
}
function bamboo(x,y,color) {
 return `<g transform="translate(${x} ${y})" stroke="${color}" stroke-linecap="round"><path d="M-3-12V12M3-12V12" stroke-width="4"/><path d="M-7-10H7M-7 0H7M-7 10H7" stroke-width="3"/></g>`;
}
async function main() {
 await fs.mkdir(path.join(root,'faces'),{recursive:true});
 const base=await sharp(path.join(root,'../../art-source/mahjong/blank.png')).trim().resize(W,H,{fit:'fill',kernel:'nearest'}).png().toBuffer();
 await fs.writeFile(path.join(root,'blank.png'),base);
 await sharp(path.join(root,'../../art-source/mahjong/back.png')).trim().resize(W,H,{fit:'fill',kernel:'nearest'}).png().toFile(path.join(root,'back.png'));
 const atlas=path.join(root,'../../art-source/mahjong/motifs.png'), meta=await sharp(atlas).metadata();
 const motifs=[];
 for(let i=0;i<9;i++){
  const x=Math.floor(i%3*meta.width/3), y=Math.floor(Math.floor(i/3)*meta.height/3);
  const cell=await sharp(atlas).extract({left:x,top:y,width:Math.floor(meta.width/3),height:Math.floor(meta.height/3)}).png().toBuffer();
  motifs.push(await sharp(cell).trim().resize(98,112,{fit:'contain',kernel:'nearest',background:'#00000000'}).png().toBuffer());
 }
 const manifest={width:W,height:H,displayWidth:36,displayHeight:48,back:'back.png',blank:'blank.png',tabletop:'../tabletops/mahjong.png',tiles:[],sets:{standard:[],withBonus:[]}};
 async function face(id,name,group,symbol,copies=4,motif=-1){
  const layers=motif>=0?[{input:motifs[motif],left:23,top:39}]:[];
  layers.push({input:svg(symbol),left:0,top:0});
  const file=`faces/${id}.png`;
  await sharp(base).composite(layers).png().toFile(path.join(root,file));
  manifest.tiles.push({id,name,group,file,copies});
  if(copies===4)manifest.sets.standard.push(...Array(4).fill(id));
  manifest.sets.withBonus.push(...Array(copies).fill(id));
 }
 for(const suit of ['dots','bamboo','characters'])for(let n=1;n<=9;n++){
  const ps=points(n); assert.equal(ps.length,n);
  let glyph='';
  if(suit==='characters')glyph=text('一二三四五六七八九'[n-1],72,87,49)+text('萬',72,145,53,red);
  else if(suit==='dots')glyph=ps.map(([x,y],i)=>dot(x,y,[green,navy,red][i%3],n===1)).join('');
  else if(n>1)glyph=ps.map(([x,y],i)=>bamboo(x,y,n===5&&i===4?red:green)).join('');
  glyph+=text(String(n),22,28,17,navy,'Georgia');
  await face(`${suit}-${n}`,`${n} ${suit}`,suit,glyph,4,suit==='bamboo'&&n===1?0:-1);
 }
 for(const [id,glyph,letter] of [['east','東','E'],['south','南','S'],['west','西','W'],['north','北','N']])
  await face(id,`${id} wind`,'winds',text(glyph,72,123, 70)+text(letter,22,28,16,navy,'Georgia'));
 await face('red','red dragon','dragons',text('中',72,123,72,red));
 await face('green','green dragon','dragons',text('發',72,123,70,green));
 await face('white','white dragon','dragons','<rect x="38" y="48" width="68" height="101" rx="4" fill="none" stroke="#182b45" stroke-width="5"/><rect x="46" y="56" width="52" height="85" rx="2" fill="none" stroke="#182b45" stroke-width="2"/>');
 const bonus=[['plum','梅'],['orchid','蘭'],['chrysanthemum','菊'],['bamboo-flower','竹'],['spring','春'],['summer','夏'],['autumn','秋'],['winter','冬']];
 for(let i=0;i<bonus.length;i++)await face(bonus[i][0],bonus[i][0],i<4?'flowers':'seasons',text(String(i%4+1),22,28,17,i<4?red:green,'Georgia')+text(bonus[i][1],120,29,19,i<4?red:green),1,i+1);
 assert.equal(manifest.tiles.length,42);assert.equal(manifest.sets.standard.length,136);assert.equal(manifest.sets.withBonus.length,144);
 assert.equal(new Set(manifest.tiles.map(t=>t.id)).size,42);
 const previews=[];
 for(let i=0;i<manifest.tiles.length;i++){
  const f=path.join(root,manifest.tiles[i].file),m=await sharp(f).metadata();assert.equal(m.width,W);assert.equal(m.height,H);assert(m.hasAlpha);
  previews.push({input:await sharp(f).resize(72,96,{kernel:'nearest'}).png().toBuffer(),left:16+(i%9)*84,top:16+Math.floor(i/9)*112});
 }
 await sharp({create:{width:788,height:576,channels:4,background:'#142523'}}).composite(previews).png().toFile(path.join(root,'preview.png'));
 await fs.writeFile(path.join(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
 console.log('Verified 42 unique Mahjong faces; 136 standard / 144 with bonus tiles; all 144x192 RGBA.');
}
main().catch(e=>{console.error(e);process.exit(1)});
