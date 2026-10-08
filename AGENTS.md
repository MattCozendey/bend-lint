# AGENTS.md

Notes for anyone changing this repo, human or agent. How to use the tool is in
[README.md](README.md). This file is about the code.

## Setup

```sh
bun install
bun run lint
bun run format:check
bun test
bun run typecheck
git diff --check
```

`bun test` doesn't type check, so `typecheck` is its own step.

Type checking and the drift tests need a Bend checkout. `tsconfig.json` maps
`bend2/*` to `../bend/bend2`, so change that if yours is somewhere else, and set
`BEND_DIR` to the same place when you run tests. Without it the drift tests skip.

The sibling checkout currently fails typecheck twice inside Bend's own
`bend.ts` (`LTerm.k` and `TLD.v`). Mention those separately from anything your
change breaks.

## Files

- `src/lint.ts`: checker hookup, rule runner, diagnostics, fixes, library API, CLI
- `src/patch.ts`: finding Bend, downloading it, patching it as it loads
- `src/lint.bend`: what a Bend rule imports
- `src/effects.js`: the effects Bend rules call into
- `rules/`: bundled rules, one per file, tests next to them

## How we work

Small, focused changes. The PR says what was wrong, what happens now, and how
you checked.

Style is whatever the file already does: two spaces, explicit types on exported
things, `import type` for types. Order within a file is imports, types,
constants, functions, then the code that runs. Only pull a function out if
something else calls it. Long files are fine.

Use the helpers that exist. When you change something, delete the code, comments
and docs it made obsolete.

Rules live in `rules/`, one per file, with an ID like `style/file-length`. Write
down the options, what it reports and what it fixes.

Some behavior is load-bearing, so if you change it, change the tests and docs
with it:

- a file that fails Bend's checker gets no rules
- the first `error` finding ends the run
- facts are only collected when a rule asks for them
- the CLI writes fixes to the root file only

A `safe` fix must keep the program's behavior. The formatter reparses its output
and compares it to the original before offering a fix, and it keeps literals,
comments and declaration order as they are.

Everything that touches Bend's internals goes in `src/patch.ts`, with exact
matches, full argument forwarding and the startup checks. If Bend changes, fix
the patch. Let `DriftError` come through.

Every behavior change gets a regression test. Engine and CLI tests go in
`src/lint.test.ts`, rule tests next to the rule. Test what it does, not how.

Run the tests for what you touched as you go. Before you send code, run the full
suite and `typecheck`. For docs, check the examples still run, the links resolve
and `git diff --check` is clean.

The README stays short and describes what the tool does today. Internals go here.
Edit the section that exists instead of adding a second one.

## Writing rules

### TypeScript

