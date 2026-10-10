# Running rules and printing what they find. A rules program calls `run` with its rules: `Cli.run(~[R.rule()])`.
import Base
import ./config.bend as Config
import ./directives.bend as Directives
import ./fixes.bend as Fixes
import ./lint.bend as Lint
import ./program.bend as Program
import ./shared.bend as Shared
import ./wire.bend as Wire

# Rules
# =====

def Rule.id(rule: Lint.Rule) -> Lint.Rule & String:
  match rule:
    case Lint.FileRule{+id, needs, options, run}:
      (Lint.FileRule{id, needs, options, run}, id)
    case Lint.ProgramRule{+id, entries, needs, options, run}:
      (Lint.ProgramRule{id, entries, needs, options, run}, id)

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
    case Some{Config.RuleOn{severity, options}}:
      severity
    case _:
      None{}

# A rule's option values, once settled: each declared one, given or its default.
def Setting.options(setting: Maybe<&2, Config.Setting>) -> List<&2, Shared.Named<Lint.Value>>:
  match setting:
    case Some{Config.RuleOn{severity, options}}:
      options
    case _:
      []

def Rule.keep.off(off: Bool, +id: String, out: List<&2, Shared.Named<Config.Setting>>) ->
  List<&2, Shared.Named<Config.Setting>>:
  match off:
    case True{}:
      Shared.Named{id, Config.RuleOff{}} <> out
    case False{}:
      out

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

def Rule.facts(rule: Lint.Rule) -> Bool:
  match rule:
    case Lint.FileRule{id, Lint.Needs{facts}, options, run}:
      facts
    case Lint.ProgramRule{id, entries, Lint.Needs{facts}, options, run}:
      facts

# Whether a rule needs the checker's facts.
def Rule.need_facts(rules: List<&1, Lint.Rule>) -> Bool:
  match rules:
    case Nil{}:
      False{}
    case Con{r, rest}:
      Rule.facts(r) || Rule.need_facts(rest)

def Rule.unchecked.add(named: Lint.Rule & String, out: List<&2, Shared.Named<Config.Setting>>) ->
  List<&2, Shared.Named<Config.Setting>>:
  match named:
    case Tuple{rule, +id}:
      Rule.keep.off(Rule.facts(rule), id, out)

# The settings, with each rule that needs facts turned off if the check is `broken`: it gives no facts.
def Rule.unchecked(broken: Bool, rules: List<&1, Lint.Rule>, settings: List<&2, Shared.Named<Config.Setting>>) ->
  List<&2, Shared.Named<Config.Setting>>:
  match broken rules:
    case True{} Con{r, rest}:
      Rule.unchecked(True{}, rest, Rule.unchecked.add(Rule.id(r), settings))
    case _ _:
      settings

def Rule.mode(rule: Lint.Rule) -> Lint.Rule & Shared.Named<Lint.Entries>:
  match rule:
    case Lint.ProgramRule{+id, +entries, needs, options, run}:
      (Lint.ProgramRule{id, entries, needs, options, run}, Shared.Named{id, entries})
    case Lint.FileRule{+id, needs, options, run}:
      (Lint.FileRule{id, needs, options, run}, Shared.Named{id, Lint.SomeEntry{}})

def Rule.modes.add(named: Lint.Rule & Shared.Named<Lint.Entries>, out: List<&2, Shared.Named<Lint.Entries>>) ->
  List<&2, Shared.Named<Lint.Entries>>:
  match named:
    case Tuple{rule, mode}:
      mode <> out

# How each rule's findings merge over checks, by its id.
def Rule.modes(rules: List<&1, Lint.Rule>, out: List<&2, Shared.Named<Lint.Entries>>) -> List<&2, Shared.Named<Lint.Entries>>:
  match rules:
    case Nil{}:
      out
    case Con{r, rest}:
      Rule.modes(rest, Rule.modes.add(Rule.mode(r), out))

# Options
# =======

def Spec.one(spec: Lint.Spec, value: Lint.Value) -> Bool:
  match spec value:
    case Lint.NumberOption{min, max} Lint.Num{+n}:
      U32.is_le(min, n) && U32.is_le(n, max)
    case Lint.FlagOption{} Lint.Flag{on}:
      True{}
    case Lint.TextOption{Nil{}} Lint.Text{text}:
      True{}
    case Lint.TextOption{choices} Lint.Text{+text}:
      List.contains(~String, ~String.eq, choices, text)
    case _ _:
      False{}

# Whether one of `specs` accepts `value`; `fuel` bounds AnyOptions inside AnyOptions.
def Spec.fits(fuel: Nat, specs: List<&2, Lint.Spec>, +value: Lint.Value) -> Bool:
  match fuel specs:
    case 0n _:
      False{}
    case _ Nil{}:
      False{}
    case 1n+f Con{Lint.AnyOption{inner}, rest}:
      Spec.fits(f, Shared.append(&2, Lint.Spec, inner, rest), value)
    case 1n+f Con{spec, rest}:
      Spec.one(spec, value) || Spec.fits(f, rest, value)

# What the option `name` of `declared` accepts, if a rule declares it.
def Declared.spec(declared: List<&2, Lint.Declared>, +name: String) -> Maybe<&2, Lint.Spec>:
  match declared:
    case Nil{}:
      None{}
    case Con{Lint.Declared{+n, default, spec}, rest}:
      Bool.pick(Maybe<&2, Lint.Spec>, String.eq(n, name), Some{spec}, Declared.spec(rest, name))

def Option.problem(spec: Maybe<&2, Lint.Spec>, +key: String, value: Lint.Value) -> Maybe<&2, String>:
  match spec:
    case None{}:
      Some{"it has no option " ++ key}
    case Some{s}:
      Bool.pick(Maybe<&2, String>, Spec.fits(8n, [s], value), None{}, Some{key ++ " does not take that value"})

