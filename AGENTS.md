# AGENTS

Contribution guidelines, for agents and humans alike.

The rules stated here have priority over any and all rules in any skill file or tool.

## 0. Core

- If a skill does not load, read its file in `.agents/skills/`.
- Do not change any `.md` file without asking me.

## 1. Communication

- Speak the language you are spoken to; but shortly and without dropping important information in
  ASD-STE100(or language's equivalent), with learnings from the `i-have-adhd`.
- Use a global counter for your non-trivial questions that grows throught the session. Repeat each
  open question in each response until I answer it or tell you to use common sense.

## 2. Code

- Run `bend guide` once per session before you write Bend code. Use the `bend` on PATH, even if it
  is a fork or a different version. Also run `bend guide shaders` before parallel or performance
  work, and `bend guide effects` before a custom effect.

- bend-lint lints Bend code with rules written in Bend. Its TypeScript code must pass this repo's
  lint and type check.

- Before you write a new def, look for it with `bend base <Name>`.

- Trust the checker. Bend is sound, so a proof that checks is correct. Do not look for
  counterexamples, before or after you write a law.

- Do not run `--verdict` unless I ask.

- Do not use `@unsafe`. Do not use foreign code unless I approve it.

- Use a law, not a test, but ask me before you write one. Use a test only for behavior that a law
  cannot state (for example, IO output).

- Write a law only for a property that matters. For example, a hardcoded list does not need a law
  that it has no duplicates.

- A law's statement is code, and obeys the same rules as other code. Its proof body does not, unless
  it is too expensive to check. Ask me before you review a proof body, or code that a proven law
  covers. Good laws and an ergonomic API are the priority.

- If a proven law covers a def, use that def. Do not write or use an unproven def that does the same
  thing.

- When a law replaces another law or a test, delete the old one in the same change.

- Do not try to prove that generated data, or a copy of a standard's text, matches its source. Check
  generated data with a test against an independent source (for example, another implementation, or
  the standard's own test vectors). That test does not replace laws for the code. Tell me which
  copies of standard text you changed, so that I can check them.

### Tools

- You are rarely, if ever, smarter than any linter, so do not work around a lint rule and only
  expect/suppress a finding when that makes sense (with a directive whose reason says why [for
  example, a measurement]).
- Deterministic tools always win over skill suggestions.
- Every test needs my approval first, and tests that suggest implementation details should not be
  suggested at all.
- Before you present me your changes, run these in order, and repeat until they find nothing more
  about them:
  1. `thermo-nuclear-code-quality-review`. A file over 1000 lines can be fine. Ask me before you
     split one.
  2. `cyclomatic-complexity`. Extract a helper only when it has more than one caller.
  3. `erasure`.
  4. `bun run lint` and `bun run typecheck`.

### Style

- Write functional code without mutation, except when speed is a priority for a file(ask me);
  wherein any and all optimization opportunities are fair game.
- Give each concept one representation in the whole codebase.
- Give each fact one location. A comment must not repeat what the docs state or clearly imply.
- Use the helpers that exist, but inline if they will only have one caller.
- When you change something, delete the code, comments and docs it made obsolete.

### Typescript

- Lay out each file in this order, with a comment before each section: imports, types, constants,
  functions, side effects.
- Write functions as `const` arrow functions.
- Name a function by what it gives: `get…` for a value (`getRecord`), `is…` or `has…` for a Bool
  (`isSpan`). Name one that gives nothing by what it does (`writeFiles`, `prune`). `try…` catches
  what it calls, and gives the failure as a value (`undefined`, or a Result) or skips it. The type,
  not the name, says that a value can be `undefined`. Constants are SCREAMING_SNAKE_CASE, types
  PascalCase, other names camelCase. `result.ts` keeps the names of its Result (`ok`, `error`,
  `mapError`, `unwrap`).
- Do not use barrel exports or re-exports (`export { x } from "..."`, `export * from "..."`). Import
  from the module that defines the code.

### Bend

- On Windows, run Bend natively only with the fork in `../bend` (branch `feature/cuda-and-windows`).
  Otherwise, use WSL.
- Write small capabilities yourself. Import a large one from BendHub; do not copy hub code here. If
  the hub does not have it, tell me.
- Do not keep an old form for compatibility.
- Choose the representation for its access pattern first.
- Name defs as Base does, and as `layout/case` checks; where the two disagree, the linter is right.
  - `Type.verb`: the type, or the concept, that a def works on, then what it does (`Wire.ask`,
    `Reader.add`). A def about none of its file's types has the verb alone: the file's alias names
    it where it is imported (`Lists.append`, `Lint.visit`), and a rule's defs are the rule's own.
  - A Bool is `is_x`, `has_x` or a verb in the third person (`fits`); `is_lt`, `is_le` and `is_eq`
    compare; `to_x` and `from_x` convert; `show` gives a String, and `read` parses one back (a
    Maybe); `get`, `set` and `add` act on a collection. `T.of` makes a T from its parts.
  - A helper of `f` is `f.go` (its loop), `f.step` (one step of it), `f.done` (its result, at the
    end), `f.if` (a branch on a Bool), `f.of` (`f`, from parts that `f` computed), or another short
    verb.
  - A def that goes on after an effect, or after a match on what another def gave, is named by what
    happened, in the past tense, and takes it: `Config.opened(folder, opened)`.
- `bun run c-cpu-prof-md` profiles the C lane (see its header).
- After a change, run `bend <namespace>/PROOF.bend` for each changed namespace, and report it.

## 3. Project

- README.md is for users and stays short. Internals go here and in code comments.
- `src/linter/` holds the linter, `bend-lint-rules/` its default rules, `src/files/` files (their
  text, folders and globs; its effects in `effs/`), `src/json/` JSON, `src/text/` edits to texts and
  places in them, `src/meta/` this repo's scripts and oxlint plugins, and `src/shared/` helpers for
  any program.
- Code that knows Bend's own shapes (its parser, checker and their data) goes in
  `src/linter/seam.ts`, and nowhere else: it gives the Bend side the linter's own model, the types
  of `lint.bend`. A Bend helper that is not about linting goes in `src/shared/`, even with one user,
  in the file of its concept (`lists.bend`, `strings.bend`, ...); one that is not simple gets a
  folder of its own, as `src/json/` and `src/text/` do. Name a shared Bend file after its concept,
  never `utils`, and import it with its name capitalized as the alias. A Bend helper about linting
  that more than one file of the linter or its rules uses goes in `src/linter/lint.bend`.
- `bun run sync-bend` moves the pinned Bend (`bendRelease` in package.json) to Bend's newest
  release, only if the tests, typecheck and lint pass on it. Run it on Linux or macOS: on Windows,
  bend-lint uses the fork's pinned commit (`bendWindows`), which moves by hand when the fork moves.
- bend-lint.json is the only way to run rules: bend-lint writes the program of the rules it names
  (`src/linter/build/rules.<hash>.bend`), and a rule's id is its path in `bend-lint-rules/`. This
  repo lints itself so, with every default rule. Users install bend-lint per project, never
  globally: Bend imports only relative paths of plain names.
- The rule API is `src/linter/lint.bend` and the files it imports. Rules import it from BendHub, as
  the package `bend-lint` at bend-lint's version (`0.1.0` is `bend-lint@0.1.0.0`); this repo imports
  it by relative paths. bend-lint's own rules go to BendHub as `bend-lint-rules`, at the same
  version. `bun run ship <folder>` writes both packages, and the npm package, whose Bend files
  import the API from BendHub, and whose install runs init and downloads Bend; `--publish` publishes
  both packages. A change to the API's files changes its hash, so users' rules must move to the new
  version.
- A default rule lives in `bend-lint-rules/<namespace>/<name>.bend`, and its id is
  `<namespace>/<name>`. Its header, in this order: `# <id>: <what it reports>.`, `Fix:`, `Options:`
  (with defaults), `Heuristics:` (how it decides and when it is wrong; required for a dangerous fix
  or a guess). Its fixes make its findings go.
- A rule's tests go beside it, in `<name>.test.ts`, through `src/linter/testing.ts`.

```sh
bun install
bun test --parallel # does not type check
bun run typecheck
bun run lint
bun run format:check
git diff --check
```
