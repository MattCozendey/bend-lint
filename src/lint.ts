#!/usr/bin/env bun
// bend-lint checks a Bend file with bend's checker, then runs rules over
// its source and the checker's results. Rules are TS modules, or Bend files
// built on ./bend/lint.bend. It reaches bend2 only through ./seam.ts; anything
// there it cannot follow stops it with a drift error. The types below are
// bend-lint's own, so a rule does not depend on bend2's internals. Entry
// points return a Result rather than throw. As a CLI, it exits 0 when ok,
// 1 when it found an error, 2 on bad usage or a tool failure.

import * as url from "node:url";
import * as util from "node:util";

import { ERROR, ERROR_METADATA, error, ok, unwrap } from "./result.ts";
import type { Result } from "./result.ts";
import {
  DRIFT,
  check,
  compile,
  fs,
  layout,
  line,
  load,
  message,
  operations,
  path,
  select,
  starts,
} from "./seam.ts";
import type { Loaded, Unstable } from "./seam.ts";

// Types
// =====

export type Severity = "error" | "warning" | "information" | "hint";
// safe keeps behavior; suggested may change it; dangerous may break code.
export type Applicability = "safe" | "suggested" | "dangerous";

// A file of the book, as it is on disk (or as the editor holds it unsaved).
export type Source = { path: string; text: string; root: boolean; base: boolean };

// A range of a source, in UTF-16 offsets.
export type Span = { file: Source; beg: number; end: number };

export type Edit = { span: Span; text: string };
export type Fix = { title: string; applicability: Applicability; edits: Edit[] };

declare const OPAQUE: unique symbol;

// A node of a checked body, and a type with the scope it belongs to, as
// handles: what they hold is bend2's, and a rule reaches it only through
// the RuleContext.
export type Node = { readonly [OPAQUE]: "node" };
export type Type = { readonly [OPAQUE]: "type" };

// A node: its kind, annotations kept (Ann, Var, App, ...), the name a Var
// or Ref points to (else ""), its span, and its children, in bend's order.
export type Shape = { kind: string; name: string; span?: Span; children: Node[] };

// How many times a term is demanded, or a variable is used.
export type Quantity = "erased" | "once" | "many";

// What the checker found for a node: the def whose body holds it, how many
// times it is demanded, the type it was checked as, and the source it
// checked, annotations included (the node itself may have no span). A
// template body is checked as written, then again for each instance
// (generic~0) at the same spans; `inst` marks the facts of an instance.
export type Fact = {
  node: Node;
  owner: string;
  inst: boolean;
  quantity: Quantity;
  type: Type;
  span?: Span;
};

export type Diag = {
  code: string;
  severity: Severity;
  message: string;
  span?: Span;
  def?: string;
  fact?: Fact; // its scope shows as the finding's context
  fixes: Fix[];
  core?: unknown; // bend's own failure, when the check failed
};

export type DiagInit = {
  message: string;
  severity?: Severity;
  span?: Span;
  fact?: Fact;
  def?: string;
  fixes?: Fix[];
};

// The checker's facts a rule gets. A fact must match each list given; an
// absent or empty list matches all. In defs, a template's instances
// (generic~0) count as the template.
export type FactFilter = {
  scope?: "file" | "program"; // file (the default): the linted file; program: its imports too, never Base
  kinds?: string[]; // the term's kind, annotations stripped: Var, Ref, App, ...
  defs?: string[]; // the def whose body holds the term
  names?: string[]; // the name a Var or Ref points to
  instances?: boolean; // true: also the facts of template instances (generic~0)
};

// `same`, `show` and `normal` work in the scope of the (first) type.
// `unstable` is bend2's own objects: code that uses it breaks when bend2
// changes.
export type RuleContext = {
  sources: Source[];
  root: Source;
  options: Options; // the rule's defaults, with the config's values
  facts: Fact[]; // the facts it asked for; none if it asked for none
  prior: readonly Diag[]; // what earlier rules found
  signal: AbortSignal; // aborts with the run
  body(name: string): Node | undefined; // a def's checked body
  shape(node: Node): Shape;
  nodes(root: Node): Node[]; // root and every node under it, parents first
  parent(node: Node): Node | undefined;
  strip(node: Node): Node; // the node without its annotations
  fact(node: Node): Fact | undefined; // the node's fact, if this rule asked for it
  binder(fact: Fact): Type | undefined; // the declared type of the variable a Var fact uses
  uses(fact: Fact): Array<{ name: string; quantity: Quantity }>;
  same(a: Type, b: Type): boolean;
  show(type: Type): string;
  normal(type: Type): Type;
  sameDeclarations(text: string): boolean; // whether `text` declares what the linted file declares
  diag(init: DiagInit): Diag;
  unstable: Unstable;
};