# The first problem with the given option values: a name not declared, or a value its spec does not accept.
def Option.given(given: List<&2, Shared.Named<Lint.Value>>, +declared: List<&2, Lint.Declared>) -> Maybe<&2, String>:
  match given:
    case Nil{}:
      None{}
    case Con{Shared.Named{+key, value}, rest}:
      Maybe.or(&2, String, Option.problem(Declared.spec(declared, key), key, value), Option.given(rest, declared))

# The first default its own spec does not accept: a bug in the rule.
def Option.defaults(declared: List<&2, Lint.Declared>) -> Maybe<&2, String>:
  match declared:
    case Nil{}:
      None{}
    case Con{Lint.Declared{+name, default, spec}, rest}:
      Maybe.or(
        &2,
        String,
        Bool.pick(Maybe<&2, String>, Spec.fits(8n, [spec], default), None{}, Some{"the default of " ++ name ++ " is not a value it takes"}),
        Option.defaults(rest)
      )

# Each declared option, with its given value, or its default.
def Option.values(declared: List<&2, Lint.Declared>, +given: List<&2, Shared.Named<Lint.Value>>, out: List<&2, Shared.Named<Lint.Value>>) ->
  List<&2, Shared.Named<Lint.Value>>:
  match declared:
    case Nil{}:
      List.reverse(&2, Shared.Named<Lint.Value>, out)
    case Con{Lint.Declared{+name, default, spec}, rest}:
      Option.values(rest, given, Shared.Named{name, Maybe.default(&2, Lint.Value, Shared.lookup(Lint.Value, name, given), default)} <> out)

# A rule's id and the options it declares.
def Rule.declared(rule: Lint.Rule) -> String & List<&2, Lint.Declared>:
  match rule:
    case Lint.FileRule{id, needs, options, run}:
      (id, options)
    case Lint.ProgramRule{id, entries, needs, options, run}:
      (id, options)

def Rule.problem.of(declared: String & List<&2, Lint.Declared>, +settings: List<&2, Shared.Named<Config.Setting>>) ->
  Maybe<&2, String>:
  match declared:
    case Tuple{+id, +options}:
      Maybe.map(
        &2,
        String,
        String,
        why => id ++ ": " ++ why,
        Maybe.or(&2, String, Option.defaults(options), Option.given(Setting.options(Shared.lookup(Config.Setting, id, settings)), options))
      )

# The first problem with the rules' options: what the config gives, or a rule's own defaults.
def Rule.problem(rules: List<&1, Lint.Rule>, +settings: List<&2, Shared.Named<Config.Setting>>) -> Maybe<&2, String>:
  match rules:
    case Nil{}:
      None{}
    case Con{r, rest}:
      Maybe.or(&2, String, Rule.problem.of(Rule.declared(r), settings), Rule.problem(rest, settings))

def Rule.settle.of(declared: String & List<&2, Lint.Declared>, setting: Maybe<&2, Config.Setting>) ->
  Shared.Named<Config.Setting>:
  match declared setting:
    case Tuple{id, options} Some{Config.RuleOff{}}:
      Shared.Named{id, Config.RuleOff{}}
    case Tuple{id, options} Some{Config.RuleOn{severity, given}}:
      Shared.Named{id, Config.RuleOn{severity, Option.values(options, given, [])}}
    case Tuple{id, options} None{}:
      Shared.Named{id, Config.RuleOn{None{}, Option.values(options, [], [])}}

# Each rule's setting, its option values settled: off, or on with its severity, if any, and every option it declares.
def Rule.settle.at(declared: String & List<&2, Lint.Declared>, +settings: List<&2, Shared.Named<Config.Setting>>) ->
  Shared.Named<Config.Setting>:
  match declared:
    case Tuple{+id, options}:
      Rule.settle.of((id, options), Shared.lookup(Config.Setting, id, settings))

def Rule.settle(rules: List<&1, Lint.Rule>, +settings: List<&2, Shared.Named<Config.Setting>>, out: List<&2, Shared.Named<Config.Setting>>) ->
  List<&2, Shared.Named<Config.Setting>>:
  match rules:
    case Nil{}:
      List.reverse(&2, Shared.Named<Config.Setting>, out)
    case Con{r, rest}:
      Rule.settle(rest, settings, Rule.settle.at(Rule.declared(r), settings) <> out)

# Jobs
# ====

# Where rules run: on one file, for file rules; or on the whole program of a check, for program rules, with the path
# of the named file and the check's number (from 1).
type Place is Data:
  AtFile{here: Lint.Here}
  AtProgram{whole: Lint.Whole, path: String, check: U32}

# A rule's run at one place: the rule's id, the severity the config gives its findings, the file a failure of it is
# reported in, its group (0 for a file rule, the check's number for a program rule), and how far it got.
type Job is Type:
  Job{rule: String, severity: Maybe<&2, Lint.Severity>, path: String, group: U32, step: Lint.Step<List<&2, Lint.Finding>>}

# What a rule sees, with its options.
def Here.with(here: Lint.Here, options: List<&2, Shared.Named<Lint.Value>>) -> Lint.Here:
  match here:
    case Lint.Here{program, source, declarations, index, none}:
      Lint.Here{program, source, declarations, index, options}

def Whole.with(whole: Lint.Whole, options: List<&2, Shared.Named<Lint.Value>>) -> Lint.Whole:
  match whole:
    case Lint.Whole{program, declarations, none}:
      Lint.Whole{program, declarations, options}

