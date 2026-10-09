# bend-lint

A linter and formatter for Bend 2.

```sh
bun src/lint.ts main.bend --rules rules/layout-format.bend --fix
```

## What it does

1. It checks each file with Bend's own type checker.
2. It runs the rules you load. A rule sees the source text and what the
   checker found: types, scope, and how often each variable is used.
3. It prints the findings. With a fix flag, it also writes the fixes.

No rule runs by default. Load rules with `--rules` or with the config.

## Setup

1. Install Bun 1.4.2.
2. On Windows, run Bend itself only through WSL, not natively (as of
   2026-10-09). See
   [Bend's platform limitations](https://github.com/bendlang/bend#limitations).
3. Run:

```sh
git clone https://github.com/MattCozendey/bend-lint.git
cd bend-lint
bun install
```

## Run it

```sh
bun src/lint.ts <glob>... [--imports | --no-imports] [--rules <file>]... [--config <file>]
                [--fix | --fix-suggested | --fix-dangerously]
                [--json] [--show-suppressed] [--bend <dir>]
```

| To lint         | Command                                                                |
| --------------- | ---------------------------------------------------------------------- |
| One file        | `bun src/lint.ts main.bend --rules rules/layout-format.bend`           |
| Many files      | `bun src/lint.ts "src/**/*.bend" --rules rules/layout-format.bend`     |
| A whole program | `bun src/lint.ts main.bend --imports --rules rules/layout-format.bend` |

### Inputs

- Each input is a glob. A plain path matches only that file.
- Use `/` in paths, on every system. An input with `\` is an error.
- Quote globs, so that bend-lint expands them the same way in every shell.
- An input that matches no file is an error.

### Which files get findings

Findings appear only in the **linted files**:

- Without `--imports`: each file you name.
- With `--imports`: the one file you name, and every file it imports, except
  Base and hub packages. `--imports` takes one file, and ignores `entries`.
- `"imports": true` in the config turns `--imports` on. `--no-imports` turns
  it off.

A rule can read more than the linted files. It still shows findings only in
them.

### Entries: lint one file, read the whole program

Some rules look at the whole program, for example "this def is never used".
When you lint `lib.bend` alone, such a rule cannot see `main.bend`, which
uses lib. So list your program's entry files in the config:

```json
{ "entries": ["main.bend", "tests/*.bend"] }
```

- When you lint a file that an entry imports, bend-lint checks the program
  from that entry. Findings still appear only in the file you named.
- A file that no entry imports is checked alone.
- With several entries that import the file, each entry's check runs. The
  rule decides whether a finding needs one entry (`some`, the default) or
  every entry (`every`).
- An entry that fails Bend's check is reported. Then:
  - an `every` rule does not run, since its answer would be incomplete;
  - a `some` rule reads the entries that passed, or, if none did, the file
    checked alone.
- An entry's check is reused for the next file while no file it read has
  changed.

### Fixes

Each fix is `safe`, `suggested` or `dangerous`.

| Flag                | Applies                                                  |
| ------------------- | -------------------------------------------------------- |
| `--fix`             | `safe` fixes. They keep what the program does.           |
| `--fix-suggested`   | `safe` and `suggested` fixes. These can change behavior. |
| `--fix-dangerously` | All fixes. These can break code.                         |

- Fixes are written to the linted files, also when the run has errors.
- A fix that edits more than one file is skipped.
- When two fixes overlap, the later one is skipped. Run again to apply it.

### Output and exit code

- `--json` prints one JSON object: `ok`, `findings` and `suppressed`.
  [AGENTS.md](AGENTS.md#json-output) shows the format.
- `--show-suppressed` also prints the findings that a directive covers.

| Exit code | Meaning                              |
| --------- | ------------------------------------ |
| 0         | No errors. Warnings do not count.    |
| 1         | A checker error or an error finding. |
| 2         | Bad arguments, or bend-lint failed.  |

## Config

bend-lint reads one config file:

1. the file `--config` names, or else
2. the nearest `bend-lint.json`, `bend-lint.js` or `bend-lint.ts`, from the
   linted file's folder up. In one folder, JSON wins, then JS, then TS.

```json
{
  "load": ["./rules/layout-format.bend"],
  "rules": {
    "layout/format": { "tabWidth": 2, "wrapAtWidth": 100, "severity": "warning" }
  }
}
```

| Key       | What                                                          |
| --------- | ------------------------------------------------------------- |
| `load`    | rule files, relative to the config. They run after `--rules`. |
| `entries` | globs of the program's entry files, relative to the config.   |
| `imports` | `true` to lint as with `--imports`.                           |
| `rules`   | per rule: `"off"`, or its options and a `severity`.           |

- Severities: `error`, `warning`, `information`, `hint`.
- An unknown option, or a value that does not fit, is an error.

A JS or TS config exports the same object as `config`:

```ts
export const config = { rules: { "layout/format": { tabWidth: 4 } } };
```

## Bundled rules

### `layout/format` (`rules/layout-format.bend`)

The formatter. It fixes indentation, spacing, comments, blank lines between
declarations, line wrapping and the final newline. Its fix is `safe`.

| Option        | Default | Values                           |
| ------------- | ------- | -------------------------------- |
| `tabWidth`    | `2`     | a positive integer               |
| `wrapAtWidth` | `100`   | a positive integer, or `"never"` |
| `endOfLine`   | `"lf"`  | `"lf"`, `"crlf"`, `"preserve"`   |

- `wrapAtWidth` is a target. Long literals and comments can go past it.
- Width counts code points. An emoji, a CJK character and a combining mark
  each count as 1.
- `"preserve"` keeps the first line ending, or LF if there is none.
- It keeps literals, comments and declaration order. The only change in a
  comment is a space after a `#` that has none.
- It parses its own output and compares it with the original. If they
  differ, you get a warning and no fix.

## Suppress findings

A directive comment can silence a rule (`disable`) or require a finding
(`expect`):

```
# bend-lint: disable-file layout/format -- generated tables
# bend-lint: disable-begin layout/format -- hand-aligned table
# bend-lint: disable-end layout/format
# bend-lint: disable-next my/rule -- the old name stays
# bend-lint: expect-next my/rule@hint -- the sample must report this
```

Form: `# bend-lint: <disable|expect>-<scope> <rule>[@severity] -- <reason>`

| Scope           | Covers                                                |
| --------------- | ----------------------------------------------------- |
| `file`          | the whole file                                        |
| `begin` … `end` | the lines between them; regions of one rule nest      |
| `next`          | the next line with code, past blank and comment lines |
| `line`          | its own line; it must follow code                     |

- One directive names one rule, and needs a reason. `end` takes none.
- `expect` names the severity the finding must have. `disable` names none.
- A finding is covered when it starts on a covered line of its own file.
- Only the directives of linted files count.
- `layout/format` reports on line 1. Use `file`, or a region that starts on
  line 1.
- Directives on consecutive comment lines must be sorted: by rule, then
  severity, then keyword. The `safe` fix sorts them.
- Findings of the checker (`bend/...`) and of bend-lint (`bend-lint/...`)
  cannot be suppressed.

bend-lint reports problems with the directives:

| Code                          | Severity | When                                 |
| ----------------------------- | -------- | ------------------------------------ |
| `bend-lint/directive`         | error    | a directive is wrong or out of order |
| `bend-lint/unmet-expectation` | error    | an `expect` got no finding           |
| `bend-lint/unused-disable`    | warning  | a `disable` covered nothing          |

A rule that crashed reports neither of the last two for its directives,
because its findings are unknown.

## What can go wrong

| Problem                    | You get                                                   | Then                                    |
| -------------------------- | --------------------------------------------------------- | --------------------------------------- |
| The checker rejects a file | a `bend/check` error, also when the error is in an import | Only the rules that read just text run. |
| A rule crashes             | a `bend-lint/rule-crash` error                            | The other rules still run.              |

## Where Bend comes from

bend-lint loads Bend's TypeScript source and patches it in memory. It does not
run the `bend` binary. It looks, in this order:

1. `--bend <dir>`, or `$BEND_DIR`: a Bend checkout or its `bend2` folder.
2. A release from GitHub: the one `bend version` names, or else the one this
   bend-lint is tested with.

Downloads go to `~/.cache/bend-lint/` (`$XDG_CACHE_HOME`, or `%LOCALAPPDATA%`
on Windows), and are reused.

## Write a rule

Save this as `no-tabs.ts` in the repo root:

```ts
import type { LintRule } from "./src/lint.ts";

export const rules: LintRule[] = [
  {
    id: "style/no-tabs",
    run: (cx) =>
      [...cx.root.text.matchAll(/\t/g)].map((match) =>
        cx.diag({
          message: "Use spaces instead of a tab.",
          span: { file: cx.root, beg: match.index!, end: match.index! + 1 },
        }),
      ),
  },
];
```

Run it:

```sh
bun src/lint.ts file.bend --rules no-tabs.ts
```

This rule reads raw text, so it also finds tabs in literals and comments. To
read types and scope, a rule asks for the checker's facts. Rules can also be
written in Bend. [AGENTS.md](AGENTS.md#writing-rules) explains both.

## Work on bend-lint

See [AGENTS.md](AGENTS.md).
