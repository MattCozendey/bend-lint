import test from 'node:test';
import assert from 'node:assert/strict';
import M from '../demos/probability/math.bend';
import S from '../demos/probability/simulation.bend';
import T from '../demos/times-table/circle.bend';
import {config,parseProbability} from '../scripts/demo-lib.mjs';

const near=(a,b,tolerance=1e-5)=>assert.ok(Math.abs(a-b)<tolerance,`${a} != ${b}`);

test('circle boundary and needle crossings follow the geometric predicates',()=>{
  for(const [x,y,hit] of [[0,0,1],[1,0,1],[0,-1,1],[.7,.7,1],[1,1,0],[1.01,0,0]])assert.equal(M.circle_hit(x,y),hit);
  for(const [x,dx,hit] of [[.5,.9,0],[.2,.8,1],[.8,.8,1],[1.5,-.9,0],[2,0,0]])assert.equal(M.needle_hit(x,dx),hit);
  near(M.estimate(false,100,79),3.16);near(M.estimate(true,100,64),3.125);
});

test('seeded points are reproducible and needle directions are unit and isotropic',()=>{
  let sumX=0,sumY=0,xx=0,hits=0;
  for(let i=0;i<20000;i++){
    const p=M.sample(true,i,42),q=M.sample(false,i,42);
    assert.equal(p.valid,1);assert.ok(p.x>=0&&p.x<8&&p.y>=0&&p.y<8);near(p.dx*p.dx+p.dy*p.dy,1,4e-7);
    assert.equal(p.hit,Number(Math.floor(Math.fround(p.x-Math.fround(p.dx*.5)))!==Math.floor(Math.fround(p.x+Math.fround(p.dx*.5)))));
    assert.ok(q.x>=-1&&q.x<1&&q.y>=-1&&q.y<1);
    assert.equal(q.hit,Number(Math.fround(Math.fround(q.x*q.x)+Math.fround(q.y*q.y))<=1));
    sumX+=p.dx;sumY+=p.dy;xx+=p.dx*p.dx;hits+=p.hit;
  }
  assert.ok(Math.abs(sumX/20000)<.02);assert.ok(Math.abs(sumY/20000)<.02);near(xx/20000,.5,.015);near(2*20000/hits,Math.PI,.05);
  assert.deepEqual(M.sample(true,123,42),M.sample(true,123,42));assert.notDeepEqual(M.sample(true,123,42),M.sample(true,123,43));
  assert.equal(M.orientation(0n,false,1,1,0,0,42).valid,0);
});

test('parallel counts and summary batches cover every sample exactly once',()=>{
  for(const needle of [false,true])for(const n of [1,7,255,256,257,4099]){
    let expected=0;for(let i=0;i<n;i++)expected+=M.sample(needle,i,7).hit;
    const serial=S.count(0n,0,n,needle,7),parallel=S.count(4n,0,n,needle,7);
    assert.deepEqual(parallel,serial);assert.equal(parallel.hits,expected);assert.equal(parallel.failed,0);
    const tree=S.run(8n,0,n,2n,needle,7),c=config('probability',{method:needle?'buffon':'montecarlo',samples:n,seed:7});
    const result=parseProbability(c,{metadata:c,lines:['PROBABILITY 0',...S.text(tree,0,0,needle).trim().split('\n')]});
    assert.equal(result.frames.at(-1).n,n);assert.equal(result.frames.at(-1).hits,expected);
    let prev=0,visible=0;
    for(const f of result.frames){
      assert.ok(f.n>prev);assert.ok(f.points.length/5<=f.n-prev);
      for(let k=0;k<f.points.length;k+=5){const p=M.sample(needle,prev+k/5,7);const actual=f.points.slice(k,k+5);[p.x,p.y,p.dx,p.dy,p.hit].forEach((v,j)=>near(actual[j],v,1e-6));}
      visible+=f.points.length/5;prev=f.n;
    }
    assert.ok(visible<=2048);
  }
});

test('large counts are runtime inputs and summaries reject partial or invalid output',()=>{
  for(const samples of [1,100000000,0xffffffff])assert.equal(config('probability',{samples}).samples,samples);
  for(const samples of [0,-1,1.2,2**32])assert.throws(()=>config('probability',{samples}));
  assert.throws(()=>config('probability',{method:'bad'}));
  assert.throws(()=>parseProbability(config('probability'),{metadata:{},lines:['PROBABILITY 1']}));
  assert.throws(()=>parseProbability(config('probability'),{metadata:{},lines:['PROBABILITY 0','1 1 4']}));
});

test('Bend times-table endpoints lie on the circle and obey modular multiplication',()=>{
  for(const multiplier of [0,1,2,3,17.25,199.5,200])for(let i=0;i<512;i++){
    const c=T.chord(i,512,multiplier),theta=2*Math.PI*((i*multiplier)%512)/512;
    near(c.x*c.x+c.y*c.y,1);near(c.u*c.u+c.v*c.v,1);near(c.u,Math.cos(theta));near(c.v,Math.sin(theta));
    if(multiplier===1){near(c.x,c.u);near(c.y,c.v);}
    if(multiplier===0){near(c.u,1);near(c.v,0);}
  }
  const c=T.chord(128,512,2);near(c.x,0);near(c.y,1);near(c.u,-1);near(c.v,0);
});
