import {existsSync,mkdirSync,statSync,writeFileSync,renameSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {setup,root} from './setup.mjs';
const modules={fourier:['demos/fourier/math.bend'],sorting:['demos/sorting/sort.bend','demos/shared/grid.bend','demos/probability/math.bend'],shakespeare:['demos/shakespeare/evolution.bend','demos/probability/math.bend'],polar:['demos/polar/curves.bend']};
export async function buildLabs(){
  setup();mkdirSync(resolve(root,'build'),{recursive:true});
  for(const [name,files] of Object.entries(modules)){
    const target=resolve(root,`build/${name}-engine.js`),source=resolve(root,files[0]);
    const modified=Math.max(...[...files,'.tools/bend/bend2/main.ts'].map(f=>statSync(resolve(root,f)).mtimeMs));
    if(existsSync(target)&&statSync(target).mtimeMs>=modified)continue;
    const {load}=await import('../.tools/bend/bend2/main.ts');
    const result=await load(pathToFileURL(source).href,{},()=>{throw new Error('Expected a Bend module.');});
    const temporary=`${target}.${process.pid}.tmp`;
    writeFileSync(temporary,`// Generated from ${files[0]} by Bend.\n`+result.source);renameSync(temporary,target);
  }
}
if(process.argv[1]&&pathToFileURL(resolve(process.argv[1])).href===import.meta.url){await buildLabs();console.log('Bend browser labs ready.');}
