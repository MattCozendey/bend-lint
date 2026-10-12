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

- Use a law, not a test. Use a test only for behavior that a law cannot state (for example, IO
  output).

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

### Rule headers

Each rule file starts with a comment header, in this order:

1. `# <id>: <what it reports>.`
2. `Fix:` what its fix does, and the flag that applies it (`--fix` or `--fix-dangerously`).
3. `Options:` each option, with its default.
4. `Heuristics:` how the rule decides, and when it can be wrong. A rule with a dangerous fix, or a
   rule that guesses (by statistics, a threshold, or a pattern that can miss), must have it.

Leave out a part that does not apply. Notes on the code come after the header, after a `#` line.

### Where code goes

- Everything that touches Bend's internals goes in `src/linter/server.ts`.
- Bend logic that more than one file uses, and that is not about linting, goes in
  `src/shared/utils.bend`.
- A fix that `--fix` applies must keep what the program does.

### Changes

- Keep each change small and focused.
- A PR says what was wrong, what happens now, and how you checked.
- Before you send code, run the full suite, `bun run typecheck` and `bun run lint`.
- For docs, check that the examples run and the links resolve.
- README.md is for users and stays short. Internals go here.
- Edit the section that exists. Do not add a second one on the same topic.

## Setup

```sh
bun install
BEND_DIR=/path/to/bend bun test --parallel
bun run typecheck
bun run lint
bun run format:check
git diff --check
```

- `bun run typecheck` and `bun run lint` first link `.bend2` to the Bend that `BEND_DIR` or the
  download picks.
- `bun test` does not type check.
- `bun run typecheck` checks this repo's files only, not Bend's.
- The tests build rules programs with the `bend` on PATH. Without it, they skip.
- CI (`.github/workflows/ci.yml`) runs all of these on Linux and Windows:
  - pushes and pull requests: against the pinned Bend release;
  - the daily run: against Bend's main.
- `bun run c-cpu-prof-md <rules program.bend> <server args...>` profiles the C lane, like bun's
  `--cpu-prof-md`: it writes `C-CPU.*.md`, with calls (not time) per def, and the `.c` it points
  into. It needs clang's `llvm-profdata` and `llvm-cov`.

## Files

- `src/linter/` holds the linter. [src/linter/PLAN.md](src/linter/PLAN.md) says how to write its
  Bend code, and [src/linter/RULES.md](src/linter/RULES.md) how to write, run and test its rules.
- `src/shared/` holds helpers that are not about linting: TypeScript that the linter and `src/meta/`
  use, and Bend that the linter uses.
- `src/json-parser/` reads and writes JSON for the linter.
- `src/meta/` holds this repo's scripts and oxlint plugins.

| File                         | Holds                                                        |
| ---------------------------- | ------------------------------------------------------------ |
| `src/linter/lint.bend`       | what a rule sees, and the design notes                       |
| `src/linter/main.bend`       | the default rules program                                    |
| `src/linter/cli.bend`        | running the rules, and the output                            |
| `src/linter/program.bend`    | the program a check gives, and its declarations              |
| `src/linter/config.bend`     | `bend-lint.json`                                             |
| `src/linter/directives.bend` | `# bend-lint:` directives                                    |
| `src/linter/fixes.bend`      | planning and making fixes                                    |
| `src/linter/wire.bend`       | every request to the server, and its answers decoded         |
| `src/linter/server.ts`       | runs a rules program, and answers it with Bend's checker     |
| `src/linter/testing.ts`      | what the tests share                                         |
| `src/linter/rules/`          | bundled rules, one folder per namespace, each with its tests |
| `src/linter/tests/`          | rules that only the tests use                                |
| `src/json-parser/json.bend`  | reading and writing JSON                                     |
| `src/shared/result.ts`       | the `Result` that entry points return                        |
| `src/shared/bend2.ts`        | finding Bend (see [Finding Bend](#finding-bend))             |
| `src/shared/text.ts`         | text helpers: line offsets, exact edits, line ends           |
| `src/shared/utils.ts`        | other helpers that are not about Bend or linting             |
| `src/shared/utils.bend`      | Bend helpers that are not about linting                      |

## Finding Bend

`src/shared/bend2.ts` finds the Bend whose checker the server loads:

1. `$BEND_DIR`: a checkout or its `bend2` folder.
2. A downloaded release: the one `bend version` names, or, if Bend is not installed, the pinned one
   (`bendRelease` in package.json).

- A download holds `bend2/bend.ts`, `comp.ts`, `main.ts`, `safe.ts`, `base.bend` and the `effs/`
  files Base imports.
- It goes to `~/.cache/bend-lint/<tag>/bend2` (`XDG_CACHE_HOME`, or `LOCALAPPDATA` on Windows), and
  is reused.
- `bun run sync-bend` moves the pin to Bend's newest release, only if the tests, typecheck and lint
  pass on a clone of it.
