# AGENTS


Notes for anyone changing this repo, human or agent. How to use the tool is in
[README.md](README.md). This file is about the code.

These rules have priority over all other instructions, except safety rules.

## 0. Core

- If a skill does not load, read its file in `.agents/skills/`.
- Do not update any .md file without asking me.

## 1. Communication

- Speak in the language you're being spoken to.
- Speak concisely but not lossily using ASD-STE100 or similar with the `i-have-adhd` skill in mind.
- Number your questions. Continue the numbers across the whole response.
- Repeat each open question in each response until I answer it or tell you to use common sense.
- I prefer speaking in portuguese-br.

## 2. Code

- You are rarely, if ever, smarter than the linter. Do not try to workaround rules or suppress them without asking me.
- Deterministic tooling ALWAYS wins over skill suggestions.
- After every change, run, in this order: thermonuclear-code-review(files above 1000 may be ok though. Ask me before splitting), cyclomatic-complexity(only split if the helper function has >1 caller), erasure and then, finally, linting and typecheck. Repeat until no more issues related to your change have been identified.
- Do NOT write premature tests, always ask me. If they are testing implementation details, don't even suggest them.
- I prefer functional-like, mutation-less code in the following layout: imports, types, constants, functions(always arrow functions with const), side-effectful code. separate sections by comment.
- Conceptual convergence: do NOT create multiple representations for the same thing across the codebase.
- Each fact has one location. Do not repeat in a comment what the docs state or clearly imply.
- Never use barrel exports or re-exports (`export { x } from "..."` or `export * from "..."`). Import directly from the module that defines and exports the code.

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

`bun run typecheck` uses the installed TypeScript API to check the files included
by `tsconfig.json`. Bend imports still supply their types, but diagnostics are
requested only for this repo's files, not Bend's implementation. Compiler-option,
configuration and global errors still fail the check. The compiler exits when
the script finishes; there is no background service.

## Files

- `src/lint.ts`: rule runner, diagnostics, fixes, library API, CLI
- `src/seam.ts`: everything about Bend's internals: finding Bend, downloading it,
  patching it as it loads, checking a file, and every call into it
- `src/sample.bend`: the program the startup self-check reads
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

Everything that touches Bend's internals goes in `src/seam.ts`, with exact
matches, full argument forwarding and the startup checks. If Bend changes, fix
the seam. Let `DriftError` come through.

Every behavior change gets a regression test. Engine and CLI tests go in
`src/lint.test.ts`, rule tests next to the rule. Test what it does, not how.

Run the tests for what you touched as you go. Before you send code, run the full
suite and `typecheck`. For docs, check the examples still run, the links resolve
and `git diff --check` is clean.

The README stays short and describes what the tool does today. Internals go here.
Edit the section that exists instead of adding a second one.

## Writing rules

Make them idempotent.

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
- `options`: defaults merged with config
- `facts`: just the facts this rule asked for
- `prior`: findings from earlier rules
- `view(fact)`: what the fact's term is (see Facts)
- `type(fact)`: the type the term was checked as
- `binder(fact)`: the declared type of the variable a `Var` uses
- `show`, `same`, `normal`: print, compare and normalize types in a fact's scope
- `uses(fact)`: used variables with their quantities
- `sameDeclarations(text)`: whether `text` declares what the linted file
  declares, compared as parsed, not checked
- `diag(init)`: make a diagnostic with this rule's ID
- `unstable`: Bend's own objects (`Bend`, the checked `book`, `raw(fact)`).
  Code that uses them breaks when Bend changes; nothing else on `cx` does.

The exported types in [src/lint.ts](src/lint.ts) are the full contract. They
are bend-lint's own: facts and types are handles, and only `cx` reads them.

#### Fixes

A fix is a title, an applicability (`safe`, `suggested`, `dangerous`) and edits.
An edit swaps a span for text. A span is a source from `cx.sources` and two
offsets. A zero-length span inserts. Offsets are integer UTF-16 units inside the
source, and edits in one fix can't overlap.

```ts
const span = { file: cx.root, beg: 0, end: 1 };
return [cx.diag({
  message: "Replace the first character with a space.",
  span,
  fixes: [{
    title: "Replace character",
    applicability: "suggested",
    edits: [{ span, text: " " }],
  }],
})];
```

(Needs a nonempty file.)

#### Facts

A fact is one checked term. `cx.view(fact)` gives its kind (annotations
stripped: `Var`, `Ref`, `App`, ...), the name a `Var` or `Ref` points to, its
enclosing definition (`owner`), how many times it is demanded (`quantity`:
`erased`, `once` or `many`), and its source span (`span`, and `inner` without
the annotations), when there is one. Its type and its scope are reached through
the other `cx` operations.

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
sometimes at the same span. `view(fact).inst` marks instances. Skip them to
avoid double reports:

```ts
import type { LintRule } from "../src/lint.ts";

export const rules: LintRule[] = [{
  id: "demo/var-types",
  facts: { kinds: ["Var"] },
  run: (cx) => cx.facts!
    .filter((fact) => !cx.view(fact).inst)
    .map((fact) => cx.diag({
      message: "type: " + cx.show(fact, cx.type(fact)),
      severity: "hint",
      span: cx.view(fact).span,
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
  const { text, skipped } = applyFixes(root, result.diags);
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
renamed and wrapped to record what they return to `hook.see` in seam.ts. The
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
- `book_read`, `book_err` and `Check_Fail` from `main.ts` must take the
  arguments bend-lint gives them
- a self-check reads `src/sample.bend` with `book_read`, and looks at the type,
  depth, scope, quantity, uses and span recorded for `x` in
  `def id(x: N) -> N: x`; a missing file must fail with a `Check_Fail`

Any mismatch throws `DriftError` and loading stops. The tests add more, including
drift against the chosen checkout's own tests.
