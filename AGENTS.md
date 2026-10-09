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

## 2. Code

bend-lint is currently written in TypeScript. It lints Bend code using rules
written in Bend or TypeScript. The TypeScript implementation and TypeScript
rules must also pass this repository's linting and type checks.

- You are rarely, if ever, smarter than the linter. Do not try to workaround rules or suppress them without asking me.
- Deterministic tooling ALWAYS wins over skill suggestions.
- After every change, run, in this order: thermonuclear-code-review(files above 1000 may be ok though. Ask me before splitting), cyclomatic-complexity(only split if the helper function has >1 caller), erasure and then, finally, linting and typecheck. Repeat until no more issues related to your change have been identified.
- For new rules, always add behavior regression tests without asking. For other changes, do NOT write premature tests, always ask me. If they are testing implementation details, don't even suggest them.
- I prefer functional-like, mutation-less code in the following layout: imports, types, constants, functions(always arrow functions with const), side-effectful code. separate sections by comment.
- Conceptual convergence: do NOT create multiple representations for the same thing across the codebase.
- Each fact has one location. Do not repeat in a comment what the docs state or clearly imply.
- Never use barrel exports or re-exports (`export { x } from "..."` or `export * from "..."`). Import directly from the module that defines and exports the code.

## Setup

```sh
bun install
BEND_DIR=../bend bun test
bun run typecheck
bun run lint
bun run format:check
git diff --check
```

- Type checking and the drift tests need a Bend checkout.
- `tsconfig.json` maps `bend2/*` to `../bend/bend2`. If your checkout is
  somewhere else, change that, and set `BEND_DIR` to the same place.
- Without `BEND_DIR`, the drift tests skip.
- `bun test` does not type check. `bun run typecheck` does, for this repo's
  files only, not Bend's.

## Files

| File                   | Holds                                             |
| ---------------------- | ------------------------------------------------- |
| `src/lint.ts`          | rule runner, findings, fixes, library API, CLI    |
| `src/seam.ts`          | everything about Bend's internals (see Internals) |
| `src/suppress.ts`      | `# bend-lint:` directives                         |
| `src/result.ts`        | the `Result` the entry points return              |
| `src/bend/lint.bend`   | what a Bend rule imports                          |
| `src/bend/effects.js`  | the effects a Bend rule calls                     |
| `src/bend/sample.bend` | the program the startup self-check reads          |
| `rules/`               | bundled rules, one per file, with their tests     |

## How a run works

1. **Pick the checks.** With `imports`, the named file's own check. Else
   the check of each config entry that imports the named file, or, if none
   does (or each such check fails), the named file's own check.
2. **Pick the linted files:** the named file, and with `imports` every other
   file the check read, Base aside.
3. **Run the rules** in the given order. Each rule runs as one of two kinds:

| Rule                    | Runs                 | `cx.root`        | Reports in      | Names                    |
| ----------------------- | -------------------- | ---------------- | --------------- | ------------------------ |
| file scope, or no facts | once per linted file | that file        | that file only  | as that file spells them |
| `scope: "program"`      | once per check       | the check's root | any linted file | the check's              |

4. A finding in another file:
   - from a file rule: the rule crashes;
   - from a program rule, outside the linted files: dropped.
5. With several checks, a program rule's runs agree on a finding when it has
   the same code, severity and span. The rule's `entries` says what stands:
   `"some"` (default) keeps a finding one run makes, `"every"` one all make.
   When an entry that imports the named file fails its check, no `"every"`
   rule runs.
6. A finding without a span counts in the file its run was for.
7. Directives are read from the linted files only. An unused `disable` or
   unmet `expect` is reported only where its rule ran to its end.
8. The result lists findings file by file, in the check's order. Directive
   findings come last.

"As that file spells them" means as the file writes them in its source: its
own definitions bare (`keep`), an import's through its alias (`U.N`). This
holds for `owner`, the `defs` and `names` filters, `shape().name`,
`body()` and `show()`. So a file gets the same names whichever check it is
read from.

## Behavior that must not break

Change the tests and these docs with any of these:

- A file that fails Bend's check gets only the rules that ask for no facts.
- When an entry that imports the file fails its check, no `entries: "every"`
  rule runs.
- A `bend/check` error is shown even when it is in an import.
- No finding ends the run. A rule that throws is a `bend-lint/rule-crash`
  finding at the start of the file its run was for.
- Facts are collected only when a rule asks for them.
- A file gets the same file-rule findings alone, through `imports`, or
  through an entry.