def Job.start(
  +id: String,
  +settings: List<&2, Shared.Named<Config.Setting>>,
  path: String,
  group: U32,
  run: Lint.Ask(List<&2, Lint.Finding>)
) -> List<&1, Job>:
  [
    Job{
      id,
      Setting.severity(Shared.lookup(Config.Setting, id, settings)),
      path,
      group,
      run(List<&2, Lint.Finding>, xs => Lint.Finished{xs})
    }
  ]

# A rule's job at `place`: none where it does not run.
def Rule.at(rule: Lint.Rule, +settings: List<&2, Shared.Named<Config.Setting>>, +place: Place) -> List<&1, Job>:
  match rule place:
    case Lint.FileRule{+id, needs, declared, run} AtFile{+here}:
      Job.start(
        id,
        settings,
        Lint.Here.path(here),
        0,
        run(Here.with(here, Setting.options(Shared.lookup(Config.Setting, id, settings))))
      )
    case Lint.ProgramRule{+id, entries, needs, declared, run} AtProgram{whole, path, check}:
      Job.start(id, settings, path, check, run(Whole.with(whole, Setting.options(Shared.lookup(Config.Setting, id, settings)))))
    case _ _:
      []

def Rule.each(rules: List<&1, Lint.Rule>, +settings: List<&2, Shared.Named<Config.Setting>>, +place: Place, out: List<&1, Job>) ->
  List<&1, Job>:
  match rules:
    case Nil{}:
      List.reverse(&1, Job, out)
    case Con{r, rest}:
      Rule.each(rest, settings, place, Shared.onto(&1, Job, Rule.at(r, settings, place), out))

# The jobs of the rules of both halves at `place`, in the rules' order: the halves in parallel, dealt again until
# `depth` runs out.
def Rule.all(
  +depth: Nat,
  halves: List<&1, Lint.Rule> & List<&1, Lint.Rule>,
  +settings: List<&2, Shared.Named<Config.Setting>>,
  +place: Place
) -> List<&1, Job>:
  match depth halves:
    case 0n Tuple{a, b}:
      Shared.append(&1, Job, Rule.each(a, settings, place, []), Rule.each(b, settings, place, []))
    case 1n+d Tuple{a, b}:
      x y = Rule.all(d, Shared.deal(&1, Lint.Rule, a), settings, place) Rule.all(d, Shared.deal(&1, Lint.Rule, b), settings, place)
      Shared.append(&1, Job, x, y)

# The jobs of the rules the config leaves on at `place`.
def Rule.jobs(~rules: List<&1, Lint.Rule>, +settings: List<&2, Shared.Named<Config.Setting>>, +place: Place) -> List<&1, Job>:
  Rule.all(3n, Shared.deal(&1, Lint.Rule, Rule.on(rules, settings, [])), settings, place)

def File.each(
  ~rules: List<&1, Lint.Rule>,
  files: List<&2, Lint.Source>,
  +settings: List<&2, Shared.Named<Config.Setting>>,
  +program: Lint.Program,
  out: List<&1, Job>
) -> List<&1, Job>:
  match files:
    case Nil{}:
      out
    case Con{f, rest}:
      File.each(~rules, rest, settings, program, Shared.onto(&1, Job, Rule.jobs(~rules, settings, AtFile{Program.Here.of(program, f)}), out))

# The jobs of the file rules on each file of both halves: the halves in parallel, dealt again until `depth` runs out.
def File.all(
  ~rules: List<&1, Lint.Rule>,
  +depth: Nat,
  halves: List<&2, Lint.Source> & List<&2, Lint.Source>,
  +settings: List<&2, Shared.Named<Config.Setting>>,
  +program: Lint.Program
) -> List<&1, Job>:
  match depth halves:
    case 0n Tuple{a, b}:
      Shared.append(&1, Job, File.each(~rules, a, settings, program, []), File.each(~rules, b, settings, program, []))
    case 1n+d Tuple{a, b}:
      x y = File.all(~rules, d, Shared.deal(&2, Lint.Source, a), settings, program) File.all(~rules, d, Shared.deal(&2, Lint.Source, b), settings, program)
      Shared.append(&1, Job, x, y)

# The jobs of the program rules on the whole program of each check, numbered from `check`.
def Check.jobs(
  ~rules: List<&1, Lint.Rule>,
  programs: List<&2, Lint.Program>,
  +settings: List<&2, Shared.Named<Config.Setting>>,
  +path: String,
  +check: U32,
  out: List<&1, Job>
) -> List<&1, Job>:
  match programs:
    case Nil{}:
      out
    case Con{p, rest}:
      Check.jobs(
        ~rules,
        rest,
        settings,
        path,
        (check + 1 : U32),
        Shared.onto(&1, Job, Rule.jobs(~rules, settings, AtProgram{Program.Whole.of(p), path, check}), out)
      )

# Rounds
# ======

# A finding, with its job's group.
type Tagged is Data:
  Tagged{group: U32, found: Lint.Found}

# A job held for answers: its rule, severity, path and group, how many answers it waits for, and what it does with
# them; or settled, with its findings.
type Held is Type:
  Held{rule: String, severity: Maybe<&2, Lint.Severity>, path: String, group: U32, count: Nat, then: List<&2, Lint.Answer> -> Lint.Step<List<&2, Lint.Finding>>}
  Settled{rule: String, severity: Maybe<&2, Lint.Severity>, path: String, group: U32, findings: List<&2, Lint.Finding>}

# The jobs held, in order, and all their questions, in order.
type Holding is Type:
  Holding{held: List<&1, Held>, questions: List<&2, Lint.Question>}

