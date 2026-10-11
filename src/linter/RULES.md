# Writing rules

How to write, run and test a rule. The design notes are in [lint.bend](lint.bend), at the top.

- A rule is a Bend file.
- A rules program puts rules together. [main.bend](main.bend) is the default one.
- [server.ts](server.ts) runs the program on files, and answers its questions about Bend files. It
  goes when Bend's checker is Bend; the rules stay.

## A rule

A rule file imports [lint.bend](lint.bend) and defines `rule()`. Saved as `rules/demo/no-foo.bend`:

```python
# demo/no-foo: a parameter named foo.
# Fix: renames it to bar, with its uses (--fix-dangerously).
import Base
import ../../lint.bend as Lint

def found(foo: Bool, id: U32, span: Lint.Span) -> List<&2, Lint.Finding>:
  match foo:
    case True{}:
      [Lint.Finding{Lint.Warning{}, span, "Rename foo to bar.", [Lint.Fix{"Rename to bar", [Lint.Rename{id, "bar"}]}]}]
    case False{}:
      []

def judge(node: Lint.Node) -> List<&2, Lint.Finding>:
  match node:
    case Lint.Node{id, parent, owner, Lint.Parameter{}, name, binder, quantity, Some{span}, target}:
      found(String.eq(name, "foo"), id, span)
    case _:
      []

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  Lint.done(Lint.findings(~Lint.Node, ~judge, Lint.Here.nodes(here)))

def rule() -> Lint.Rule:
  Lint.Rule{"demo/no-foo", Lint.Needs{False{}, False{}}, [], Lint.OnFile{run}}
```

A rule is `Rule{id, needs, options, run}`. Its `run` says how it runs:

| `run`                   | Runs                 | Sees (`run` gets)        | May report in |
| ----------------------- | -------------------- | ------------------------ | ------------- |
| `OnFile{run}`           | once per linted file | `Lint.Here`: one file    | that file     |
| `OnProgram{every, run}` | once per check       | `Lint.Whole`: every file | any file      |

- The id is `namespace/.../name`, each part kebab-case. The rule file is
  `rules/namespace/.../name.bend`. The id is the code of its findings.