- Findings appear only in linted files, also with entries.
- Fixes are written to the linted files. A fix that edits two files is
  skipped.

## How we work

- Small, focused changes. The PR says what was wrong, what happens now, and
  how you checked.
- Style is what the file already does: two spaces, explicit types on exports,
  `import type` for types.
- Pull a function out only when something else calls it. Long files are fine.
- Use the helpers that exist.
- When you change something, delete the code, comments and docs it made
  obsolete.
- A `safe` fix must keep what the program does.
- Everything that touches Bend's internals goes in `src/seam.ts`.
- Every behavior change gets a regression test:
  - engine and CLI: `src/lint.test.ts`;
  - a rule: next to the rule.
- Test what it does, not how.
- Before you send code, run the full suite and `typecheck`.
- For docs, check that the examples run and the links resolve.
- README.md is for users and stays short. Internals go here. Edit the
  section that exists instead of adding a second one.

## Writing rules

A rule has an ID like `namespace/name`. That ID is the `code` of its
findings. Make rules idempotent.

### TypeScript

A module exports `rules: LintRule[]`.

```ts
import type { LintRule } from "../src/lint.ts";

export const rules: LintRule[] = [
  {
    id: "demo/var-types",
    facts: { kinds: ["Var"] },
    run: (cx) =>
      cx.facts.map((fact) =>
        cx.diag({
          message: "type: " + cx.show(fact.type),
          severity: "hint",
          span: fact.span,
          fact,
        }),
      ),
  },
];
```

(Saved under `rules/`.)

- `run(cx)` returns findings, and can be async.
- `facts`, `options` and `entries` are optional. `entries` (`"some"` or
  `"every"`) matters only for a rule of program scope (see How a run works).
- Build findings with `cx.diag()`. Severity defaults to `warning`.
- A rule that throws, or returns a bad fix, gives `bend-lint/rule-crash`.
- An abort reaches whoever called the library.

What is on `cx`:

| Field                    | What                                                        |
| ------------------------ | ----------------------------------------------------------- |
| `root`                   | the file this run is for                                    |
| `sources`                | every file the check read, text as on disk                  |
| `options`                | the defaults, with the config's values                      |
| `facts`                  | the facts this rule asked for (none if it asked for none)   |
| `prior`                  | what earlier rules found in the files this run reaches      |
| `signal`                 | aborts with the run                                         |
| `body(name)`             | a def's checked body, as a node                             |
| `shape(node)`            | a node's kind, name, span and children                      |
| `nodes(root)`            | a node and every node under it, parents first               |
| `parent(node)`           | a node's parent                                             |
| `strip(node)`            | a node without its annotations                              |
| `fact(node)`             | the node's fact, if this rule asked for it                  |
| `binder(fact)`           | the declared type of the variable a `Var` uses              |
| `uses(fact)`             | the variables a term uses, with how many times              |
| `show`, `same`, `normal` | print, compare and normalize types                          |
| `sameDeclarations(text)` | whether `text` declares what `root` declares                |
| `diag(init)`             | a finding with this rule's ID                               |
| `unstable`               | Bend's own objects: `Bend`, the checked `book`, `raw(fact)` |

- Only code that uses `unstable` breaks when Bend changes.
- The exported types in [src/lint.ts](src/lint.ts) are the full contract.
- Types and nodes are handles. Only `cx` can read them.

#### Fixes

A fix has a title, an applicability (`safe`, `suggested`, `dangerous`) and
edits. An edit replaces a span with text.

```ts
const span = { file: cx.root, beg: 0, end: 1 };
return [
  cx.diag({
    message: "Replace the first character with a space.",
    span,
    fixes: [
      { title: "Replace character", applicability: "suggested", edits: [{ span, text: " " }] },
    ],
  }),
];
```

(Needs a file that is not empty.)

- A span is a source from `cx.sources` and two offsets.
- Offsets are whole UTF-16 units inside the source.
- A span of length zero inserts.
- The edits of one fix must not overlap.

#### Nodes

A node is one term of a def's checked body.

```ts
const matches = cx.nodes(cx.body("main")!).filter((n) => cx.shape(n).kind === "Mat");
```

- Kinds and child order are Bend's. A rule that reads them can need changes
  when Bend's terms change. Facts alone do not.
- `nodes` and `parent` walk once per check, for all rules.

#### Facts

A fact is what the checker found for one node:

| Field      | What                                                    |
| ---------- | ------------------------------------------------------- |
| `node`     | the node                                                |
| `owner`    | the def whose body holds it                             |
| `quantity` | how often it is demanded: `erased`, `once` or `many`    |
| `type`     | the type it was checked as                              |
| `span`     | the source it checked, annotations included, if any     |
| `inst`     | whether it comes from a template instance (`generic~0`) |