def Round.hold(jobs: List<&1, Job>, held: List<&1, Held>, questions: List<&2, Lint.Question>) -> Holding:
  match jobs:
    case Nil{}:
      Holding{List.reverse(&1, Held, held), List.reverse(&2, Lint.Question, questions)}
    case Con{Job{r, s, p, g, Lint.Finished{fs}}, rest}:
      Round.hold(rest, Settled{r, s, p, g, fs} <> held, questions)
    case Con{Job{r, s, p, g, Lint.Pending{+qs, k}}, rest}:
      Round.hold(rest, Held{r, s, p, g, Shared.length(&2, Lint.Question, qs), k} <> held, Shared.onto(&2, Lint.Question, qs, questions))

# The held jobs, each given its answers (the next of `answers`, as many as it waits for), as jobs again.
def Round.resume(held: List<&1, Held>, +answers: List<&2, Lint.Answer>, out: List<&1, Job>) -> List<&1, Job>:
  match held:
    case Nil{}:
      List.reverse(&1, Job, out)
    case Con{Held{r, s, p, g, +n, k}, rest}:
      Round.resume(rest, List.drop(&2, Lint.Answer, answers, n), Job{r, s, p, g, k(List.take(&2, Lint.Answer, answers, n))} <> out)
    case Con{Settled{r, s, p, g, fs}, rest}:
      Round.resume(rest, answers, Job{r, s, p, g, Lint.Finished{fs}} <> out)

# Each finding of `findings`, tagged with `rule`, `group`, and `severity` if the config gives the rule one, onto
# `out` (last first).
def Found.tag(
  +rule: String,
  +severity: Maybe<&2, Lint.Severity>,
  +group: U32,
  findings: List<&2, Lint.Finding>,
  out: List<&2, Tagged>
) -> List<&2, Tagged>:
  match findings:
    case Nil{}:
      out
    case Con{Lint.Finding{s, span, message, fixes}, rest}:
      Found.tag(
        rule,
        severity,
        group,
        rest,
        Tagged{group, Lint.Found{rule, Lint.Finding{Maybe.default(&2, Lint.Severity, severity, s), span, message, fixes}}} <> out
      )

# What the jobs found, in order: a job still waiting when the rounds ran out is a failure of its rule.
def Round.found(held: List<&1, Held>, out: List<&2, Tagged>) -> List<&2, Tagged>:
  match held:
    case Nil{}:
      List.reverse(&2, Tagged, out)
    case Con{Settled{r, s, p, g, fs}, rest}:
      Round.found(rest, Found.tag(r, s, g, fs, out))
    case Con{Held{+r, s, p, g, n, k}, rest}:
      Round.found(
        rest,
        Tagged{
          g,
          Lint.Found{
            "bend-lint/rule-crash",
            Lint.Finding{Lint.Error{}, Lint.Span{p, 0, 0}, "The rule " ++ r ++ " asked the checker more rounds than its budget.", []}
          }
        } <> out
      )

def Question.field(q: Lint.Question) -> String:
  match q:
    case Lint.Show{Lint.TypeRef{c, i}}:
      "show:" ++ U32.show(c) ++ ":" ++ U32.show(i)
    case Lint.Same{Lint.TypeRef{c, i}, Lint.TypeRef{d, j}}:
      "same:" ++ U32.show(c) ++ ":" ++ U32.show(i) ++ ":" ++ U32.show(d) ++ ":" ++ U32.show(j)
    case Lint.Normal{Lint.TypeRef{c, i}}:
      "normal:" ++ U32.show(c) ++ ":" ++ U32.show(i)

def Question.fields(questions: List<&2, Lint.Question>, out: List<&2, String>) -> List<&2, String>:
  match questions:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{q, rest}:
      Question.fields(rest, Question.field(q) <> out)

def Answer.normalized(check: String, id: String) -> Maybe<&2, Lint.Answer>:
  do Maybe<&2, Lint.Answer>:
    c : U32 <- U32.read(check)
    i : U32 <- U32.read(id)
    return Lint.Normalized{Lint.TypeRef{c, i}}

def Answer.read.two(which: Maybe<&2, U32>, +text: String) -> Maybe<&2, Lint.Answer>:
  match which:
    case Some{0}:
      Some{Lint.Shown{text}}
    case Some{1}:
      Some{Lint.Equal{String.eq(text, "true")}}
    case _:
      None{}

def Answer.read(record: List<&2, String>) -> Maybe<&2, Lint.Answer>:
  match record:
    case Con{tag, Con{text, Nil{}}}:
      Answer.read.two(Shared.lookup(U32, tag, [Shared.Named{"shown", 0}, Shared.Named{"same", 1}]), text)
    case Con{tag, Con{check, Con{id, Nil{}}}}:
      Answer.normalized(check, id)
    case _:
      None{}

def Answer.all(records: List<&2, List<&2, String>>, out: List<&2, Lint.Answer>) -> Maybe<&2, List<&2, Lint.Answer>>:
  match records:
    case Nil{}:
      Some{List.reverse(&2, Lint.Answer, out)}
    case Con{r, rest}:
      do Maybe<&2, List<&2, Lint.Answer>>:
        a : Lint.Answer <- Answer.read(r)
        Answer.all(rest, a <> out)

def Answer.got(answers: Maybe<&2, List<&2, Lint.Answer>>) -> IO(List<&2, Lint.Answer>):
  match answers:
    case Some{a}:
      IO.pure(List<&2, Lint.Answer>, a)
    case None{}:
      IO.die(List<&2, Lint.Answer>, 1, "bend-lint: the checker's answers are malformed")

