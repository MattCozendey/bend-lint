import { mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { setup, root } from './setup.mjs';

setup();
mkdirSync(new URL('../build/', import.meta.url), { recursive: true });
execFileSync(process.execPath, ['.tools/bend/bend2/main.ts', 'main.bend', '-o', 'build/pi'], { cwd: root, stdio: 'inherit' });
console.log('Native executable: ./build/pi');