export type OptionValue = number | boolean | string;
export type Options = Record<string, OptionValue>;

// What a rule option accepts: a small part of JSON Schema. A value must
// match each part given: its type ("integer": a whole number), one of
// enum, at least minimum, at most maximum, and one of anyOf.
export type OptionSchema = {
  type?: "integer" | "number" | "boolean" | "string";
  enum?: OptionValue[];
  minimum?: number;
  maximum?: number;
  anyOf?: OptionSchema[];
};

// Config: rule files to load (readConfig makes them absolute), and per
// rule id, "off", or a severity and option values.
export type Config = {
  load?: string[];
  rules?: Record<string, "off" | ({ severity?: Severity } & Options)>;
};

// `unsaved` maps file paths to text an editor holds but has not saved. bend
// and the rules read it in place of the file, for that run only.
export type LintOptions = {
  signal?: AbortSignal;
  config?: Config;
  unsaved?: ReadonlyMap<string, string>;
};

export type LintRule = {
  id: string; // namespace/name; the code of its findings
  facts?: true | FactFilter; // the checker's facts it needs; true: all of the linted file's
  options?: Record<string, OptionSchema & { default: OptionValue }>; // what it accepts; none if absent
  run(cx: RuleContext): Diag[] | Promise<Diag[]>;
};

// root: the linted file, unless bend could not read it. facts: those kept
// for the rules.
export type LintResult = {
  diags: Diag[];
  sources: Source[];
  root?: Source;
  facts: Fact[];
  unstable: Unstable;
};

// Why an entry point failed: a bad config, a rule file or rule that does
// not load, no bend to load, bend changed in a way bend-lint does not
// follow (drift), an abort, or a bug (internal).
export type LintError = {
  type: "config" | "rule-module" | "bend-missing" | "drift" | "aborted" | "internal";
  [ERROR_METADATA]: { message: string; cause: unknown };
};

// bend-lint over one bend2. Rules from bendRule and loadRules work only
// with the linter that made them.
export type Linter = {
  BEND2: string; // the bend2 folder it uses
  lint: (
    file: string,
    rules: LintRule[],
    options?: LintOptions,
  ) => Promise<Result<LintResult, LintError>>;
  bendRule: (file: string) => Promise<Result<LintRule, LintError>>;
  loadRules: (files: string[]) => Promise<Result<LintRule[], LintError>>;
  render: (d: Diag) => string;
};

// An LSP position: 0-based line and character, in UTF-16 units.
export type Position = { line: number; character: number };

// A span as lint.bend has it: a file's path and two code-point offsets.
type Spot = { path: string; beg: number; end: number };

// What a Bend rule reports, as effects.js reads it.
// A fact as it crosses to a Bend rule: its node and type as indexes.
type Wire = Omit<Fact, "node" | "type" | "span"> & { node: number; type: number; span?: Spot };

// A finding as it crosses: from a Bend rule its fact is a node index (A
// = number); to one, as a prior finding, a Wire.
type Reported<A> = {
  severity: Severity;
  message: string;
  span?: Spot;
  fixes: Array<{
    title: string;
    applicability: Applicability;
    edits: Array<{ span: Spot; text: string }>;
  }>;
  about?: A;
};

// What effects.js asks of bend-lint while a Bend rule runs. Nodes and types
// cross as indexes into the run's tables; a fact, by its node.
type Channel = {
  input(): {
    sources: Array<{ path: string; text: string; root: boolean }>;
    options: Options;
    prior: Array<{ code: string; diag: Reported<Wire> }>;
  };
  sameDeclarations(text: string): boolean;
  aborted(): boolean;
  next(): Wire | undefined;
  report(diags: Array<Reported<number>>): void;
  text(span: Spot): string;
  body(name: string): number | undefined;
  shape(node: number): Omit<Shape, "span" | "children"> & { span?: Spot; children: number[] };
  nodes(root: number): number[];
  parent(node: number): number | undefined;
  strip(node: number): number;
  fact(node: number): Wire | undefined;
  binder(node: number): number | undefined;
  uses(node: number): Array<{ name: string; quantity: Quantity }>;
  same(a: number, b: number): boolean;
  show(t: number): string;
  normal(t: number): number;
};

