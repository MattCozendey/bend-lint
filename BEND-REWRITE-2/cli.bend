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
    case Lint.ProgramRule{+id, run}:
      (Lint.ProgramRule{id, run}, id)

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
    case Lint.ProgramRule{id, run} AtProgram{whole}:
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

# Lints `linted`, files of `program`, with the rules the config leaves on.
def lint(
  ~rules: List<&1, Lint.Rule>,
  +linted: List<&2, Lint.Source>,
  +program: Lint.Program,
  +settings: List<&2, Shared.Named<Config.Setting>>
) -> IO(Unit):
  print(
    report(
      linted,
      File.all(~rules, 3n, Shared.deal(&2, Lint.Source, linted), settings, program),
      Rule.run(~rules, settings, AtProgram{Program.Whole.of(program)}),
      Rule.ids(rules, []),
      Rule.ids(Rule.on(rules, settings, []), []),
      Report{[], [], []}
    )
  )

# The files to lint: the program's own, with `imports`; else the file the check was for, the last it parsed.
def linted(imports: Bool, +sources: List<&2, Lint.Source>) -> List<&2, Lint.Source>:
  match imports:
    case True{}:
      Program.Program.own(sources)
    case False{}:
      Maybe.default(&2, List<&2, Lint.Source>, Maybe.map(&2, Lint.Source, List<&2, Lint.Source>, s => [s], List.last(&2, Lint.Source, sources)), [])

# Whether to lint the files the named file imports: as the command line says, else as the config says, else not.
def imports(flag: Maybe<&2, Bool>, project: Maybe<&2, Bool>) -> Bool:
  Maybe.default(&2, Bool, Maybe.or(&2, Bool, flag, project), False{})

def checked(~rules: List<&1, Lint.Rule>, +file: String, flag: Maybe<&2, Bool>, project: Config.Project, check: Program.Check) ->
  IO(Unit):
  match project check:
    case Config.Project{entries, from, settings} Program.Passed{Lint.Program{+sources}}:
      lint(~rules, linted(imports(flag, from), sources), Lint.Program{sources}, settings)
    case _ Program.Failed{message}:
      do IO<Unit>:
        IO.print(file ++ ": error bend/check: " ++ message)
        IO.die(Unit, 1, "bend-lint: FAIL")

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

def configured(~rules: List<&1, Lint.Rule>, +file: String, flag: Maybe<&2, Bool>, project: Config.Project) -> IO(Unit):
  IO.bind(Program.Check, Unit, Program.Check.run(file), check => checked(~rules, file, flag, project, check))

def checking(~rules: List<&1, Lint.Rule>, options: Maybe<&2, Options>) -> IO(Unit):
  match options:
    case Some{Options{+file, flag}}:
      IO.bind(
        Config.Project,
        Unit,
        IO.bind(String, Config.Project, Config.real(file), Config.find),
        project => configured(~rules, file, flag, project)
      )
    case None{}:
      IO.die(Unit, 2, "usage: bun server.ts <program> <file> [--imports | --no-imports]")

# The command line: lint the named file with `rules`.
def run(~rules: List<&1, Lint.Rule>) -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), args => checking(~rules, options(args)))