Ask for facts with `facts: true` (every fact of `root`), or a filter:

```ts
facts: {
  scope: "file",   // default: facts of root. "program": every file the check read, not Base
  kinds: ["Var"],  // term kind, annotations stripped: Var, Ref, App, ...
  defs: ["main"],  // the def that holds the term; an instance counts as its template
  names: ["U.foo"], // the name a Var or Ref points to, as root spells it
  instances: true, // also template instances' facts; scope "program" only
}
```

- A fact must match every list given. A missing or empty list matches all.
- Keep filters narrow. Memory grows with the number of facts.
- A template is checked as written, and again for each instance, sometimes
  at the same span.
- Instances depend on who uses a template, so they are a program fact.

#### Options

Each option is a JSON Schema with a `default`. Use `defineRule` to infer
`cx.options` from the schemas:

```ts
import { defineRule } from "../src/lint.ts";
import type { LintRule } from "../src/lint.ts";

export const rules: LintRule[] = [
  defineRule({
    id: "demo/width",
    options: {
      tabWidth: { type: "integer", minimum: 1, default: 2 },
      wrapAtWidth: { anyOf: [{ type: "integer", minimum: 1 }, { enum: ["never"] }], default: 100 },
    },
    run: (cx) => [
      cx.diag({
        message:
          "indent: " +
          cx.options.tabWidth.toFixed(0) +
          ", width: " +
          (cx.options.wrapAtWidth === "never" ? "unlimited" : cx.options.wrapAtWidth.toFixed(0)),
      }),
    ],
  }),
];
```

The schemas stay plain data. `tabWidth` is a `number`; `wrapAtWidth` is
`number | "never"`. A schema known only at run time cannot give TypeScript
these types. Defaults fill missing options; supplied values are checked
with TypeBox.

- `cx.options` has every declared option.
- Unknown keys, and values that do not match, are config errors.
- A rule without `options` takes none.

### Bend

A `.bend` rule imports [src/bend/lint.bend](src/bend/lint.bend). This one
reports nothing (saved under `rules/`):

```python
import Base
import ../src/bend/lint.bend as Lint

def id() -> String:
  "demo/nothing"

def facts() -> Lint.Want:
  Lint.NoFacts{}

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  IO.pure(List<&2, Lint.Diag>, [])

def main() -> IO(Unit):
  Lint.serve(run)
```

The input is `Lint.Input{root, sources, options, prior}`, as on `cx`.
`prior` holds `Lint.Found{code, diag}`.

Findings:

- `Lint.diag(severity, message, span)` makes a finding with no fix.
- `Lint.Diag{severity, message, span, fixes, about}` adds fixes, or the fact
  it is about (`about`).

Facts:

- Return a filter from `facts()`, for example
  `Lint.Want{Lint.File{}, ["Var"], [], [], False{}}`.
- Empty lists match all. `Lint.Program{}` adds the other files.
- `True{}` at the end adds template instances. It needs `Lint.Program{}`.
- A rule of program scope can define `entries() -> Lint.Entries`:
  `Lint.SomeEntry{}` (the default) or `Lint.EveryEntry{}`.
- Read facts one at a time with `next_fact`, or fold:

```python
def step(found: List<&2, Lint.Diag>, +f: Lint.Fact) -> IO(List<&2, Lint.Diag>):
  ...

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  Lint.fold_facts(~List<&2, Lint.Diag>, ~step, [])
```

- `step` goes in as a template (`~step`) and takes the fact as `+f`.
- A fact is `Lint.Fact{node, owner, inst, quantity, term, span}`. `term` is
  its type.

Effects: `body`, `shape`, `nodes`, `parent`, `strip`, `fact`, `binder`,
`uses`, `same`, `show`, `normal`, `text`, `same_declarations`, `aborted`,
plus Base's own I/O (files, processes, sockets).

- `aborted` lets a long rule stop early. bend-lint cannot stop a Bend rule.
- While a Bend rule waits on I/O, bend-lint waits too.

Options:

```python
def options() -> List<&2, Lint.Declared>:
  [Lint.Declared{"maxLines", Lint.Num{500}, Lint.NumberOption{0, 4294967295}}]
```