// Constants
// =========

const RULE_ID = /^[^/\s]+\/[^/\s]+$/;
const CRASH = "bend-lint/rule-crash";
const SCOPES = ["file", "program"];
const CONFIG_FILES = ["bend-lint.json", "bend-lint.js", "bend-lint.ts"];
const LINE = /[^\n]*\n|[^\n]+$/g;
const HEAD: Record<Severity, string> = {
  error: "Error",
  warning: "Warning",
  information: "Information",
  hint: "Hint",
};

const shared = globalThis as typeof globalThis & { BEND_LINT?: Channel };

// Compiled Bend rules, by bend2 folder and path, with the text they were
// compiled from.
const COMPILED = new Map<string, { text: string; rule: LintRule }>();

// Linters, by the --bend folder asked for ("" for none).
const LINTERS = new Map<string, Promise<Result<Linter, LintError>>>();

// Errors whose cause bend-lint knows.
const CAUSES = new WeakMap<object, LintError["type"]>();

const OPTIONS = {
  rules: { type: "string", multiple: true },
  fix: { type: "boolean" },
  "fix-suggested": { type: "boolean" },
  "fix-dangerously": { type: "boolean" },
  json: { type: "boolean" },
  config: { type: "string" },
  bend: { type: "string" },
  help: { type: "boolean", short: "h" },
} as const;

const USAGE =
  "usage: bun src/lint.ts <file.bend> [--rules <rules.ts|rule.bend>]... [--config <config.json|config.js|config.ts>] [--fix | --fix-suggested | --fix-dangerously] [--json] [--bend <dir>]";

// The fix levels each flag applies; the widest flag given wins.
const FIXES: ReadonlyArray<
  readonly ["fix" | "fix-suggested" | "fix-dangerously", Applicability[]]
> = [
  ["fix-dangerously", ["safe", "suggested", "dangerous"]],
  ["fix-suggested", ["safe", "suggested"]],
  ["fix", ["safe"]],
];

// Functions
// =========

// The bend-lint over the bend2 that --bend, $BEND_DIR or the search in
// seam.ts finds; made once per folder asked for, and again after a failure.
export const createLinter = ({ bend }: { bend?: string } = {}): Promise<
  Result<Linter, LintError>
> => {
  const key = bend ?? "";
  const made =
    LINTERS.get(key) ??
    attempted("bend-missing", async () => linterOf(await load(bend))).then((res) => {
      if (ERROR in res) {
        LINTERS.delete(key);
      }
      return res;
    });
  LINTERS.set(key, made);
  return made;
};

const linterOf = (m: Loaded): Linter => ({
  BEND2: m.BEND2,
  lint: (file, rules, options = {}) =>
    attempted("internal", () => lintWith(m, file, rules, options), options.signal),
  bendRule: (file) => attempted("rule-module", () => bendRuleFrom(m, file)),
  loadRules: (files) => attempted("rule-module", () => rulesFrom(m, files)),
  render: (d) => renderWith(m, d),
});

// A config file; its `load` paths become absolute, from the file's folder.
export const readConfig = (file: string): Promise<Result<Config, LintError>> =>
  attempted("config", () => configAt(file));

// The nearest config; JSON, JS, then TS within each directory.
export const findConfig = (file: string): Promise<Result<Config, LintError>> =>
  attempted("config", () => nearestConfig(file));

// `e`, caused by `cause`, unless it already says what caused it.
const blame = (cause: LintError["type"], e: unknown): unknown => {
  if (typeof e === "object" && e !== null && !CAUSES.has(e)) {
    CAUSES.set(e, cause);
  }
  return e;
};

const fault = (cause: LintError["type"], message: string): unknown =>
  blame(cause, new Error(message));

// `e` as a LintError: an abort, a drift error, what blamed it, or `fallback`.
const settle = (fallback: LintError["type"], e: unknown, signal?: AbortSignal): LintError => {
  const known = typeof e === "object" && e !== null ? CAUSES.get(e) : undefined;
  const drifted = (e as { [DRIFT]?: boolean } | null)?.[DRIFT] === true;
  return {
    type: signal?.aborted ? "aborted" : drifted ? "drift" : (known ?? fallback),
    [ERROR_METADATA]: { message: message(e), cause: e },
  };
};

