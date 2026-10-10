# Running rules and printing what they find. A rules program calls `run` with its rules: `Cli.run(~[R.rule()])`.
import Base
import ./config.bend as Config
import ./directives.bend as Directives
import ./lint.bend as Lint
import ./program.bend as Program
import ./shared.bend as Shared

# Running
# =======

# Where rules run: on one file, for file rules, or on the whole program, for program rules.
type Place is Data:
  AtFile{here: Lint.Here}
  AtProgram{whole: Lint.Whole}

def Rule.id(rule: Lint.Rule) -> Lint.Rule & String:
  match rule:
    case Lint.FileRule{+id, run}:
      (Lint.FileRule{id, run}, id)
    case Lint.ProgramRule{+id, entries, run}:
      (Lint.ProgramRule{id, entries, run}, id)

# Whether the config leaves a rule on.
def Setting.on(setting: Maybe<&2, Config.Setting>) -> Bool:
  match setting:
    case Some{Config.RuleOff{}}:
      False{}
    case _:
      True{}

# The severity the config gives a rule's findings, if it gives one.
def Setting.severity(setting: Maybe<&2, Config.Setting>) -> Maybe<&2, Lint.Severity>:
  match setting:
    case Some{Config.RuleSeverity{s}}:
      Some{s}
    case _:
      None{}

def Rule.keep.if(on: Bool, rule: Lint.Rule, out: List<&1, Lint.Rule>) -> List<&1, Lint.Rule>:
  match on:
    case True{}:
      rule <> out
    case False{}:
      out

def Rule.keep(named: Lint.Rule & String, +settings: List<&2, Shared.Named<Config.Setting>>, out: List<&1, Lint.Rule>) ->
  List<&1, Lint.Rule>:
  match named:
    case Tuple{rule, id}:
      Rule.keep.if(Setting.on(Shared.lookup(Config.Setting, id, settings)), rule, out)

# The rules the config leaves on, in order.
def Rule.on(rules: List<&1, Lint.Rule>, +settings: List<&2, Shared.Named<Config.Setting>>, out: List<&1, Lint.Rule>) ->
  List<&1, Lint.Rule>:
  match rules:
    case Nil{}:
      List.reverse(&1, Lint.Rule, out)
    case Con{r, rest}:
      Rule.on(rest, settings, Rule.keep(Rule.id(r), settings, out))

# Each finding of `findings`, tagged with `rule`, with `severity` if the config gives the rule one, onto `out` (last
# first).
def Found.tag(
  +rule: String,
  +severity: Maybe<&2, Lint.Severity>,
  findings: List<&2, Lint.Finding>,
  out: List<&2, Lint.Found>
) -> List<&2, Lint.Found>:
  match findings:
    case Nil{}:
      out
    case Con{Lint.Finding{s, span, message}, rest}:
      Found.tag(
        rule,
        severity,
        rest,
        Lint.Found{rule, Lint.Finding{Maybe.default(&2, Lint.Severity, severity, s), span, message}} <> out
      )

def Rule.found(+id: String, +settings: List<&2, Shared.Named<Config.Setting>>, findings: List<&2, Lint.Finding>) ->
  List<&2, Lint.Found>:
  List.reverse(&2, Lint.Found, Found.tag(id, Setting.severity(Shared.lookup(Config.Setting, id, settings)), findings, []))

# What a rule finds at `place`, in order, tagged with its id: nothing where it does not run.
def Rule.at(rule: Lint.Rule, +settings: List<&2, Shared.Named<Config.Setting>>, +place: Place) -> List<&2, Lint.Found>:
  match rule place:
    case Lint.FileRule{id, run} AtFile{here}:
      Rule.found(id, settings, run(here))
    case Lint.ProgramRule{id, entries, run} AtProgram{whole}:
      Rule.found(id, settings, run(whole))
    case _ _:
      []

# What each rule finds at `place`, one list per rule, in order.
def Rule.each(
  rules: List<&1, Lint.Rule>,
  +settings: List<&2, Shared.Named<Config.Setting>>,
  +place: Place,
  out: List<&2, List<&2, Lint.Found>>
) -> List<&2, List<&2, Lint.Found>>:
  match rules:
    case Nil{}:
      List.reverse(&2, List<&2, Lint.Found>, out)
    case Con{r, rest}:
      Rule.each(rest, settings, place, Rule.at(r, settings, place) <> out)

