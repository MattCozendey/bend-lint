# bend-lint

A linter and formatter for Bend 2.

It runs your file through Bend's type checker first. If that passes, it runs
whatever rules you loaded. Rules are TypeScript or Bend files, and they can see
the source text, the types, variable scope and how often each variable is used.
A rule can also suggest a fix.

## Setup

Use Bun 1.4.2, pinned in `package.json`.

```sh
git clone https://github.com/MattCozendey/bend-lint.git
cd bend-lint
bun install
```

## Running it

```sh
bun src/lint.ts file.bend --rules rules/format.ts
```

Nothing runs by default. Pass `--rules`, more than once if you like, or list
rule files in the config (see Config):

```sh
bun src/lint.ts file.bend --rules rules/format.ts --rules rules/file_length.bend
```

Add `--fix` to write the fixes back to the file.

```
bun src/lint.ts <file.bend> [--rules <file>]... [--config <file>]
                [--fix | --fix-suggested | --fix-dangerously]
                [--json] [--bend <dir>]
```

Every fix is marked `safe`, `suggested` or `dangerous`:

- `--fix` applies the safe ones. They shouldn't change what the program does.
- `--fix-suggested` adds the suggested ones, which might.
- `--fix-dangerously` applies everything. Expect breakage sometimes.

Fixes go into the file you passed in, even if the run had errors. A fix that
also edits another file is skipped. When two fixes overlap, the later one is
skipped. Run it again to get it.

Exit code is 0 if there were no errors (warnings don't count), 1 for a checker
or rule error, and 2 for bad arguments or a crash.

`--json` prints the findings as JSON. The format is in
[AGENTS.md](AGENTS.md#json-output).

## Where Bend comes from

bend-lint loads Bend's TypeScript source and patches it in memory. To find that
source it tries, in order:

1. `--bend <dir>` or `$BEND_DIR`. A Bend checkout or its `bend2` folder both work.
2. The Bend checkout around it, if you put bend-lint at `tools/bend-lint`.
3. A release downloaded from GitHub. It matches `bend version` if Bend is on
   your PATH, otherwise it takes the latest.

Downloads are cached in `~/.cache/bend-lint/`. `XDG_CACHE_HOME` moves that, and
on Windows it's under `LOCALAPPDATA`. With no network it falls back to the
newest cached release.

## Rules included

`format/layout` (`rules/format.ts`) is the formatter. It fixes indentation,
spacing, comments, blank lines between declarations, wrapping and the final
newline. Options: `tabWidth` (default 2) and `wrapAtWidth` (default 100). Both
must be positive integers, or `"never"` for `wrapAtWidth`. The width is a target;
long literals and comments can run past it. `endOfLine` is `"lf"` (default),
`"crlf"` or `"preserve"`; preserve uses the first line ending, or LF if there
is none. Line endings inside literals stay as written. Its fix is `safe`.

Declaration order and literals stay as written. The only comment change is a
space added after `#` when it's missing. Before offering a fix it parses
its own output and compares that to the original program. If they differ you
get a warning and no fix.

`style/file-length` (`rules/file_length.bend`) warns when the file has more than
`maxLines` lines (default 500). Imports don't count. No fix.

## Config

Put a `bend-lint.json`, `bend-lint.js` or `bend-lint.ts` next to the file you're
linting or in any parent folder, or point at one with `--config`. The closest
folder wins. Inside a folder, JSON beats JS beats TS. Only one file is read.

```json
{
  "load": ["./rules/format.ts", "./rules/file_length.bend"],
  "rules": {
    "format/layout": { "tabWidth": 2, "wrapAtWidth": 100 },
    "style/file-length": { "maxLines": 400, "severity": "warning" }
  }
}
```

JS and TS configs export the same thing as a named `config`.

```ts
export const config = {
  rules: {
    "style/file-length": { maxLines: 400 },
  },
};
```

`load` lists rule files, relative to the config file. They run after the ones
from `--rules`. `rules` sets their options and severity. `"off"` turns a rule
off. Severities are `error`, `warning`, `information` and `hint`.

Each rule declares the options it accepts. Unknown keys and values that don't
match are rejected.

## What you get back

If Bend's checker rejects the file you get a `bend/check` error, and only the
rules that read just the text run (`format/layout` and `style/file-length` do).
A rule that crashes is a `bend-lint/rule-crash` error, and the other rules still
run.

## Writing your own rule

Save this as `no-tabs.ts` in the repo root:

```ts
import type { LintRule } from "./src/lint.ts";

export const rules: LintRule[] = [{
  id: "style/no-tabs",
  run(cx) {
    return [...cx.root.text.matchAll(/\t/g)].map((match) => cx.diag({
      message: "Use spaces instead of a tab.",
      span: { file: cx.root, beg: match.index!, end: match.index! + 1 },
    }));
  },
}];
```

```sh
bun src/lint.ts file.bend --rules no-tabs.ts
```

That one reads raw text, so it also flags tabs inside literals and comments. For types and scope you ask for checker facts. Rules can be written in
Bend too, see `rules/file_length.bend`. The rest (facts, fixes, options, using
bend-lint as a library) is in [AGENTS.md](AGENTS.md#writing-rules).

## Hacking on it

```sh
bun run lint
bun run format:check
bun test
bun run typecheck
```

`bun run format` writes formatting changes. Oxlint and oxfmt both exclude
`.bend` files.

Type checking needs a Bend checkout. Setup and house rules are in
[AGENTS.md](AGENTS.md).