const attempted = async <T>(
  fallback: LintError["type"],
  f: () => T | Promise<T>,
  signal?: AbortSignal,
): Promise<Result<T, LintError>> => {
  try {
    return ok(await f());
  } catch (e) {
    return error(settle(fallback, e, signal));
  }
};

const configAt = (file: string): Config => {
  try {
    const config: Config = [".js", ".ts"].includes(path.extname(file))
      ? exported(file)
      : JSON.parse(fs.readFileSync(file, "utf8"));
    if (!strings(config.load)) {
      throw new Error("`load` must be a list of rule files");
    }
    const at = path.dirname(path.resolve(file));
    return config.load === undefined
      ? config
      : { ...config, load: config.load.map((p) => path.resolve(at, p)) };
  } catch (e) {
    throw fault("config", file + ": " + message(e));
  }
};

// A JS or TS config's named `config` export.
const exported = (file: string): Config => {
  const module = import.meta.require(url.pathToFileURL(path.resolve(file)).href);
  if (!Object.hasOwn(module, "config")) {
    throw new Error("must export a named `config` object");
  }
  if (typeof module.config !== "object" || module.config === null || Array.isArray(module.config)) {
    throw new Error("`config` must be an object");
  }
  return module.config;
};

// The rules of rule files: a TS or JS module's `rules`, or a Bend rule. A
// Bend rule is compiled again only when its text changes.
const rulesFrom = async (m: Loaded, files: string[]): Promise<LintRule[]> => {
  const modules = await Promise.all(
    files.map(async (file): Promise<LintRule[]> => {
      if (file.endsWith(".bend")) {
        const text = fs.readFileSync(file, "utf8");
        const key = m.BEND2 + "\0" + path.resolve(file);
        const known = COMPILED.get(key);
        const rule = known?.text === text ? known.rule : await bendRuleFrom(m, file);
        COMPILED.set(key, { text, rule });
        return [rule];
      }
      const { rules } = await import(url.pathToFileURL(path.resolve(file)).href);
      if (!Array.isArray(rules)) {
        throw new Error(file + " must export `rules`, an array of rules");
      }
      return rules;
    }),
  );
  return modules.flat();
};

const nearestConfig = (file: string): Config => {
  for (let dir = path.dirname(path.resolve(file)); ; dir = path.dirname(dir)) {
    const config = CONFIG_FILES.map((name) => path.join(dir, name)).find((candidate) =>
      fs.existsSync(candidate),
    );
    if (config !== undefined) {
      return configAt(config);
    }
    if (path.dirname(dir) === dir) {
      return {};
    }
  }
};

// Whether a value matches an option's schema.
const fits = (s: OptionSchema, v: unknown): boolean =>
  ["number", "boolean", "string"].includes(typeof v) &&
  (s.type === undefined || (s.type === "integer" ? Number.isInteger(v) : typeof v === s.type)) &&
  (s.enum === undefined || s.enum.includes(v as OptionValue)) &&
  (s.minimum === undefined || (typeof v === "number" && v >= s.minimum)) &&
  (s.maximum === undefined || (typeof v === "number" && v <= s.maximum)) &&
  (s.anyOf === undefined || s.anyOf.some((a) => fits(a, v)));

const strings = (xs: unknown): boolean =>
  xs === undefined || (Array.isArray(xs) && xs.every((x) => typeof x === "string"));

const validFacts = (f: LintRule["facts"]): boolean =>
  f === undefined ||
  f === true ||
  (typeof f === "object" &&
    f !== null &&
    (f.scope === undefined || SCOPES.includes(f.scope)) &&
    strings(f.kinds) &&
    strings(f.defs) &&
    strings(f.names) &&
    [undefined, true, false].includes(f.instances));

const validOptions = (o: LintRule["options"]): boolean =>
  o === undefined ||
  (typeof o === "object" &&
    o !== null &&
    Object.values(o).every((s) => typeof s === "object" && s !== null && fits(s, s.default)));