| Spec                             | Accepts                                   |
| -------------------------------- | ----------------------------------------- |
| `NumberOption{minimum, maximum}` | a whole number (a U32)                    |
| `FlagOption{}`                   | a boolean                                 |
| `TextOption{choices}`            | text, one of `choices` unless it is empty |
| `AnyOption{specs}`               | what one of `specs` accepts               |

Read them with `Lint.option_number`, `option_flag` and `option_text`, or
`Lint.find` for the `Lint.Value`.

Good to know:

- Spans count Unicode code points here. TypeScript counts UTF-16 units.
- The rule is compiled once, and again only when its text changes.
- It runs on Bend's JavaScript runtime. Use tail recursion over long text or
  lists, to stay inside the stack.
- Streaming facts saves building a list of all of them.
- A `String` is a JS string at run time: `++` and `String.length` are
  native; a match on `SCon` reads one character and slices off the rest.
- A branch that uses a string or character its match took apart gets it
  rebuilt: a string as a rope of the whole rest, which the next read copies.
  Take the value twice and match one copy (`keep` in
  [rules/format.bend](rules/format.bend)).
- `Bool.pick` evaluates both branches. Match on a `Bool` parameter when a
  branch is costly.

Examples: [rules/file_length.bend](rules/file_length.bend), and the
formatter, [rules/format.bend](rules/format.bend). In
[src/lint.test.ts](src/lint.test.ts), `COMMA_BEND`, `TYPES_BEND`,
`COUNT_BEND` and `PARITY_BEND` cover fixes, facts, earlier findings, the
guard and union options.

## As a library

From a file in the repo root:

```ts
import { applyFixes, createLinter } from "./src/lint.ts";
import { ERROR, ERROR_METADATA } from "./src/result.ts";

const made = await createLinter();
if (ERROR in made) throw new Error(made[ERROR][ERROR_METADATA].message);
const linter = made.OK;
const rules = await linter.loadRules(["rules/format.bend", "rules/file_length.bend"]);
if (ERROR in rules) throw new Error(rules[ERROR][ERROR_METADATA].message);
const res = await linter.lint("src/bend/sample.bend", rules.OK);
if (ERROR in res) {
  console.error(res[ERROR].type, res[ERROR][ERROR_METADATA].message);
} else {
  console.log(res.OK.diags.map(linter.render));
  for (const file of res.OK.linted) {
    const { text, skipped, elsewhere } = applyFixes(file, res.OK.diags);
    // text is the fixed source; saving it is up to you
    console.log(file.path, text, skipped, elsewhere);
  }
}
```

Entry points return a `Result` ([src/result.ts](src/result.ts)) and do not
throw:

- `{ OK: value }`, or
- `{ ERROR: { type, ERROR_METADATA: { message, cause } } }`.
- `type` is `config`, `rule-module`, `bend-missing`, `drift`, `aborted` or
  `internal`.
- `unwrap` gives the value, or throws the message.

An `OK` lint result can hold error findings. Check `diags` for severity
`error`. A failed Bend check, a missing file or a rule crash is a finding,
not an `ERROR` result.

`createLinter({ bend })`:

- loads the Bend that `bend`, `$BEND_DIR` or the search in Internals picks;
- loads once per folder asked for;
- must run before anything else loads Bend, so the patch comes first.

`linter.lint(file, rules, options)`:

| Option    | What                                                         |
| --------- | ------------------------------------------------------------ |
| `imports` | lint every file the check reads too, Base aside              |
| `config`  | the config; without it, the nearest one is read              |
| `signal`  | aborts the run                                               |
| `unsaved` | file paths mapped to editor text not saved yet, for this run |

- The result has `diags`, `suppressed`, `sources`, `root` (the named
  file), `linted`, `facts` and `unstable`. With entries, `sources`, `facts`
  and `unstable` are those of the first check the rules read.
- Runs at the same time wait for each other's check. Rules still run side
  by side.
- `lint` also runs the rules of the config's `load` files, after the given
  ones. The config can turn off a given rule or change its options and
  severity. Pass `config: {}` to skip config discovery.
- `position(span)` gives an LSP range.

Config:

- `findConfig(file)` looks in the file's folder, then each parent, for
  `bend-lint.json`, `.js` or `.ts`. The closest folder wins, then JSON, JS,
  TS.
- `readConfig(file)` loads the path you give it. It makes `load` and
  `entries` absolute, from the config's folder.
- JS and TS configs export a named `config`, load through Bun (cache
  included), and can import relative files.

`linter.loadRules(files)` loads rule files: a module's `rules`, or a Bend
rule. Loaded rules belong to the linter that loaded them. Use them only
with that linter. The same holds for `linter.bendRule(file)`.

