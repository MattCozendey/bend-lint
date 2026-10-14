import { parseArgs } from 'node:util';
import { availableParallelism } from 'node:os';
import { mkdirSync,writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { config,execute,parseWords,output } from './demo-lib.mjs';

const {values}=parseArgs({options:{demo:{type:'string',default:'both'},width:{type:'string'},height:{type:'string'},bounces:{type:'string'},scene:{type:'string'},samples:{type:'string'},size:{type:'string'},steps:{type:'string'},seed:{type:'string'},pattern:{type:'string'}}});
const demos=values.demo==='both'?['raytracer','life']:[values.demo];
const results=[];
for(const demo of demos) {
  let reference;
  for(const backend of [{threads:1},{threads:Math.min(8,availableParallelism())},{gpu:true}]) {
    const c=config(demo,{...values,...backend});
    const result=execute(c,demo==='raytracer');
    const data=parseWords(result.lines[1]).slice(0,demo==='raytracer'?c.width*c.height:undefined);
    if(demo==='raytracer'&&data.length!==c.width*c.height)throw new Error('Incomplete ray-tracer benchmark output.');
    if(!reference) reference=data;
    if(data.length!==reference.length) throw new Error(`${demo}: result lengths differ`);
    let maxDifference=0,squaredDifference=0;
    for(let i=0;i<data.length;i++) {
      if(demo==='life' && data[i]!==reference[i]) throw new Error(`Life CPU/GPU mismatch at word ${i}`);
      if(demo==='raytracer') for(const shift of [0,8,16]){const difference=Math.abs(((data[i]>>>shift)&255)-((reference[i]>>>shift)&255));maxDifference=Math.max(maxDifference,difference);squaredDifference+=difference*difference;}
    }
    const rmsDifference=Math.sqrt(squaredDifference/(data.length*3)),stochastic=demo==='raytracer'&&c.scene!=='mirrors';
    // F32 differences can change individual stochastic paths at grazing hits.
    // Keep the original per-channel check for mirrors; compare path-traced
    // images by RMS error as well as reporting their worst channel difference.
    if((stochastic?rmsDifference:maxDifference)>2) throw new Error(`Ray CPU/GPU ${stochastic?'RMS':'maximum'} color difference exceeds 2/255.`);
    results.push({...result.metadata,maxChannelDifference:maxDifference,rmsChannelDifference:rmsDifference});
    console.log(`${demo.padEnd(10)} ${result.metadata.backend.padEnd(18)} compute ${String(result.metadata.kernelMs).padStart(6)} ms | process ${String(result.metadata.wallMs).padStart(6)} ms | ${demo==='life'?'exact match':`max RGB difference ${maxDifference}/255, RMS ${rmsDifference.toFixed(3)}/255`}`);
  }
}
mkdirSync(output,{recursive:true});
writeFileSync(join(output,'benchmarks.json'),JSON.stringify(results,null,2));
console.log('Saved output/benchmarks.json. Compute includes native Bend scheduling; process includes CUDA initialization and output. Single runs, not statistical benchmarks.');
