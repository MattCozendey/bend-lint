import { copyFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';
import { setup, root } from './setup.mjs';
import { buildRubik } from './build-rubik.mjs';
import { buildTimesTable } from './build-times-table.mjs';
import { buildLabs } from './build-labs.mjs';

setup();
await buildRubik(); await buildTimesTable(); await buildLabs();
const { load } = await import('../.tools/bend/bend2/main.ts');
const modules = {
  ray: 'demos/raytracer/ray.bend', path: 'demos/raytracer/grid-path.bend',
  life: 'demos/life/sparse.bend', collisions: 'accelerated.bend',
  replay: 'demos/cubes/replay.bend', probability: 'demos/probability/simulation.bend',
};
const base = process.env.PAGES_BASE || '/bend-playground/';
if (!/^\/(?:[\w.-]+\/)*$/.test(base)) throw new Error('PAGES_BASE must be an absolute directory path ending in /.');
execFileSync('npm', ['--prefix', 'ui', 'run', 'build'], {
  cwd: root, stdio: 'inherit', env: { ...process.env, VITE_STATIC: 'true', PAGES_BASE: base },
});
const output = resolve(root, 'build/pages');
mkdirSync(output, { recursive: true });
for (const [name, source] of Object.entries(modules)) {
  const result = await load(pathToFileURL(resolve(root, source)).href, {}, () => { throw new Error('Expected a Bend module.'); });
  writeFileSync(resolve(output, `${name}-engine.js`), `// Compiled from ${source} by Bend 2.0.5.\n${result.source}`);
}
for (const name of ['rubik', 'times-table', 'fourier', 'sorting', 'shakespeare', 'polar'])
  copyFileSync(resolve(root, `build/${name}-engine.js`), resolve(output, `${name}-engine.js`));
writeFileSync(resolve(output, '.nojekyll'), '');
console.log(`Standalone site ready in build/pages (base ${base}).`);
