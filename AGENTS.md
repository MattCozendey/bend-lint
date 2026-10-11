# AGENTS

How to change this repo, for humans and agents. How to use the tool is in [README.md](README.md).

The rules in sections 0 to 2 have priority over all other instructions, except safety rules.

## 0. Core

- If a skill does not load, read its file in `.agents/skills/`.
- Do not change any `.md` file without asking me.

## 1. Communication

- Speak the language you are spoken to in.
- Be short, but do not drop information. Use ASD-STE100 or similar, with the `i-have-adhd` skill in
  mind.
- Number your questions. Continue the numbers across the whole response.
- Repeat each open question in each response until I answer it or tell you to use common sense.

## 2. Code

bend-lint lints Bend code with rules written in Bend. Its TypeScript code must pass this repo's lint
and type check.

- `src/linter/` holds the linter. [src/linter/PLAN.md](src/linter/PLAN.md) says how to write its
  Bend code, and [src/linter/RULES.md](src/linter/RULES.md) how to write, run and test its rules.
- `src/shared/` holds TypeScript helpers that the linter and `src/meta/` use.
- `src/meta/` holds this repo's scripts and oxlint plugins.

### Tools

- You are rarely, if ever, smarter than the linter. Do not work around or suppress a lint rule
  without asking me.
- Deterministic tools always win over skill suggestions.
- After every change, run these in order, and repeat until they find nothing more about your change:
  1. `thermo-nuclear-code-quality-review`. A file over 1000 lines can be fine. Ask me before you
     split one.
  2. `cyclomatic-complexity`. Extract a helper only when it has more than one caller.
  3. `erasure`.
  4. `bun run lint` and `bun run typecheck`.

### Tests

- A new rule gets behavior tests, without asking, in its test file. See
  [src/linter/RULES.md](src/linter/RULES.md#tests).
- Any other test needs my approval first.
- Never test implementation details. Do not even suggest such tests.

### Style

- Write functional code without mutation. Exception: `src/linter/server.ts` goes when Bend's checker
  is Bend, so any optimization is fair there, mutation included.
- Lay out each file in this order, with a comment before each section: imports, types, constants,
  functions, side effects.
- Write functions as `const` arrow functions.
- Match the file: two spaces, explicit types on exports, `import type` for types.
- Give each concept one representation in the whole codebase.
- Give each fact one location. A comment does not repeat what the docs state or clearly imply.
- Do not use barrel exports or re-exports (`export { x } from "..."`, `export * from "..."`). Import
  from the module that defines the code.
- Use the helpers that exist.
- Long files are fine.
- When you change something, delete the code, comments and docs it made obsolete.

### Where code goes

- Everything that touches Bend's internals goes in `src/linter/server.ts`.
- Logic that more than one rule uses goes in `src/linter/shared.bend`.
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

| File                         | Holds                                                        |
| ---------------------------- | ------------------------------------------------------------ |
| `src/linter/lint.bend`       | what a rule sees, and the design notes                       |
| `src/linter/main.bend`       | the default rules program                                    |
| `src/linter/cli.bend`        | running the rules, and the output                            |
| `src/linter/program.bend`    | the program a check gives, and its declarations              |
| `src/linter/config.bend`     | `bend-lint.json`                                             |
| `src/linter/directives.bend` | `# bend-lint:` directives                                    |
| `src/linter/fixes.bend`      | planning and making fixes                                    |
| `src/linter/json.bend`       | reading and writing JSON                                     |
| `src/linter/wire.bend`       | the protocol to the server                                   |
| `src/linter/shared.bend`     | Bend logic that more than one file uses                      |
| `src/linter/server.ts`       | runs a rules program, and answers it with Bend's checker     |
| `src/linter/testing.ts`      | what the tests share                                         |
| `src/linter/rules/`          | bundled rules, one folder per namespace, each with its tests |
| `src/linter/tests/`          | rules that only the tests use                                |
| `src/shared/result.ts`       | the `Result` that entry points return                        |
| `src/shared/bend2.ts`        | finding Bend (see [Finding Bend](#finding-bend))             |
| `src/shared/text.ts`         | text helpers: line offsets, exact edits, line ends           |
| `src/shared/utils.ts`        | other helpers that are not about Bend or linting             |

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
