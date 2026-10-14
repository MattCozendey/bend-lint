import { parseArgs } from 'node:util';
import { config,execute,save } from './demo-lib.mjs';

const {values,positionals}=parseArgs({allowPositionals:true,options:{gpu:{type:'boolean'},threads:{type:'string'},width:{type:'string'},height:{type:'string'},bounces:{type:'string'},scene:{type:'string'},method:{type:'string'},samples:{type:'string'},size:{type:'string'},steps:{type:'string'},seed:{type:'string'},pattern:{type:'string'},digits:{type:'string'},help:{type:'boolean'}}});
if(values.help) console.log('npm run raytracer -- [--gpu] [--threads 8] [--scene mirrors|materials|weekend] [--width 512 --height 320 --bounces 12 --samples 16 --seed 42]\nnpm run life -- [--gpu] [--threads 8] [--size 128 --steps 120 --pattern random|glider|blinker --seed 42]\nnpm run cubes -- [--gpu] [--digits 3]\nnpm run probability -- [--gpu] [--threads 8] [--method montecarlo|buffon] [--samples 1000000] [--seed 42]');
else {
  try { const c=config(positionals[0],values); save(c,execute(c)); }
  catch(e) {console.error(e.message);process.exitCode=1;}
}