# What each rule of both halves finds at `place`, one list per rule, in the rules' order: the halves in parallel,
# dealt again until `depth` runs out.
def Rule.all(
  +depth: Nat,
  halves: List<&1, Lint.Rule> & List<&1, Lint.Rule>,
  +settings: List<&2, Shared.Named<Config.Setting>>,
  +place: Place
) -> List<&2, List<&2, Lint.Found>>:
  match depth halves:
    case 0n Tuple{a, b}:
      Shared.interleave(List<&2, Lint.Found>, Rule.each(a, settings, place, []), Rule.each(b, settings, place, []))
    case 1n+d Tuple{a, b}:
      x y = Rule.all(d, Shared.deal(&1, Lint.Rule, a), settings, place) Rule.all(d, Shared.deal(&1, Lint.Rule, b), settings, place)
      Shared.interleave(List<&2, Lint.Found>, x, y)

# What each rule the config leaves on finds on the whole of `program`, one list per rule.
def Rule.found_on(~rules: List<&1, Lint.Rule>, +settings: List<&2, Shared.Named<Config.Setting>>, program: Lint.Program) ->
  List<&2, List<&2, Lint.Found>>:
  Rule.all(3n, Shared.deal(&1, Lint.Rule, Rule.on(rules, settings, [])), settings, AtProgram{Program.Whole.of(program)})

# What the rules the config leaves on find at `place`, in the rules' order.
def Rule.run(~rules: List<&1, Lint.Rule>, +settings: List<&2, Shared.Named<Config.Setting>>, +place: Place) ->
  List<&2, Lint.Found>:
  List.concat(&2, Lint.Found, Rule.all(3n, Shared.deal(&1, Lint.Rule, Rule.on(rules, settings, [])), settings, place))

def File.each(
  ~rules: List<&1, Lint.Rule>,
  files: List<&2, Lint.Source>,
  +settings: List<&2, Shared.Named<Config.Setting>>,
  +program: Lint.Program,
  out: List<&2, List<&2, Lint.Found>>
) -> List<&2, List<&2, Lint.Found>>:
  match files:
    case Nil{}:
      List.reverse(&2, List<&2, Lint.Found>, out)
    case Con{f, rest}:
      File.each(~rules, rest, settings, program, Rule.run(~rules, settings, AtFile{Program.Here.of(program, f)}) <> out)

# What the file rules find on each file of both halves, one list per file, in the files' order: the halves in
# parallel, dealt again until `depth` runs out.
def File.all(
  ~rules: List<&1, Lint.Rule>,
  +depth: Nat,
  halves: List<&2, Lint.Source> & List<&2, Lint.Source>,
  +settings: List<&2, Shared.Named<Config.Setting>>,
  +program: Lint.Program
) -> List<&2, List<&2, Lint.Found>>:
  match depth halves:
    case 0n Tuple{a, b}:
      Shared.interleave(
        List<&2, Lint.Found>,
        File.each(~rules, a, settings, program, []),
        File.each(~rules, b, settings, program, [])
      )
    case 1n+d Tuple{a, b}:
      x y = File.all(~rules, d, Shared.deal(&2, Lint.Source, a), settings, program) File.all(~rules, d, Shared.deal(&2, Lint.Source, b), settings, program)
      Shared.interleave(List<&2, Lint.Found>, x, y)

