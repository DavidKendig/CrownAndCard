// SPDX-License-Identifier: AGPL-3.0-or-later
// Export source masters at the game's 640x360 grid. Requires sharp.
const fs=require('node:fs/promises'),sharp=require('sharp'),path=require('node:path');
const root=path.resolve(__dirname,'..');
(async()=>{
 const prompts=JSON.parse(await fs.readFile(path.join(root,'art-source/tabletops/prompts.json'),'utf8'));
 await fs.mkdir(path.join(root,'res/tabletops'),{recursive:true});
 const previews=[];
 for(const [i,{name}]of prompts.entries()){
  const file=path.join(root,'res/tabletops',name+'.png');
  await sharp(path.join(root,'art-source/tabletops',name+'.png')).resize(640,360,{fit:'fill'}).png().toFile(file);
  const title=Buffer.from(`<svg width="320" height="24"><text x="8" y="17" fill="#f4dba5" font-size="14" font-family="Georgia">${name.toUpperCase()}</text></svg>`);
  previews.push({input:await sharp(file).resize(320,180).png().toBuffer(),left:(i%2)*332+8,top:Math.floor(i/2)*214+30});
  previews.push({input:title,left:(i%2)*332+8,top:Math.floor(i/2)*214+6});
 }
 await sharp({create:{width:672,height:856,channels:4,background:'#101524'}}).composite(previews).png().toFile(path.join(root,'art-source/tabletops/preview.png'));
 console.log('Verified and exported eight tabletop textures at 640x360.');
})().catch(e=>{console.error(e);process.exit(1)});
