# bend-lint

A linter and formatter for Bend 2, with rules written in Bend.

## Install

Install bend-lint in each project, never globally:

```sh
bun add -D github:MattCozendey/bend-lint
bunx bend-lint init
```

`init` writes `bend-lint.json` and `bend-lint-rules/format.bend`, which turns on the formatter.

> **Why per project:** a Bend limitation. Bend imports a file only by a relative path of plain names
> (or from BendHub), so your rules can reach bend-lint's files only inside your project. bend-lint
> refuses to run from anywhere else.

Needs Bun 1.4.3. bend-lint downloads the Bend it is tested with, once. With clang 14 or newer, it
builds your rules natively; without clang, it builds them to JavaScript, about 3 to 8 times slower,
and says so on each run.

> **On Windows, bend-lint uses a fork of Bend**,
> [MattCozendey/bend](https://github.com/MattCozendey/bend/tree/feature/cuda-and-windows), because
> Bend's releases do not run on Windows. bend-lint says so on each run.

## Run

```sh
bunx bend-lint [<file or glob>...] [--fix | --fix-dangerously] [--show-suppressed] [--json]
               [--jobs <number or max>]
```

| Flag                | Does                                                                               |
| ------------------- | ---------------------------------------------------------------------------------- |
| `--fix`             | applies the fixes proven safe. For now: those that only rewrite comments           |
| `--fix-dangerously` | applies every fix. These can change what the program does, or break it             |
| `--show-suppressed` | also prints the findings that a directive covers                                   |
| `--json`            | prints one JSON object on stdout, with every fix. The summary goes to stderr       |
| `--jobs`            | how many files to lint at once: a number, or `max` (default: half the CPU threads) |

- With no files, it lints the `.bend` files in the folder you run it in: those git lists (so none
  that `.gitignore` lists), and none in `node_modules` or a hidden folder.
- Quote globs, and use `/` in paths.
- bend-lint builds your rules on its first run (about 40 s), and keeps the build until a rule or
  Bend changes.
- A fix that touches an earlier fix's edits waits for the next run.
- bend-lint runs at low priority: a long run slows down, not your computer.
- bend-lint does not report Bend's own errors: `bend <file> --check-only` does. If Bend's check of a
  file fails, the rules that need its types do not run on it, and bend-lint names them on stderr.
- Exit code: 0 no errors (warnings do not count), 1 an error, 2 a usage or config error.
- The downloaded Bend, builds and cached checks go to `~/.cache/bend-lint/`. You can delete it at
  any time.

## Config

`bend-lint.json` is the only place that picks the rules: a rule runs only if `rules` names it.
bend-lint reads the nearest `bend-lint.json` above the folder it runs in.

```json
{
  "entries": ["src/main.bend"],
  "imports": true,
  "rules": {
    "format": { "tabWidth": 4, "severity": "hint" },
    "style/no-foo": "error",
    "style/no-bar": "off"
  }
}
```

- `rules`: each rule to run, by its id: its path in `bend-lint-rules/`, without `.bend`
  (`bend-lint-rules/style/no-foo.bend` is `style/no-foo`). Give it `"off"`, a severity (`error`,
  `warning`, `information`, `hint`), or an object of its options and a `"severity"`.
- `entries`: your program's entry files, as paths from the folder of `bend-lint.json`. A rule that
  reads the whole program ("this def is never used") then sees it, even when you lint one file.
- `imports`: also lint every file the named file imports (not Base, nor hub packages).

bend-lint ships more rules, in [bend-lint-rules/](bend-lint-rules/). Each file's header says what
the rule reports, what its fix does, and its options. To use one, add a file to your
`bend-lint-rules/` that imports it, as `format.bend` does.

## Suppress findings

```
# bend-lint: disable-next my/rule -- <reason> not-expected-because: <why>
# bend-lint: expect-next my/rule@hint -- <reason>
```

Form: `# bend-lint: <disable|expect>-<scope> <rule>[@severity] -- <reason>`.

| Scope           | Covers                                       |
| --------------- | -------------------------------------------- |
| `file`          | the whole file                               |
| `begin` … `end` | the lines between them (`end` has no reason) |
| `next`          | the next line with code                      |
| `line`          | its own line, after code                     |

- A finding is covered when it starts on a covered line.
- `bend-lint/...` findings cannot be suppressed.
- bend-lint reports a wrong directive and an unmet `expect` as errors, and a `disable` that covers
  nothing as a warning.

## Write a rule

A rule is a file in `bend-lint-rules/`. It imports bend-lint's toolkit,
[lint.bend](src/linter/lint.bend), whose comments are the API, and defines `rule()`:

```
import Base
import ../node_modules/bend-lint/src/linter/lint.bend as Lint

def rule() -> Lint.Rule:
  ...
```

Then name it in `bend-lint.json`. A rule in a subfolder starts its import with one more `../`.
