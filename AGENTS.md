# Contributor guide

This file applies to the whole repository. It contains contribution rules
and the technical reference for bend-lint. User-facing setup and usage
belong in [README.md](README.md).

## Development setup

Requires Bun 1.2 or newer. Run `bun install` from the repo root.

Type checking needs a Bend checkout. The `bend2/*` mapping in
[tsconfig.json](tsconfig.json) expects `../bend/bend2`; adjust it if your
checkout is elsewhere. Set `BEND_DIR` to that same checkout for tests.
The drift tests need its `tests/` directory as well.

```sh
bun test
bun run typecheck
git diff --check
```

Bun does not check types. TypeScript also checks imported Bend source.
The current sibling checkout reports two upstream errors in `bend.ts`
(accesses to `LTerm.k` and `TLD.v`). Report upstream failures separately
from errors introduced by a change; do not suppress them to make checks pass.

## Contribution rules

- Keep changes focused. Explain the concrete problem, resulting behavior
  and validation in the PR description.
- Match the surrounding code: two-space indentation, explicit TypeScript
  types at API boundaries, and `import type` for type-only dependencies.
- Reuse existing helpers. Keep functions focused, flatten nested branches,
  and remove code, comments and documentation made obsolete by the change.
- Keep lint rules in `rules/`, one file per rule. Give each a
  `namespace/name` ID and document its defaults, diagnostics and fixes.
- Preserve the engine's contracts: checker failures skip rules, error
  findings stop execution, facts are collected on request, and CLI fixes
  write only to the root file. Change a contract deliberately and update
  its tests and documentation together.
- Classify fixes honestly. A safe fix must preserve behavior. Formatter
  changes must retain the parsed-program guard and preserve literals,
  comments and declaration order.
- Keep Bend instrumentation in `src/patch.ts`. Preserve argument forwarding,
  exact patch matching and startup compatibility checks. Do not edit
  upstream Bend source or bypass `DriftError` to hide incompatibility.
- Add regression tests for behavior changes beside the relevant code:
  engine and CLI tests in `src/lint.test.ts`, rule tests beside their rules.
  Cover affected edge cases, not private implementation details.
- Run the affected tests while working, then the full suite and type check
  before submitting code changes. For documentation-only edits, check
  examples, local links and `git diff --check`.
- Keep the README concise and describe current behavior. Put contributor
  and implementation details here. Update existing sections instead of
  appending duplicate guidance.

## Writing rules and using the API

### TypeScript rules

A module exports `rules: LintRule[]`. Each rule has a `namespace/name` ID,
which becomes the code of every finding, and a `run(cx, signal)` function
that returns diagnostics. `run` may be async. The signal supports
cancellation; thrown errors and aborts reach the library caller.

Use `cx.diag()` to build a finding. Severity defaults to `warning`.
Rules run in order and can read earlier findings through `cx.prior`.
The first `error` finding ends the run: later findings from that rule and
later rules are omitted. A file that fails Bend's checker runs no rules.

| Context member | Purpose |
| --- | --- |
| `root`, `sources` | The linted file and its imports, with text as stored on disk |
| `book` | The checked Bend program |
| `options` | Rule defaults merged with configuration |
| `facts` | Only the checker facts requested by this rule |
| `prior` | Findings from earlier rules |
| `span(s)` | Maps a Bend span to its source file on disk |
| `walk(tm)` | Traverses Bend terms |
| `binder(fact, v)` | Looks up a variable's binder |
| `show(fact, ty)`, `same(fact, a, b)`, `normal(fact, ty)` | Prints, compares or normalizes types in the fact's scope |
| `uses(fact)` | Lists used variables and their quantities |
| `diag(init)` | Builds a diagnostic with the rule's ID |
| `Bend` | The loaded Bend module; use this rather than importing `bend2/bend.ts` |

The exported [types in src/lint.ts](src/lint.ts) define the full contract.

#### Fixes

A fix has a title, an applicability (`safe`, `suggested` or `dangerous`)
and edits. Each edit replaces a span with text. For example, inside `run`:

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

This example requires a nonempty file. TypeScript span offsets use UTF-16
units. Edits must have integer offsets within the source and must not
overlap within a fix. Use a zero-length span for an insertion.

#### Facts

A fact records a checked term (`tm`), its type (`ty`), book (`bok`), scope
(`ctx`), depth (`dep`), enclosing definition (`def`), demanded quantity
(`qt`), variable uses (`us`) and source span (`spn`, when available).

Facts are collected only when requested. Set `facts: true` for all facts
in the linted file, or supply a filter:

```ts
facts: {
  scope: "file",   // Default. "program" includes imports, but never Base.
  kinds: ["Var"],  // Term kind after stripping annotations: Var, Ref, App, ...
  defs: ["main"],  // Enclosing definition; instances count as the template.
  names: ["foo"],  // Name referenced by a Var or Ref.
}
```

A fact must match every specified list. Omitted or empty lists match all.
The checker discards facts no rule needs, and each rule receives only its
own selection. Request narrow filters to reduce memory use.

Template bodies are checked as written and again for each instance
(`generic~0`, for example), sometimes at the same source spans.
`fact.inst` identifies instance facts. This rule skips them to avoid
duplicate findings:

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

