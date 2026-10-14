import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { resolve, relative, extname, sep } from 'node:path';
import { config } from './demo-lib.mjs';
import {buildRubik} from './build-rubik.mjs';
import {buildTimesTable} from './build-times-table.mjs';
import {buildLabs} from './build-labs.mjs';
await buildRubik();
await buildTimesTable();
await buildLabs();
import { root } from './setup.mjs';
import { gzip } from 'node:zlib';
import { promisify } from 'node:util';

const compress=promisify(gzip),compressed=new Map();

const outputs={'/output/raytracer.ppm':['output/raytracer.ppm','image/x-portable-pixmap'],'/output/raytracer.json':['output/raytracer.json','application/json'],
  '/output/life.json':['output/life.json','application/json'],'/output/cubes.json':['output/cubes.json','application/json'],'/output/benchmarks.json':['output/benchmarks.json','application/json'],
  '/output/montecarlo.json':['output/montecarlo.json','application/json'],
  '/output/buffon.json':['output/buffon.json','application/json'],
  '/times-table-engine.js':['build/times-table-engine.js','text/javascript'],
  '/rubik-engine.js':['build/rubik-engine.js','text/javascript']};
for(const name of ['fourier','sorting','shakespeare','polar'])outputs[`/${name}-engine.js`]=[`build/${name}-engine.js`,'text/javascript'];
const types={'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.woff2':'font/woff2','.json':'application/json'};
// The React UI (ui/) is built by Vite into build/ui; run `npm run build:ui` or `npm run playground`.
const ui=resolve(root,'build/ui');
function resolveFile(path){
  if(outputs[path])return outputs[path];
  const target=resolve(ui,'.'+path);
  if(target!==ui&&!target.startsWith(ui+sep))return null;
  if(path==='/'||!extname(path))return ['build/ui/index.html','text/html'];
  return [relative(root,target),types[extname(path)]||'application/octet-stream'];
}
let job=null;
createServer(async(req,res)=>{
  const path=new URL(req.url,'http://localhost').pathname;
  if(req.method==='POST' && path==='/api/cancel') {
    if(job){
      job.cancelled=true;
      // The launcher synchronously runs Bend (or its compiler); stop that entire
      // process group so cancelling actually releases the CPU/GPU work.
      try{process.kill(-job.child.pid,'SIGKILL');}
      catch(e){if(e.code!=='ESRCH'){res.writeHead(500).end(e.message);return;}}
    }
    res.writeHead(200).end('Cancellation requested.');return;
  }
  if(req.method==='POST' && path==='/api/run') {
    if(job) {res.writeHead(409).end('A Bend job is already running. Cancel it before starting another.');return;}
    try {
      let text='';for await(const chunk of req) {text+=chunk;if(text.length>8192) throw new Error('Request too large.');}
      const body=JSON.parse(text),c=config(body.demo,body);
      const args=['scripts/demo.mjs',c.demo];
      if(c.gpu) args.push('--gpu'); else args.push('--threads',String(c.threads));
      for(const k of c.demo==='raytracer'?['width','height','bounces','scene','samples','seed']:c.demo==='cubes'?['digits']:c.demo==='probability'?['method','samples','seed']:['size','steps','seed','pattern']) args.push(`--${k}`,String(c[k]));
      if(job) {res.writeHead(409).end('A Bend job is already running. Cancel it before starting another.');return;}
      const child=spawn(process.execPath,args,{cwd:root,detached:true,stdio:['ignore','pipe','pipe']});
      const current={child,cancelled:false};job=current;
      let log='';child.stdout.on('data',c=>{log+=c;process.stdout.write(c);});child.stderr.on('data',c=>{log+=c;process.stderr.write(c);});
      child.on('error',e=>{if(job===current)job=null;if(!res.writableEnded)res.writeHead(500).end(e.message);});
      child.on('close',code=>{if(job===current)job=null;if(!res.writableEnded)res.writeHead(current.cancelled?409:code===0?200:500,{'Content-Type':'text/plain'}).end(current.cancelled?'Computation cancelled. Change settings and run again.':log);});
    } catch(e) {res.writeHead(400).end(e.message);}
    return;
  }
  const file=req.method==='GET'?resolveFile(path):null;
  if(!file) {res.writeHead(404).end('Not found');return;}
  try {
    const filename=resolve(root,file[0]),info=await stat(filename),etag=`W/"${info.size}-${info.mtimeMs}"`;
    const headers={'Content-Type':file[1],'Cache-Control':path.startsWith('/assets/')?'public, max-age=31536000, immutable':'no-cache',ETag:etag,Vary:'Accept-Encoding'};
    if(req.headers['if-none-match']===etag){res.writeHead(304,headers).end();return;}
    const acceptsGzip=/(?:^|,)\s*gzip\s*(?:;\s*q=(?!0(?:\.0*)?(?:\s*,|\s*$))[\d.]+)?\s*(?:,|$)/i.test(req.headers['accept-encoding']||'');
    let data;
    if(['application/json','text/javascript','text/css','text/html','image/x-portable-pixmap'].includes(file[1])&&acceptsGzip){
      let cached=compressed.get(path);
      if(cached?.etag!==etag){cached={etag,data:compress(await readFile(filename))};compressed.set(path,cached);}
      data=await cached.data;headers['Content-Encoding']='gzip';
    }else data=await readFile(filename);
    res.writeHead(200,{...headers,'Content-Length':data.length}).end(data);
  }
  catch {res.writeHead(404).end(outputs[path]?'No output yet. Generate this demo first.':'UI not built. Run `npm run build:ui` first.');}
}).listen(Number(process.env.PORT||3000),'127.0.0.1',()=>console.log(`Bend playground: http://localhost:${process.env.PORT||3000}`));
