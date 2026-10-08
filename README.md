# bend-lint

A linter and formatter for Bend 2. It checks your file with Bend's type
checker, then runs rules written in TypeScript or Bend. Rules can inspect
source text, types, variable scope and usage, and report findings with fixes.

## Quick start

Requires Bun 1.2 or newer. Clone this repo and run commands from its root:

```sh
git clone https://github.com/MattCozendey/bend-lint.git
cd bend-lint
bun install

# Check formatting
bun src/lint.ts example.bend --rules rules/format.ts

# Apply formatting
bun src/lint.ts example.bend --rules rules/format.ts --fix
```

Replace `example.bend` with your file's path. No lint rules run by default;
load them with `--rules`. Repeat the flag to load multiple rule files:

```sh
bun src/lint.ts example.bend --rules rules/format.ts --rules rules/file_length.bend
```

bend-lint loads Bend's source. By default, it uses a surrounding Bend
checkout, or downloads and caches the release matching `bend version`.
If Bend is not installed, it selects the latest release. To use a specific
checkout, pass `--bend /path/to/bend` (its `bend2` directory also works)
or set `BEND_DIR`. See [Bend loading](AGENTS.md#bend-loading) for
cache and offline behavior.

## Included rules

| File | Rule | Behavior | Defaults |
| --- | --- | --- | --- |
| `rules/format.ts` | `format/layout` | Formats indentation, spacing, comments, declaration gaps, wrapping and the final newline. Offers a safe fix. | `tabWidth: 2`, `wrapAtWidth: 100` |
| `rules/file_length.bend` | `style/file-length` | Warns when the root file exceeds the line limit. No fix. | `maxLines: 500` |

The formatter uses spaces for indentation. Both numeric options must be
positive integers; set `wrapAtWidth` to `"never"` to disable optional wrapping.
The width is a target: literals, comments and other indivisible text may
exceed it. Wrapped lists use one item per line; continuations use one extra
indentation level.

Formatting preserves literal contents and comment text, except for adding
a space after `#` when missing. Empty comments, `#|` test expectations,
`#!` directives and `##` headings keep their markers. Declarations keep
their order. Before offering a fix, the formatter reparses the result and
checks that the parsed program is unchanged. If that check fails, it reports
a warning without a fix.

The file-length rule counts physical lines in the root file, excluding
imports. A final newline does not add a line; an empty file has zero lines.

## Configuration

Put `bend-lint.json` in the linted file's directory or an ancestor, or select
one with `--config /path/to/bend-lint.json`:

```json
{
  "rules": {
    "format/layout": { "tabWidth": 2, "wrapAtWidth": 100 },
    "style/file-length": { "maxLines": 400, "severity": "warning" }
  }
}
```

Configuration adjusts rules loaded with `--rules`; it does not load them.
Set a rule to `"off"` to disable it. Severities are `error`, `warning`,
`information` and `hint`. An error finding stops later rules.

TypeScript rules can declare option defaults; unknown options or values of
the wrong type then cause a configuration error. Rules without declared
defaults validate their own options, including the formatter. Bend rules
read defaults through their option helpers; numeric values must fit a U32.

## Findings and fixes

Findings use Bend's diagnostic layout, with the rule ID and a diff for each
fix. Rules run in the order supplied, after the file passes Bend's checker.
A checker failure produces a `bend/check` error and skips all rules.
Unlike `bend --check-only`, using `@unsafe` or foreign code alone does not
make the check fail.

| Flag | Fixes applied |
| --- | --- |
| `--fix` | `safe`: intended to preserve behavior |
| `--fix-suggested` | `safe` and `suggested`: may change behavior |
| `--fix-dangerously` | All fixes, including `dangerous`: may break code |

The CLI applies fixes only when the run has no errors, and writes only to
the linted file. It does not edit imports or BendHub packages. Identical
edits merge; fixes that conflict with earlier ones are skipped and counted.
Run again to apply remaining fixes.

Use `--json` for machine-readable findings. Ranges use zero-based lines
and UTF-16 character offsets, as in LSP. See the
[JSON output reference](AGENTS.md#json-output).

Exit codes: `0` for a run without errors (warnings are allowed), `1` for a
checker or rule error, and `2` for invalid usage or a tool failure.

## Writing a rule

A TypeScript module exports a `rules` array. Save this as `my-rule.ts` in
the repo root:

```ts
import type { LintRule } from "./src/lint.ts";

export const rules: LintRule[] = [{
  id: "style/no-tabs",
  run(cx) {
    return [...cx.root.text.matchAll(/\t/g)].map((match) => cx.diag({
      message: "Use spaces instead of a tab.",
      spn: { file: cx.root.file, beg: match.index!, end: match.index! + 1 },
    }));
  },
}];
```

```sh
bun src/lint.ts example.bend --rules my-rule.ts
```

This rule checks raw text, including literals and comments. For rules that
need type information, request checker facts. Rules can also be written in
Bend; [file_length.bend](rules/file_length.bend) is a complete example.

See [Writing rules and using the API](AGENTS.md#writing-rules-and-using-the-api) for facts, fixes,
context helpers, Bend rules and programmatic use.

## Development

```sh
bun test
bun run typecheck
```

Bun does not check types. See [AGENTS.md](AGENTS.md) for the Bend checkout
setup, contribution rules, test guidance and implementation reference.