// What the config says for a rule: off, a severity, and its options (the
// defaults, with the given values, which must be declared and match).
const settings = (
  rule: LintRule,
  config: Config,
): { off: boolean; severity?: Severity; options: Options } => {
  const given = config.rules?.[rule.id];
  const where = "bend-lint config: " + rule.id;
  const defaults = Object.fromEntries(
    Object.entries(rule.options ?? {}).map(([key, s]) => [key, s.default]),
  );
  if (given === undefined || given === "off") {
    return { off: given === "off", options: defaults };
  }
  if (typeof given !== "object" || given === null) {
    throw fault("config", where + ' must be "off" or an object');
  }
  const { severity, ...options } = given;
  if (severity !== undefined && !Object.hasOwn(HEAD, severity)) {
    throw fault("config", where + ": severity must be one of " + Object.keys(HEAD).join(", "));
  }
  for (const [key, value] of Object.entries(options)) {
    const schema =
      rule.options !== undefined && Object.hasOwn(rule.options, key)
        ? rule.options[key]
        : undefined;
    if (schema === undefined) {
      throw fault("config", where + " has no option " + key);
    }
    if (!fits(schema, value)) {
      const shown = JSON.stringify(schema, (k, v) => (k === "default" ? undefined : v));
      throw fault("config", `${where}: ${key} must match ${shown}`);
    }
  }
  return { off: false, severity, options: { ...defaults, ...options } };
};

// The given rules run in order, then the config's `load` files' that are
// not given already; the config may turn one off, set its severity, and
// give its options. A rule that throws is a bend-lint/rule-crash finding,
// and the run goes on; an abort reaches the caller.
const lintWith = async (
  m: Loaded,
  file: string,
  given: LintRule[],
  {
    signal = new AbortController().signal,
    config = nearestConfig(file),
    unsaved: held,
  }: LintOptions,
): Promise<LintResult> => {
  const extra = await rulesFrom(m, config.load ?? []).catch((e: unknown) => {
    throw blame("rule-module", e);
  });
  const rules = [...given, ...extra.filter((r, i) => !given.includes(r) && extra.indexOf(r) === i)];
  const bad = rules.findIndex(
    (r) =>
      !RULE_ID.test(String(r?.id)) ||
      typeof r?.run !== "function" ||
      !validFacts(r.facts) ||
      !validOptions(r.options),
  );
  if (bad >= 0) {
    throw fault(
      "rule-module",
      `invalid rule at ${bad} (${JSON.stringify(rules[bad]?.id)}): it needs an id like ns/name, a run function, facts, if given, true or a FactFilter, and options, if given, schemas their defaults match`,
    );
  }
  const plans = rules
    .map((rule) => ({
      rule,
      ...settings(rule, config),
      want: rule.facts === true ? {} : rule.facts,
    }))
    .filter((p) => !p.off);
  const wide = {
    program: plans.some((p) => p.want?.scope === "program"),
    instances: plans.some((p) => p.want?.instances === true),
  };
  const checked = await check(
    m,
    file,
    plans.flatMap((p) => (p.want === undefined ? [] : [p.want])),
    signal,
    held,
  );
  const { sources, facts, failure } = checked;
  const ops = operations(m, checked);
  const failed = failure === undefined ? [] : [failure];
  const root = sources.find((s) => s.root);
  if (root === undefined) {
    return { diags: failed, sources, facts, unstable: ops.unstable };
  }
  // What one rule finds; a rule that throws or reports a bad fix fails.
  const run = async (
    { rule, severity, options, want }: (typeof plans)[number],
    prior: Diag[],
  ): Promise<Diag[]> => {
    const mine = want === undefined ? [] : select(m, checked, want, wide);
    const asked = new Set(mine);
    const out = await rule.run({
      ...ops,
      sources,
      root,
      options,
      facts: mine,
      fact: (node) => {
        const fact = ops.fact(node);
        return fact !== undefined && asked.has(fact) ? fact : undefined;
      },
      prior,
      signal,
      diag: (d) => ({
        code: rule.id,
        severity: d.severity ?? "warning",
        message: d.message,
        span: d.span,
        def: d.def ?? d.fact?.owner,
        fact: d.fact,
        fixes: d.fixes ?? [],
      }),
    });
    if (!Array.isArray(out)) {
      throw new TypeError("it must return an array of diagnostics");
    }
    const settled = out.map((d): Diag => ({
      ...d,
      code: rule.id,
      severity: severity ?? d.severity,
    }));
    const broken = settled
      .flatMap((d) => d.fixes)
      .find((f) =>
        f.edits.some(
          ({ span }, i) =>
            !validRange(span.beg, span.end, span.file.text.length) ||
            f.edits.some((o, j) => j !== i && clash(f.edits[i], o)),
        ),
      );
    if (broken !== undefined) {
      throw new TypeError(
        'fix "' + broken.title + '" has an edit out of bounds, or two that clash',
      );
    }
    return settled;
  };
  // Without the checker's facts, only the rules that need none run.
  const runnable = plans.filter((p) => failure === undefined || p.want === undefined);
  let diags: Diag[] = failed;
  for (const plan of runnable) {
    signal.throwIfAborted();
    const found = await run(plan, diags).catch((e: unknown): Diag[] => {
      if (signal.aborted) {
        throw signal.reason;
      }
      return [
        {
          code: CRASH,
          severity: "error",
          message: plan.rule.id + ": " + message(e),
          fixes: [],
        },
      ];
    });
    diags = [...diags, ...found];
  }
  return { diags, sources, root, facts, unstable: ops.unstable };
};

