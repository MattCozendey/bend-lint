# AGENTS

How to change this repo, for humans and agents. How to use the tool is in
[README.md](README.md).

The rules in sections 0 to 2 have priority over all other instructions,
except safety rules.

## 0. Core

- If a skill does not load, read its file in `.agents/skills/`.
- Do not change any `.md` file without asking me.

## 1. Communication

- Speak the language you are spoken to in.
- Be short, but do not drop information. Use ASD-STE100 or similar, with the
  `i-have-adhd` skill in mind.
- Number your questions. Continue the numbers across the whole response.
- Repeat each open question in each response until I answer it or tell you to
  use common sense.

## 2. Code

bend-lint is written in TypeScript. It lints Bend code with rules written in
Bend or TypeScript. The TypeScript code, rules included, must pass this repo's
lint and type check.

### Tools

- You are rarely, if ever, smarter than the linter. Do not work around or
  suppress a lint rule without asking me.
- Deterministic tools always win over skill suggestions.
- After every change, run these in order, and repeat until they find nothing
  more about your change:
  1. `thermo-nuclear-code-quality-review`. A file over 1000 lines can be fine.
     Ask me before you split one.
  2. `cyclomatic-complexity`. Extract a helper only when it has more than one
     caller.
  3. `erasure`.
  4. `bun run lint` and `bun run typecheck`.

### Tests