def Found.keep(hit: Bool, found: Lint.Found, out: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  match hit:
    case True{}:
      found <> out
    case False{}:
      out

# The findings of `founds` in the file at `path`, in order.
def Found.in(founds: List<&2, Lint.Found>, +path: String, out: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  match founds:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{Lint.Found{rule, Lint.Finding{severity, Lint.Span{+p, beg, end}, message}}, rest}:
      Found.in(rest, path, Found.keep(String.eq(p, path), Lint.Found{rule, Lint.Finding{severity, Lint.Span{p, beg, end}, message}}, out))

def Rule.ids.add(named: Lint.Rule & String, out: List<&2, String>) -> List<&2, String>:
  match named:
    case Tuple{rule, id}:
      id <> out

# The ids of the rules, in order.
def Rule.ids(rules: List<&1, Lint.Rule>, out: List<&2, String>) -> List<&2, String>:
  match rules:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{r, rest}:
      Rule.ids(rest, Rule.ids.add(Rule.id(r), out))

# Output
# ======

# What the run found so far: the lines to print, the findings that stay and those directives suppressed (all last
# first).
type Report is Data:
  Report{lines: List<&2, String>, kept: List<&2, Lint.Found>, suppressed: List<&2, Lint.Found>}

# A finding as a line: path:line:column: severity rule: message.
def Found.show(+text: String, found: Lint.Found) -> String:
  match found:
    case Lint.Found{rule, Lint.Finding{severity, Lint.Span{path, beg, end}, message}}:
      path ++ ":" ++ Shared.position(text, beg) ++ ": " ++ Lint.Severity.show(severity) ++ " " ++ rule ++ ": " ++ message

def Found.lines(+text: String, founds: List<&2, Lint.Found>, out: List<&2, String>) -> List<&2, String>:
  match founds:
    case Nil{}:
      out
    case Con{f, rest}:
      Found.lines(text, rest, Found.show(text, f) <> out)

def Found.is_error(found: Lint.Found) -> Bool:
  match found:
    case Lint.Found{rule, Lint.Finding{Lint.Error{}, span, message}}:
      True{}
    case _:
      False{}

# A linted file's findings, after its directives, added to the report.
def Report.add(+text: String, found: Directives.Suppressed, report: Report) -> Report:
  match found report:
    case Directives.Suppressed{+kept, suppressed} Report{lines, k, s}:
      Report{Found.lines(text, kept, lines), Shared.onto(Lint.Found, kept, k), Shared.onto(Lint.Found, suppressed, s)}

# The summary line: how many findings stay, and how many directives suppressed.
def summary(n: Nat, suppressed: Nat) -> String:
  match suppressed:
    case 0n:
      "bend-lint: " ++ Nat.show(n) ++ " finding(s)"
    case _:
      "bend-lint: " ++ Nat.show(n) ++ " finding(s), " ++ Nat.show(suppressed) ++ " suppressed"

def end(failed: Bool, summary: String) -> IO(Unit):
  match failed:
    case True{}:
      IO.die(Unit, 1, "bend-lint: FAIL")
    case False{}:
      IO.print(summary)

# Prints `lines`, if there are any.
def say(lines: List<&2, String>) -> IO(Unit):
  match lines:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{h, t}:
      IO.print(String.join(h <> t, "\n"))

# Prints the report; fails if a finding that stays is an error.
def print(report: Report) -> IO(Unit):
  match report:
    case Report{lines, +kept, suppressed}:
      do IO<Unit>:
        say(List.reverse(&2, String, lines))
        end(
          List.any(~&2, ~Lint.Found, ~Found.is_error, kept),
          summary(List.length(&2, Lint.Found, kept), List.length(&2, Lint.Found, suppressed))
        )

# Entries
# =======

def Rule.mode(rule: Lint.Rule) -> Lint.Entries:
  match rule:
    case Lint.ProgramRule{id, entries, run}:
      entries
    case _:
      Lint.SomeEntry{}

# How each rule's findings merge over checks, in the rules' order.
def Rule.modes(rules: List<&1, Lint.Rule>, out: List<&2, Lint.Entries>) -> List<&2, Lint.Entries>:
  match rules:
    case Nil{}:
      List.reverse(&2, Lint.Entries, out)
    case Con{r, rest}:
      Rule.modes(rest, Rule.mode(r) <> out)

# Whether two findings are the same: the same rule, severity and span.
def Found.same(+a: Lint.Found, b: Lint.Found) -> Bool:
  match a b:
    case Lint.Found{r, Lint.Finding{s, Lint.Span{p, beg, end}, m}} Lint.Found{r2, Lint.Finding{s2, Lint.Span{p2, beg2, end2}, m2}}:
      String.eq(r, r2) && String.eq(Lint.Severity.show(s), Lint.Severity.show(s2)) && String.eq(p, p2)
        && U32.is_eq(beg, beg2) && U32.is_eq(end, end2)

def Found.among(+found: Lint.Found, founds: List<&2, Lint.Found>) -> Bool:
  match founds:
    case Nil{}:
      False{}
    case Con{f, rest}:
      Found.same(found, f) || Found.among(found, rest)

def Merge.keep(hit: Bool, found: Lint.Found, out: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  match hit:
    case True{}:
      found <> out
    case False{}:
      out

def Merge.every(kept: List<&2, Lint.Found>, +more: List<&2, Lint.Found>, out: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  match kept:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{+f, rest}:
      Merge.every(rest, more, Merge.keep(Found.among(f, more), f, out))

# What a rule found so far (`kept`) and what one more check finds (`more`), merged by `mode`: with some, each finding of
# `more` not kept yet joins; with every, a kept finding stays only if `more` has it too. `out` is last first.
def Merge.step(mode: Lint.Entries, +kept: List<&2, Lint.Found>, more: List<&2, Lint.Found>, out: List<&2, Lint.Found>) ->
  List<&2, Lint.Found>:
  match mode more:
    case Lint.SomeEntry{} Nil{}:
      List.append(&2, Lint.Found, kept, List.reverse(&2, Lint.Found, out))
    case Lint.SomeEntry{} Con{+f, rest}:
      Merge.step(Lint.SomeEntry{}, kept, rest, Merge.keep(Bool.not(Found.among(f, kept)), f, out))
    case Lint.EveryEntry{} _:
      Merge.every(kept, more, [])

# Each rule's findings so far, merged with one more check's, rule by rule.
def Merge.rules(
  modes: List<&2, Lint.Entries>,
  kept: List<&2, List<&2, Lint.Found>>,
  more: List<&2, List<&2, Lint.Found>>,
  out: List<&2, List<&2, Lint.Found>>
) -> List<&2, List<&2, Lint.Found>>:
  match modes kept more:
    case Con{m, ms} Con{k, ks} Con{n, ns}:
      Merge.rules(ms, ks, ns, Merge.step(m, k, n, []) <> out)
    case _ _ _:
      List.reverse(&2, List<&2, Lint.Found>, out)

# What each rule finds on the whole program of each check (the first one's, then merged), one list per rule.
def Merge.checks(
  ~rules: List<&1, Lint.Rule>,
  programs: List<&2, Lint.Program>,
  +settings: List<&2, Shared.Named<Config.Setting>>,
  +modes: List<&2, Lint.Entries>,
  kept: Maybe<&2, List<&2, List<&2, Lint.Found>>>
) -> List<&2, List<&2, Lint.Found>>:
  match programs kept:
    case Nil{} _:
      Maybe.default(&2, List<&2, List<&2, Lint.Found>>, kept, [])
    case Con{p, rest} None{}:
      Merge.checks(~rules, rest, settings, modes, Some{Rule.found_on(~rules, settings, p)})
    case Con{p, rest} Some{k}:
      Merge.checks(~rules, rest, settings, modes, Some{Merge.rules(modes, k, Rule.found_on(~rules, settings, p), [])})

# A rule's findings, unless it is an every rule and an entry that reads the named file failed its check.
def Merge.partial(partial: Bool, mode: Lint.Entries, found: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  match partial mode:
    case True{} Lint.EveryEntry{}:
      []
    case _ _:
      found

def Merge.done(+partial: Bool, modes: List<&2, Lint.Entries>, found: List<&2, List<&2, Lint.Found>>, out: List<&2, Lint.Found>) ->
  List<&2, Lint.Found>:
  match modes found:
    case Con{m, ms} Con{f, fs}:
      Merge.done(partial, ms, fs, Shared.onto(Lint.Found, Merge.partial(partial, m, f), out))
    case _ _:
      List.reverse(&2, Lint.Found, out)

# CLI
# ===

# Each linted file's findings: those of the file rules (`files`, one list per file), then those of the program rules in
# it, after its directives.
def report(
  linted: List<&2, Lint.Source>,
  files: List<&2, List<&2, Lint.Found>>,
  +program: List<&2, Lint.Found>,
  +known: List<&2, String>,
  +ran: List<&2, String>,
  out: Report
) -> Report:
  match linted files:
    case Con{Lint.Source{+path, namespace, +text, nodes}, rest} Con{found, more}:
      report(
        rest,
        more,
        program,
        known,
        ran,
        Report.add(
          text,
          Directives.apply(Directives.Linted{path, text, known, ran}, List.append(&2, Lint.Found, found, Found.in(program, path, []))),
          out
        )
      )
    case _ _:
      out

# Lints `linted`, files of the first of `programs` (the checks of the named file), with the rules the config leaves
# on. Program rules run on each check; `partial` says whether an entry that reads the named file failed its check.
def lint(
  ~rules: List<&1, Lint.Rule>,
  +linted: List<&2, Lint.Source>,
  +programs: List<&2, Lint.Program>,
  partial: Bool,
  +settings: List<&2, Shared.Named<Config.Setting>>
) -> IO(Unit):
  print(
    report(
      linted,
      File.all(
        ~rules,
        3n,
        Shared.deal(&2, Lint.Source, linted),
        settings,
        Maybe.default(&2, Lint.Program, List.head(&2, Lint.Program, programs), Lint.Program{[]})
      ),
      Merge.done(
        partial,
        Rule.modes(Rule.on(rules, settings, []), []),
        Merge.checks(~rules, programs, settings, Rule.modes(Rule.on(rules, settings, []), []), None{}),
        []
      ),
      Rule.ids(rules, []),
      Rule.ids(Rule.on(rules, settings, []), []),
      Report{[], [], []}
    )
  )

# The source at `path`, among `sources`.
def Source.at(sources: List<&2, Lint.Source>, +path: String) -> Maybe<&2, Lint.Source>:
  match sources:
    case Nil{}:
      None{}
    case Con{Lint.Source{+p, namespace, text, nodes}, rest}:
      Bool.pick(Maybe<&2, Lint.Source>, String.eq(p, path), Some{Lint.Source{p, namespace, text, nodes}}, Source.at(rest, path))

# Whether to lint the files the named file imports: as the command line says, else as the config says, else not.
def imports(flag: Maybe<&2, Bool>, project: Maybe<&2, Bool>) -> Bool:
  Maybe.default(&2, Bool, Maybe.or(&2, Bool, flag, project), False{})

# The checks of the named file: the programs to lint it in (the first one's file rules run), and whether an entry that
# reads it failed its check.
type Checks is Data:
  Checks{programs: List<&2, Lint.Program>, partial: Bool}

# The files to lint: the named file (at `path`), or, with `imports`, every own file of its check.
def linted(imports: Bool, +path: String, +sources: List<&2, Lint.Source>) -> List<&2, Lint.Source>:
  match imports:
    case True{}:
      Program.Program.own(sources)
    case False{}:
      Maybe.default(&2, List<&2, Lint.Source>, Maybe.map(&2, Lint.Source, List<&2, Lint.Source>, s => [s], Source.at(sources, path)), [])

def checked(~rules: List<&1, Lint.Rule>, +path: String, imports: Bool, +settings: List<&2, Shared.Named<Config.Setting>>, checks: Checks) ->
  IO(Unit):
  match checks:
    case Checks{Con{Lint.Program{+sources}, rest}, partial}:
      lint(~rules, linted(imports, path, sources), Lint.Program{sources} <> rest, partial, settings)
    case Checks{Nil{}, partial}:
      IO.die(Unit, 2, "bend-lint: no check")

# The named file's own check, as the checks to lint it in; if it fails, the failure is the finding.
def own(+file: String, partial: Bool, check: Program.Check) -> IO(Checks):
  match check:
    case Program.Passed{p}:
      IO.pure(Checks, Checks{[p], partial})
    case Program.Failed{message, read}:
      do IO<Checks>:
        IO.print(file ++ ": error bend/check: " ++ message)
        IO.die(Checks, 1, "bend-lint: FAIL")

# Whether a check read the file at `path`.
def Check.reads(+path: String, +check: Program.Check) -> Bool:
  match check:
    case Program.Passed{Lint.Program{sources}}:
      Maybe.is_some(&2, Lint.Source, Source.at(sources, path))
    case Program.Failed{message, read}:
      List.contains(~String, ~String.eq, read, path)

# One check sorted into `checks`: if it reads the named file, its program joins the programs, or its failure is
# noted.
def Check.sort.step(reads: Bool, check: Program.Check, checks: Checks) -> Checks:
  match reads check checks:
    case True{} Program.Passed{p} Checks{programs, failed}:
      Checks{p <> programs, failed}
    case True{} Program.Failed{message, read} Checks{programs, failed}:
      Checks{programs, True{}}
    case False{} _ _:
      checks

# The checks that read the named file (at `path`): the programs of those that passed, and whether one failed.
def Check.sort(checks: List<&2, Program.Check>, +path: String, sorted: Checks) -> Checks:
  match checks sorted:
    case Nil{} Checks{programs, failed}:
      Checks{List.reverse(&2, Lint.Program, programs), failed}
    case Con{+c, rest} _:
      Check.sort(rest, path, Check.sort.step(Check.reads(path, c), c, sorted))

# The checks of `entries`, in order; `out` holds those so far, last first.
def Check.all(entries: List<&2, String>, out: List<&2, Program.Check>) -> IO(List<&2, Program.Check>):
  match entries:
    case Nil{}:
      IO.pure(List<&2, Program.Check>, List.reverse(&2, Program.Check, out))
    case Con{e, rest}:
      IO.bind(Program.Check, List<&2, Program.Check>, Program.Check.run(e), c => Check.all(rest, c <> out))

# The checks to lint the named file in: those of the entries that read it and passed; if none, its own.
def Check.chosen(sorted: Checks, +file: String) -> IO(Checks):
  match sorted:
    case Checks{Nil{}, partial}:
      IO.bind(Program.Check, Checks, Program.Check.run(file), c => own(file, partial, c))
    case Checks{programs, partial}:
      IO.pure(Checks, Checks{programs, partial})

# The checks to lint the named file in: with `imports` or no entries, its own; else those `Check.chosen` picks.
def Check.of(imports: Bool, entries: List<&2, String>, +file: String, +path: String) -> IO(Checks):
  match imports entries:
    case False{} Con{e, es}:
      IO.bind(List<&2, Program.Check>, Checks, Check.all(Con{e, es}, []), checks => Check.chosen(Check.sort(checks, path, Checks{[], False{}}), file))
    case _ _:
      IO.bind(Program.Check, Checks, Program.Check.run(file), c => own(file, False{}, c))

def configured(~rules: List<&1, Lint.Rule>, +file: String, +path: String, +flag: Maybe<&2, Bool>, project: Config.Project) -> IO(Unit):
  match project:
    case Config.Project{entries, +from, +settings}:
      IO.bind(
        Checks,
        Unit,
        Check.of(imports(flag, from), entries, file, path),
        checks => checked(~rules, path, imports(flag, from), settings, checks)
      )

# What the command line asks: the file to lint, and whether to lint the files it imports too, if it says.
type Options is Data:
  Options{file: String, imports: Maybe<&2, Bool>}

# The flags, by what they set: whether to lint the files the named file imports.
def flags() -> List<&2, Shared.Named<Bool>>:
  [Shared.Named{"--imports", True{}}, Shared.Named{"--no-imports", False{}}]

# The options of the command line, past the program's name: `<file> [--imports | --no-imports]`.
def options(args: List<String>) -> Maybe<&2, Options>:
  match args:
    case Con{program, Con{file, Nil{}}}:
      Some{Options{file, None{}}}
    case Con{program, Con{file, Con{f, Nil{}}}}:
      Maybe.map(&2, Bool, Options, i => Options{file, Some{i}}, Shared.lookup(Bool, f, flags()))
    case _:
      None{}

def found(~rules: List<&1, Lint.Rule>, +file: String, flag: Maybe<&2, Bool>, +path: String) -> IO(Unit):
  IO.bind(Config.Project, Unit, Config.find(path), project => configured(~rules, file, path, flag, project))

def checking(~rules: List<&1, Lint.Rule>, options: Maybe<&2, Options>) -> IO(Unit):
  match options:
    case Some{Options{+file, flag}}:
      IO.bind(String, Unit, Config.real(file), path => found(~rules, file, flag, path))
    case None{}:
      IO.die(Unit, 2, "usage: bun server.ts <program> <file> [--imports | --no-imports]")

# The command line: lint the named file with `rules`.
def run(~rules: List<&1, Lint.Rule>) -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), args => checking(~rules, options(args)))