A module exports `rules: LintRule[]`. A rule has an `id` (`namespace/name`, it
becomes the finding's `code`) and `run(cx, signal)`, which returns diagnostics
and can be async. It can also have `facts` and `options`. If `run` throws or the
signal aborts, the error goes to whoever called the library.

Build findings with `cx.diag()`. Severity defaults to `warning`. Rules run in
order and see earlier findings in `cx.prior`. The first `error` ends the run:
the rest of that rule's findings and every later rule are dropped.

What's on `cx`:

- `root`, `sources`: the linted file and its imports, text as on disk
- `book`: the checked Bend program
- `options`: defaults merged with config
- `facts`: just the facts this rule asked for
- `prior`: findings from earlier rules
- `span(s)`: Bend span to a file on disk
- `walk(tm)`: walk Bend terms
- `binder(fact, v)`: find a variable's binder
- `show`, `same`, `normal`: print, compare and normalize types in a fact's scope
- `uses(fact)`: used variables with their quantities
- `diag(init)`: make a diagnostic with this rule's ID
- `Bend`: the loaded Bend module. Use it instead of importing `bend2/bend.ts`

The exported types in [src/lint.ts](src/lint.ts) are the full contract.

#### Fixes

A fix is a title, an applicability (`safe`, `suggested`, `dangerous`) and edits.
An edit swaps a span for text. A zero-length span inserts. Offsets are integer
UTF-16 units inside the source, and edits in one fix can't overlap.

```ts
const spn = { file: cx.root.file, beg: 0, end: 1 };
return [cx.diag({
  message: "Replace the first character with a space.",
  spn,
  fixes: [{
    title: "Replace character",
    applicability: "suggested",
    edits: [{ spn, text: " " }],
  }],
})];
```

(Needs a nonempty file.)

#### Facts

A fact is one checked term with its type (`ty`), scope (`ctx`), depth (`dep`),
enclosing definition (`def`), demanded quantity (`qt`), variable uses (`us`),
book (`bok`) and source span (`spn`, when there is one). The term itself is `tm`.

Ask for them with `facts: true` (everything in the linted file) or a filter:

```ts
facts: {
  scope: "file",   // default. "program" adds imports, not Base
  kinds: ["Var"],  // term kind without annotations: Var, Ref, App, ...
  defs: ["main"],  // enclosing definition, instances count as their template
  names: ["foo"],  // name used by a Var or Ref
}
```

All the lists you give must match. Leave one out or empty and it matches
everything. Keep filters narrow, since memory goes up with the number of facts.

Template bodies get checked as written and again per instance (`generic~0`),
sometimes at the same span. `fact.inst` marks instances. Skip them to avoid
double reports:

```ts
import type { LintRule } from "../src/lint.ts";

export const rules: LintRule[] = [{
  id: "demo/var-types",
  facts: { kinds: ["Var"] },
  run: (cx) => [...cx.facts!.values()]
    .filter((fact) => !fact.inst)
    .map((fact) => cx.diag({
      message: "type: " + cx.show(fact, fact.ty),
      severity: "hint",
      spn: fact.spn,
      fact,
    })),
}];
```

(Saved under `rules/`.)

#### Options

`options: { tabWidth: 2, breakLines: false }` sets defaults. They also set which
keys are allowed and their types (`number`, `boolean`, `string`). Unknown keys
and wrong types are errors. A rule with no defaults gets the raw options and has
to check them itself.

### Bend

A `.bend` rule imports [src/lint.bend](src/lint.bend). Here's one that reports
nothing, saved under `rules/`:

```python
import Base
import ../src/lint.bend as Lint

def id() -> String:
  "demo/nothing"

def facts() -> Lint.Want:
  Lint.NoFacts{}

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  IO.pure(List<&2, Lint.Diag>, [])

def main() -> IO(Unit):
  Lint.serve(run)
```

`input` has the sources and options. To get facts, return a filter from
`facts()`, e.g. `Lint.Want{Lint.File{}, ["Var"], [], []}`. Empty lists match
everything, and `Lint.Program{}` adds imports (not Base).

Read facts one by one with `next_fact`, or fold:

```python
def step(found: List<&2, Lint.Diag>, +f: Lint.Fact) -> IO(List<&2, Lint.Diag>):
  ...

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  Lint.fold_facts(~List<&2, Lint.Diag>, ~step, [])
```

`step` goes in as a template (`~step`) and takes the fact as `+f`. Effects:
`view`, `type_of`, `binder`, `same`, `show`, `normal`, `uses`, `text`, plus
Base's. Options come from `Lint.option_number`, `option_flag` and `option_text`,
each with a default. Numbers are whole, 0 to 4294967295 (U32).

Spans count Unicode code points here. TypeScript counts UTF-16 units.

The rule is compiled once and runs on Bend's JavaScript runtime. Use tail
recursion over long text or lists to stay inside the stack. Streaming facts
saves building a list of all of them.

For examples see [file_length.bend](rules/file_length.bend) and
[shared.bend](rules/shared.bend). `COMMA_BEND`, `TYPES_BEND` and `COUNT_BEND` in
[src/lint.test.ts](src/lint.test.ts) cover fixes and facts.

### As a library

From a file in the repo root:

```ts
import { applyFixes, bendRule, lint, render } from "./src/lint.ts";
import { rules } from "./rules/format.ts";

const result = await lint("example.bend", [
  ...rules,
  await bendRule("rules/file_length.bend"),
]);
console.log(result.ok, result.diags.map(render));

if (result.ok) {
  const root = result.sources.find((source) => source.root)!;
  const { text, skipped } = applyFixes(root.file, result.diags);
  // text is the edited source; saving it is up to you
  console.log(text, skipped);
}
```

Set `BEND_DIR` before importing bend-lint to pick a Bend checkout. Import
bend-lint before you load Bend yourself, so the patching happens first. `lint`
takes `{ config, signal, unsaved }` as a third argument. Without `config` it looks
next to the file. `unsaved` maps file paths to editor text that isn't saved yet.
Bend and the rules read that text instead of the file, for that run only. Runs
at the same time wait for each other's check, one at a time; rules still run
side by side. `position(span)` gives an LSP range.

`findConfig(file)` checks the file's directory, then each parent, for
`bend-lint.json`, `.js` or `.ts`. Closest directory wins, then JSON, JS, TS.
`readConfig(file)` loads a path you give it. Both are synchronous. JS and TS
configs export a named `config` object and go through Bun's loader, cache
included. They can import relative files. Rule settings and option validation
are the same for all three formats.

### JSON output

`--json` prints one JSON object on stdout. Status and failure messages can still
show up on stderr. A finding with a fix:

```json
{
  "ok": true,
  "findings": [{
    "code": "style/example",
    "severity": "warning",
    "message": "Replace this character.",
    "def": "main",
    "path": "/abs/example.bend",
    "range": {
      "start": { "line": 2, "character": 0 },
      "end": { "line": 2, "character": 1 }
    },
    "fixes": [{
      "title": "Replace character",
      "applicability": "suggested",
      "edits": [{
        "path": "/abs/example.bend",
        "range": {
          "start": { "line": 2, "character": 0 },
          "end": { "line": 2, "character": 1 }
        },
        "text": " "
      }]
    }]
  }]
}
```

`def`, `path` and `range` are left out when there's nothing to put. Lines start
at 0, characters are UTF-16. With a fix flag, findings describe the source as it
was before the fixes.

## Internals

### Finding Bend

bend-lint reads Bend's source directly. Where it looks, in order:

1. `--bend <dir>`, or `BEND_DIR` if there's no flag. A checkout or its `bend2`
   folder.
2. The checkout around it, if bend-lint is at `tools/bend-lint`.
3. A downloaded release. It matches `bend version` from PATH, or is the latest
   if Bend isn't installed.

The latest-release lookup is cached for a day. Offline it uses the newest cached
release. A version picked by flag or PATH needs its source available.

A download is `bend2/bend.ts`, `comp.ts`, `main.ts`, `safe.ts`, `base.bend` and
the `effs/` files Base imports. It lands in `~/.cache/bend-lint/<tag>/bend2`
(`XDG_CACHE_HOME` changes the root, `LOCALAPPDATA` on Windows) and gets reused.
A cached release without `main.ts` downloads again.

### Patching

Bun patches Bend's modules while they load. `term_infer` and `term_check` are
renamed and wrapped to record what they return to `hook.see` in patch.ts. The
wrappers pass every argument on. The hook is global, so checks run one at a
time. The `fs` and `path` adapters, in `bend.ts` and `main.ts`, turn real paths
into `/` paths so imports resolve on Windows. `comp.ts` also exports
`RUNTIME_MAIN` and `js_sat`, which compiling Bend rules needs. `main.ts` exports
`book_read`, `book_err` and `Check_Fail`: a file is read and checked by the same
code as `bend <file>`, never a copy of it. Imported, `main.ts` also registers
Bend's loader for `import "x.bend"`.

If a file has a line that's exactly `import Base` (what `bend --checkup` reads),
it reuses one Base, checked once per process. Base facts are left out of rule
requests.

A failed check is one `bend/check` finding. Its message is Bend's, without the
location: expected and observed, with the names in scope, and Bend's note.

### Staying compatible

We don't pin a Bend version. Instead, on load, for checkouts and downloads
alike:

- every source edit has to match exactly once, and the compiler exports we need
  have to be declared
- wrapper signatures are checked against Bend's at type-check time, and argument
  counts at runtime
- a self-check looks at the type, depth, scope, quantity, uses and span recorded
  for `x` in `def id(x: N) -> N: x`

Any mismatch throws `DriftError` and loading stops. The tests add more, including
drift against the chosen checkout's own tests.