# The checker's answers to `questions`, in order, in one request.
def Round.ask(questions: List<&2, Lint.Question>) -> IO(List<&2, Lint.Answer>):
  IO.bind(
    List<&2, List<&2, String>>,
    List<&2, Lint.Answer>,
    Wire.ask("ask" <> Question.fields(questions, [])),
    records => Answer.got(Answer.all(records, []))
  )

# What the jobs find: each round asks all their questions at once, and resumes them with the answers, until none asks
# or `budget` runs out.
def Rounds.go(budget: Nat, holding: Holding) -> IO(List<&2, Tagged>):
  match budget holding:
    case _ Holding{held, Nil{}}:
      IO.pure(List<&2, Tagged>, Round.found(held, []))
    case 0n Holding{held, questions}:
      IO.pure(List<&2, Tagged>, Round.found(held, []))
    case 1n+b Holding{held, Con{q, qs}}:
      IO.bind(
        List<&2, Lint.Answer>,
        List<&2, Tagged>,
        Round.ask(Con{q, qs}),
        answers => Rounds.go(b, Round.hold(Round.resume(held, answers, []), [], []))
      )

# Merging
# =======

# What makes a finding the same across checks: its rule, severity and span.
def Found.key(found: Lint.Found) -> String:
  match found:
    case Lint.Found{r, Lint.Finding{s, Lint.Span{p, beg, end}, m, fixes}}:
      r ++ "\t" ++ Lint.Severity.show(s) ++ "\t" ++ p ++ "\t" ++ U32.show(beg) ++ "\t" ++ U32.show(end)

# The keys of `founds`, onto `keys`.
def Found.keys(founds: List<&2, Lint.Found>, keys: Map<&2, Unit>) -> Map<&2, Unit>:
  match founds:
    case Nil{}:
      keys
    case Con{f, rest}:
      Found.keys(rest, Map.set(&2, Unit, keys, Found.key(f), Unit{}))

# Whether `found`'s key is among `keys`.
def Found.among(+keys: Map<&2, Unit>, found: Lint.Found) -> Bool:
  Pair.snd(Map<&2, Unit>, Bool, Map.has(&2, Unit, keys, Found.key(found)))

