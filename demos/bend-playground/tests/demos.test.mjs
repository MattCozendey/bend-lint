import test from 'node:test';
import assert from 'node:assert/strict';
import Life from '../demos/life/life.bend';
import Ray from '../demos/raytracer/ray.bend';

function tree(words) {
  if (words.length === 1) return {$:'Leaf', word: words[0] >>> 0};
  const mid = words.length / 2;
  return {$:'Branch', left:tree(words.slice(0,mid)), right:tree(words.slice(mid))};
}
function words(g) { return g.$ === 'Leaf' ? [g.word] : [...words(g.left), ...words(g.right)]; }
function scalar(input, size) {
  const get=(x,y)=> (input[((y+size)%size)*size/32 + Math.floor((x+size)%size/32)] >>> ((x+size)%size%32)) & 1;
  const out=Array(size*size/32).fill(0);
  for(let y=0;y<size;y++) for(let x=0;x<size;x++) {
    let n=0;
    for(let dy=-1;dy<=1;dy++) for(let dx=-1;dx<=1;dx++) if(dx||dy) n+=get(x+dx,y+dy);
    if(n===3 || (n===2 && get(x,y))) out[y*size/32+Math.floor(x/32)] |= 1 << (x%32);
  }
  return out.map(x=>x>>>0);
}
for(const size of [32,64]) test(`Life matches an independent scalar torus, ${size}x${size}`,()=>{
  const depth=BigInt(Math.log2(size*size/32));
  let state=Life.initial(depth,0,size,123,0);
  let expected=words(state);
  for(let i=0;i<10;i++) {
    state=Life.step(depth,size,state);
    expected=scalar(expected,size);
    assert.deepEqual(words(state),expected);
  }
});
test('Life blinker oscillates, block stays still, glider crosses both torus edges',()=>{
  const size=64, depth=7n;
  const fromCells=cells=>{const w=Array(128).fill(0); for(const [x,y] of cells) w[y*2+Math.floor(x/32)] |= 1<<(x%32); return tree(w);};
  const block=fromCells([[31,31],[32,31],[31,32],[32,32]]);
  assert.deepEqual(Life.step(depth,size,block),block);
  const blinker=Life.initial(depth,2,size,0,0);
  assert.notDeepEqual(Life.step(depth,size,blinker),blinker);
  assert.deepEqual(Life.run(2n,depth,size,blinker),blinker);
  const shape=[[1,0],[2,1],[0,2],[1,2],[2,2]];
  const glider=fromCells(shape.map(([x,y])=>[(x+62)%64,(y+62)%64]));
  const shifted=fromCells(shape.map(([x,y])=>[(x+63)%64,(y+63)%64]));
  assert.deepEqual(Life.run(4n,depth,size,glider),shifted);
});

const v=(x,y,z)=>({$: 'Vec',x,y,z});
test('ray intersections handle misses, near hits and rays inside a sphere',()=>{
  assert.equal(Ray.intersect(v(0,0,0),v(0,0,1),v(0,0,5),1),4);
  assert.equal(Ray.intersect(v(0,0,0),v(0,0,1),v(0,0,0),1),1);
  assert.ok(Ray.intersect(v(0,0,0),v(0,0,-1),v(0,0,5),1)>1e10);
  assert.ok(Ray.intersect(v(0,0,0),v(0,0,1),v(10,0,5),1)>1e10);
});
test('mirror reflection preserves tangential direction and reverses the normal',()=>{
  const reflected=Ray.reflect(v(0.6,-0.8,0),v(0,1,0));
  assert.ok(Math.abs(reflected.x-0.6)<1e-6);
  assert.ok(Math.abs(reflected.y-0.8)<1e-6);
});
test('small rendered image has finite colors and nontrivial scene detail',()=>{
  const image=words(Ray.render(10n,0,32,24,3n)).slice(0,32*24);
  assert.ok(image.every(x=>Number.isInteger(x)&&x>=0&&x<=0xffffff));
  assert.ok(new Set(image).size>150);
});

test('sky misses return immediately even with a million allowed reflections',()=>{
  const origin=v(0,10,-5),direction=v(0,1,0);
  assert.deepEqual(Ray.trace(1_000_000n,origin,direction),Ray.sky(direction));
  assert.deepEqual(Ray.trace(0n,origin,direction),Ray.sky(direction));
});
test('reflection colors retain the original renderer values at different depths',()=>{
  for(const [depth,expected] of [[0,10861014],[1,8754339],[3,5135978],[8,4938599],[128,4938599]])assert.equal(Ray.pixel(16,10,32,20,BigInt(depth)),expected);
});
