import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { root } from './setup.mjs';

const binary = fileURLToPath(new URL('../build/pi-gpu', import.meta.url));
if (!existsSync(binary)) throw new Error('Run npm run build:gpu first.');
const localCuda = fileURLToPath(new URL('../.tools/cuda', import.meta.url));
const cuda = process.env.CUDA_HOME || (existsSync(`${localCuda}/lib64`) ? localCuda : '/usr/local/cuda');
const env = { ...process.env, LD_LIBRARY_PATH: `${cuda}/lib64:${cuda}/lib:${process.env.LD_LIBRARY_PATH || ''}` };
console.log('Backend: NVIDIA CUDA (GPU required; no CPU fallback)');
const result = spawnSync(binary, ['--gpu', '1GB'], { cwd: root, env, stdio: 'inherit' });
if (result.error) throw result.error;
process.exit(result.status ?? 1);