- `needs` is `Needs{facts, declarations}`: whether the rule reads the checker's facts (see
  [Facts](#facts-and-questions)), and the declarations with their uses (see
  [Declarations](#declarations)). Each costs time and memory, so a rule gets them only if it asks.
- `options` lists the options the rule declares. See [Options](#options).
- A program rule's finding in a file that is not linted is dropped.
- `every` matters when several entries of the config check the named file: `False{}` keeps what one
  check finds, `True{}` what all find.
- Make a rule idempotent: its fixes make its findings go.

## Running rules

A rules program calls `Cli.run` with its rules:

```python
import Base
import ./cli.bend as Cli
import ./rules/demo/no-foo.bend as NoFoo

def main() -> IO(Unit):
  Cli.run(~[NoFoo.rule()])
```

Run it through the server, which builds it on the first run and keeps the build:

```sh
bend-lint --program main.bend <file or glob>... [--imports | --no-imports] [--fix | --fix-dangerously] [--show-suppressed] [--json]
```

`--program` also takes a build: an executable (the C lane), or a `.js` build from
`bend main.bend -o lint.js` (the JS lane).

| Flag                | What                                                                             |
| ------------------- | -------------------------------------------------------------------------------- |
| `--imports`         | also lint the files the named file imports (one named file only)                 |
| `--fix`             | make the fixes the linter proves safe: for now, those that only rewrite comments |
| `--fix-dangerously` | make every fix it can                                                            |
| `--show-suppressed` | also print the findings directives suppressed                                    |
| `--json`            | print one JSON object on stdout; the summary goes to stderr                      |

- Globs use `/` between parts. Each file is linted once, in turn.
- The run exits 1 if a finding is an error (a failed check is one), 2 on a usage or config error,
  else 0.
- The server caches each passed check, by root, in `~/.cache/bend-lint/server/checks`
  (`$XDG_CACHE_HOME`, or `%LOCALAPPDATA%` on Windows). A later run whose files are unchanged skips
  Bend's check. Builds go to `server/programs` beside it. An entry unused for a week is deleted.

The config, `bend-lint.json`, is the nearest one up from the named file:

```json
{
  "entries": ["src/main.bend"],
  "imports": true,
  "rules": { "demo/no-foo": "off", "layout/case": "error", "demo/max-lines": { "max": 300 } }
}
```

A rule's setting is `"off"`, a severity, or an object of an optional `"severity"` and option values.

Users silence or demand findings with directives:
`# bend-lint: <disable|expect>-<file|begin|end|next|line> <rule>[@severity] -- <reason>`. See
[directives.bend](directives.bend), at the top.

## What a rule sees

A file rule reads `Lint.Here`:

| Accessor                  | Gives                                                              |
| ------------------------- | ------------------------------------------------------------------ |
| `Here.path(here)`         | the file's real path, with `/`                                     |
| `Here.namespace(here)`    | its namespace in the check: `""` for the checked file              |
| `Here.text(here)`         | its text, as on disk                                               |
| `Here.nodes(here)`        | its syntax nodes, parents first                                    |
| `Here.node(here, id)`     | its node `id`, if there is one (a parent, say)                     |
| `Here.declarations(here)` | each name it declares, with its uses in it, if the rule needs them |
| `Here.facts(here)`        | the checker's facts on its nodes, if the rule needs them           |
| `Here.option(here, name)` | an option's value                                                  |

A program rule reads `Lint.Whole`: `Whole.sources` (each file of the check, hub packages aside),
`Whole.declarations` (with their uses in all of them, if the rule needs them) and `Whole.option`.

### Nodes

A node is a piece of the source as Bend's parser reads it:
`Node{id, parent, owner, syntax, name, binder, quantity, span, target}`.

- `syntax` says what it is: a declaration (`Definition`, `Datatype`, `Constructor`, `Law`,
  `Import`), a part of one (`Parameter`, `Field`, `Returns`, `Body`, `ImportPath`), a term or a
  pattern. The full list is `Syntax` in [lint.bend](lint.bend).
- `parent` is the parent's id, 0 for none. `owner` is the top-level declaration's.
- `name` is as written. `target` is the global name it declares or uses, as the check names it; an
  import's is the path of the file it loads.
- `binder` numbers the binder it declares or uses, per top-level declaration.
- `span` is `Some` where the source writes the node. The parser also makes nodes of its own (a
  do-block's binds); those have none.
- A span counts code points. Output columns count UTF-16 units, as editors do.

### Declarations

`Declaration{node, references}`: a node that declares a name, and the nodes that use it, in order. A
global name (def, type, constructor, law) is used by name; a binder by its number; an import by its
alias's prefix (`U.two`). A rule gets them if it sets `Needs{facts, True{}}`; else the list is
empty.

## Facts and questions

A rule that sets `Needs{True{}, declarations}` gets facts:
`Fact{node, role, quantity, used, checked}`.

- `role` is `OfTerm{}` (the type of the term the node is) or `OfBinder{}` (the type its binder
  declares).
- `quantity` is how often the term is demanded, or the binder's.
- `used`, for a binder, is how often its body uses it, the most over its branches: `Some{Erased{}}`
  for an unused one. A parameter that a match takes apart has none.
- `checked` is a `TypeRef`, a handle to a type the checker holds.
- A node can have no fact: the checker rewrote its term into another.
- A rule that needs facts does not run on a file whose check fails.

A rule asks about types in a `do Lint.Ask<A>:` block, with `Lint.show`, `Lint.same`, `Lint.normal`,
and `Lint.show_all` for many types at once. Each question waits for a round; the runner answers
every rule's questions of a round together. A rule may ask 64 rounds; past that, it fails with
`bend-lint/rule-crash`. So ask for all at once. Saved as `rules/demo/param-types.bend`:

```python
# demo/param-types: each parameter's type, as its file writes it. It asks the checker once, for all.
import Base
import ../../lint.bend as Lint

type Param is Data:
  Param{span: Lint.Span, checked: Lint.TypeRef}

# The parameters among `facts`, in order, onto `out` (last first).
def params(facts: List<&2, Lint.Fact>, out: List<&2, Param>) -> List<&2, Param>:
  match facts:
    case Nil{}:
      List.reverse(&2, Param, out)
    case Con{Lint.Fact{Lint.Node{i, p, o, Lint.Parameter{}, n, b, q, Some{span}, t}, Lint.OfBinder{}, quantity, used, checked}, rest}:
      params(rest, Param{span, checked} <> out)
    case Con{fact, rest}:
      params(rest, out)

def types(ps: List<&2, Param>, out: List<&2, Lint.TypeRef>) -> List<&2, Lint.TypeRef>:
  match ps:
    case Nil{}:
      List.reverse(&2, Lint.TypeRef, out)
    case Con{Param{span, checked}, rest}:
      types(rest, checked <> out)

def said(ps: List<&2, Param>, shown: List<&2, String>, out: List<&2, Lint.Finding>) -> List<&2, Lint.Finding>:
  match ps shown:
    case Con{Param{span, checked}, rest} Con{text, more}:
      said(rest, more, Lint.Finding{Lint.Hint{}, span, "type: " ++ text, []} <> out)
    case _ _:
      List.reverse(&2, Lint.Finding, out)

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +ps = params(Lint.Here.facts(here), [])
  do Lint.Ask<List<&2, Lint.Finding>>:
    shown : List<&2, String> <- Lint.show_all(types(ps, []))
    return said(ps, shown, [])

def rule() -> Lint.Rule:
  Lint.Rule{"demo/param-types", Lint.Needs{True{}, False{}}, [], Lint.OnFile{run}}
```

Facts cost time and memory: ask for them only in a rule that reads them.

## Findings and fixes

A finding is `Finding{severity, span, message, fixes}`. The severity is `Error{}`, `Warning{}`,
`Information{}` or `Hint{}`; the config can change it. An error fails the run.

A fix is `Fix{title, operations}`, in any of the program's own files (not Base, nor a hub package):

| Operation              | Does                                                                        |
| ---------------------- | --------------------------------------------------------------------------- |
| `Replace{span, text}`  | writes `text` over the span; an empty span inserts                          |
| `Rename{node, to}`     | renames what the declaration `node` (an id) declares, with each use         |
| `RenameUses{node, to}` | renames only its uses, to point them at a name the program declares already |

- A rename changes an import's alias (`U` of `U.two`), and any other name's last part.
- The linter drops a Rename of a global name (def, type, constructor, law): files the check did not
  read can use it. It also drops one whose new name is taken in its file.
- It drops a fix if the text does not write the name where a use is.
- It makes each finding's first fix, whole or not at all. A fix whose edits touch an earlier fix's
  waits for the next run.
- `--fix` makes the fixes the linter proves safe: those whose edits each write one comment (a `#`
  and no line end) over exactly one comment. A comment cannot change what the program does. Until
  Bend's checker is Bend, every other fix needs `--fix-dangerously`.
- `--json` shows every fix the linter can make, with its edits.

## Options

A rule declares each option with its name, its default and what it accepts. The config gives values;
the runner checks them before any rule runs (exit 2), and fills in the defaults. Saved as
`rules/demo/max-lines.bend`:

```python
# demo/max-lines: a file of more than `max` lines.
# Options: max (500).
import Base
import ../../lint.bend as Lint

def lines(text: String, n: U32) -> U32:
  match text:
    case SNil{}:
      n
    case SCon{'\n', rest}:
      lines(rest, (n + 1 : U32))
    case SCon{c, rest}:
      lines(rest, n)

def judge(over: Bool, path: String, max: U32) -> List<&2, Lint.Finding>:
  match over:
    case True{}:
      [Lint.Finding{Lint.Warning{}, Lint.Span{path, 0, 0}, "Keep the file to " ++ U32.show(max) ++ " lines.", []}]
    case False{}:
      []

def run(+here: Lint.Here) -> Lint.Ask(List<&2, Lint.Finding>):
  +max = Lint.Value.number(Lint.Here.option(here, "max"))
  Lint.done(judge(U32.is_gt(lines(Lint.Here.text(here), 0), max), Lint.Here.path(here), max))

def rule() -> Lint.Rule:
  Lint.Rule{"demo/max-lines", Lint.Needs{False{}, False{}}, [Lint.Declared{"max", Lint.Num{500}, Lint.NumberOption{1, 4294967295}}], Lint.OnFile{run}}
```

| Spec                     | Accepts                                    |
| ------------------------ | ------------------------------------------ |
| `NumberOption{min, max}` | a whole number in the range                |
| `FlagOption{}`           | a boolean                                  |
| `TextOption{choices}`    | text: one of `choices`, unless it is empty |
| `AnyOption{specs}`       | what one of `specs` accepts                |

Read a value with `Value.number`, `Value.flag` or `Value.text`.

## Tests

A rule's behavior tests go in `rules/namespace/.../name.test.ts`. Test what a user sees, never how
the rule works. [testing.ts](testing.ts) helps:

```ts
import { expect, setDefaultTimeout, test } from "bun:test";

import { build, lint, run } from "../../testing.ts";

const PROGRAM = await build("rules/demo/no-foo.bend");

setDefaultTimeout(120_000);

test("a parameter named foo is reported, and renamed with --fix-dangerously", async () => {
  const text = "import Base\n\ndef twice(+foo: U32) -> U32:\n  (foo + foo : U32)\n";
  expect((await lint(PROGRAM, { "main.bend": text }, "main.bend")).map(({ at }) => at)).toEqual([
    "3:12",
  ]);
  expect(
    (await run(PROGRAM, { "main.bend": text }, "main.bend", ["--fix-dangerously"])).files[
      "main.bend"
    ],
  ).toBe("import Base\n\ndef twice(+bar: U32) -> U32:\n  (bar + bar : U32)\n");
});
```

- `build(rule)` builds a program with that rule alone, and keeps it until the rule, a file it
  imports or Bend changes.
- `lint(program, files, named)` writes the files to a fresh folder and gives the findings.
- `run(program, files, named, args, dir)` also gives the exit code, the output and the files after
  the run.
- Tests build with the `bend` on PATH; without it they skip.
- Tests in a file run at the same time, so no test may depend on another.

## Bend for rule authors

- Recurse in tail position over long lists and text: the JS lane's stack is small.
  [shared.bend](shared.bend) has tail-recursive `append`, `concat`, `length`, `any` and `sort`;
  Base's own are not.
- `match` works on a parameter only: pass a computed value to a helper.
- `Bool.pick`, `&&` and `||` compute both sides.
- A template argument (`~f`) must be closed: no local variables.
- Logic that more than one rule uses goes in [shared.bend](shared.bend).
