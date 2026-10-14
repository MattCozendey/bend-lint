import { existsSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const root = fileURLToPath(new URL('../', import.meta.url));
export const tool = fileURLToPath(new URL('../.tools/bend/', import.meta.url));
// Bend 2.0.5. Pin the compiler because Bend 1 and Bend 2 are incompatible.
export const revision = '0b7e2b11c1054f5d0f4eb955cadb47997ef1115d';

export function setup() {
  const git = (...args) => execFileSync('git', args, { cwd: tool, stdio: 'inherit' });
  if (!existsSync(new URL('../.tools/bend/.git', import.meta.url))) {
    mkdirSync(tool, { recursive: true });
    git('init', '--quiet');
    git('remote', 'add', 'origin', 'https://github.com/bendlang/bend.git');
  }
  let current = '';
  try {
    current = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: tool, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch { /* An empty checkout still needs fetching. */ }
  if (current !== revision) {
    if (execFileSync('git', ['status', '--porcelain'], { cwd: tool, encoding: 'utf8' }).trim()) {
      throw new Error('The local .tools/bend checkout has edits; preserve them before running setup.');
    }
    git('fetch', '--depth=1', 'origin', revision);
    git('checkout', '--detach', revision);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  setup();
  console.log('Bend 2.0.5 is ready in .tools/bend (no global installation).');
}

