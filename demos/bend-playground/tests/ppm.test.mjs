import test from 'node:test';
import assert from 'node:assert/strict';
import {ppm} from '../scripts/demo-lib.mjs';
import {decodePpm} from '../ui/src/lib/ppm.js';
import Ray from '../demos/raytracer/ray.bend';

test('PPM output uses the book’s P3 header and top-to-bottom RGB triplets',()=>{
  const text=ppm(2,2,[0xff0000,0x00ff00,0x0000ff,0x123456,0]);
  assert.equal(text,'P3\n2 2\n255\n255 0 0\n0 255 0\n0 0 255\n18 52 86\n');
  assert.deepEqual(decodePpm(text),{width:2,height:2,rgba:new Uint8ClampedArray([
    255,0,0,255,0,255,0,255,0,0,255,255,18,52,86,255,
  ])});
});

test('PPM reader accepts comments, CRLF, and arbitrary whitespace',()=>{
  assert.deepEqual([...decodePpm('P3 # format\r\n1\t1\n# colors\n255\n10 32 35 # final\n').rgba],[10,32,35,255]);
});

test('PPM rejects missing pixels, invalid channels, and inconsistent headers',()=>{
  for(const text of ['P6\n1 1\n255\n0 0 0','P3 0 1 255','P3 1 1 100 1 2 3','P3 1 1 255 0 0','P3 1 1 255 -1 0 0','P3 1 1 255 256 0 0','P3 1 1 255 0.5 0 0','P3 1 1 255 0 0 0 0','P3 99999999999 99999999999 255 0 0 0'])assert.throws(()=>decodePpm(text));
  assert.throws(()=>ppm(2,2,[0,0]));
  for(const pixel of [NaN,-1,0x1000000,1.5])assert.throws(()=>ppm(1,1,[pixel]));
});

test('Bend ray colors survive PPM and canvas conversion without flipping or gamma changes',()=>{
  const flatten=g=>g.$==='Leaf'?[g.word]:[...flatten(g.left),...flatten(g.right)];
  const width=13,height=7,pixels=flatten(Ray.render(7n,0,width,height,3n));
  const decoded=decodePpm(ppm(width,height,pixels));
  for(let y=0;y<height;y++)for(let x=0;x<width;x++){
    const p=Ray.pixel(x,y,width,height,3n),i=(y*width+x)*4;
    assert.deepEqual([...decoded.rgba.slice(i,i+4)],[(p>>>16)&255,(p>>>8)&255,p&255,255]);
  }
});
