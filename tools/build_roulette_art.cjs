// SPDX-License-Identifier: AGPL-3.0-or-later
const fs=require('node:fs/promises'),path=require('node:path'),sharp=require('sharp'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),values=[1,5,10,25,50,100,250];
async function main(){
 const out=path.join(root,'res/chips'),source=path.join(root,'art-source/roulette');
 await fs.mkdir(out,{recursive:true});
 // Refresh with: haxe -cp src -cp tools -main ExportRouletteArt --interp
 const layout=JSON.parse(await fs.readFile(path.join(source,'layout.json'),'utf8'));
 const cells=layout.spots.map(s=>s.small
  ? `<circle cx="${s.x+4}" cy="${s.y+4}" r="1.25" fill="#bda06c"/>`
  : `<rect x="${s.x+.5}" y="${s.y+.5}" width="${s.w}" height="${s.h}" fill="${s.color}" fill-opacity=".94" stroke="#bda06c"/><text x="${s.x+s.w/2}" y="${s.y+(s.number?12:(s.h+8)/2)}" text-anchor="middle" font-family="DejaVu Sans" font-size="10" fill="#efe6d2">${s.label}</text>`).join('');
 const step=2*Math.PI/37;
 const ring=layout.pockets.map((n,i)=>{
  const a=i*step-Math.PI/2,points=[];
  for(let j=0;j<5;j++){const t=a-step/2+step*j/4;points.push(`${120+Math.cos(t)*77},${120+Math.sin(t)*77}`);}
  for(let j=0;j<5;j++){const t=a+step/2-step*j/4;points.push(`${120+Math.cos(t)*54},${120+Math.sin(t)*54}`);}
  return `<polygon points="${points.join(' ')}" fill="${n===0?'#176e49':layout.reds.includes(n)?'#8c2636':'#141923'}" stroke="#bda06c" stroke-width=".6"/><text x="${120+Math.cos(a)*71}" y="${122+Math.sin(a)*71}" text-anchor="middle" font-family="DejaVu Sans" font-size="5.5" fill="#efe6d2">${n}</text>`;
 }).join('');
 const bowl=await sharp(path.join(root,'res/roulette/roulette-bowl.png')).resize(240,240).png().toBuffer();
 const hub=await sharp(path.join(root,'res/roulette/roulette-rotor.png')).resize(110,110).png().toBuffer();
 const wheelFull=await sharp(bowl).composite([{input:Buffer.from(`<svg width="240" height="240">${ring}</svg>`)},{input:hub,left:65,top:65}]).png().toBuffer();
 const wheel=await sharp(wheelFull).resize(156,156).png().toBuffer();
 const felt=await sharp(path.join(source,'mat.png')).resize(640,360,{fit:'fill'}).png().toBuffer();
 await sharp(felt).composite([{input:Buffer.from(`<svg width="640" height="360">${cells}</svg>`)},{input:wheel,left:12,top:91}]).png().toFile(path.join(root,'res/tabletops/roulette.png'));
 const atlas=path.join(source,'chips.png'),m=await sharp(atlas).metadata();
 const previews=[];
 for(let i=0;i<values.length;i++){
  const left=Math.floor(i*m.width/7),right=Math.floor((i+1)*m.width/7);
  const cell=await sharp(atlas).extract({left,top:0,width:right-left,height:m.height}).png().toBuffer();
  const chip=await sharp(cell).trim().resize(128,128,{fit:'contain',kernel:'nearest',background:'#00000000'}).png().toBuffer();
  const label=Buffer.from(`<svg width="128" height="128"><text x="64" y="77" text-anchor="middle" fill="#172132" font-family="Georgia" font-weight="bold" font-size="${values[i]>=100?32:40}">${values[i]}</text></svg>`);
  const file=path.join(out,values[i]+'.png');
  await sharp(chip).composite([{input:label}]).png().toFile(file);
  const meta=await sharp(file).metadata();assert.equal(meta.width,128);assert.equal(meta.height,128);assert(meta.hasAlpha);
  previews.push({input:file,left:8+i*136,top:8});
 }
 await sharp({create:{width:960,height:144,channels:4,background:'#13362e'}}).composite(previews).png().toFile(path.join(source,'chip-preview.png'));
 await fs.writeFile(path.join(out,'manifest.json'),JSON.stringify({currency:'Sovereigns',width:128,height:128,denominations:values.map(v=>({value:v,file:v+'.png'}))},null,2)+'\n');
 console.log('Exported complete roulette tabletop (betting layout and static wheel) and seven Sovereign chips.');
}
main().catch(e=>{console.error(e);process.exit(1)});
