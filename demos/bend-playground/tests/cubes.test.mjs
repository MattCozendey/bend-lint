import test from 'node:test';
import assert from 'node:assert/strict';
import Replay from '../demos/cubes/replay.bend';
import A from '../accelerated.bend';
import D from '../precise.bend';
import Physics from '../physics.bend';

function frames(r) {
  if(r.$==='Empty')return [];
  if(r.$==='Frame')return [r.state];
  return [...frames(r.left),...frames(r.right)];
}
for(let places=0;places<=3;places++)test(`cube snapshots match event-by-event physics for ${places+1} digits`,()=>{
  const t=D.tenth(BigInt(places)),base=A.rotation(t);
  let reference=Physics.initial(100**places);
  while(!Physics.finished(reference)) {
    reference=Physics.next(reference);
    const s=Replay.snapshot(BigInt(reference.count),base,t);
    // The old F32 solver accumulates drift (especially the last position).
    for(const k of ['x','y','v','w','time']) assert.ok(Math.abs(s[k]-reference[k])<=0.0005*Math.max(1,Math.abs(reference[k])),`${reference.count}: ${k} ${s[k]} vs ${reference[k]}`);
    assert.equal(s.wall,reference.wall);
    assert.ok(Math.abs(s.u*s.u+s.w*s.w-1)<0.000001);
  }
});
test('four-digit final position agrees with a double-precision physical simulation',()=>{
  let x=1,y=3,v=0,w=-1,time=0,count=0;const mass=1e6;
  while(v<0||v>w) {
    const tw=v<0?-x/v:Infinity,tb=v>w?(y-x)/(v-w):Infinity,dt=Math.min(tw,tb);
    x+=v*dt;y+=w*dt;time+=dt;
    if(tw<tb){x=0;v=-v;}else{y=x;const nv=((1-mass)*v+2*mass*w)/(1+mass);w=(2*v+(mass-1)*w)/(1+mass);v=nv;}
    count++;
  }
  const t=D.tenth(3n),s=Replay.snapshot(BigInt(count),A.rotation(t),t);
  for(const [k,value] of Object.entries({x,y,v,w,time}))assert.ok(Math.abs(s[k]-value)<0.000001,`${k}: ${s[k]} vs ${value}`);
});
test('small replay includes every collision, including the final wall impact',()=>{
  const r=frames(Replay.make(2n,314n));
  assert.equal(r.length,315);
  r.forEach((s,i)=>assert.equal(s.count,BigInt(i)));
  assert.equal(r.at(-1).wall,true);
});
test('large replay samples actual block/wall pairs and preserves exact endpoints',()=>{
  const total=A.count(9n),r=frames(Replay.make(9n,total));
  assert.ok(r.length<=2049);
  assert.equal(r[0].count,0n);
  assert.equal(r[1].count,1n);
  assert.equal(r.at(-1).count,3141592653n);
  assert.equal(r.at(-1).wall,false);
  r.forEach((s,i)=>{
    assert.ok([s.x,s.y,s.v,s.w,s.time,s.u].every(Number.isFinite));
    assert.ok(s.x>=0&&s.y>=s.x-0.000001);
    assert.ok(Math.abs(s.u*s.u+s.w*s.w-1)<0.000001);
    if(i>0) {assert.ok(s.count>r[i-1].count);assert.ok(s.time>=r[i-1].time-0.000001);}
    if(i>0&&s.wall)assert.equal(s.count,r[i-1].count+1n);
  });
});

// Independent double-precision event solver, queried by physical time.
function referenceAt(mass,target){
  let x=1,y=3,v=0,w=-1,time=0,count=0;
  while(v<0||v>w){
    const tw=v<0?-x/v:Infinity,tb=v>w?(y-x)/(v-w):Infinity,dt=Math.min(tw,tb);
    if(time+dt>target)break;
    x+=v*dt;y+=w*dt;time+=dt;
    if(tw<tb){x=0;v=-v;}else{y=x;const nv=((1-mass)*v+2*mass*w)/(1+mass);w=(2*v+(mass-1)*w)/(1+mass);v=nv;}
    count++;
  }
  return {x:x+v*(target-time),y:y+w*(target-time),v,w,count};
}
for(let places=0;places<=3;places++)test(`physical-time Bend states match independent dynamics for ${places+1} digits`,()=>{
  const t=D.tenth(BigInt(places)),base=A.rotation(t),total=A.count(BigInt(places));
  // Before first contact, the burst, after it, and outgoing free motion.
  for(const time of [0,0.5,1.5,2.125,2.75,2.99,3,3.01,3.125,3.5,4.5,9.5,12]){
    const clock=Math.fround(time),actual=Replay.at_time(clock,base,t,total),expected=referenceAt(100**places,clock);
    assert.equal(actual.count,BigInt(expected.count),`collision count at ${clock}s`);
    for(const k of ['x','y','v','w'])assert.ok(Math.abs(actual[k]-expected[k])<2e-6*Math.max(1,Math.abs(expected[k])),`${k} at ${clock}s: ${actual[k]} vs ${expected[k]}`);
    assert.ok(Math.abs(actual.u**2+actual.w**2-1)<1e-6);
  }
});
test('ten-digit motion has physical-time samples through the burst and departure',()=>{
  const total=A.count(9n),r=frames(Replay.motion(true,9n,total));
  assert.equal(r.length,1024);assert.equal(r[0].time,0);assert.equal(r[0].count,0n);assert.equal(r.at(-1).count,total);
  r.forEach((s,i)=>{assert.ok(s.x>=-1e-6&&s.y>=s.x-1e-6);if(i){assert.ok(s.time>r[i-1].time);assert.ok(s.count>=r[i-1].count);}});
  const t=D.tenth(9n),base=A.rotation(t),near=Replay.at_time(3,base,t,total);
  assert.ok(near.count>1_000_000_000n&&near.count<2_000_000_000n);
  assert.ok(near.y<1e-8);assert.ok(Math.abs(near.w)<1e-6);
  assert.ok(r.at(-1).x>0&&r.at(-1).w>=r.at(-1).v);
});
