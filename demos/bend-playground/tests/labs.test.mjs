import test from 'node:test';
import assert from 'node:assert/strict';
import S from '../demos/sorting/sort.bend';
import G from '../demos/shared/grid.bend';
import F from '../demos/fourier/math.bend';
import P from '../demos/polar/curves.bend';
import E from '../demos/shakespeare/evolution.bend';
const list=a=>a.reduceRight((tail,head)=>({$:'Con',head,tail}),{$:'Nil'});
const array=xs=>{const out=[];for(let x=xs;x.$==='Con';x=x.tail)out.push(x.head);return out;};
const near=(a,b,e=1e-4)=>assert.ok(Math.abs(a-b)<e,`${a} != ${b}`);
const events=e=>{const stack=[e],out=[];while(stack.length){const e=stack.pop();if(e.$==='Both')stack.push(e.right,e.left);else if(e.$==='Op')out.push(e);}return out;};

test('all sorting algorithms and their event replays agree with an independent sort',()=>{
 for(const n of [1,2,5,17,32,128])for(const pattern of [0n,1n,2n,3n])for(const algorithm of [0n,1n,2n]){
  const depth=BigInt(Math.ceil(Math.log2(n))),input=S.build(depth,0,n,pattern,42),values=Array.from({length:n},(_,i)=>G.lookup(depth,input,i)),expected=[...values].sort((a,b)=>a-b);
  const result=S.sort(algorithm,input,n,depth),replay=[...values];
  for(const e of events(result.events)){
   assert.ok(e.a>=0&&e.a<n);
   if(e.kind===0)assert.ok(e.b>=0&&e.b<n);
   if(e.kind===1){assert.ok(e.b<n);[replay[e.a],replay[e.b]]=[replay[e.b],replay[e.a]];}
   if(e.kind===2)replay[e.a]=e.b;
   if(e.kind===3)assert.ok(e.b>e.a&&e.b<=n);
  }
  assert.deepEqual(replay,expected);assert.deepEqual(Array.from({length:n},(_,i)=>G.lookup(depth,result.array,i)),expected);
  assert.deepEqual(Array.from({length:n},(_,i)=>G.lookup(depth,input,i)),values,'input tree was mutated');
 }
});

test('sorting comparisons reflect the algorithms rather than manufactured animation',()=>{
 const n=32,depth=5n,input=S.build(depth,0,n,1n,42);
 const count=k=>events(S.sort(k,input,n,depth).events).filter(e=>e.kind===0).length;
 assert.equal(count(0n),n*(n-1)/2);assert.equal(count(2n),n*(n-1)/2);assert.ok(count(1n)<=n*5);
 assert.ok(events(S.sort(1n,input,n,depth).events).some(e=>e.kind===3),'merge reads have explicit buffer events');
});

test('complex DFT reconstructs an independent signal at every original sample',()=>{
 const n=32,points=Array.from({length:n},(_,i)=>({$:'Point',x:Math.cos(2*Math.PI*i/n)+.3*Math.sin(6*Math.PI*i/n),y:.7*Math.sin(4*Math.PI*i/n)-.2}));
 const coefficients=Array.from({length:n},(_,k)=>F.dft(list(points),k,n));
 for(let i=0;i<n;i++){
  const p=F.endpoint(list(coefficients),2*Math.PI*i/n,0,0);near(p.x,points[i].x);near(p.y,points[i].y);
  const last=array(F.chain(list(coefficients),2*Math.PI*i/n,0,0)).at(-1);near(last.x,p.x);near(last.y,p.y);
 }
 const c=Array.from({length:32},(_,i)=>({$:'Point',x:Math.cos(2*Math.PI*i/32),y:Math.sin(2*Math.PI*i/32)}));
 near(F.dft(list(c),1,32).amplitude,1);near(F.dft(list(c),0,32).amplitude,0);
});

test('square-wave harmonics use odd frequencies and converge away from jumps',()=>{
 const coefficients=Array.from({length:32},(_,i)=>F.harmonic(i));
 coefficients.forEach((c,i)=>{assert.equal(c.frequency,2*i+1);near(c.amplitude,4/(Math.PI*(2*i+1)));});
 near(F.endpoint(list(coefficients),Math.PI/2,0,0).y,1,.011);near(F.endpoint(list(coefficients),3*Math.PI/2,0,0).y,-1,.011);
});

test('polar curves implement the heart, two distinct spirals, rose, and cardioid',()=>{
 near(P.point(0n,0,5,3).y,-5/16);near(P.point(0n,.5,5,3).y,17/16);
 for(const [kind,radius] of [[1n,.25],[4n,.5]]){const p=P.point(kind,.5,5,3);near(Math.hypot(p.x,p.y),radius);}
 for(const kind of [0n,2n,3n]){const a=P.point(kind,0,5,3),b=P.point(kind,1,5,3);near(a.x,b.x);near(a.y,b.y);}
 near(P.point(3n,0,5,3).x,0);near(P.point(3n,.5,5,3).x,-1);
});

test('Shakespeare fitness, weighted selection, and locked crossover are correct',()=>{
 const target=list([1,2,3,4]);assert.equal(E.score(target,list([1,0,3,0])),2);
 for(let seed=0;seed<100;seed++){
  const child=array(E.cross(target,list([1,0,0,0]),list([0,2,0,0]),5,10000,seed));assert.equal(child[0],1);assert.equal(child[1],2);assert.ok(child.every(n=>n>=0&&n<5));
  const noMutation=array(E.cross(target,list([1,0,0,0]),list([0,2,0,0]),5,0,seed));assert.deepEqual(noMutation,[1,2,0,0]);
 }
 const a={$:'Genome',genes:list([1]),fitness:0},b={$:'Genome',genes:list([2]),fitness:2},pop=list([a,b]);
 assert.equal(E.weights(pop),4);assert.equal(E.select(pop,0).genes.head,1);for(const ticket of [1,2,3])assert.equal(E.select(pop,ticket).genes.head,2);
});

test('seeded genetic search preserves best fitness, population size, and reaches a short target',()=>{
 const target=list([1,2,3,4,5,6]),count=100n;let pop=E.initial(count,6n,12,42,target),seed=42,best=0;
 assert.deepEqual(pop,E.initial(count,6n,12,42,target));
 for(let generation=0;generation<100&&best<6;generation++){
  const genomes=array(pop);assert.equal(genomes.length,100);
  for(const g of genomes){assert.equal(array(g.genes).length,6);assert.equal(g.fitness,E.score(target,g.genes));}
  const next=E.best(pop).fitness;assert.ok(next>=best);best=next;seed=E.next_seed(seed);pop=E.generation(count,pop,target,12,100,seed);
 }
 assert.equal(best,6);
});

test('default Shakespeare phrase converges with independent generation mutation streams',()=>{
 const phrase='To be or not to be!',alphabet=Array.from(new Set(Array.from('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz 0123456789!;.,?\'"-:'+phrase))),target=list(Array.from(phrase).map(c=>alphabet.indexOf(c)));
 let seed=42,pop=E.initial(200n,BigInt(phrase.length),alphabet.length,seed,target),generation=0;
 while(E.best(pop).fitness<phrase.length&&generation<300){seed=E.next_seed(seed);pop=E.generation(200n,pop,target,alphabet.length,100,seed);generation++;}
 assert.equal(E.best(pop).fitness,phrase.length);assert.equal(array(E.best(pop).genes).map(i=>alphabet[i]).join(''),phrase);
});