const validRange = (beg: number, end: number, length: number): boolean =>
  Number.isInteger(beg) && Number.isInteger(end) && beg >= 0 && beg <= end && end <= length;

// Whether two edits to one file cannot both apply: their ranges overlap,
// or they insert at the same point.
const clash = (a: Edit, b: Edit): boolean =>
  a.span.file === b.span.file &&
  ((a.span.beg < b.span.end && b.span.beg < a.span.end) ||
    (a.span.beg === b.span.beg && a.span.end === b.span.end));

// `text` with edits applied; their spans are offsets into `text`, and they
// do not clash.
const apply = (text: string, edits: Edit[]): string =>
  [...edits]
    .sort((a, b) => b.span.beg - a.span.beg || b.span.end - a.span.end)
    .reduce((s, { span, text: t }) => s.slice(0, span.beg) + t + s.slice(span.end), text);

// The text of `file` with the fixes of the given levels applied, in order.
// An edit equal to one already taken is merged; a fix with an edit that
// clashes with one already taken is skipped and counted. A fix for other
// files is left out; one that edits `file` and another file is skipped
// whole, never half applied, and counted apart.
export const applyFixes = (
  file: Source,
  diags: Diag[],
  levels: Applicability[] = ["safe"],
): { text: string; skipped: number; elsewhere: number } => {
  const kept: Edit[] = [];
  let skipped = 0;
  let elsewhere = 0;
  for (const fix of diags.flatMap((d) => d.fixes).filter((f) => levels.includes(f.applicability))) {
    if (fix.edits.every((e) => e.span.file !== file)) {
      continue;
    }
    if (fix.edits.some((e) => e.span.file !== file)) {
      elsewhere += 1;
      continue;
    }
    const fresh = fix.edits.filter(
      (e) =>
        !kept.some(
          (k) => k.span.beg === e.span.beg && k.span.end === e.span.end && k.text === e.text,
        ),
    );
    if (fresh.some((e) => kept.some((k) => clash(k, e)))) {
      skipped += 1;
    } else {
      kept.push(...fresh);
    }
  }
  return { text: apply(file.text, kept), skipped, elsewhere };
};

// bend's own error layout; the head names the severity and the code, and
// each fix follows as a unified diff of the lines it touches.
const renderWith = (m: Loaded, d: Diag): string => {
  const fixes = d.fixes.map(
    (fix) =>
      `\n\nFix: ${fix.title} [${fix.applicability}]` +
      [...new Set(fix.edits.map((e) => e.span.file))]
        .map((file) => {
          const mine = fix.edits.filter((e) => e.span.file === file);
          const ls = starts(file, file.text);
          const first = line(ls, Math.min(...mine.map((e) => e.span.beg)));
          const from = ls[first];
          const to = ls[line(ls, Math.max(...mine.map((e) => e.span.end))) + 1] ?? file.text.length;
          const old = file.text.slice(from, to);
          const gone = old.match(LINE) ?? [];
          const came =
            apply(
              old,
              mine.map((e) => ({
                ...e,
                span: { ...e.span, beg: e.span.beg - from, end: e.span.end - from },
              })),
            ).match(LINE) ?? [];
          const name = file.path;
          const range = (n: number): string => (n === 0 ? first : first + 1) + "," + n;
          const show = (xs: string[], sign: string): string[] =>
            xs.map(
              (l) =>
                sign +
                l.replace(/\r?\n$/, "") +
                (l.endsWith("\n") ? "" : "\n\\ No newline at end of file"),
            );
          return (
            `\n--- ${name}\n+++ ${name}\n@@ -${range(gone.length)} +${range(came.length)} @@\n` +
            [...show(gone, "-"), ...show(came, "+")].join("\n")
          );
        })
        .join(""),
  );
  return layout(m, d, HEAD[d.severity] + " [" + d.code + "]:") + fixes.join("");
};

