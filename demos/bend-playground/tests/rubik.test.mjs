import test from 'node:test';
import assert from 'node:assert/strict';
import Cube from '../demos/rubik/cube.bend';
const array=xs=>{const out=[];for(;xs.$==='Con';xs=xs.tail)out.push(xs.head);return out;};
const list=xs=>xs.reduceRight((tail,head)=>({$:'Con',head,tail}),{$:'Nil'});
const solved=Cube.solved();
test('Rubik sticker coordinates round-trip all 54 distinct positions',()=>{
 for(let i=0;i<54;i++)assert.equal(Cube.index(Cube.site(i)),i);
 assert.deepEqual(array(solved),Array.from({length:54},(_,i)=>i));assert(Cube.is_solved(solved));
});
for(let face=0;face<6;face++)test(`face ${'URFDLB'[face]} turns clockwise, fixes centers, and has order four`,()=>{
 const move=face*3,perm=Array.from({length:54},(_,i)=>Cube.destination(i,move));
 assert.equal(new Set(perm).size,54);assert.equal(perm.filter((v,i)=>v!==i).length,20);
 for(let f=0;f<6;f++)assert.equal(perm[f*9+4],f*9+4);
 const clockwise=[2,5,8,1,4,7,0,3,6];for(let i=0;i<9;i++)assert.equal(perm[face*9+i],face*9+clockwise[i]);
 assert.deepEqual(Cube.sequence(list([move,move,move,move]),solved),solved);
 const cubies=new Map();
 for(let i=0;i<54;i++){
  const key=JSON.stringify(Cube.site(i).position),destination=Cube.site(perm[i]).position;
  if(cubies.has(key))assert.deepEqual(destination,cubies.get(key));else cubies.set(key,destination);
 }
});
test('front turn transfers the upper front edge to the right front edge',()=>{
 assert.deepEqual([6,7,8].map(i=>Cube.destination(i,6)),[9,12,15]);
});
test('all 18 moves have exact inverses, and applying a move follows its sticker permutation',()=>{
 for(let move=0;move<18;move++){
  const state=Cube.apply(solved,move),values=array(state);assert(!Cube.is_solved(state));
  assert.deepEqual(Cube.apply(state,Cube.inverse(move)),solved);
  for(let i=0;i<54;i++)assert.equal(values[Cube.destination(i,move)],i);
 }
});
test('opposite face turns commute; six R U R′ U′ sequences return to solved',()=>{
 for(const [a,b] of [[0,9],[3,12],[6,15]])assert.deepEqual(Cube.sequence(list([a,b]),solved),Cube.sequence(list([b,a]),solved));
 assert.deepEqual(Cube.sequence(list(Array.from({length:6},()=>[3,0,5,2]).flat()),solved),solved);
});
test('Bend-generated scrambles unwind from their move history without losing a sticker',()=>{
 for(const seed of [0,42,123,0xffffffff]){
  const moves=Cube.scramble(100n,seed,6),sequence=array(moves),state=Cube.sequence(moves,solved);
  assert.equal(sequence.length,100);assert(sequence.every((m,i)=>m>=0&&m<18&&(!i||Math.floor(m/3)!==Math.floor(sequence[i-1]/3))));
  assert.deepEqual(array(state).sort((a,b)=>a-b),array(solved));
  assert.deepEqual(Cube.sequence(Cube.undo_moves(moves,{$:'Nil'}),state),solved);
 }
});
