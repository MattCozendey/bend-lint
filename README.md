# bend-lint

A linter and formatter for Bend 2, with rules written in Bend.

## Install

Install bend-lint in each project, never globally:

```sh
bun add -D --trust bend-lint
```

The install writes a `bend-lint.json` that turns on the formatter, downloads Bend, and builds your
rules. Without `--trust`, Bun skips that: run `bunx bend-lint init`, then `bunx bend-lint prepare`.

> **Why per project:** a Bend limitation. Bend imports a file only by a relative path of plain names
> (or from BendHub), so bend-lint can reach your rules only inside your project. bend-lint refuses
> to run from anywhere else.

Needs Bun 1.4.3. bend-lint downloads the Bend it is tested with, once. With clang 14 or newer, it
builds your rules natively; without clang, it builds them to JavaScript, about 3 to 8 times slower,
and says so on each run.

> **On Windows, bend-lint uses a fork of Bend**,
> [MattCozendey/bend](https://github.com/MattCozendey/bend/tree/feature/cuda-and-windows), because
> Bend's releases do not run on Windows. bend-lint says so on each run.

## Run

```sh
bunx bend-lint [<file or glob>...] [--fix | --fix-dangerously] [--show-suppressed] [--json]
               [--jobs <number or max>] [--overlays]
```

| Flag                | Does                                                                               |
| ------------------- | ---------------------------------------------------------------------------------- |
| `--fix`             | makes no fix until Bend's checker in Bend can prove that a fix keeps the program   |
| `--fix-dangerously` | applies every fix. These can change what the program does, or break it             |
| `--show-suppressed` | also prints the findings that a directive covers                                   |
| `--json`            | prints one JSON object on stdout, with every fix. The summary goes to stderr       |
| `--jobs`            | how many files to lint at once: a number, or `max` (default: half the CPU threads) |
| `--overlays`        | reads a JSON object of paths to texts on stdin, which stand for those files        |

- With no files, it lints the `.bend` files in the folder you run it in: those git lists (so none
  that `.gitignore` lists), and none in `node_modules` or a hidden folder.
- Quote globs, and use `/` in paths.
- With `--overlays`, the checker and the rules read each overlay in place of its file, also when a
  file imports it, and the file need not be on disk; name such a file to lint it. An editor gives
  its unsaved buffers so. It does not go with `--fix-dangerously`, which writes files on disk.
- bend-lint builds your rules on its first run (about 40 s), and keeps the build until a rule or
  Bend changes. `bunx bend-lint prepare` builds them, and lints nothing: an editor runs it at start.
  If each rule you turn on is one of bend-lint's own, from `bend-lint-rules`, the build holds all of
  them, so you can turn them on and off without a new build.
- A fix that touches an earlier fix's edits waits for the next run.
- bend-lint runs at low priority: a long run slows down, not your computer.
- bend-lint does not report Bend's own errors: `bend <file> --check-only` does. If Bend's check of a
  file fails, the rules that need its types do not run on it, and bend-lint names them on stderr.
- With `--json`, a finding of one of bend-lint's own rules has `docs`: the link to its rule's file,
  whose header explains it.
- With `--json`, `skipped` gives each file that rules did not run on: its `path`, the `reason`
  (`unloaded`, `unchecked` or `unentered`), the `rules`, the `entry` (for `unentered`), and the
  `message` stderr gets. An error that ends the run prints `{"ok": false, "errors": [...]}` instead,
  each error with its `message`, and the `path` of the file it is about, if one.
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
  "packages": { "jane-rules": "1.0.0.0" },
  "rules": {
    "format": { "tabWidth": 4, "severity": "hint" },
    "style/no_foo": "error",
    "style/no_bar": "off",
    "jane-rules/no_baz": "warning"
  }
}
```

- `rules`: each rule to run, by its id: its path in `bend-lint-rules/`, without `.bend`
  (`bend-lint-rules/style/no_foo.bend` is `style/no_foo`). Give it `"off"`, a severity (`error`,
  `warning`, `information`, `hint`), or an object of its options and a `"severity"`.
- `packages`: BendHub packages of rules, names to versions. A rule whose id starts with a package's
  name, then `/`, is that package's file at the rest of the id: `jane-rules/no_baz` is `no_baz.bend`
  in `jane-rules@1.0.0.0`.
- `entries`: your program's entry files, as paths from the folder of `bend-lint.json`. A rule that
  reads the whole program ("this def is never used") then sees it, even when you lint one file.
- `imports`: also lint every file the named file imports (not Base, nor hub packages).

bend-lint's own rules are on BendHub, as the package `bend-lint-rules` at bend-lint's version, with
`.0` added. Name it in `packages`, then turn a rule on by its id, like
`bend-lint-rules/layout/case`. Each file's header in [bend-lint-rules/](bend-lint-rules/) says what
the rule reports, what its fix does, and its options.

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

A rule is a file in `bend-lint-rules/`. It imports bend-lint's rule API from BendHub,
[lint.bend](src/linter/lint.bend), whose comments are the API, and defines `rule()`:

```
import Base
import bend-lint-api@0.1.1.0/linter/lint.bend as Lint

def rule() -> Lint.Rule:
  ...
```

Then name it in `bend-lint.json`. The version is your bend-lint's, with `.0` added. After you update
bend-lint, change it if Bend's check of your rule fails.

To share rules, publish them to BendHub. A project then names your package in `packages`.