// The LSP range of a span in a file on disk.
export const position = (span: Span): { start: Position; end: Position } => {
  const ss = starts(span.file, span.file.text);
  const at = (off: number): Position => {
    const i = line(ss, off);
    return { line: i, character: off - ss[i] };
  };
  return { start: at(span.beg), end: at(span.end) };
};

// A rule written in Bend: a file built on ./bend/lint.bend (see there). It is
// checked and compiled once; each run calls its main, while effects.js
// reaches bend-lint through globalThis.BEND_LINT. Offsets cross as code points.
const bendRuleFrom = async (m: Loaded, file: string): Promise<LintRule> => {
  const checked = await check(m, file, [], new AbortController().signal);
  if (checked.failure !== undefined) {
    throw fault("rule-module", file + " does not check:\n" + renderWith(m, checked.failure));
  }
  const { id, want, options, main } = compile(m, checked, file);
  return {
    id,
    ...(want === null ? {} : { facts: want }),
    ...(options === undefined ? {} : { options }),
    run: (cx) => {
      const tables = new Map<string, { points: number[]; units: number[] }>();
      const table = (text: string): { points: number[]; units: number[] } => {
        const known = tables.get(text);
        if (known !== undefined) {
          return known;
        }
        const points: number[] = [];
        const units: number[] = [];
        for (const ch of text) {
          units.push(points.length);
          points.push(...Array<number>(ch.length).fill(units.length - 1));
        }
        units.push(points.length);
        points.push(units.length - 1);
        tables.set(text, { points, units });
        return { points, units };
      };
      const spotOf = (span: Span): Spot => {
        const { points } = table(span.file.text);
        return { path: span.file.path, beg: points[span.beg], end: points[span.end] };
      };
      const spot = (span: Span | undefined): Spot | undefined => span && spotOf(span);
      const span = (s: Spot): Span => {
        const src = cx.sources.find((x) => x.path === s.path);
        if (src === undefined) {
          throw new Error("it reported a span in " + s.path + ", which is not in the book");
        }
        const { units } = table(src.text);
        const at = (n: number): number => units[Math.min(n, units.length - 1)];
        return { file: src, beg: at(s.beg), end: at(s.end) };
      };
      let given = 0;
      const types: Type[] = [];
      const nodes: Node[] = [];
      const pick = <T>(xs: T[], i: number, what: string): T => {
        if (xs[i] === undefined) {
          throw new Error("it asked about " + what + " " + i + ", which it was not given");
        }
        return xs[i];
      };
      const keep = (t: Type): number => types.push(t) - 1;
      const hold = (n: Node): number => nodes.push(n) - 1;
      const wire = (f: Fact): Wire => ({
        ...f,
        node: hold(f.node),
        type: keep(f.type),
        span: spot(f.span),
      });
      const factOf = (i: number): Fact => {
        const f = cx.fact(pick(nodes, i, "node"));
        if (f === undefined) {
          throw new Error("it asked about node " + i + ", which has no fact for it");
        }
        return f;
      };
      const found: Array<Array<Reported<number>>> = [];
      shared.BEND_LINT = {
        input: () => ({
          sources: cx.sources.map((s) => ({ path: s.path, text: s.text, root: s.root })),
          options: cx.options,
          prior: cx.prior.map((d) => ({
            code: d.code,
            diag: {
              severity: d.severity,
              message: d.message,
              span: spot(d.span),
              fixes: d.fixes.map((f) => ({
                ...f,
                edits: f.edits.map((e) => ({ span: spotOf(e.span), text: e.text })),
              })),
              about: d.fact && wire(d.fact),
            },
          })),
        }),
        sameDeclarations: (text) => cx.sameDeclarations(text),
        aborted: () => cx.signal.aborted,
        next: () => (given < cx.facts.length ? wire(cx.facts[given++]) : undefined),
        report: (diags) => void found.push(diags),
        text: (s) => {
          const { file, beg, end } = span(s);
          return file.text.slice(beg, end);
        },
        body: (name) => {
          const n = cx.body(name);
          return n === undefined ? undefined : hold(n);
        },
        shape: (i) => {
          const { span, children, ...rest } = cx.shape(pick(nodes, i, "node"));
          return { ...rest, span: spot(span), children: children.map(hold) };
        },
        nodes: (i) => cx.nodes(pick(nodes, i, "node")).map(hold),
        parent: (i) => {
          const p = cx.parent(pick(nodes, i, "node"));
          return p === undefined ? undefined : hold(p);
        },
        strip: (i) => hold(cx.strip(pick(nodes, i, "node"))),
        fact: (i) => {
          const f = cx.fact(pick(nodes, i, "node"));
          return f === undefined ? undefined : wire(f);
        },
        binder: (i) => {
          const t = cx.binder(factOf(i));
          return t === undefined ? undefined : keep(t);
        },
        uses: (i) => cx.uses(factOf(i)),
        same: (a, b) => cx.same(pick(types, a, "term"), pick(types, b, "term")),
        show: (t) => cx.show(pick(types, t, "term")),
        normal: (t) => keep(cx.normal(pick(types, t, "term"))),
      };
      let code: number;
      try {
        code = main([file]);
      } finally {
        shared.BEND_LINT = undefined;
      }
      if (code !== 0 || found.length !== 1) {
        throw new Error(
          "it exited with " + code + " after " + found.length + " reports; it must report once",
        );
      }
      return found[0].map((d) =>
        cx.diag({
          message: d.message,
          severity: d.severity,
          span: d.span && span(d.span),
          fact: d.about === undefined ? undefined : factOf(d.about),
          fixes: d.fixes.map((f) => ({
            ...f,
            edits: f.edits.map((e) => {
              const at = span(e.span);
              if (!validRange(e.span.beg, e.span.end, table(at.file.text).units.length - 1)) {
                throw new TypeError('fix "' + f.title + '" has an edit out of bounds');
              }
              return { span: at, text: e.text };
            }),
          })),
        }),
      );
    },
  };
};