The import assumes the rule is saved under `rules/`.

#### Options

Declare defaults with `options: { tabWidth: 2, breakLines: false }` and
read the merged values through `cx.options`. Defaults define the accepted
keys and primitive types (`number`, `boolean` or `string`). Unknown keys
or type mismatches cause an error. Without declared defaults, the engine
passes options through and the rule must validate them itself.

### Bend rules

A `.bend` rule imports [src/lint.bend](src/lint.bend), which defines the
contract and effects. Save this under `rules/`:

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

`input` contains sources and options. Request facts by returning a filter
such as `Lint.Want{Lint.File{}, ["Var"], [], []}`. Empty lists match all;
`Lint.Program{}` includes imports but excludes Base.

Read facts one at a time with `next_fact` or `fold_facts`:

```python
def step(found: List<&2, Lint.Diag>, +f: Lint.Fact) -> IO(List<&2, Lint.Diag>):
  ...

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  Lint.fold_facts(~List<&2, Lint.Diag>, ~step, [])
```

`step` is passed as a template (`~step`) and takes its fact as `+f`.
Effects provide `view`, `type_of`, `binder`, `same`, `show`, `normal`,
`uses` and `text`. Base's effects are also available. Bend span offsets
count Unicode code points, rather than UTF-16 units.

Read options with `Lint.option_number`, `option_flag` or `option_text`,
each with a default. Numbers must be whole values from 0 to 4294967295 (U32).

A Bend rule is compiled once and runs on Bend's JavaScript runtime.
Use tail recursion for long text or lists; other recursion can overflow
the stack. Streaming facts avoids building a Bend list of all facts.

See [file_length.bend](rules/file_length.bend) and its
[shared helpers](rules/shared.bend) for a working source-text rule.
`COMMA_BEND`, `TYPES_BEND` and `COUNT_BEND` in
[src/lint.test.ts](src/lint.test.ts) provide complete examples of fixes
and checker facts.

### Library API

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
  // applyFixes returns edited text; it does not write to disk.
  console.log(text, skipped);
}
```

Set `BEND_DIR` before importing bend-lint to select a Bend checkout.
Import bend-lint before directly loading Bend so instrumentation can run.
Pass `{ config, signal }` as the third argument to `lint` to supply
configuration or cancellation. Otherwise, configuration is discovered
from the linted file's directory. `position(span)` returns an LSP range.

### JSON output

`--json` writes a JSON object to stdout. Status and failure messages may
still appear on stderr. A finding with a fix has this shape:

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

`def`, `path` and `range` are omitted when unavailable. Positions use
zero-based lines and UTF-16 character offsets. With fix flags, findings
describe the source before fixes are written.

## Implementation and compatibility

### Bend loading

bend-lint loads Bend's source rather than invoking the `bend` executable
to check files. Selection follows this order:

1. `--bend <dir>`, or `BEND_DIR` if the flag is absent. Either a Bend
   checkout or its `bend2` directory works.
2. A surrounding Bend checkout when bend-lint is under `tools/bend-lint`.
3. A downloaded release matching the `bend version` on PATH, or the latest
   release when no installed version is found.

The latest-release lookup is cached for a day. Offline, that lookup falls
back to the newest cached release. An explicitly selected or installed
version still needs its source available.

Downloads contain `bend2/bend.ts`, `comp.ts`, `base.bend` and the `effs/`
files imported by Base. Releases are cached under
`~/.cache/bend-lint/<version>/`; `XDG_CACHE_HOME` overrides the cache root,
and Windows otherwise uses `LOCALAPPDATA`. Cached source is reused on
later runs.

### Instrumentation

| File | Responsibility |
| --- | --- |
| [src/lint.ts](src/lint.ts) | Checker integration, rule execution, diagnostics, fixes, library API and CLI |
| [src/patch.ts](src/patch.ts) | Bend discovery, downloads and source instrumentation |
| [src/lint.bend](src/lint.bend) | Contract for Bend rules |
| [src/effects.js](src/effects.js) | Effects connecting Bend rules to the linter |

Bun patches Bend modules as they load; Bend's files on disk are unchanged.
`term_infer` and `term_check` are renamed and wrapped to record their
results. The wrappers forward every argument to Bend's checker.
The `fs` and `path` adapters normalize real paths to `/` so imports resolve
on Windows; on POSIX they behave like Node's equivalents.
`comp.ts` exports `RUNTIME_MAIN` and `js_sat` to support compiling Bend rules.

A file containing a line exactly `import Base`, as read by
`bend --checkup`, reuses Base checked once per process. Base facts are
excluded from rule requests.

### Compatibility checks

bend-lint is not pinned to a Bend release. It checks the parts it depends on:

- Each source edit must match exactly once, and required compiler exports
  must be declared.
- Type checking checks wrapper signatures against Bend; runtime checks
  verify their expected argument counts.
- A startup self-check inspects the type, depth, scope, quantity, uses and
  span recorded for `x` in `def id(x: N) -> N: x`.

A detected mismatch raises `DriftError` and stops loading. This applies
to both checkouts and downloaded releases. The test suite checks additional
behavior, including drift against the selected checkout's own tests.