def Found.keep(hit: Bool, found: Lint.Found, out: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  match hit:
    case True{}:
      found <> out
    case False{}:
      out

# The findings of group `group`, in order.
def Tagged.of(tagged: List<&2, Tagged>, +group: U32, out: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  match tagged:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{Tagged{+g, f}, rest}:
      Tagged.of(rest, group, Found.keep(U32.is_eq(g, group), f, out))

# The findings of `more` whose keys are not among `keys`, nor before them in `more`, onto `out`.
def Merge.new(more: List<&2, Lint.Found>, +keys: Map<&2, Unit>, out: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  match more:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{+f, rest}:
      Merge.new(rest, Map.set(&2, Unit, keys, Found.key(f), Unit{}), Found.keep(Bool.not(Found.among(keys, f)), f, out))

# `founds`, then each finding of `more` that is not among them.
def Merge.union(+founds: List<&2, Lint.Found>, more: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  Shared.append(&2, Lint.Found, founds, Merge.new(more, Found.keys(founds, Map.new(&2, Unit)), []))

# The findings of `founds` whose keys are among `keys`, onto `out`.
def Merge.common(founds: List<&2, Lint.Found>, +keys: Map<&2, Unit>, out: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  match founds:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{+f, rest}:
      Merge.common(rest, keys, Found.keep(Found.among(keys, f), f, out))

# The findings of `founds` that `more` finds too.
def Merge.every(founds: List<&2, Lint.Found>, more: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  Merge.common(founds, Found.keys(more, Map.new(&2, Unit)), [])

# The findings of every check, `first` with those of the checks numbered from `check` up to `last`: all of them (some),
# or those all of them find (every).
def Merge.checks(
  fuel: Nat,
  +tagged: List<&2, Tagged>,
  +check: U32,
  some: List<&2, Lint.Found>,
  +every: List<&2, Lint.Found>
) -> List<&2, Lint.Found> & List<&2, Lint.Found>:
  match fuel:
    case 0n:
      (some, every)
    case 1n+k:
      Merge.checks(
        k,
        tagged,
        (check + 1 : U32),
        Merge.union(some, Tagged.of(tagged, check, [])),
        Merge.every(every, Tagged.of(tagged, check, []))
      )

# Whether a finding of a rule stays: a some rule's, if some check found it; an every rule's, if every check found it,
# and no entry that reads the named file failed its check.
def Merge.stays(mode: Maybe<&2, Lint.Entries>, partial: Bool, every: Bool) -> Bool:
  match mode partial:
    case Some{Lint.EveryEntry{}} True{}:
      False{}
    case Some{Lint.EveryEntry{}} False{}:
      every
    case _ _:
      True{}

def Merge.pick(
  some: List<&2, Lint.Found>,
  +every: Map<&2, Unit>,
  +modes: List<&2, Shared.Named<Lint.Entries>>,
  +partial: Bool,
  out: List<&2, Lint.Found>
) -> List<&2, Lint.Found>:
  match some:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{Lint.Found{+r, +f}, rest}:
      Merge.pick(
        rest,
        every,
        modes,
        partial,
        Found.keep(
          Merge.stays(Shared.lookup(Lint.Entries, r, modes), partial, Found.among(every, Lint.Found{r, f})),
          Lint.Found{r, f},
          out
        )
      )

def Merge.done(
  merged: List<&2, Lint.Found> & List<&2, Lint.Found>,
  +modes: List<&2, Shared.Named<Lint.Entries>>,
  +partial: Bool
) -> List<&2, Lint.Found>:
  match merged:
    case Tuple{some, every}:
      Merge.pick(some, Found.keys(every, Map.new(&2, Unit)), modes, partial, [])

# What the program rules find over `checks` checks, merged as each rule's entries say.
def Merge.program(
  +tagged: List<&2, Tagged>,
  +checks: Nat,
  +modes: List<&2, Shared.Named<Lint.Entries>>,
  +partial: Bool
) -> List<&2, Lint.Found>:
  Merge.done(Merge.checks(checks, tagged, 1, [], Tagged.of(tagged, 1, [])), modes, partial)

# Output
# ======

# What the run found so far: the lines to print, the findings that stay and those directives suppressed (all last
# first).
type Report is Data:
  Report{lines: List<&2, String>, kept: List<&2, Lint.Found>, suppressed: List<&2, Lint.Found>}

# A finding as a line: path:line:column: severity rule: message.
def Found.show(found: Lint.Found, at: Shared.Position) -> String:
  match found at:
    case Lint.Found{rule, Lint.Finding{severity, Lint.Span{path, beg, end}, message, fixes}} Shared.Position{line, column}:
      path ++ ":" ++ U32.show(line) ++ ":" ++ U32.show(column) ++ ": " ++ Lint.Severity.show(severity) ++ " " ++ rule ++ ": "
        ++ message

# The findings as lines, each with where it starts (`at`, in order), onto `out` (last first).
def Found.lines(founds: List<&2, Lint.Found>, at: List<&2, Shared.Position>, out: List<&2, String>) -> List<&2, String>:
  match founds at:
    case Con{f, rest} Con{p, more}:
      Found.lines(rest, more, Found.show(f, p) <> out)
    case _ _:
      out

def Found.is_error(found: Lint.Found) -> Bool:
  match found:
    case Lint.Found{rule, Lint.Finding{Lint.Error{}, span, message, fixes}}:
      True{}
    case _:
      False{}

# The findings of `founds` in the file at `path`, in order.
def Found.in(founds: List<&2, Lint.Found>, +path: String, out: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  match founds:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{Lint.Found{rule, Lint.Finding{severity, Lint.Span{+p, beg, end}, message, fixes}}, rest}:
      Found.in(rest, path, Found.keep(String.eq(p, path), Lint.Found{rule, Lint.Finding{severity, Lint.Span{p, beg, end}, message, fixes}}, out))

# A linted file's findings, after its directives, added to the report.
def Report.add(+text: String, found: Directives.Suppressed, report: Report) -> Report:
  match found report:
    case Directives.Suppressed{+kept, suppressed} Report{lines, k, s}:
      Report{
        Found.lines(kept, Shared.positions(text, Lint.Found.offsets(kept, [])), lines),
        Shared.onto(&2, Lint.Found, kept, k),
        Shared.onto(&2, Lint.Found, suppressed, s)
      }

# The summary line: how many findings stay, how many directives suppressed, and, if the run fixes, how many fixes it
# made.
def summary.fixed(fixed: Maybe<&2, U32>) -> String:
  match fixed:
    case Some{n}:
      ", " ++ U32.show(n) ++ " fixed"
    case None{}:
      ""

def summary(n: Nat, suppressed: Nat, fixed: Maybe<&2, U32>) -> String:
  match suppressed:
    case 0n:
      "bend-lint: " ++ Nat.show(n) ++ " finding(s)" ++ summary.fixed(fixed)
    case _:
      "bend-lint: " ++ Nat.show(n) ++ " finding(s), " ++ Nat.show(suppressed) ++ " suppressed" ++ summary.fixed(fixed)

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

# Prints the report, then makes the fixes `fixing` allows in `program`'s files; fails if a finding that stays is an
# error, or the check is `broken`.
def print(report: Report, broken: Bool, +fixing: Fixes.Fixing, program: Lint.Program) -> IO(Unit):
  match report:
    case Report{lines, +kept, suppressed}:
      do IO<Unit>:
        say(List.reverse(&2, String, lines))
        fixed : Maybe<&2, U32> <- Fixes.apply(fixing, List.reverse(&2, Lint.Found, kept), program)
        end(
          broken || Shared.any(~Lint.Found, ~Found.is_error, kept),
          summary(Shared.length(&2, Lint.Found, kept), Shared.length(&2, Lint.Found, suppressed), fixed)
        )

# Each linted file's findings: those of the file rules, then those of the program rules, after its directives.
def report(
  linted: List<&2, Lint.Source>,
  +files: List<&2, Lint.Found>,
  +program: List<&2, Lint.Found>,
  +known: List<&2, String>,
  +ran: List<&2, String>,
  out: Report
) -> Report:
  match linted:
    case Con{Lint.Source{+path, namespace, +text, nodes, facts}, rest}:
      report(
        rest,
        files,
        program,
        known,
        ran,
        Report.add(
          text,
          Directives.apply(
            Directives.Linted{path, text, known, ran},
            Shared.append(&2, Lint.Found, Found.in(files, path, []), Found.in(program, path, []))
          ),
          out
        )
      )
    case Nil{}:
      out

# CLI
# ===

# How many rounds of questions a run may ask: past it, a rule still asking fails.
def budget() -> Nat:
  64n

# Prints what the jobs found in the linted files, after the rounds; `checks` is the number of checks.
def finish(
  linted: List<&2, Lint.Source>,
  +tagged: List<&2, Tagged>,
  +checks: Nat,
  +modes: List<&2, Shared.Named<Lint.Entries>>,
  +partial: Bool,
  +known: List<&2, String>,
  +ran: List<&2, String>,
  broken: Bool,
  +fixing: Fixes.Fixing,
  program: Lint.Program
) -> IO(Unit):
  print(
    report(linted, Tagged.of(tagged, 0, []), Merge.program(tagged, checks, modes, partial), known, ran, Report{[], [], []}),
    broken,
    fixing,
    program
  )

# Lints `linted`, files of the first of `programs` (the checks of the named file, at `path`), with the rules the
# config leaves on. Program rules run on each check; `partial` says whether an entry that reads the named file failed
# its check, and `broken` whether its own check did, and `programs` is only what it parsed.
def lint(
  ~rules: List<&1, Lint.Rule>,
  +linted: List<&2, Lint.Source>,
  +path: String,
  +programs: List<&2, Lint.Program>,
  +partial: Bool,
  +settings: List<&2, Shared.Named<Config.Setting>>,
  +broken: Bool,
  +fixing: Fixes.Fixing
) -> IO(Unit):
  IO.bind(
    List<&2, Tagged>,
    Unit,
    Rounds.go(
      budget(),
      Round.hold(
        Shared.append(
          &1,
          Job,
          File.all(
            ~rules,
            3n,
            Shared.deal(&2, Lint.Source, linted),
            settings,
            Maybe.default(&2, Lint.Program, List.head(&2, Lint.Program, programs), Lint.Program{[]})
          ),
          Check.jobs(~rules, programs, settings, path, 1, [])
        ),
        [],
        []
      )
    ),
    tagged =>
      finish(
        linted,
        tagged,
        Shared.length(&2, Lint.Program, programs),
        Rule.modes(rules, []),
        partial,
        Rule.ids(rules, []),
        Rule.ids(Rule.on(rules, settings, []), []),
        broken,
        fixing,
        Maybe.default(&2, Lint.Program, List.head(&2, Lint.Program, programs), Lint.Program{[]})
      )
  )

# The source at `path`, among `sources`.
def Source.at(sources: List<&2, Lint.Source>, +path: String) -> Maybe<&2, Lint.Source>:
  match sources:
    case Nil{}:
      None{}
    case Con{Lint.Source{+p, namespace, text, nodes, facts}, rest}:
      Bool.pick(
        Maybe<&2, Lint.Source>,
        String.eq(p, path),
        Some{Lint.Source{p, namespace, text, nodes, facts}},
        Source.at(rest, path)
      )

# Whether to lint the files the named file imports: as the command line says, else as the config says, else not.
def imports(flag: Maybe<&2, Bool>, project: Maybe<&2, Bool>) -> Bool:
  Maybe.default(&2, Bool, Maybe.or(&2, Bool, flag, project), False{})

# The checks of the named file: the programs to lint it in (the first one's file rules run), whether an entry that
# reads it failed its check, and whether its own check failed (then the program is what it parsed).
type Checks is Data:
  Checks{programs: List<&2, Lint.Program>, partial: Bool, broken: Bool}

# The files to lint: the named file (at `path`), or, with `imports`, every own file of its check.
def linted(imports: Bool, +path: String, +sources: List<&2, Lint.Source>) -> List<&2, Lint.Source>:
  match imports:
    case True{}:
      Program.Program.own(sources)
    case False{}:
      Maybe.default(&2, List<&2, Lint.Source>, Maybe.map(&2, Lint.Source, List<&2, Lint.Source>, s => [s], Source.at(sources, path)), [])

def checked(~rules: List<&1, Lint.Rule>, +path: String, imports: Bool, +settings: List<&2, Shared.Named<Config.Setting>>, +fixing: Fixes.Fixing, checks: Checks) ->
  IO(Unit):
  match checks:
    case Checks{Con{Lint.Program{+sources}, rest}, partial, +broken}:
      lint(
        ~rules,
        linted(imports, path, sources),
        path,
        Lint.Program{sources} <> rest,
        partial,
        Rule.unchecked(broken, rules, settings),
        broken,
        fixing
      )
    case Checks{Nil{}, partial, broken}:
      IO.die(Unit, 2, "bend-lint: no check")

# The named file's own check, as the checks to lint it in. If it fails, the failure is the first finding, and the rules
# that need no facts run on what it parsed, if it parsed the files.
def own(+file: String, partial: Bool, check: Program.Check) -> IO(Checks):
  match check:
    case Program.Passed{p}:
      IO.pure(Checks, Checks{[p], partial, False{}})
    case Program.Failed{message, read, Some{p}}:
      do IO<Checks>:
        IO.print(file ++ ": error bend/check: " ++ message)
        return Checks{[p], partial, True{}}
    case Program.Failed{message, read, None{}}:
      do IO<Checks>:
        IO.print(file ++ ": error bend/check: " ++ message)
        IO.die(Checks, 1, "bend-lint: FAIL")

# Whether a check read the file at `path`.
def Check.reads(+path: String, +check: Program.Check) -> Bool:
  match check:
    case Program.Passed{Lint.Program{sources}}:
      Maybe.is_some(&2, Lint.Source, Source.at(sources, path))
    case Program.Failed{message, read, parsed}:
      List.contains(~String, ~String.eq, read, path)

# One check sorted into `checks`: if it reads the named file, its program joins the programs, or its failure is
# noted.
def Check.sort.step(reads: Bool, check: Program.Check, checks: Checks) -> Checks:
  match reads check checks:
    case True{} Program.Passed{p} Checks{programs, failed, broken}:
      Checks{p <> programs, failed, broken}
    case True{} Program.Failed{message, read, parsed} Checks{programs, failed, broken}:
      Checks{programs, True{}, broken}
    case False{} _ _:
      checks

# The checks that read the named file (at `path`): the programs of those that passed, and whether one failed.
def Check.sort(checks: List<&2, Program.Check>, +path: String, sorted: Checks) -> Checks:
  match checks sorted:
    case Nil{} Checks{programs, failed, broken}:
      Checks{List.reverse(&2, Lint.Program, programs), failed, broken}
    case Con{+c, rest} _:
      Check.sort(rest, path, Check.sort.step(Check.reads(path, c), c, sorted))

# The checks of `entries`, in order; `out` holds those so far, last first.
def Check.all(entries: List<&2, String>, +facts: Bool, out: List<&2, Program.Check>) -> IO(List<&2, Program.Check>):
  match entries:
    case Nil{}:
      IO.pure(List<&2, Program.Check>, List.reverse(&2, Program.Check, out))
    case Con{e, rest}:
      IO.bind(Program.Check, List<&2, Program.Check>, Program.Check.run(e, facts), c => Check.all(rest, facts, c <> out))

# The checks to lint the named file in: those of the entries that read it and passed; if none, its own.
def Check.chosen(sorted: Checks, +file: String, +facts: Bool) -> IO(Checks):
  match sorted:
    case Checks{Nil{}, partial, broken}:
      IO.bind(Program.Check, Checks, Program.Check.run(file, facts), c => own(file, partial, c))
    case Checks{programs, partial, broken}:
      IO.pure(Checks, Checks{programs, partial, broken})

# The checks to lint the named file in: with `imports` or no entries, its own; else those `Check.chosen` picks.
def Check.of(imports: Bool, entries: List<&2, String>, +file: String, +path: String, +facts: Bool) -> IO(Checks):
  match imports entries:
    case False{} Con{e, es}:
      IO.bind(
        List<&2, Program.Check>,
        Checks,
        Check.all(Con{e, es}, facts, []),
        checks => Check.chosen(Check.sort(checks, path, Checks{[], False{}, False{}}), file, facts)
      )
    case _ _:
      IO.bind(Program.Check, Checks, Program.Check.run(file, facts), c => own(file, False{}, c))

# Stops the run if the config's options do not fit what the rules declare.
def Options.checked(problem: Maybe<&2, String>) -> IO(Unit):
  match problem:
    case Some{why}:
      IO.die(Unit, 2, "bend-lint config: " ++ why)
    case None{}:
      IO.pure(Unit, Unit{})

# What the command line asks: the file to lint, and whether to lint the files it imports too, if it says.
type Options is Data:
  Options{file: String, imports: Maybe<&2, Bool>, fixing: Fixes.Fixing}

def settled(~rules: List<&1, Lint.Rule>, +file: String, +path: String, +options: Options, +entries: List<&2, String>, +from: Maybe<&2, Bool>, +settings: List<&2, Shared.Named<Config.Setting>>) -> IO(Unit):
  match options:
    case Options{name, flag, +fixing}:
      IO.bind(
        Checks,
        Unit,
        Check.of(imports(flag, from), entries, file, path, Rule.need_facts(Rule.on(rules, settings, []))),
        checks => checked(~rules, path, imports(flag, from), settings, fixing, checks)
      )

def configured(~rules: List<&1, Lint.Rule>, +file: String, +path: String, +options: Options, project: Config.Project) -> IO(Unit):
  match project:
    case Config.Project{entries, from, +settings}:
      IO.bind(
        Unit,
        Unit,
        Options.checked(Rule.problem(rules, settings)),
        none => settled(~rules, file, path, options, entries, from, Rule.settle(rules, settings, []))
      )

# What a flag sets: whether to lint the files the named file imports, or how to fix.
type Flag is Data:
  ImportsFlag{on: Bool}
  FixFlag{fixing: Fixes.Fixing}

def flags() -> List<&2, Shared.Named<Flag>>:
  [
    Shared.Named{"--imports", ImportsFlag{True{}}},
    Shared.Named{"--no-imports", ImportsFlag{False{}}},
    Shared.Named{"--fix", FixFlag{Fixes.SafeFixes{}}},
    Shared.Named{"--fix-dangerously", FixFlag{Fixes.DangerousFixes{}}}
  ]

def Options.set(flag: Maybe<&2, Flag>, options: Maybe<&2, Options>) -> Maybe<&2, Options>:
  match flag options:
    case Some{ImportsFlag{on}} Some{Options{file, imports, fixing}}:
      Some{Options{file, Some{on}, fixing}}
    case Some{FixFlag{set}} Some{Options{file, imports, fixing}}:
      Some{Options{file, imports, set}}
    case _ _:
      None{}

def Options.read(args: List<String>, options: Maybe<&2, Options>) -> Maybe<&2, Options>:
  match args:
    case Nil{}:
      options
    case Con{+f, rest}:
      Options.read(rest, Options.set(Shared.lookup(Flag, f, flags()), options))

# The options of the command line, past the program's name: `<file> [--imports | --no-imports] [--fix |
# --fix-dangerously]`.
def options(args: List<String>) -> Maybe<&2, Options>:
  match args:
    case Con{program, Con{file, rest}}:
      Options.read(rest, Some{Options{file, None{}, Fixes.NoFixes{}}})
    case _:
      None{}

def found(~rules: List<&1, Lint.Rule>, +file: String, +options: Options, +path: String) -> IO(Unit):
  IO.bind(Config.Project, Unit, Config.find(path), project => configured(~rules, file, path, options, project))

def checking(~rules: List<&1, Lint.Rule>, options: Maybe<&2, Options>) -> IO(Unit):
  match options:
    case Some{Options{+file, flag, fixing}}:
      IO.bind(String, Unit, Config.real(file), path => found(~rules, file, Options{file, flag, fixing}, path))
    case None{}:
      IO.die(Unit, 2, "usage: bun server.ts <program> <file> [--imports | --no-imports] [--fix | --fix-dangerously]")

# The command line: lint the named file with `rules`.
def run(~rules: List<&1, Lint.Rule>) -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), args => checking(~rules, options(args)))
