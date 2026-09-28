// SPDX-License-Identifier: AGPL-3.0-or-later
// Deterministic card layout and PNG export. Requires Node.js and sharp.
const fs = require('node:fs/promises');
const path = require('node:path');
const assert = require('node:assert/strict');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..', 'res', 'cards');
const W = 200, H = 280;
const ranks = '23456789TJQKA';
const suits = 'cdhs'; // Must match cards.Card and cards.Suit.
const ink = {c:'#14202c', d:'#972637', h:'#972637', s:'#14202c'};
const shapes = {
  d:'<path d="M0 -15L11 0 0 15 -11 0Z"/>',
  h:'<path d="M0 14C-3 10-14 2-14-6C-14-17-3-18 0-9C3-18 14-17 14-6C14 2 3 10 0 14Z"/>',
  s:'<path d="M0-16C-3-11-14-4-14 3C-14 13-4 14 0 6C4 14 14 13 14 3C14-4 3-11 0-16Z"/><path d="M-3 4C-2 10-3 13-7 16H7C3 13 2 10 3 4Z"/>',
  c:'<circle cx="0" cy="-8" r="8"/><circle cx="-8" cy="3" r="8"/><circle cx="8" cy="3" r="8"/><path d="M-3 2C-2 10-3 13-7 16H7C3 13 2 10 3 2Z"/>'
};
function pip(s,x,y,scale=1,flip=false) {
  return `<g fill="${ink[s]}" transform="translate(${x} ${y}) rotate(${flip?180:0}) scale(${scale})">${shapes[s]}</g>`;
}
function points(rank) {
  const outer = [[62,68],[138,68],[62,212],[138,212]];
  const six = [...outer,[62,140],[138,140]];
  const eight = [62,138].flatMap(x=>[68,116,164,212].map(y=>[x,y]));
  switch(rank) {
    case 14:return [[100,140]];
    case 2:return [[100,68],[100,212]];
    case 3:return [[100,68],[100,140],[100,212]];
    case 4:return outer;
    case 5:return [...outer,[100,140]];
    case 6:return six;
    case 7:return [...six,[100,104]];
    case 8:return [...six,[100,104],[100,176]];
    case 9:return [...eight,[100,140]];
    case 10:return [...eight,[100,92],[100,188]];
    default:return [];
  }
}
function svg(rank,s,court) {
  const label=rank===10?'10':ranks[rank-2];
  const corner=`<text x="13" y="32" fill="${ink[s]}" font-family="Georgia,serif" font-size="25" font-weight="bold">${label}</text>${pip(s,23,49,.47)}`;
  const art=court ? `<rect x="47" y="34" width="106" height="212" rx="2" fill="#172132" stroke="#af8846" stroke-width="2"/>
    <image x="49" y="36" width="102" height="103" href="${court}"/>
    <g transform="translate(200 280) rotate(180)"><image x="49" y="36" width="102" height="103" href="${court}"/></g>
    <path d="M48 140H152" stroke="#c8a35e" stroke-width="3"/>`
    : points(rank).map(([x,y])=>pip(s,x,y,rank===14?2.25:.9,y>140)).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
    <rect x="1" y="1" width="198" height="278" rx="9" fill="#f2e8d2" stroke="#bda16c" stroke-width="2"/>
    <rect x="6" y="6" width="188" height="268" rx="6" fill="none" stroke="#d3bd90"/>
    ${corner}<g transform="translate(200 280) rotate(180)">${corner}</g>${art}
  </svg>`;
}
async function main() {
  await fs.mkdir(path.join(root,'faces'),{recursive:true});
  const meta=await sharp(path.join(root,'source/courts.png')).metadata();
  // Source has four aligned rows with measured transparent separators.
  const cuts=meta.height===1448?[0,356,710,1064,1448]:[0,1,2,3,4].map(n=>Math.floor(n*meta.height/4));
  const courts={};
  for (const [row,s] of [...'shcd'].entries()) for(let col=0;col<3;col++) {
    const left=Math.floor(col*meta.width/3), right=Math.floor((col+1)*meta.width/3);
    const png=await sharp(path.join(root,'source/courts.png')).extract({left,top:cuts[row],width:right-left,height:cuts[row+1]-cuts[row]})
      .resize(102,103,{fit:'contain',background:{r:0,g:0,b:0,alpha:0},kernel:'nearest'}).png().toBuffer();
    courts[`${col+11}${s}`]='data:image/png;base64,'+png.toString('base64');
  }
  const manifest={width:W,height:H,aspect:'5:7',back:'back.png',cards:[]};
  const previews=[];
  for(let rank=2;rank<=14;rank++) for(const s of suits) {
    const code=ranks[rank-2]+s, pips=points(rank);
    if(rank<=10 || rank===14) assert.equal(pips.length,rank===14?1:rank);
    const file=`faces/${code}.png`;
    await sharp(Buffer.from(svg(rank,s,courts[`${rank}${s}`]))).png().toFile(path.join(root,file));
    const data=await sharp(path.join(root,file)).metadata(); assert.equal(data.width*7,data.height*5);
    manifest.cards.push({index:(rank-2)*4+suits.indexOf(s),code,rank,suit:s,file,pips:pips.length});
    previews.push({input:await sharp(path.join(root,file)).resize(100,140,{kernel:'nearest'}).toBuffer(),left:(rank-2)*106+12,top:suits.indexOf(s)*148+12});
  }
  assert.equal(new Set(manifest.cards.map(c=>c.code)).size,52);
  await sharp(path.join(root,'source/back-master.png')).resize(W,H,{fit:'fill',kernel:'nearest'}).png().toFile(path.join(root,'back.png'));
  await sharp({create:{width:1390,height:604,channels:4,background:'#101524'}}).composite(previews).png().toFile(path.join(root,'deck-preview.png'));
  await fs.writeFile(path.join(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
  console.log('52 unique 200x280 card faces + back: ranks, suit mapping, numeric pip counts and 5:7 dimensions PASS');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
