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
- Do not use barrel exports or re-exports (`export { x } from "..."`, `export * from "..."`). Import
  from the module that defines the code.

### Bend

- On Windows, run Bend natively only with the fork in `../bend` (branch `feature/cuda-and-windows`).
  Otherwise, use WSL.
- Write small capabilities yourself. Import a large one from BendHub; do not copy hub code here. If
  the hub does not have it, tell me.
- Do not keep an old form for compatibility.
- Choose the representation for its access pattern first. Name defs `Type.verb`, as Base does.
- `bun run c-cpu-prof-md` profiles the C lane (see its header).
- After a change, run `bend <namespace>/PROOF.bend` for each changed namespace, and report it.

## 3. Project

- README.md is for users and stays short. Internals go here and in code comments.
- `src/linter/` holds the linter, `src/bend-lint-default-rules/` its default rules, `src/files/`
  files (their text, folders and globs; its effects in `effs/`), `src/json/` JSON, `src/meta/` this
  repo's scripts and oxlint plugins, and `src/shared/` helpers for any program.
- Code that touches Bend's internals goes in `src/linter/server.ts`. A Bend helper that is not about
  linting goes in `src/shared/`, even with one user, in the file of its concept (`lists.bend`,
  `strings.bend`, ...). Name a shared Bend file after its concept, never `utils`, and import it with
  its name capitalized as the alias. A Bend helper about linting that more than one file of the
  linter or its rules uses goes in `src/linter/shared.bend`.
- `bun run sync-bend` moves the pinned Bend (`bendRelease` in package.json) to Bend's newest
  release, only if the tests, typecheck and lint pass on it.
- A default rule lives in `src/bend-lint-default-rules/<namespace>/<name>.bend`, and its id is
  `<namespace>/<name>`. Its header, in this order: `# <id>: <what it reports>.`, `Fix:` (and its
  flag), `Options:` (with defaults), `Heuristics:` (how it decides and when it is wrong; required
  for a dangerous fix or a guess). Its fixes make its findings go.
- A rule's tests go beside it, in `<name>.test.ts`, through `src/linter/testing.ts`.

```sh
bun install
BEND_DIR=/path/to/bend bun test --parallel # does not type check
bun run typecheck
bun run lint
bun run format:check
git diff --check
```
