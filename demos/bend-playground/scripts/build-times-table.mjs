import {existsSync,mkdirSync,statSync,writeFileSync,renameSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {setup,root} from './setup.mjs';

export async function buildTimesTable(){
  setup();
  const source=resolve(root,'demos/times-table/circle.bend'),target=resolve(root,'build/times-table-engine.js');
  const modified=Math.max(statSync(source).mtimeMs,statSync(resolve(root,'.tools/bend/bend2/main.ts')).mtimeMs);
  if(existsSync(target)&&statSync(target).mtimeMs>=modified)return target;
  const {load}=await import('../.tools/bend/bend2/main.ts');
  const result=await load(pathToFileURL(source).href,{},()=>{throw new Error('Expected a Bend module.');});
  mkdirSync(resolve(root,'build'),{recursive:true});
  const temporary=`${target}.${process.pid}.tmp`;
  writeFileSync(temporary,'// Generated from demos/times-table/circle.bend by Bend.\n'+result.source);
  renameSync(temporary,target);return target;
}
if(process.argv[1]&&pathToFileURL(resolve(process.argv[1])).href===import.meta.url)console.log(await buildTimesTable());