- A new rule gets behavior tests, without asking, in its test file. See
  [Names](#names).
- Any other test, `src/lint.test.ts` included, needs my approval first.
- Never test implementation details. Do not even suggest such tests.

### Style

- Write functional code without mutation.
- Lay out each file in this order, with a comment before each section:
  imports, types, constants, functions, side effects.
- Write functions as `const` arrow functions.
- Match the file: two spaces, explicit types on exports, `import type` for
  types.
- Give each concept one representation in the whole codebase.
- Give each fact one location. A comment does not repeat what the docs state
  or clearly imply.
- Do not use barrel exports or re-exports (`export { x } from "..."`,
  `export * from "..."`). Import from the module that defines the code.
- Use the helpers that exist.
- Long files are fine.
- When you change something, delete the code, comments and docs it made
  obsolete.

### Where code goes

- Everything that touches Bend's internals goes in `src/seam.ts`.
- A `safe` fix must keep what the program does.

### Changes

- Keep each change small and focused.
- A PR says what was wrong, what happens now, and how you checked.
- Before you send code, run the full suite, `bun run typecheck` and
  `bun run lint`.
- For docs, check that the examples run and the links resolve.
- README.md is for users and stays short. Internals go here.
- Edit the section that exists. Do not add a second one on the same topic.

## Setup

```sh
bun install
BEND_DIR=/path/to/bend bun test
bun run typecheck
bun run lint
bun run format:check
git diff --check
```

- `bun run typecheck` and `bun run lint` first link `.bend2` to the Bend that
  `BEND_DIR` or the download picks.
- `bun test` does not type check.
- `bun run typecheck` checks this repo's files only, not Bend's.
- The drift tests need a Bend checkout. Without `BEND_DIR`, they skip.
- CI (`.github/workflows/ci.yml`) runs all of these on Linux and Windows:
  - pushes and pull requests: against the pinned Bend release;
  - the daily run: against Bend's main.

## Files

| File                  | Holds                                                           |
| --------------------- | --------------------------------------------------------------- |
| `src/lint.ts`         | the rule runner, findings, fixes, library API and CLI           |
| `src/seam.ts`         | everything about Bend's internals (see [Internals](#internals)) |
| `src/suppress.ts`     | `# bend-lint:` directives                                       |
| `src/result.ts`       | the `Result` that entry points return                           |
| `src/bend/lint.bend`  | what a Bend rule imports                                        |
| `src/bend/effects.js` | the effects a Bend rule calls                                   |
| `samples/`            | `.bend` files to lint by hand                                   |
| `samples/sample.bend` | the program the startup self-check reads                        |
| `rules/`              | bundled rules, one folder per namespace, each with its tests    |
| `rules/shared.ts`     | logic that more than one TypeScript rule uses                   |
| `rules/shared.bend`   | logic that more than one Bend rule uses                         |

## How a run works

You lint one file: the **named file**.

1. **Pick the checks.** A check is one run of Bend's type checker, from one
   root file.
   - With `imports`: one check, from the named file.
   - Else: one check from each config entry that imports the named file.
   - If no entry imports it, or each such check fails: one check, from the
     named file.
2. **Pick the linted files.** Findings appear only in these.
   - Without `imports`: the named file.
   - With `imports`: every file the check read, except Base and hub packages.
3. **Run the rules**, in the given order. Each rule has a scope. See
   [Rule scope and `imports`](#rule-scope-and-imports).
4. **Merge the checks.** With several checks, a program rule runs once per
   check. Two runs find the same finding when it has the same code, severity
   and span. The rule's `entries` decides which findings stay:
   - `"some"` (the default): a finding that one run makes;
   - `"every"`: a finding that all runs make. When an entry that imports the
     named file fails its check, no `"every"` rule runs.
5. **Place the findings.** A finding without a span goes to the file its run
   was for.
6. **Read the directives**, from the linted files only. An unused `disable`
   or an unmet `expect` is reported only where its rule ran to its end. A rule
   that crashed did not.
7. **List the result**, file by file, in the check's order. Directive
   findings come last.

### Rule scope and `imports`

Two settings decide what happens:

- The rule's **scope** decides what the rule sees, and where it may report.
- **`imports`** decides which files are linted: where you see findings.

| Scope              | Runs                 | `cx.root`        | Sees                                          | May report in | Names                    |
| ------------------ | -------------------- | ---------------- | --------------------------------------------- | ------------- | ------------------------ |
| file (the default) | once per linted file | that file        | that file                                     | that file     | as that file spells them |
| program            | once per check       | the check's root | the whole check, except Base and hub packages | any file      | the check's              |

Example: `main.bend` imports `util.bend`. You lint `main.bend`.

|              | without `imports` (linted: `main`)                                       | with `imports` (linted: `main`, `util`)                            |
| ------------ | ------------------------------------------------------------------------ | ------------------------------------------------------------------ |
| file rule    | 1 run, on `main`. Sees `main`. Shows findings in `main`.                 | 2 runs, one per file. Each sees its file and shows findings in it. |
| program rule | 1 run. Sees `main` and `util`. Shows findings in `main`. Drops `util`'s. | 1 run. Sees `main` and `util`. Shows findings in both.             |

- A rule that asks for no facts is a file rule.
- A file rule gives a file the same findings in every mode.
- A program rule does not add linted files. Only `imports` does.
- A file rule can read every file's text in `cx.sources`, but may report only
  in `root`. A finding in another file is a bug in the rule. The run crashes,
  and its other findings are discarded.
- A program rule's finding in a file that is not linted is not a bug. It is
  dropped, because you did not ask to see that file.

### Names

"As that file spells them" means as the file writes them in its source:

- its own definitions bare (`keep`);
- an import's definitions through the import's alias (`U.N`).

This holds for `owner`, the `defs` and `names` filters, `shape().name`,
`body()` and `show()`. So a file gets the same names from every check that
reads it.

## Behavior that must not break

If you change any of these, change the tests and these docs with it:

- A file that fails Bend's check gets only the rules that ask for no facts.
- When an entry that imports the file fails its check, no `entries: "every"`
  rule runs.
- A `bend/check` error is shown, also when it is in an import.
- No finding ends the run. A rule that throws is a `bend-lint/rule-crash`
  finding at the start of the file its run was for.
- Facts are collected only when a rule asks for them.
- A file gets the same file-rule findings alone, through `imports`, or
  through an entry.
- Findings appear only in linted files, also with entries.
- Fixes are written to the linted files. A fix that edits two files is
  skipped.

## Writing rules

### Names

A rule ID is parts separated by `/`. Each part is kebab-case. The last part
is the rule's name. The parts before it are namespaces, and namespaces can
nest. The folders under `rules/` mirror the ID.

| What      | Form                                 | Example                       |
| --------- | ------------------------------------ | ----------------------------- |
| rule ID   | `namespace/…/name`                   | `layout/canon-import-path`    |
| rule file | `rules/namespace/…/name.ts`, `.bend` | `rules/layout/format.bend`    |
| test file | `rules/namespace/…/name.test.ts`     | `rules/layout/format.test.ts` |

- The rule ID is the `code` of its findings.
- Make rules idempotent.

### Shared logic

- Logic that more than one rule uses goes in `rules/shared.ts` or
  `rules/shared.bend`. Rules import it from there, and keep no copy.
- These two files are not rules. Do not load them as rules.

### TypeScript

A module exports `rules: LintRule[]`. Saved as `rules/demo/var-types.ts`:

```ts
import type { LintRule } from "../../src/lint.ts";

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

- `run(cx)` returns findings. It can be async.
- `facts`, `options` and `entries` are optional.
- `entries` (`"some"` or `"every"`) matters only for a program rule. See
  [How a run works](#how-a-run-works), step 4.
- Build findings with `cx.diag()`. The severity defaults to `warning`.
- A rule that throws, or returns a bad fix, gives `bend-lint/rule-crash`.
- An abort reaches whoever called the library.

What is on `cx`:

| Field                    | What                                                                     |
| ------------------------ | ------------------------------------------------------------------------ |
| `root`                   | the file this run is for                                                 |
| `sources`                | every file the check read, text as on disk                               |
| `options`                | the defaults, with the config's values                                   |
| `facts`                  | the facts this rule asked for (none if it asked for none)                |
| `prior`                  | what earlier rules found in the files where this run's findings can show |
| `signal`                 | aborts with the run                                                      |
| `declarations(file?)`    | named declarations and bindings, with their references                   |
| `body(name)`             | a def's checked body, as a node                                          |
| `shape(node)`            | a node's kind, name, span and children                                   |
| `nodes(root)`            | a node and every node under it, parents first                            |
| `parent(node)`           | a node's parent                                                          |
| `strip(node)`            | a node without its annotations                                           |
| `fact(node)`             | the node's fact, if this rule asked for it                               |
| `binder(fact)`           | the declared type of the variable a `Var` uses                           |
| `uses(fact)`             | the variables a term uses, with how many times                           |
| `show`, `same`, `normal` | print, compare and normalize types                                       |
| `sameDeclarations(text)` | whether `text` declares what `root` declares                             |
| `diag(init)`             | a finding with this rule's ID                                            |
| `unstable`               | Bend's own objects: `Bend`, the checked `book`, `raw(fact)`              |

- Only code that uses `unstable` can break when Bend changes.
- The exported types in [src/lint.ts](src/lint.ts) are the full contract.
- Types and nodes are handles. Only `cx` can read them.

#### Fixes

A fix has a title, an applicability (`safe`, `suggested` or `dangerous`) and
edits. An edit replaces a span with text. For a file that is not empty:

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

- A span is a source from `cx.sources` and two offsets.
- Offsets are whole UTF-16 units inside the source.
- A span of length zero inserts.
- The edits of one fix must not overlap.

#### Declarations

`cx.declarations()` returns the source's declarations, in file and offset
order. It does not collect checker facts. Each record has `kind`, `name`,
`span`, `references`, and the optional `owner`, `loads`, `fills` and `type`.

| TypeScript kind | Bend kind            | Declares                               |
| --------------- | -------------------- | -------------------------------------- |
| `import`        | `Lint.Import{}`      | an import alias, or `Base`             |
| `def`           | `Lint.Definition{}`  | a def or law                           |
| `type`          | `Lint.Datatype{}`    | a datatype                             |
| `constructor`   | `Lint.Constructor{}` | a datatype's constructor               |
| `parameter`     | `Lint.Parameter{}`   | a parameter or named type binder       |
| `variable`      | `Lint.Variable{}`    | a local, lambda, pattern or do binding |
| `field`         | `Lint.Field{}`       | a constructor field                    |

The record:

- `span` covers the written name.
- `owner` is the enclosing def or datatype. Bindings and constructors have
  one. Top-level declarations and imports do not.
- `loads`, on an import, is the file it loads: a source of the check, Base
  and hub packages included.
- `fills`, on a def, is `true` when the def fills a law of another file
  (`def B.L(x):`). A fill of a law of its own file has no `fills`.
- `type` is the written type, as a type handle: a def's or datatype's
  parameter's, a field's, or a def's or datatype's after its parameters.
  Variables, binders inside terms (`@x: A ->`, lambdas) and the parameters
  of a law's fill have none.

References:

- Each reference has a `span` and the `owner` of its enclosing declaration.
- A reference span can cover an expression, when syntax supplies an implicit
  use.
- References include types, proofs, patterns, operators and template
  arguments.
- Self-references are kept.
- Template instances do not repeat the uses in the source.
- A proof fill counts as a use of the alias through which it names its law.

Identity:

- Shadowed bindings are separate records.
- A law and its proof fill are separate records, also when their names
  agree.
- So do not identify bindings by name.

Scope:

- File rule: declarations and references come only from `root`, with that
  file's spelling.
- Program rule (`facts.scope: "program"`): they come from every checked
  source except Base and hub packages, with the check's names. An import of Base is still
  listed, with references to its symbols.
- `cx.declarations(file)`, with a source of the check, gives that file's
  declarations as that file spells them, in any scope: what a file rule on
  it gets. Base, or a file the check did not read, gives an empty list.
- A failed check gives an empty list.
- Each checked source is parsed once, when first asked, without another type
  check, disk writes or import fetching.

#### Nodes

A node is one term of a def's checked body.

```ts
const matches = cx.nodes(cx.body("main")!).filter((n) => cx.shape(n).kind === "Mat");
```

- Kinds and child order are Bend's. A rule that reads them can need changes
  when Bend's terms change. Facts alone do not.
- `nodes` and `parent` walk each check once, for all rules.

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

Ask for facts with `facts: true` (every fact of `root`), or with a filter:

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
- Instances depend on who uses a template, so they are program facts.

#### Options

Each option is a JSON Schema with a `default`. Use `defineRule` to get the
types of `cx.options` from the schemas. Saved as `rules/demo/width.ts`:

```ts
import { defineRule } from "../../src/lint.ts";
import type { LintRule } from "../../src/lint.ts";

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

- Here `tabWidth` is a `number`, and `wrapAtWidth` is `number | "never"`.
- The schemas stay plain data. A schema known only at run time cannot give
  TypeScript these types.
- `cx.options` has every declared option. Defaults fill the missing ones.
- TypeBox checks the given values. An unknown key, or a value that does not
  match, is a config error.
- A rule without `options` takes none.

### Bend

A `.bend` rule imports [src/bend/lint.bend](src/bend/lint.bend). This one,
saved as `rules/demo/nothing.bend`, reports nothing:

```python
import Base
import ../../src/bend/lint.bend as Lint

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

#### Findings

- `Lint.diag(severity, message, span)` makes a finding with no fix.
- `Lint.Diag{severity, message, span, fixes, about}` also takes fixes, and
  the fact the finding is about (`about`).

#### Facts

- Return a filter from `facts()`, for example
  `Lint.Want{Lint.File{}, ["Var"], [], [], False{}}`.
- An empty list matches all.
- `Lint.Program{}` instead of `Lint.File{}` adds the other files.
- `True{}` at the end adds template instances. It needs `Lint.Program{}`.
- A program rule can define `entries() -> Lint.Entries`: `Lint.SomeEntry{}`
  (the default) or `Lint.EveryEntry{}`.
- A fact is `Lint.Fact{node, owner, inst, quantity, term, span}`. `term` is
  its type.
- Read facts one at a time with `next_fact`, or fold them:

```python
def step(found: List<&2, Lint.Diag>, +f: Lint.Fact) -> IO(List<&2, Lint.Diag>):
  ...

def run(input: Lint.Input) -> IO(List<&2, Lint.Diag>):
  Lint.fold_facts(~List<&2, Lint.Diag>, ~step, [])
```

- `step` goes in as a template (`~step`), and takes the fact as `+f`.

#### Effects

`declarations`, `declarations_of`, `body`, `shape`, `nodes`, `parent`, `strip`, `fact`,
`binder`, `uses`, `same`, `show`, `normal`, `text`, `same_declarations` and
`aborted`, plus Base's own I/O (files, processes, sockets).

- `Lint.declarations()` returns `IO(List<&2, Lint.Declaration>)`, in one
  effect. Read the list with ordinary Bend code.
- `Lint.declarations_of(path)` is `cx.declarations(file)` for the file at
  `path`.
- A record is
  `Lint.Declaration{kind, name, owner, span, references, loads, fills, term}`.
  `owner` is a `Maybe<&2, String>`, `loads` a `Maybe<&2, String>` (a path),
  `fills` a `Bool`, and `term` a `Maybe<&2, Lint.Term>` (`type` in
  TypeScript). A reference is
  `Lint.Reference{owner, span}`. Kinds and scope are as in
  [Declarations](#declarations).
- `aborted` lets a long rule stop early. bend-lint cannot stop a Bend rule.
- While a Bend rule waits on I/O, bend-lint waits too.

#### Options

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

Read them with `Lint.option_number`, `Lint.option_flag` and
`Lint.option_text`, or get the `Lint.Value` with `Lint.find`.

#### Good to know

- Spans count Unicode code points here. TypeScript counts UTF-16 units.
- The rule is compiled once, and again only when a file it reads (its
  imports and their `.js` effects included) or the compiler changes. The
  compiled rule is kept in `~/.cache/bend-lint/rules/`, one file per rule
  file. An entry whose rule file is gone is deleted.
- It runs on Bend's JavaScript runtime. Use tail recursion over long text or
  lists, to stay inside the stack.
- Streaming facts saves building a list of all of them.
- A `String` is a JS string at run time. `++` and `String.length` are native.
  A match on `SCon` reads one character and slices off the rest.
- A branch that uses a string or character its match took apart gets it
  rebuilt: a string as a rope of the whole rest, which the next read copies.
  Take the value twice and match one copy (`keep` in
  [rules/layout/format.bend](rules/layout/format.bend)).
- `Bool.pick` evaluates both branches. Match on a `Bool` parameter when a
  branch is costly.

#### Examples

- The formatter: [rules/layout/format.bend](rules/layout/format.bend)
- In [src/lint.test.ts](src/lint.test.ts): `COMMA_BEND` (fixes),
  `TYPES_BEND` (facts), `COUNT_BEND` (earlier findings) and `PARITY_BEND`
  (the guard and union options).

## As a library

From a file in the repo root:

```ts
import { applyFixes, createLinter } from "./src/lint.ts";
import { ERROR, ERROR_METADATA } from "./src/result.ts";

const made = await createLinter();
if (ERROR in made) throw new Error(made[ERROR][ERROR_METADATA].message);
const linter = made.OK;
const rules = await linter.loadRules(["rules/layout/format.bend"]);
if (ERROR in rules) throw new Error(rules[ERROR][ERROR_METADATA].message);
const res = await linter.lint("samples/sample.bend", rules.OK);
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

### Results

Entry points return a `Result` ([src/result.ts](src/result.ts)). They do not
throw.

- Success: `{ OK: value }`.
- Failure: `{ ERROR: { type, ERROR_METADATA: { message, cause } } }`.
- `type` is `config`, `rule-module`, `bend-missing`, `drift`, `aborted` or
  `internal`.
- `unwrap` gives the value, or throws the message.

An `OK` lint result can hold error findings. A failed Bend check, a missing
file and a rule crash are findings, not `ERROR` results. Check `diags` for
severity `error`.

### `createLinter({ bend })`

- Loads the Bend that `bend`, `$BEND_DIR` or the download picks. See
  [Finding Bend](#finding-bend).
- Loads each folder once.
- Must run before anything else loads Bend, so that the patch comes first.

### `linter.lint(file, rules, options)`

| Option    | What                                                                                                |
| --------- | --------------------------------------------------------------------------------------------------- |
| `imports` | also lint every file the check reads, except Base and hub packages. Default: the config's `imports` |
| `config`  | the config. Without it, the nearest one is read                                                     |
| `signal`  | aborts the run                                                                                      |
| `unsaved` | file paths mapped to editor text not saved yet, for this run                                        |

- The result has `diags`, `suppressed`, `sources`, `root` (the named file),
  `linted`, `facts` and `unstable`.
- With entries, `sources`, `facts` and `unstable` come from the first check
  the rules read.
- Runs at the same time wait for each other's check. Their rules still run
  side by side.
- `lint` also runs the rules of the config's `load` files, after the given
  ones. The config can turn off a given rule, or change its options and
  severity.
- Pass `config: {}` to skip config discovery.
- `position(span)` gives an LSP range.

### Config

- `findConfig(file)` looks for `bend-lint.json`, `.js` or `.ts` in the file's
  folder, then in each parent. The closest folder wins. In one folder, JSON
  wins, then JS, then TS.
- `readConfig(file)` loads the path you give. It makes `load` and `entries`
  absolute, from the config's folder.
- JS and TS configs export a named `config`. They load through Bun, cache
  included, and can import relative files.

### Rules

- `linter.loadRules(files)` loads rule files: a module's `rules`, or a Bend
  rule.
- `linter.bendRule(file)` loads one Bend rule.
- Loaded rules belong to the linter that loaded them. Use them only with that
  linter.

## JSON output

`--json` prints one JSON object on stdout, for all linted files. Status and
failure messages can still go to stderr. A finding with a fix:

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

- `suppressed` has the same shape. It holds the findings a directive covers.
  They do not count for `ok`.
- `def`, `path` and `range` are left out when there is no value.
- Lines start at 0. Characters are UTF-16 units.
- With a fix flag, findings describe the source before the fixes.

## Internals

All of this lives in `src/seam.ts`.

bend-lint works in three layers, however Bend is built:

1. **Ask Bend.** The seam runs Bend's own parser and checker, and reads what
   they computed: through probes, wrappers and the checked book.
2. **Convert.** The seam turns that into bend-lint's own types: `Declaration`,
   `Fact`, `Node`, `Span`. These types are the contract.
3. **Work with it.** Rules see only the contract, except through
   `cx.unstable`.

- When Bend changes inside, only step 1 follows, or a drift check stops the
  load. The contract and the rules stay.
- When Bend is written in Bend, the seam goes. Something fills the same
  contract, and the rules stay.
- Put logic in rules (`rules/shared.*`), not in the seam. The seam only
  passes on what Bend knows. Logic there is rewritten when the seam goes.

### Finding Bend

1. `--bend <dir>`, or else `$BEND_DIR`: a checkout or its `bend2` folder.
2. A downloaded release: the one `bend version` names, or, if Bend is not
   installed, the pinned one (`bendRelease` in package.json).

- A version picked by flag or PATH needs its source.
- A download holds `bend2/bend.ts`, `comp.ts`, `main.ts`, `safe.ts`,
  `base.bend` and the `effs/` files Base imports.
- It goes to `~/.cache/bend-lint/<tag>/bend2` (`XDG_CACHE_HOME`, or
  `LOCALAPPDATA` on Windows), and is reused.
- `bun run sync-bend` moves the pin to Bend's newest release, only if the
  tests, typecheck and lint pass on a clone of it.

### Patching

Bun patches Bend's modules while they load.

Wrappers and probes:

- `term_infer` and `term_check` are wrapped. The wrappers pass every argument
  on, and report what they return to `hook.see`.
- `parse_bind`, `parse_tele` and `parse_term` are wrapped. They report to
  `hook.parse`, only while a rule's source metadata is read. They keep names
  and binding identities from before Bend lowers the source.
- Probes in `parse_book`, `parse_def` and `book_load` report each
  declaration's and import's name and span to `hook.declare` and
  `hook.import`, in every check. The guard and source metadata read these
  names. bend-lint has no parser of its own for them.
- The hook is global, so checks run one at a time.

Other edits:

- `fs` and `path` in `bend.ts` and `main.ts` are replaced by adapters that
  turn real paths into `/` paths, so imports resolve on Windows.
- `comp.ts` exports `RUNTIME_MAIN` and `js_sat`, to compile Bend rules.
- `main.ts` exports `book_read`, `book_err` and `Check_Fail`. So a file is
  read and checked by the same code as `bend <file>`.

Base and failures:

- A file with a line that is exactly `import Base` reuses one Base, checked
  once per process. Rules never get Base facts.
- A failed check is one `bend/check` finding: Bend's message (expected and
  observed, the names in scope, Bend's note), without the location.

### One check, many files

Bend names each file by its path from the check root's folder. So one file
has different names under different roots. bend-lint does not use these
names for file rules:

- A file rule's names go through Bend's own `name_show`, with the file's own
  alias table from the check. So a file spells the same under any root.
- A program rule keeps the check's names. They are unique in the program.

`sameDeclarations` parses each file against the book as Bend had it when it
parsed that file. Declarations parsed later are hidden. Writes go to a layer
of their own, so the book never changes and is never copied.

Per check, these are made once, when first asked: walks and parents, each
file's spelling, the guard and source metadata, aliases, the book's order,
and the facts by file. The guard and source metadata use the same parsing
boundary.

### Reusing a check

A passed entry check is kept, one per entry. The next `lint` reuses it while
these are unchanged: the bend2 folder, the filters, and the text of every
file it read, unsaved text included. To tell, as git does:

- Each file is stamped (size, change times, file ID) before it is read.
- A file whose stat matches its stamp is unchanged, unless the stamp is less
  than 2 s after the file's last change. Then a later write could leave the
  stat the same, so the file is read and compared, and stamped again if it is
  unchanged.
- Unsaved text is compared as text.

### Staying compatible

Only the fallback download is pinned. Each load, of a checkout or a
download, checks:

- Each source edit matches exactly once, after CRLF line ends become LF.
- The compiler exports and runtime names bend-lint needs are there once.
- Wrapper signatures match, at type-check time. Argument counts match, at run
  time.
- `book_read`, `book_err` and `Check_Fail` take the arguments bend-lint gives
  them.
- A self-check runs `samples/sample.bend`:
  - in `def id(x: N) -> N: x`, `x` has the right type, binder, quantity, uses
    and span;
  - each checker wrapper reports the terms only it sees;
  - the source metadata reports `id`, its parameter `x`, and the constructor
    `Z` of `N`, each with one reference.

Any mismatch throws a drift error, and loading stops. The error's `name` is
`DriftError`, and `e[DRIFT]` is true, with `DRIFT` from `src/seam.ts`. The
tests add more checks, including Bend's own tests from the chosen checkout.
