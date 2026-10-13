# bend-lint

A linter and formatter for Bend 2, with rules written in Bend.

## Install

Needs Bun 1.4.3. bend-lint downloads the Bend it is tested with, once. With clang 14 or newer, it
builds your rules natively; without clang, it builds them to JavaScript, about 3 to 8 times slower,
and says so on each run.

> **On Windows, bend-lint uses a fork of Bend**,
> [MattCozendey/bend](https://github.com/MattCozendey/bend/tree/feature/cuda-and-windows), because
> Bend's releases do not run on Windows. bend-lint says so on each run.

```sh
bun add -g github:MattCozendey/bend-lint
```

## Run

```sh
bend-lint [--program <rules program>] <file or glob>... [--imports | --no-imports]
          [--fix | --fix-dangerously] [--show-suppressed] [--json] [--jobs <number or max>]
```

| Flag                | Does                                                                               |
| ------------------- | ---------------------------------------------------------------------------------- |
| `--program`         | runs your rules program (default: [main.bend](src/linter/main.bend))               |
| `--imports`         | also lints every file the one named file imports (not Base, nor hub packages)      |
| `--fix`             | applies the fixes proven safe. For now: those that only rewrite comments           |
| `--fix-dangerously` | applies every fix. These can change what the program does, or break it             |
| `--show-suppressed` | also prints the findings that a directive covers                                   |
| `--json`            | prints one JSON object on stdout, with every fix. The summary goes to stderr       |
| `--jobs`            | how many files to lint at once: a number, or `max` (default: half the CPU threads) |

- Quote globs, and use `/` in paths.
- A `.bend` rules program builds on its first run (about 40 s), and stays built until it or Bend
  changes.
- A fix that touches an earlier fix's edits waits for the next run.
- bend-lint runs at low priority: a long run slows down, not your computer.
- bend-lint does not report Bend's own errors: `bend <file> --check-only` does. If Bend's check of a
  file fails, the rules that need its types do not run on it, and bend-lint names them on stderr.
- Exit code: 0 no errors (warnings do not count), 1 an error, 2 a usage or config error.
- The downloaded Bend, builds and cached checks go to `~/.cache/bend-lint/`. You can delete it at
  any time.

## Config

The nearest `bend-lint.json`, from the named file's folder up:

```json
{
  "entries": ["src/main.bend"],
  "imports": true,
  "rules": {
    "layout/case": "off",
    "no-unused/imports": "error",
    "layout/format": { "tabWidth": 4, "severity": "hint" }
  }
}
```

- `entries`: your program's entry files. A rule that reads the whole program ("this def is never
  used") then sees it, even when you lint one file.
- `imports`: as `--imports`. The flag wins.
- `rules`: per rule, `"off"`, a severity (`error`, `warning`, `information`, `hint`), or its options
  and a `"severity"`.

The rules are in [src/bend-lint-default-rules/](src/bend-lint-default-rules/). Each file's header
says what the rule reports, what its fix does, and its options.

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

A rule is a Bend file that imports [lint.bend](src/linter/lint.bend), whose comments are the API. To
run your rules, copy [main.bend](src/linter/main.bend) in a clone of this repo, and pass it to
`--program`.
