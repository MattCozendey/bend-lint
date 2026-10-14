import { existsSync, mkdirSync, mkdtempSync, rmSync, statSync, readdirSync, writeFileSync, renameSync } from 'node:fs';
import { execFileSync, spawnSync } from 'node:child_process';
import { resolve, join } from 'node:path';
import { setup, root } from './setup.mjs';

export const output = resolve(root, 'output');
function writeOutput(name,data){
  // Publish only complete artifacts, including when a viewer job is cancelled.
  const target=join(output,name),temporary=`${target}.${process.pid}.tmp`;
  writeFileSync(temporary,data);renameSync(temporary,target);
}
export function runtimeEnv() {
  const local = resolve(root, '.tools/cuda');
  const cuda = process.env.CUDA_HOME || (existsSync(`${local}/include/nvrtc.h`) ? local : '/usr/local/cuda');
  return {...process.env, CUDA_HOME:cuda, LD_LIBRARY_PATH:`${cuda}/lib64:${cuda}/lib:${process.env.LD_LIBRARY_PATH || ''}`};
}
function newest(path) {
  return Math.max(statSync(path).mtimeMs, ...readdirSync(path,{withFileTypes:true}).map(e=> e.isDirectory() ? newest(join(path,e.name)) : statSync(join(path,e.name)).mtimeMs));
}
export function buildDemo(demo, gpu) {
  setup();
  const env=runtimeEnv();
  if(gpu && !existsSync(`${env.CUDA_HOME}/include/nvrtc.h`)) throw new Error('CUDA NVRTC is missing. Run npm run setup:gpu first.');
  const binary=resolve(root,`build/${demo}-${gpu?'gpu':'cpu'}`);
  mkdirSync(resolve(root,'build'),{recursive:true});
  const modified=Math.max(newest(resolve(root,`demos/${demo}`)),newest(resolve(root,'demos/shared')), ...(demo==='cubes'?['accelerated.bend','precise.bend'].map(f=>statSync(resolve(root,f)).mtimeMs):[]));
  if(!existsSync(binary) || statSync(binary).mtimeMs<modified || (gpu && !existsSync(`${binary}.gpu`))) {
    console.log(`Building ${demo} for ${gpu?'CUDA':'CPU'}…`);
    // A deliberately absent CUDA_HOME prevents a CPU-only build from creating a CUDA kernel.
    const buildEnv=gpu?env:{...env,CUDA_HOME:resolve(root,'.tools/no-cuda')};
    // A cancelled compiler must not leave a partial binary in the build cache.
    const staging=mkdtempSync(resolve(root,`build/.${demo}-`)),candidate=join(staging,'program');
    try{
      execFileSync(process.execPath,['--stack-size=16000','.tools/bend/bend2/main.ts',`demos/${demo}/main.bend`,'-o',candidate],{cwd:root,env:buildEnv,stdio:'inherit'});
      if(gpu&&!existsSync(`${candidate}.gpu`)) throw new Error('No CUDA kernel was produced. Check your NVIDIA driver.');
      if(gpu)renameSync(`${candidate}.gpu`,`${binary}.gpu`);
      renameSync(candidate,binary);
    }finally{rmSync(staging,{recursive:true,force:true});}
  }
  return binary;
}