## JSON output

`--json` prints one JSON object on stdout, for all the files linted. Status
and failure messages can still go to stderr. A finding with a fix:

```json
{
  "ok": true,
  "findings": [
    {
      "code": "style/example",
      "severity": "warning",
      "message": "Replace this character.",
      "def": "main",
      "path": "/abs/example.bend",
      "range": { "start": { "line": 2, "character": 0 }, "end": { "line": 2, "character": 1 } },
      "fixes": [
        {
          "title": "Replace character",
          "applicability": "suggested",
          "edits": [
            {
              "path": "/abs/example.bend",
              "range": {
                "start": { "line": 2, "character": 0 },
                "end": { "line": 2, "character": 1 }
              },
              "text": " "
            }
          ]
        }
      ]
    }
  ],
  "suppressed": []
}
```

- `suppressed` has the same shape: the findings a directive covers. They do
  not count for `ok`.
- `def`, `path` and `range` are left out when there is nothing to put.
- Lines start at 0. Characters are UTF-16 units.
- With a fix flag, findings describe the source before the fixes.

## Internals

All of this lives in `src/seam.ts`.

### Finding Bend

1. `--bend <dir>`, or `$BEND_DIR` without the flag: a checkout or its
   `bend2` folder.
2. The checkout around bend-lint, when it is at `tools/bend-lint`.
3. A downloaded release: the one `bend version` names, or the latest if
   Bend is not installed.

- The latest-release lookup is cached for a day. Offline, the newest cached
  release is used.
- A version picked by flag or PATH needs its source.
- A download is `bend2/bend.ts`, `comp.ts`, `main.ts`, `safe.ts`,
  `base.bend` and the `effs/` files Base imports.
- It goes to `~/.cache/bend-lint/<tag>/bend2` (`XDG_CACHE_HOME`, or
  `LOCALAPPDATA` on Windows) and is reused.

### Patching

Bun patches Bend's modules while they load:

- `term_infer` and `term_check` are wrapped. The wrappers pass every
  argument on, and report what they return to `hook.see`.
- The hook is global, so checks run one at a time.
- `fs` and `path` in `bend.ts` and `main.ts` are swapped for adapters that
  turn real paths into `/` paths, so imports resolve on Windows.
- `comp.ts` exports `RUNTIME_MAIN` and `js_sat`, for compiling Bend rules.
- `main.ts` exports `book_read`, `book_err` and `Check_Fail`. A file is read
  and checked by the same code as `bend <file>`.

A file with a line that is exactly `import Base` reuses one Base, checked
once per process. Base facts are never given to rules.

A failed check is one `bend/check` finding: Bend's message (expected and
observed, the names in scope, Bend's note) without the location.

### One check, many files

Bend names each file by its path from the check root's folder. So the same
file has different names under different roots. bend-lint does not copy
that rule. A file rule's names go through Bend's own `name_show`, with the
file's own alias table from the check. The same file then spells the same
way under any root. Program rules keep the check's names, which are unique
in the program.

`sameDeclarations` parses each file against the book as Bend had it when it
parsed that file. Declarations parsed after it are hidden. Writes go to a
layer of their own, so the book never changes and is never copied.

Per check, these are made once, when first asked: walks and parents, each
file's spelling and guard, aliases, the book's order, and the facts by file.

An entry's check that passed is kept, one per entry, and given again to the
next `lint` while the bend2 folder, the filters and the text of every file
it read (unsaved text included) are unchanged. To tell, as git does:

- Each file is stamped (size, change times, file ID) before it is read.
- A file whose stat still matches its stamp is unchanged, unless it changed
  within 2 s of the stamp. Then a later write could leave the stat the
  same, so the file is read and compared, and stamped again if it is
  unchanged.
- Unsaved text is compared as text.

### Staying compatible

No Bend version is pinned. On every load, for checkouts and downloads:

- Each source edit must match exactly once.
- The compiler exports and runtime names bend-lint needs must be there once.
- Wrapper signatures are checked at type-check time, and argument counts at
  run time.
- `book_read`, `book_err` and `Check_Fail` must take the arguments bend-lint
  gives them.
- A self-check runs `src/bend/sample.bend`. In `def id(x: N) -> N: x`, `x`
  must have the right type, binder, quantity, uses and span, and each
  wrapper must report the terms only it sees.

Any mismatch throws a drift error (`name` is `DriftError`, and `e[DRIFT]` is
true, with `DRIFT` from `src/seam.ts`), and loading stops. The tests add more
checks, including Bend's own tests from the chosen checkout.
