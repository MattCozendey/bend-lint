import test from 'node:test';
import assert from 'node:assert/strict';
import {stateAt,duration,nextTime} from '../ui/src/lib/cube-clock.js';
const data={total:'3',frames:[
  {time:0,count:0,x:1,y:3,v:0,w:-1},
  {time:2,count:1,x:1,y:1,v:-1,w:0},
  {time:3,count:2,x:0,y:1,v:1,w:0},
  {time:4,count:3,x:1,y:1,v:0,w:1},
]};
test('clock honors unequal travel times and advances count only on contact',()=>{
  assert.equal(stateAt(data,1).count,0);assert.equal(stateAt(data,1).y,2);
  assert.equal(stateAt(data,1.999).count,0);assert.equal(stateAt(data,2).count,1);
  assert.equal(stateAt(data,2.5).x,.5);assert.equal(stateAt(data,2.5).y,1);
  assert.equal(stateAt(data,3).count,2);assert.equal(stateAt(data,3.5).x,.5);
  assert.equal(nextTime(data,0),2);assert.equal(nextTime(data,2),3);
});
test('blocks keep moving after final impact instead of freezing',()=>{
  assert.equal(duration(data),6);assert.equal(stateAt(data,5).count,3);
  assert.equal(stateAt(data,5).x,1);assert.equal(stateAt(data,5).y,2);
});
test('large-count playback interpolates time samples without long holds',()=>{
  const sampled={...data,motion:[{time:0,count:0,x:1,y:3,v:0,w:-1},{time:1,count:10,x:.25,y:2,v:2,w:-.9}]};
  const half=stateAt(sampled,.5);assert.equal(half.x,.625);assert.equal(half.y,2.5);
  assert.equal(half.sampled,true);assert.equal(duration(sampled),1);
});