export function integer(value, name, allowZero=false) {
  if(!/^\d+$/.test(String(value)) || !Number.isSafeInteger(Number(value)) || Number(value)<(allowZero?0:1) || Number(value)>0xffffffff) throw new Error(`${name} must be ${allowZero?'a nonnegative':'a positive'} U32 integer.`);
  return Number(value);
}
export function config(demo, opts={}) {
  if(!['raytracer','life','cubes','probability'].includes(demo)) throw new Error('Choose raytracer, life, cubes, or probability.');
  const gpu=opts.gpu===true;
  const threads=integer(opts.threads??1,'threads');
  if(demo==='probability') {
    const method=opts.method??'montecarlo';
    if(!['montecarlo','buffon'].includes(method))throw new Error('Choose montecarlo or buffon.');
    const samples=integer(opts.samples??1000000,'samples'),seed=integer(opts.seed??42,'seed',true);
    const inner=Math.max(0,Math.ceil(Math.log2(Math.ceil(samples/256)/128)));
    return {demo,gpu,threads,method,samples,seed,env:{PI_SAMPLES:String(samples),PI_SEED:String(seed),PI_NEEDLE:method==='buffon'?'1':'0',TREE_DEPTH:String(inner)}};
  }
  if(demo==='cubes') {
    const digits=integer(opts.digits??3,'digits');
    return {demo,gpu,threads,digits,env:{PI_DIGITS:String(digits)}};
  }
  if(demo==='raytracer') {
    const scene=opts.scene??'mirrors',kind={mirrors:0,materials:1,weekend:2}[scene];
    if(!Number.isInteger(kind))throw new Error('Ray scene must be mirrors, materials, or weekend.');
    const width=integer(opts.width??512,'width'),height=integer(opts.height??320,'height'), bounces=integer(opts.bounces??(kind?12:3),'bounces',true);
    const samples=kind?integer(opts.samples??16,'samples'):4,seed=integer(opts.seed??42,'seed',true);
    if(width*height>0x40000000) throw new Error('The pixel tree would overflow its U32 indices.');
    return {demo,gpu,threads,width,height,bounces,scene,samples,seed,env:{RAY_WIDTH:String(width),RAY_HEIGHT:String(height),RAY_BOUNCES:String(bounces),RAY_SCENE:String(kind),RAY_SAMPLES:String(samples),RAY_SEED:String(seed),TREE_DEPTH:String(Math.ceil(Math.log2(width*height)))}};
  }
  const size=integer(opts.size??128,'size'), steps=integer(opts.steps??120,'steps',true),seed=integer(opts.seed??42,'seed',true);
  if(size<32 || (size & (size-1)) || size*size/32>0x40000000) throw new Error('Life size must be a power of two, at least 32, with word indices that fit U32.');
  const pattern=opts.pattern??'random';
  const kind={random:0,glider:1,blinker:2}[pattern];
  if(kind===undefined) throw new Error('Pattern must be random, glider, or blinker.');
  return {demo,gpu,threads,size,steps,seed,pattern,env:{LIFE_SIZE:String(size),LIFE_STEPS:String(steps),LIFE_SEED:String(seed),LIFE_PATTERN:String(kind),TREE_DEPTH:String(Math.log2(size*size/32))}};
}

export function execute(c, frames=true) {
  const binary=buildDemo(c.demo,c.gpu);
  const start=performance.now();
  const r=spawnSync(binary,c.gpu?['--gpu','1GB']:['--gpu','off','--threads',String(c.threads)],{
    cwd:root,env:{...runtimeEnv(),...c.env,DUMP:frames?'1':'0'},encoding:'utf8',maxBuffer:512*1024*1024,
  });
  const wallMs=performance.now()-start;
  if(r.error) throw r.error;
  if(r.status!==0) throw new Error(r.stderr||`Bend exited with ${r.status}`);
  const kernelMs=Number(r.stderr.match(/COMPUTE_MS (\d+)/)?.[1]);
  if(!Number.isFinite(kernelMs)) throw new Error('Bend did not report its compute time.');
  const lines=r.stdout.trim().split('\n');
  const metadata={...c,env:undefined,backend:c.gpu?'NVIDIA CUDA':`CPU · ${c.threads} thread${c.threads===1?'':'s'}`,kernelMs,wallMs:Math.round(wallMs),createdAt:new Date().toISOString()};
  return {metadata,lines};
}

export function parseWords(line) { return line.trim().split(/\s+/).filter(Boolean).map(Number); }

export function parseLife(c,result){
  const sparse=result.lines[0].startsWith('LIFE_SPARSE '),words=c.size*c.size/32;
  const frames=result.lines.slice(1).map(line=>{
    if(sparse&&!line.startsWith('S'))throw new Error('Missing sparse Life frame.');
    const values=parseWords(sparse?line.slice(1):line);
    if(sparse){
      if(values.length%2)throw new Error('Incomplete sparse Life frame.');
      for(let i=0;i<values.length;i+=2)if(!Number.isInteger(values[i])||values[i]<0||values[i]>=words||(i&&values[i]<=values[i-2])||!Number.isInteger(values[i+1])||values[i+1]<=0||values[i+1]>0xffffffff)throw new Error('Invalid sparse Life word.');
    }else if(values.length!==words)throw new Error('Incomplete Life replay.');
    return values;
  });
  if(frames.length!==c.steps+1)throw new Error('Incomplete Life replay.');
  return {...result.metadata,encoding:sparse?'sparse-words':'dense-words',frames};
}