const cli = async (argv: string[]): Promise<number> => {
  const { values, positionals } = util.parseArgs({
    args: argv,
    options: OPTIONS,
    allowPositionals: true,
  });
  if (values.help) {
    console.log(USAGE);
    return 0;
  }
  if (positionals.length !== 1) {
    throw new Error("give one .bend file\n" + USAGE);
  }
  const linter = unwrap(await createLinter({ bend: values.bend }));
  const rules = unwrap(await linter.loadRules(values.rules ?? []));
  const config = values.config === undefined ? undefined : unwrap(await readConfig(values.config));
  const res = unwrap(await linter.lint(positionals[0], rules, { config }));
  const failed = res.diags.some((d) => d.severity === "error");
  const where = (span: Span) => ({ path: span.file.path, range: position(span) });
  console.log(
    values.json
      ? JSON.stringify(
          {
            ok: !failed,
            findings: res.diags.map((d) => ({
              code: d.code,
              severity: d.severity,
              message: d.message,
              def: d.def,
              ...(d.span && where(d.span)),
              fixes: d.fixes.map((f) => ({
                ...f,
                edits: f.edits.map((e) => ({ ...where(e.span), text: e.text })),
              })),
            })),
          },
          null,
          2,
        )
      : [
          ...res.diags.map(linter.render),
          failed ? "bend-lint: FAIL" : "bend-lint: " + res.diags.length + " finding(s)",
        ].join("\n\n"),
  );
  const { root } = res;
  const levels = FIXES.find(([flag]) => values[flag])?.[1];
  if (levels === undefined || root === undefined) {
    return failed ? 1 : 0;
  }
  const { text, skipped, elsewhere } = applyFixes(root, res.diags, levels);
  if (text !== root.text) {
    fs.writeFileSync(root.path, text);
    console.error("bend-lint: fixed " + root.path);
  }
  if (skipped > 0) {
    console.error(
      `bend-lint: skipped ${skipped} fix(es) that clash with earlier ones; run the fix again to apply them`,
    );
  }
  if (elsewhere > 0) {
    console.error(
      `bend-lint: skipped ${elsewhere} fix(es) that also edit other files; --fix writes only ${root.path}`,
    );
  }
  return failed ? 1 : 0;
};

const fail = (e: unknown): never => {
  console.error("bend-lint: " + message(e));
  process.exit(2);
};

// Side effects
// ============

if (import.meta.main) {
  process.exit(await cli(process.argv.slice(2)).catch(fail));
}
