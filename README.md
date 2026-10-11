# bend-lint

A linter and formatter for Bend 2.

```sh
bend src/linter/main.bend -o lint
bun src/linter/server.ts ./lint main.bend --fix
```

## What it does

1. It checks each file with Bend's own type checker.
2. It runs the rules of a rules program. A rule sees the source text and what the checker found:
   types, scope, and how often each variable is used.
3. It prints the findings. With a fix flag, it also writes the fixes.

The default rules program, [src/linter/main.bend](src/linter/main.bend), runs every
[bundled rule](#bundled-rules).

## Setup

1. Install Bun 1.4.3 and Bend.
2. On Windows, run Bend itself only through WSL, not natively (as of 2026-10-09). See
   [Bend's platform limitations](https://github.com/bendlang/bend#limitations).
3. Run:

```sh
git clone https://github.com/MattCozendey/bend-lint.git
cd bend-lint
bun install
```

## Run it

Build a rules program once, and again when its rules change:

```sh
bend src/linter/main.bend -o lint      # lint.exe on Windows; -o lint.js for the JS build
```

Then run it through the server:

```sh
bun src/linter/server.ts ./lint <file or glob>... [--imports | --no-imports]
                         [--fix | --fix-dangerously] [--show-suppressed] [--json]
```

| To lint         | Command                                               |
| --------------- | ----------------------------------------------------- |
| One file        | `bun src/linter/server.ts ./lint main.bend`           |
| Many files      | `bun src/linter/server.ts ./lint "src/**/*.bend"`     |
| A whole program | `bun src/linter/server.ts ./lint main.bend --imports` |

### Inputs

- Each input is a glob. A plain path matches only that file.
- Use `/` in paths, on every system.
- Quote globs, so that bend-lint expands them the same way in every shell.
- Each file is linted once, in turn.

### Which files get findings

Findings appear only in the **linted files**:

- Without `--imports`: each file you name.
- With `--imports`: the one file you name, and every file it imports, except Base and hub packages.
  `--imports` takes one file.
- `"imports": true` in the config turns `--imports` on. `--no-imports` turns it off.

A rule can read more than the linted files. It still shows findings only in them.

### Entries: lint one file, read the whole program

Some rules look at the whole program, for example "this def is never used". When you lint `lib.bend`
alone, such a rule cannot see `main.bend`, which uses lib. So list your program's entry files in the
config:

```json
{ "entries": ["main.bend", "tests/main.bend"] }
```

- When you lint a file that an entry imports, bend-lint checks the program from that entry. Findings
  still appear only in the file you named.
- A file that no entry imports is checked alone.
- With several entries that import the file, each entry's check runs. The rule decides whether a
  finding needs one entry (`some`, the default) or every entry (`every`).

### Fixes

| Flag                | Applies                                                                     |
| ------------------- | --------------------------------------------------------------------------- |
| `--fix`             | the fixes bend-lint proves safe. For now: those that only rewrite comments. |
| `--fix-dangerously` | every fix. These can change what the program does, or break it.             |

- Each finding's first fix is applied whole, or not at all.
- When a fix touches an earlier fix's edits, it waits. Run again to apply it.
- Until Bend's checker is written in Bend, most fixes need `--fix-dangerously`.

### Output and exit code

- `--json` prints one JSON object on stdout, with every fix and its edits. The summary goes to
  stderr.
- `--show-suppressed` also prints the findings that a directive covers.

| Exit code | Meaning                                   |
| --------- | ----------------------------------------- |
| 0         | No errors. Warnings do not count.         |
| 1         | A finding is an error. A failed check is. |
| 2         | A usage or config error.                  |

## Config

bend-lint reads the nearest `bend-lint.json`, from the named file's folder up:

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

| Key       | What                                                             |
| --------- | ---------------------------------------------------------------- |
| `entries` | the program's entry files, relative to the config's folder       |
| `imports` | `true` to lint as with `--imports`. The command line's flag wins |
| `rules`   | per rule: `"off"`, a severity, or its options and a `"severity"` |

- Severities: `error`, `warning`, `information`, `hint`.
- An unknown option, or a value that does not fit, is an error. bend-lint checks the config before
  any rule runs.
- The rules program decides which rules there are. The config only turns them off or sets them up.

## Bundled rules

In [src/linter/rules/](src/linter/rules/).

### `layout/format`

The formatter. It fixes indentation, spacing, blank lines between declarations, line wrapping and
line ends. A file that differs from its formatted text is reported where it first differs.

| Option        | Default | Values                           |
| ------------- | ------- | -------------------------------- |
| `tabWidth`    | `2`     | a positive integer               |
| `wrapAtWidth` | `100`   | a positive integer, or `"never"` |
| `endOfLine`   | `"lf"`  | `"lf"`, `"crlf"`, `"preserve"`   |

- `"never"` turns off optional wrapping.
- `"preserve"` keeps the file's first line ending, or LF if there is none.

### `layout/canon-import-path`

Each import path must be the shortest path from the importing file to the file it names, and start
with `./` or `../`.

| Import, in `src/main.bend`   | Fix             |
| ---------------------------- | --------------- |
| `util.bend`                  | `./util.bend`   |
| `../src/util.bend`           | `./util.bend`   |
| `./../lib/x.bend`            | `../lib/x.bend` |
| `/home/me/app/src/util.bend` | `./util.bend`   |

- `import Base` and hub imports are skipped.
- The shortest path goes between real paths, with symlinks resolved.

### `layout/imports`

The import block.

- `import Base` comes first. The other imports follow, sorted by written path, then by alias, by
  code point.
- Each file is imported once. The fix removes a later import of the same file, and points the uses
  of its alias to the alias that stays.
- A comment line stays with the import below it. The block has no blank lines.

### `layout/case`

A name's case follows the kind of what it names.

| Kind                                              | Case              | Examples                     |
| ------------------------------------------------- | ----------------- | ---------------------------- |
| type, constructor, import alias                   | PascalCase        | `Maybe`, `Some{}`, `M`       |
| def whose written return type ends in a sort      | PascalCase        | `IO`, `Pair`, `Set()`        |
| parameter or field whose written type ends in one | PascalCase        | `-A: Type`, `F: U32 -> Type` |
| law, other def, parameter or field                | snake_case        | `add_comm`, `from_list`, `n` |
| variable, lambda, forall, def without a return    | either            | `Big`, `small`               |
| namespace segment                                 | its parent's case | `IO.print`, `Set.from_list`  |

- A sort is `Type`, `Data` or `Kind(..)`.
- `import Base`, and a def that fills a law of another file, are skipped.

### `layout/directive-order`

Directives on consecutive comment-only lines are in order: by rule, then severity, then keyword. The
fix writes them in that order, over the same comments, so `--fix` makes it.

### `no-unused/imports`

Each import must be used: a name written through its alias, or, for `import Base`, a name that only
Base declares. The fix removes the import.

## Suppress findings

A directive comment can silence a rule (`disable`) or require a finding (`expect`):

```
# bend-lint: disable-file layout/format -- generated tables not-expected-because: they change often
# bend-lint: disable-begin layout/format -- hand-aligned table not-expected-because: the format may change
# bend-lint: disable-end layout/format
# bend-lint: disable-next my/rule -- the old name stays not-expected-because: it is found only on old Bend
# bend-lint: expect-next my/rule@hint -- the sample must report this
```

Form: `# bend-lint: <disable|expect>-<scope> <rule>[@severity] -- <reason>`, and, for a `disable`,
`not-expected-because: <why>` after the reason.

| Scope           | Covers                            |
| --------------- | --------------------------------- |
| `file`          | the whole file                    |
| `begin` … `end` | the lines between them            |
| `next`          | the next line with code           |
| `line`          | its own line; it must follow code |

- One directive names one rule, and needs a reason. `end` takes none.
- A `disable` also says why it is not an `expect`. bend-lint does not check what either reason says.
- `expect` names the severity the finding must have. `disable` names none.
- A finding is covered when it starts on a covered line.
- The order of directives on consecutive lines is the rule `layout/directive-order`'s.
- Findings of the checker (`bend/...`) and of bend-lint (`bend-lint/...`) cannot be suppressed.

bend-lint reports problems with the directives:

| Code                          | Severity | When                        |
| ----------------------------- | -------- | --------------------------- |
| `bend-lint/directive`         | error    | a directive is wrong        |
| `bend-lint/unmet-expectation` | error    | an `expect` got no finding  |
| `bend-lint/unused-disable`    | warning  | a `disable` covered nothing |

## What can go wrong

| Problem                    | You get                        | Then                                                |
| -------------------------- | ------------------------------ | --------------------------------------------------- |
| The checker rejects a file | a `bend/check` error           | The rules that need the checker's facts do not run. |
| A rule crashes             | a `bend-lint/rule-crash` error | The other rules still run.                          |

## Where Bend comes from

- Building a rules program uses the `bend` on your PATH.
- The server loads Bend's TypeScript checker: from `$BEND_DIR` (a Bend checkout or its `bend2`
  folder), or else a release from GitHub, the one `bend version` names.
- Downloads and cached checks go to `~/.cache/bend-lint/` (`$XDG_CACHE_HOME`, or `%LOCALAPPDATA%` on
  Windows). You can delete this folder at any time.

## Write a rule

A rule is a Bend file. Put it in a rules program next to the bundled ones, build it, and run it.
[src/linter/RULES.md](src/linter/RULES.md) explains how.

## Work on bend-lint

See [AGENTS.md](AGENTS.md).
