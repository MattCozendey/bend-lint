import test from 'node:test';
import assert from 'node:assert/strict';
import S from '../demos/life/sparse.bend';
import Life from '../demos/life/life.bend';
import {parseLife} from '../scripts/demo-lib.mjs';
function words(g){return g.$==='Leaf'?[g.word]:[...words(g.left),...words(g.right)];}
function packed(input,offset=0){
 if(input.length===1)return S.leaf(input[0]===0,offset,input[0]);
 const mid=input.length/2;return S.join(packed(input.slice(0,mid),offset),packed(input.slice(mid),offset+mid));
}
function scalar(input,size){
 const cell=(x,y)=>(input[((y+size)%size)*size/32+Math.floor((x+size)%size/32)]>>>((x+size)%size%32))&1;
 const output=Array(size*size/32).fill(0);
 for(let y=0;y<size;y++)for(let x=0;x<size;x++){
  let n=0;for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++)if(dx||dy)n+=cell(x+dx,y+dy);
  if(n===3||(n===2&&cell(x,y)))output[y*size/32+(x>>>5)]|=1<<(x&31);
 }
 return output.map(w=>w>>>0);
}
for(const size of [32,64,128])test(`sparse Life matches independent scalar rules on ${size}x${size}`,()=>{
 const depth=BigInt(Math.log2(size*size/32));let g=S.initial(depth,0,size,123,0),expected=words(Life.initial(depth,0,size,123,0));
 for(let i=0;i<12;i++){assert.deepEqual(words(S.expand(depth,g)),expected);g=S.step(depth,size,g);expected=scalar(expected,size);}
});
test('sparse updates preserve gliders across both torus edges and word boundaries',()=>{
 const size=64,depth=7n,shape=[[1,0],[2,1],[0,2],[1,2],[2,2]];
 for(const [ox,oy] of [[62,62],[31,63],[63,31],[0,0]]){
  let expected=Array(128).fill(0);for(const [x,y] of shape){const a=(x+ox)%size,b=(y+oy)%size;expected[b*2+(a>>>5)]|=1<<(a&31);}expected=expected.map(w=>w>>>0);
  let g=packed(expected);
  for(let i=0;i<16;i++){assert.deepEqual(words(S.expand(depth,g)),expected);g=S.step(depth,size,g);expected=scalar(expected,size);}
 }
});
test('distant live regions and an empty universe remain correct',()=>{
 let expected=Array(128).fill(0);for(const i of [0,1,31,32,63,64,126,127])expected[i]=0x80000007;
 let g=packed(expected);
 for(let i=0;i<12;i++){assert.deepEqual(words(S.expand(7n,g)),expected);g=S.step(7n,64,g);expected=scalar(expected,64);}
 assert.deepEqual(S.run(1000n,13n,512,{$:'Empty'}),{$:'Empty'});
});
test('sparse replay decoding preserves empty frames and unsigned words',()=>{
 const parsed=parseLife({size:32,steps:2},{metadata:{},lines:['LIFE_SPARSE 32 2','S 0 4294967295 31 1','S ','S 1 2']});
 assert.equal(parsed.encoding,'sparse-words');assert.deepEqual(parsed.frames,[[0,4294967295,31,1],[],[1,2]]);
 assert.throws(()=>parseLife({size:32,steps:0},{metadata:{},lines:['LIFE_SPARSE 32 0','S 32 1']}));
});
test('batched replay retains every intermediate state and the final state',()=>{
 const initial=S.initial(7n,0,64,42,0);let expected=initial,r=S.record(33n,7n,64,initial),count=0;
 while(r.$==='Frame'){assert.deepEqual(r.grid,expected);expected=S.step(7n,64,expected);r=r.next;count++;}
 assert.equal(count,33);assert.equal(r.$,'End');assert.deepEqual(r.last,expected);
 assert.deepEqual(S.record(0n,7n,64,initial),{$:'End',last:initial});
});