export function parseCubes(result) {
  const total=result.lines[0].split(' ')[2];
  if(!/^\d+$/.test(total) || !Number.isSafeInteger(Number(total))) throw new Error('Invalid collision count.');
  const marker=result.lines.indexOf('MOTION');
  const parse=line=>{
    const values=parseWords(line);
    if(values.length!==8||!values.every(Number.isFinite)) throw new Error('Non-finite collision state; this request exceeds the current numerical precision.');
    const [count,x,y,v,w,time,u,wall]=values;
    return {count,x,y,v,w,time,u,wall:wall===1};
  };
  const frames=result.lines.slice(1,marker<0?undefined:marker).map(parse);
  const motion=marker<0?[]:result.lines.slice(marker+1).map(parse);
  if(frames[0]?.count!==0||frames.at(-1)?.count!==Number(total)||frames.some((f,i)=>!Number.isSafeInteger(f.count)||(i>0&&f.count<=frames[i-1].count))) throw new Error('Incomplete collision replay.');
  if(motion.length&&(motion[0].count!==0||motion[0].time!==0||motion.at(-1).count!==Number(total)||motion.some((f,i)=>!Number.isSafeInteger(f.count)||f.x < -0.0001||f.y<f.x-0.0001||(i>0&&(f.time<=motion[i-1].time||f.count<motion[i-1].count)))))throw new Error('Invalid physical-time replay.');
  return {...result.metadata,total,pi:total.length===1?total:`${total[0]}.${total.slice(1)}`,sampled:frames.length!==Number(total)+1,frames,motion};
}
export function ppm(width,height,pixels) {
  const count=width*height;
  if(!Number.isSafeInteger(width)||!Number.isSafeInteger(height)||width<1||height<1||!Number.isSafeInteger(count)||pixels.length<count)throw new Error('Incomplete ray-tracer output.');
  const lines=[`P3\n${width} ${height}\n255`];
  // The balanced Bend tree can contain padded leaves after the final pixel.
  for(let i=0;i<count;i++){
    const p=pixels[i];
    if(!Number.isInteger(p)||p<0||p>0xffffff)throw new Error('Invalid Bend RGB pixel.');
    lines.push(`${(p>>>16)&255} ${(p>>>8)&255} ${p&255}`);
  }
  return lines.join('\n')+'\n';
}
export function save(c,result) {
  mkdirSync(output,{recursive:true});
  if(c.demo==='probability') {
    writeOutput(`${c.method}.json`,JSON.stringify(parseProbability(c,result)));
  } else if(c.demo==='raytracer') {
    const pixels=parseWords(result.lines[1]);
    writeOutput('raytracer.ppm',ppm(c.width,c.height,pixels));
    writeOutput('raytracer.json',JSON.stringify({...result.metadata,encoding:'ppm-p3'}));
  } else if(c.demo==='cubes') {
    const replay=parseCubes(result);
    writeOutput('cubes.json',JSON.stringify(replay));
    console.log(`${replay.total} collisions -> pi = ${replay.pi}; ${replay.frames.length} ${replay.sampled?'sampled':'consecutive'} states.`);
  } else {
    writeOutput('life.json',JSON.stringify(parseLife(c,result)));
  }
  console.log(`${c.demo}: ${result.metadata.backend}; compute ${result.metadata.kernelMs} ms, process ${result.metadata.wallMs} ms.`);
  console.log(`Saved output/${c.demo==='raytracer'?'raytracer.ppm':`${c.method??c.demo}.json`}. View the experiments with npm run playground.`);
}

export function parseProbability(c,result) {
  if(result.lines[0]!=='PROBABILITY 0')throw new Error('Needle orientation sampling exhausted its retry budget; try another seed.');
  let previous=0,previousHits=0;
  const frames=result.lines.slice(1).filter(Boolean).map(line=>{
    const [n,hits,estimate,...points]=parseWords(line);
    if(!Number.isInteger(n)||n<previous||n>c.samples||!Number.isInteger(hits)||hits<previousHits||hits>n||hits-previousHits>n-previous||(points.length%5)||points.length>40||!points.every(Number.isFinite))throw new Error('Invalid probability replay.');
    if(n>0&&(c.method==='montecarlo'||hits>0)&&!Number.isFinite(estimate))throw new Error('Invalid pi estimate.');
    previous=n;previousHits=hits;
    return {n,hits,estimate:Number.isFinite(estimate)?estimate:null,points};
  });
  if(frames.length!==256||previous!==c.samples)throw new Error('Incomplete probability replay.');
  return {...result.metadata,frames:frames.filter((f,i)=>f.n>0&&(i===0||f.n!==frames[i-1].n)),previewLimit:c.method==='buffon'?512:2048};
}
