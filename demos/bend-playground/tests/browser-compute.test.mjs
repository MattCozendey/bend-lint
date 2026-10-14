import test from 'node:test';
import assert from 'node:assert/strict';
import { compute } from '../ui/src/lib/browser-compute.ts';
import Ray from '../demos/raytracer/ray.bend';
import Path from '../demos/raytracer/grid-path.bend';
import Life from '../demos/life/sparse.bend';
import Count from '../accelerated.bend';
import Replay from '../demos/cubes/replay.bend';
import Probability from '../demos/probability/simulation.bend';
import { decodePpm } from '../ui/src/lib/ppm.js';
const engines = {ray: Ray, path: Path, life: Life, collisions: Count, replay: Replay, probability: Probability};
const run = body => compute(body, async name => engines[name]);
test('browser rays preserve Bend pixel colors in downloadable PPM for every scene', async () => {
  for (const scene of ['mirrors', 'materials', 'weekend']) {
    const result = await run({demo:'raytracer',scene,width:8,height:5,bounces:3,samples:2,seed:42});
    const image = decodePpm(result.ppm);
    assert.equal(image.width,8);assert.equal(image.height,5);
    for(let y=0;y<5;y++)for(let x=0;x<8;x++){
      const p=scene==='mirrors'?Ray.pixel(x,y,8,5,3n):Path.pixel(x,y,8,5,3n,scene==='weekend',42,2,42);
      assert.deepEqual([...image.rgba.slice((y*8+x)*4,(y*8+x+1)*4)],[p>>>16&255,p>>>8&255,p&255,255]);
    }
  }
});
test('browser Life replay retains the initial frame and blinker period',async()=>{
  const {data}=await run({demo:'life',size:64,steps:4,seed:42,pattern:'blinker'});
  assert.equal(data.frames.length,5);assert.equal(data.encoding,'sparse-words');
  assert.notDeepEqual(data.frames[0],data.frames[1]);assert.deepEqual(data.frames[0],data.frames[2]);assert.deepEqual(data.frames[0],data.frames[4]);
});
test('browser collision replays recover known counts and physical-time motion',async()=>{
  for(const [digits,count] of [[1,'3'],[3,'314'],[10,'3141592653']]){
    const {data}=await run({demo:'cubes',digits});
    assert.equal(data.total,count);assert.equal(data.frames[0].count,0);assert.equal(data.frames.at(-1).count,Number(count));
    if(digits===10){assert.ok(data.motion.length>1000);assert.equal(data.motion.at(-1).count,Number(count));}
  }
});
test('browser estimators count every trial and limit only the displayed samples',async()=>{
  for(const method of ['montecarlo','buffon'])for(const samples of [1,257,10000]){
    const {name,data}=await run({demo:'probability',method,samples,seed:42});
    assert.equal(name,method);assert.equal(data.frames.at(-1).n,samples);
    const expected=Probability.count(8n,0,samples,method==='buffon',42);
    assert.equal(data.frames.at(-1).hits,expected.hits);
    assert.ok(data.frames.reduce((n,f)=>n+f.points.length/5,0)<=data.previewLimit);
  }
});
test('browser inputs reject invalid work instead of wrapping U32',async()=>{
  await assert.rejects(run({demo:'life',size:63,steps:2,seed:42,pattern:'random'}));
  await assert.rejects(run({demo:'probability',method:'montecarlo',samples:4294967296,seed:42}));
  await assert.rejects(run({demo:'cubes',digits:0}));
});
