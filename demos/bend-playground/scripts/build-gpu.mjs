import { existsSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { setup, root } from './setup.mjs';

setup();
const localCuda = fileURLToPath(new URL('../.tools/cuda', import.meta.url));
const cuda = process.env.CUDA_HOME || (existsSync(`${localCuda}/include/nvrtc.h`) ? localCuda : '/usr/local/cuda');
if (process.platform !== 'linux' || !existsSync(`${cuda}/include/nvrtc.h`)) {
  throw new Error('This GPU build needs Linux/NVIDIA and CUDA NVRTC. Run npm run setup:gpu or set CUDA_HOME.');
}
mkdirSync(new URL('../build/', import.meta.url), { recursive: true });
const env = { ...process.env, CUDA_HOME: cuda, LD_LIBRARY_PATH: `${cuda}/lib64:${cuda}/lib:${process.env.LD_LIBRARY_PATH || ''}` };
execFileSync(process.execPath, ['.tools/bend/bend2/main.ts', 'gpu.bend', '-o', 'build/pi-gpu'], { cwd: root, env, stdio: 'inherit' });
if (!existsSync(new URL('../build/pi-gpu.gpu', import.meta.url))) {
  throw new Error('Bend did not produce a GPU kernel. Check the NVIDIA driver and GPU availability.');
}
console.log('Built build/pi-gpu and its CUDA kernel. Run npm run gpu.');
