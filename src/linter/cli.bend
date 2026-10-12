# A rules program calls `run` with its rules: `Cli.run(~[R.rule()])`.
import Base
import ../json-parser/main.bend as Json
import ../shared/utils.bend as Utils
import ./config.bend as Config
import ./directives.bend as Directives
import ./fixes.bend as Fixes
import ./lint.bend as Lint
import ./program.bend as Program
import ./wire.bend as Wire

# Rules
# =====

# What the runner reads of a rule, besides its run: its id, what it needs, the options it declares, and, for a program
# rule, whether its findings must be found by every check.
type About is Data:
  About{id: String, needs: Lint.Needs, options: List<&2, Lint.Declared>, every: Maybe<&2, Bool>}

def About.all(rules: List<&1, Lint.Rule>, out: List<&2, About>) -> List<&2, About>:
  match rules:
    case Nil{}:
      List.reverse(&2, About, out)
    case Con{Lint.Rule{id, needs, options, Lint.OnFile{run}}, rest}:
      About.all(rest, About{id, needs, options, None{}} <> out)
    case Con{Lint.Rule{id, needs, options, Lint.OnProgram{every, run}}, rest}:
      About.all(rest, About{id, needs, options, Some{every}} <> out)

def About.facts(about: About) -> Bool:
  match about:
    case About{id, Lint.Needs{facts, declarations}, options, every}:
      facts

def About.declarations(about: About) -> Bool:
  match about:
    case About{id, Lint.Needs{facts, declarations}, options, every}:
      declarations

def About.whole(about: About) -> Bool:
  match about:
    case About{id, needs, options, every}:
      Maybe.is_some(&2, Bool, every)

def Setting.on(setting: Maybe<&2, Config.Setting>) -> Bool:
  match setting:
    case Some{Config.RuleOff{}}:
      False{}
    case _:
      True{}

def Setting.severity(setting: Maybe<&2, Config.Setting>) -> Maybe<&2, Lint.Severity>:
  match setting:
    case Some{Config.RuleOn{severity, options}}:
      severity
    case _:
      None{}

# A rule's option values, once settled: each declared one, given or its default.
def Setting.options(setting: Maybe<&2, Config.Setting>) -> List<&2, Utils.Named<Lint.Value>>:
  match setting:
    case Some{Config.RuleOn{severity, options}}:
      options
    case _:
      []

def About.on(
  abouts: List<&2, About>,
  +settings: List<&2, Utils.Named<Config.Setting>>,
  out: List<&2, About>
) -> List<&2, About>:
  match abouts:
    case Nil{}:
      List.reverse(&2, About, out)
    case Con{About{+id, needs, options, every}, rest}:
      About.on(
        rest,
        settings,
        Utils.push(
          About,
          Utils.when(
            About,
            Setting.on(Utils.lookup(Config.Setting, id, settings)),
            About{id, needs, options, every}
          ),
          out
        )
      )

def Rule.keep.if(on: Bool, rule: Lint.Rule, out: List<&1, Lint.Rule>) -> List<&1, Lint.Rule>:
  match on:
    case True{}:
      rule <> out
    case False{}:
      out

def Rule.on(
  rules: List<&1, Lint.Rule>,
  +settings: List<&2, Utils.Named<Config.Setting>>,
  out: List<&1, Lint.Rule>
) -> List<&1, Lint.Rule>:
  match rules:
    case Nil{}:
      List.reverse(&1, Lint.Rule, out)
    case Con{Lint.Rule{+id, needs, options, run}, rest}:
      Rule.on(
        rest,
        settings,
        Rule.keep.if(
          Setting.on(Utils.lookup(Config.Setting, id, settings)),
          Lint.Rule{id, needs, options, run},
          out
        )
      )

def About.ids(abouts: List<&2, About>, out: List<&2, String>) -> List<&2, String>:
  match abouts:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{About{id, needs, options, every}, rest}:
      About.ids(rest, id <> out)

# The settings, with each rule that needs facts turned off if the check is `broken`: it gives no facts.
def About.unchecked(
  broken: Bool,
  abouts: List<&2, About>,
  settings: List<&2, Utils.Named<Config.Setting>>
) -> List<&2, Utils.Named<Config.Setting>>:
  match broken abouts:
    case True{} Con{About{id, Lint.Needs{facts, declarations}, options, every}, rest}:
      About.unchecked(
        True{},
        rest,
        Utils.push(
          Utils.Named<Config.Setting>,
          Utils.when(Utils.Named<Config.Setting>, facts, Utils.Named{id, Config.RuleOff{}}),
          settings
        )
      )
    case _ _:
      settings

def About.modes(
  abouts: List<&2, About>,
  out: List<&2, Utils.Named<Bool>>
) -> List<&2, Utils.Named<Bool>>:
  match abouts:
    case Nil{}:
      out
    case Con{About{id, needs, options, every}, rest}:
      About.modes(rest, Utils.Named{id, Maybe.default(&2, Bool, every, False{})} <> out)

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
    case Lint.TextOption{choices} Lint.Text{text}:
      List.contains(~String, ~String.eq, choices, text)
    case _ _:
      False{}

# Whether one of `specs` accepts `value`; `fuel` bounds AnyOptions inside AnyOptions.
def Spec.fits(fuel: Nat, specs: List<&2, Lint.Spec>, hit: Bool, +value: Lint.Value) -> Bool:
  match fuel specs hit:
    case _ _ True{}:
      True{}
    case 0n _ False{}:
      False{}
    case _ Nil{} False{}:
      False{}
    case 1n+f Con{Lint.AnyOption{inner}, rest} False{}:
      Spec.fits(f, Utils.append(&2, Lint.Spec, inner, rest), False{}, value)
    case 1n+f Con{spec, rest} False{}:
      Spec.fits(f, rest, Spec.one(spec, value), value)

def Declared.spec(
  declared: List<&2, Lint.Declared>,
  found: Maybe<&2, Lint.Spec>,
  +name: String
) -> Maybe<&2, Lint.Spec>:
  match declared found:
    case _ Some{spec}:
      Some{spec}
    case Nil{} None{}:
      None{}
    case Con{Lint.Declared{n, default, spec}, rest} None{}:
      Declared.spec(rest, Utils.when(Lint.Spec, String.eq(n, name), spec), name)

def Option.problem(spec: Maybe<&2, Lint.Spec>, key: String, value: Lint.Value) -> Maybe<&2, String>:
  match spec:
    case None{}:
      Some{"it has no option " ++ key}
    case Some{s}:
      Utils.when(
        String,
        Bool.not(Spec.fits(8n, [s], False{}, value)),
        key ++ " does not take that value"
      )

# The first problem with the given option values: a name not declared, or a value its spec does not accept.
def Option.given(
  given: List<&2, Utils.Named<Lint.Value>>,
  +declared: List<&2, Lint.Declared>
) -> Maybe<&2, String>:
  match given:
    case Nil{}:
      None{}
    case Con{Utils.Named{+key, value}, rest}:
      Maybe.or(
        &2,
        String,
        Option.problem(Declared.spec(declared, None{}, key), key, value),
        Option.given(rest, declared)
      )

# The first default its own spec does not accept: a bug in the rule.
def Option.defaults(declared: List<&2, Lint.Declared>) -> Maybe<&2, String>:
  match declared:
    case Nil{}:
      None{}
    case Con{Lint.Declared{name, default, spec}, rest}:
      Maybe.or(
        &2,
        String,
        Utils.when(
          String,
          Bool.not(Spec.fits(8n, [spec], False{}, default)),
          "the default of " ++ name ++ " is not a value it takes"
        ),
        Option.defaults(rest)
      )

def Option.values(
  declared: List<&2, Lint.Declared>,
  +given: List<&2, Utils.Named<Lint.Value>>,
  out: List<&2, Utils.Named<Lint.Value>>
) -> List<&2, Utils.Named<Lint.Value>>:
  match declared:
    case Nil{}:
      List.reverse(&2, Utils.Named<Lint.Value>, out)
    case Con{Lint.Declared{+name, default, spec}, rest}:
      Option.values(
        rest,
        given,
        Utils.Named{
          name,
          Maybe.default(&2, Lint.Value, Utils.lookup(Lint.Value, name, given), default)
        }
          <> out
      )

# The first problem with a rule's options: a default its own spec does not accept, or what the config gives.
def About.problem.of(
  about: About,
  settings: List<&2, Utils.Named<Config.Setting>>
) -> Maybe<&2, String>:
  match about:
    case About{+id, needs, +options, every}:
      Maybe.map(
        &2,
        String,
        String,
        why => id ++ ": " ++ why,
        Maybe.or(
          &2,
          String,
          Option.defaults(options),
          Option.given(Setting.options(Utils.lookup(Config.Setting, id, settings)), options)
        )
      )

def About.problem(
  abouts: List<&2, About>,
  +settings: List<&2, Utils.Named<Config.Setting>>
) -> Maybe<&2, String>:
  match abouts:
    case Nil{}:
      None{}
    case Con{a, rest}:
      Maybe.or(&2, String, About.problem.of(a, settings), About.problem(rest, settings))

def About.settle.of(
  about: About,
  setting: Maybe<&2, Config.Setting>
) -> Utils.Named<Config.Setting>:
  match about setting:
    case About{id, needs, options, every} Some{Config.RuleOff{}}:
      Utils.Named{id, Config.RuleOff{}}
    case About{id, needs, options, every} Some{Config.RuleOn{severity, given}}:
      Utils.Named{id, Config.RuleOn{severity, Option.values(options, given, [])}}
    case About{id, needs, options, every} None{}:
      Utils.Named{id, Config.RuleOn{None{}, Option.values(options, [], [])}}

# Each rule's setting, its option values settled: off, or on with its severity, if any, and every option it declares.
def About.settle(
  abouts: List<&2, About>,
  +settings: List<&2, Utils.Named<Config.Setting>>,
  out: List<&2, Utils.Named<Config.Setting>>
) -> List<&2, Utils.Named<Config.Setting>>:
  match abouts:
    case Nil{}:
      List.reverse(&2, Utils.Named<Config.Setting>, out)
    case Con{About{+id, needs, options, every}, rest}:
      About.settle(
        rest,
        settings,
        About.settle.of(
          About{id, needs, options, every},
          Utils.lookup(Config.Setting, id, settings)
        )
          <> out
      )

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
  Job{
    rule: String,
    severity: Maybe<&2, Lint.Severity>,
    path: String,
    group: U32,
    step: Lint.Step<List<&2, Lint.Finding>>
  }

def Here.with(here: Lint.Here, options: List<&2, Utils.Named<Lint.Value>>) -> Lint.Here:
  match here:
    case Lint.Here{program, source, declarations, index, none}:
      Lint.Here{program, source, declarations, index, options}

def Whole.with(whole: Lint.Whole, options: List<&2, Utils.Named<Lint.Value>>) -> Lint.Whole:
  match whole:
    case Lint.Whole{program, declarations, none}:
      Lint.Whole{program, declarations, options}

def Job.start(
  +id: String,
  settings: List<&2, Utils.Named<Config.Setting>>,
  path: String,
  group: U32,
  run: Lint.Ask(List<&2, Lint.Finding>)
) -> List<&1, Job>:
  [
    Job{
      id,
      Setting.severity(Utils.lookup(Config.Setting, id, settings)),
      path,
      group,
      run(List<&2, Lint.Finding>, xs => Lint.Finished{xs})
    }
  ]

# A rule's job at `place`: none where it does not run.
def Rule.at(
  rule: Lint.Rule,
  +settings: List<&2, Utils.Named<Config.Setting>>,
  +place: Place
) -> List<&1, Job>:
  match rule place:
    case Lint.Rule{+id, needs, declared, Lint.OnFile{run}} AtFile{+here}:
      Job.start(
        id,
        settings,
        Lint.Here.path(here),
        0,
        run(Here.with(here, Setting.options(Utils.lookup(Config.Setting, id, settings))))
      )
    case Lint.Rule{+id, needs, declared, Lint.OnProgram{every, run}} AtProgram{whole, path, check}:
      Job.start(
        id,
        settings,
        path,
        check,
        run(Whole.with(whole, Setting.options(Utils.lookup(Config.Setting, id, settings))))
      )
    case _ _:
      []

def Rule.each(
  rules: List<&1, Lint.Rule>,
  +settings: List<&2, Utils.Named<Config.Setting>>,
  +place: Place,
  out: List<&1, Job>
) -> List<&1, Job>:
  match rules:
    case Nil{}:
      List.reverse(&1, Job, out)
    case Con{r, rest}:
      Rule.each(rest, settings, place, Utils.onto(&1, Job, Rule.at(r, settings, place), out))

# The jobs of the rules of both halves at `place`, in the rules' order: the halves in parallel, dealt again until
# `depth` runs out.
def Rule.all(
  +depth: Nat,
  halves: List<&1, Lint.Rule> & List<&1, Lint.Rule>,
  +settings: List<&2, Utils.Named<Config.Setting>>,
  +place: Place
) -> List<&1, Job>:
  match depth halves:
    case 0n Tuple{a, b}:
      Utils.append(&1, Job, Rule.each(a, settings, place, []), Rule.each(b, settings, place, []))
    case 1n+d Tuple{a, b}:
      x y = Rule.all(
        d,
        Utils.deal(&1, Lint.Rule, a),
        settings,
        place
      ) Rule.all(d, Utils.deal(&1, Lint.Rule, b), settings, place)
      Utils.append(&1, Job, x, y)

def Rule.jobs(
  ~rules: List<&1, Lint.Rule>,
  +settings: List<&2, Utils.Named<Config.Setting>>,
  place: Place
) -> List<&1, Job>:
  Rule.all(3n, Utils.deal(&1, Lint.Rule, Rule.on(rules, settings, [])), settings, place)

def File.each(
  ~rules: List<&1, Lint.Rule>,
  files: List<&2, Lint.Source>,
  +settings: List<&2, Utils.Named<Config.Setting>>,
  +program: Lint.Program,
  +declare: Bool,
  out: List<&1, Job>
) -> List<&1, Job>:
  match files:
    case Nil{}:
      out
    case Con{f, rest}:
      File.each(
        ~rules,
        rest,
        settings,
        program,
        declare,
        Utils.onto(
          &1,
          Job,
          Rule.jobs(~rules, settings, AtFile{Program.Here.of(program, f, declare)}),
          out
        )
      )

# The jobs of the file rules on each file of both halves: the halves in parallel, dealt again until `depth` runs out.
# `declare` says whether a rule needs declarations.
def File.all(
  ~rules: List<&1, Lint.Rule>,
  +depth: Nat,
  halves: List<&2, Lint.Source> & List<&2, Lint.Source>,
  +settings: List<&2, Utils.Named<Config.Setting>>,
  +program: Lint.Program,
  +declare: Bool
) -> List<&1, Job>:
  match depth halves:
    case 0n Tuple{a, b}:
      Utils.append(
        &1,
        Job,
        File.each(~rules, a, settings, program, declare, []),
        File.each(~rules, b, settings, program, declare, [])
      )
    case 1n+d Tuple{a, b}:
      x y = File.all(
        ~rules,
        d,
        Utils.deal(&2, Lint.Source, a),
        settings,
        program,
        declare
      ) File.all(~rules, d, Utils.deal(&2, Lint.Source, b), settings, program, declare)
      Utils.append(&1, Job, x, y)

# The jobs of the program rules on the whole program of each check, numbered from `check`; `declare` says whether a
# rule needs declarations.
def Check.jobs(
  ~rules: List<&1, Lint.Rule>,
  programs: List<&2, Lint.Program>,
  +settings: List<&2, Utils.Named<Config.Setting>>,
  +path: String,
  +declare: Bool,
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
        declare,
        (check + 1: U32),
        Utils.onto(
          &1,
          Job,
          Rule.jobs(~rules, settings, AtProgram{Program.Whole.of(p, declare), path, check}),
          out
        )
      )

# The jobs of the program rules on each check, if one is on (`whole`): else none, and no whole program is built.
def Check.jobs.if(
  ~rules: List<&1, Lint.Rule>,
  whole: Bool,
  programs: List<&2, Lint.Program>,
  settings: List<&2, Utils.Named<Config.Setting>>,
  path: String,
  declare: Bool
) -> List<&1, Job>:
  match whole:
    case True{}:
      Check.jobs(~rules, programs, settings, path, declare, 1, [])
    case False{}:
      []

# Rounds
# ======
type Tagged is Data:
  Tagged{group: U32, found: Lint.Found}

# A job held for answers: its rule, severity, path and group, how many answers it waits for, and what it does with
# them; or settled, with its findings.
type Held is Type:
  Held{
    rule: String,
    severity: Maybe<&2, Lint.Severity>,
    path: String,
    group: U32,
    count: Nat,
    then: List<&2, Lint.Answer> -> Lint.Step<List<&2, Lint.Finding>>
  }
  Settled{
    rule: String,
    severity: Maybe<&2, Lint.Severity>,
    path: String,
    group: U32,
    findings: List<&2, Lint.Finding>
  }

type Holding is Type:
  Holding{held: List<&1, Held>, questions: List<&2, Lint.Question>}

def Round.hold(
  jobs: List<&1, Job>,
  held: List<&1, Held>,
  questions: List<&2, Lint.Question>
) -> Holding:
  match jobs:
    case Nil{}:
      Holding{List.reverse(&1, Held, held), List.reverse(&2, Lint.Question, questions)}
    case Con{Job{r, s, p, g, Lint.Finished{fs}}, rest}:
      Round.hold(rest, Settled{r, s, p, g, fs} <> held, questions)
    case Con{Job{r, s, p, g, Lint.Pending{+qs, k}}, rest}:
      Round.hold(
        rest,
        Held{r, s, p, g, Utils.length(&2, Lint.Question, qs), k} <> held,
        Utils.onto(&2, Lint.Question, qs, questions)
      )

# The held jobs, each given its answers (the next of `answers`, as many as it waits for), as jobs again.
def Round.resume(
  held: List<&1, Held>,
  +answers: List<&2, Lint.Answer>,
  out: List<&1, Job>
) -> List<&1, Job>:
  match held:
    case Nil{}:
      List.reverse(&1, Job, out)
    case Con{Held{r, s, p, g, +n, k}, rest}:
      Round.resume(
        rest,
        List.drop(&2, Lint.Answer, answers, n),
        Job{r, s, p, g, k(List.take(&2, Lint.Answer, answers, n))} <> out
      )
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
        Tagged{
          group,
          Lint.Found{
            rule,
            Lint.Finding{Maybe.default(&2, Lint.Severity, severity, s), span, message, fixes}
          }
        }
          <> out
      )

# What the jobs found, in order: a job still waiting when the rounds ran out is a failure of its rule.
def Round.found(held: List<&1, Held>, out: List<&2, Tagged>) -> List<&2, Tagged>:
  match held:
    case Nil{}:
      List.reverse(&2, Tagged, out)
    case Con{Settled{r, s, p, g, fs}, rest}:
      Round.found(rest, Found.tag(r, s, g, fs, out))
    case Con{Held{r, s, p, g, n, k}, rest}:
      Round.found(
        rest,
        Tagged{
          g,
          Lint.Found{
            "bend-lint/rule-crash",
            Lint.Finding{
              Lint.Error{},
              Lint.Span{p, 0, 0},
              "The rule " ++ r ++ " asked the checker more rounds than its budget.",
              []
            }
          }
        }
          <> out
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
        Wire.answers(Con{q, qs}),
        answers => Rounds.go(b, Round.hold(Round.resume(held, answers, []), [], []))
      )

# Merging
# =======

# What makes a finding the same across checks: its rule, severity and span.
def Found.key(found: Lint.Found) -> String:
  match found:
    case Lint.Found{r, Lint.Finding{s, Lint.Span{p, beg, end}, m, fixes}}:
      r
        ++ "\t"
        ++ Lint.Severity.show(s)
        ++ "\t"
        ++ p
        ++ "\t"
        ++ U32.show(beg)
        ++ "\t"
        ++ U32.show(end)

def Found.keys(founds: List<&2, Lint.Found>, keys: Set()) -> Set():
  match founds:
    case Nil{}:
      keys
    case Con{f, rest}:
      Found.keys(rest, Set.add(keys, Found.key(f)))

def Found.among(keys: Set(), found: Lint.Found) -> Bool:
  Pair.snd(Set(), Bool, Set.has(keys, Found.key(found)))

def Found.keep(hit: Bool, found: Lint.Found, out: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  match hit:
    case True{}:
      found <> out
    case False{}:
      out

def Tagged.of(
  tagged: List<&2, Tagged>,
  +group: U32,
  out: List<&2, Lint.Found>
) -> List<&2, Lint.Found>:
  match tagged:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{Tagged{g, f}, rest}:
      Tagged.of(rest, group, Found.keep(U32.is_eq(g, group), f, out))

# The findings of `more` whose keys are not among `keys`, nor before them in `more`, onto `out`.
def Merge.new(
  more: List<&2, Lint.Found>,
  +keys: Set(),
  out: List<&2, Lint.Found>
) -> List<&2, Lint.Found>:
  match more:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{+f, rest}:
      Merge.new(
        rest,
        Set.add(keys, Found.key(f)),
        Found.keep(Bool.not(Found.among(keys, f)), f, out)
      )

def Merge.union(+founds: List<&2, Lint.Found>, more: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  Utils.append(&2, Lint.Found, founds, Merge.new(more, Found.keys(founds, Set.new()), []))

def Merge.common(
  founds: List<&2, Lint.Found>,
  +keys: Set(),
  out: List<&2, Lint.Found>
) -> List<&2, Lint.Found>:
  match founds:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{+f, rest}:
      Merge.common(rest, keys, Found.keep(Found.among(keys, f), f, out))

def Merge.every(founds: List<&2, Lint.Found>, more: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  Merge.common(founds, Found.keys(more, Set.new()), [])

# The findings of every check, `first` with those of the checks numbered from `check` up to `last`: all of them (some),
# or those all of them find (every).
def Merge.checks(
  fuel: Nat,
  +tagged: List<&2, Tagged>,
  +check: U32,
  some: List<&2, Lint.Found>,
  every: List<&2, Lint.Found>
) -> List<&2, Lint.Found>
  & List<&2, Lint.Found>:
  match fuel:
    case 0n:
      (some, every)
    case 1n+k:
      Merge.checks(
        k,
        tagged,
        (check + 1: U32),
        Merge.union(some, Tagged.of(tagged, check, [])),
        Merge.every(every, Tagged.of(tagged, check, []))
      )

# Whether a finding of a rule stays: if the rule's findings must be found by every check (`every`), if every check
# found it (`all`), and no entry that reads the named file failed its check; else, if some check found it.
def Merge.stays(every: Maybe<&2, Bool>, partial: Bool, all: Bool) -> Bool:
  match every partial:
    case Some{True{}} True{}:
      False{}
    case Some{True{}} False{}:
      all
    case _ _:
      True{}

def Merge.pick(
  some: List<&2, Lint.Found>,
  +every: Set(),
  +modes: List<&2, Utils.Named<Bool>>,
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
          Merge.stays(Utils.lookup(Bool, r, modes), partial, Found.among(every, Lint.Found{r, f})),
          Lint.Found{r, f},
          out
        )
      )

def Merge.done(
  merged: List<&2, Lint.Found> & List<&2, Lint.Found>,
  modes: List<&2, Utils.Named<Bool>>,
  partial: Bool
) -> List<&2, Lint.Found>:
  match merged:
    case Tuple{some, every}:
      Merge.pick(some, Found.keys(every, Set.new()), modes, partial, [])

# What the program rules find over `checks` checks, merged as each rule's entries say.
def Merge.program(
  +tagged: List<&2, Tagged>,
  checks: Nat,
  modes: List<&2, Utils.Named<Bool>>,
  partial: Bool
) -> List<&2, Lint.Found>:
  Merge.done(Merge.checks(checks, tagged, 1, [], Tagged.of(tagged, 1, [])), modes, partial)

# Output
# ======

# What linting the named file found: the findings that stay and those directives suppressed (both last first), and the
# texts of files outside its program (where its check failed), by path.
type Report is Data:
  Report{kept: List<&2, Lint.Found>, suppressed: List<&2, Lint.Found>, texts: Map<&2, String>}

# A finding with the edits of each of its fixes: None for a fix the linter cannot make.
type Resolved is Data:
  Resolved{found: Lint.Found, edits: List<&2, Maybe<&2, List<&2, Fixes.Edit>>>}

# A finding as the run shows it: a line of text, or a JSON object.
type Shown is Data:
  Line{text: String}
  Object{value: Json.Json}

def Found.is_error(found: Lint.Found) -> Bool:
  match found:
    case Lint.Found{rule, Lint.Finding{Lint.Error{}, span, message, fixes}}:
      True{}
    case _:
      False{}

def Found.in(
  founds: List<&2, Lint.Found>,
  +path: String,
  out: List<&2, Lint.Found>
) -> List<&2, Lint.Found>:
  match founds:
    case Nil{}:
      List.reverse(&2, Lint.Found, out)
    case Con{
      Lint.Found{rule, Lint.Finding{severity, Lint.Span{+p, beg, end}, message, fixes}},
      rest
    }:
      Found.in(
        rest,
        path,
        Found.keep(
          String.eq(p, path),
          Lint.Found{rule, Lint.Finding{severity, Lint.Span{p, beg, end}, message, fixes}},
          out
        )
      )

def Found.fixes(founds: List<&2, Lint.Found>, out: List<&2, Lint.Fix>) -> List<&2, Lint.Fix>:
  match founds:
    case Nil{}:
      List.reverse(&2, Lint.Fix, out)
    case Con{Lint.Found{rule, Lint.Finding{severity, span, message, fixes}}, rest}:
      Found.fixes(rest, Utils.onto(&2, Lint.Fix, fixes, out))

# A linted file's findings, after its directives, added to the report.
def Report.add(found: Directives.Suppressed, report: Report) -> Report:
  match found report:
    case Directives.Suppressed{kept, suppressed} Report{k, s, texts}:
      Report{Utils.onto(&2, Lint.Found, kept, k), Utils.onto(&2, Lint.Found, suppressed, s), texts}

# A failed check's message as a finding at `span`, added to the report, with the text of its file.
def Report.failure(span: Lint.Span, message: String, text: String, report: Report) -> Report:
  match span report:
    case Lint.Span{+path, beg, end} Report{kept, suppressed, texts}:
      Report{
        Lint.Found{
          "bend/check",
          Lint.Finding{Lint.Error{}, Lint.Span{path, beg, end}, message, []}
        }
          <> kept,
        suppressed,
        Map.set(&2, String, texts, path, text)
      }

def Report.failures(failures: List<&2, Program.Failure>, +path: String, report: Report) -> Report:
  match failures:
    case Nil{}:
      report
    case Con{Program.Failure{message, at, text}, rest}:
      Report.failures(
        rest,
        path,
        Report.failure(
          Maybe.default(&2, Lint.Span, at, Lint.Span{path, 0, 0}),
          message,
          text,
          report
        )
      )

def Report.unique(report: Report) -> Report:
  match report:
    case Report{kept, suppressed, texts}:
      Report{
        List.reverse(&2, Lint.Found, Merge.union([], List.reverse(&2, Lint.Found, kept))),
        suppressed,
        texts
      }

# The report of the named file (at `path`) so far: Bend's message of each failed check of it, once, as its first
# findings: at the failure, or at the file's start if Bend does not say where.
def Report.failed(path: String, failures: List<&2, Program.Failure>) -> Report:
  Report.unique(Report.failures(failures, path, Report{[], [], Map.new(&2, String)}))

# Each linted file's findings, after `out`: those of the file rules, then those of the program rules, after its
# directives.
def report(
  linted: List<&2, Lint.Source>,
  +files: List<&2, Lint.Found>,
  +program: List<&2, Lint.Found>,
  +known: List<&2, String>,
  +ran: List<&2, String>,
  out: Report
) -> Report:
  match linted:
    case Con{Lint.Source{+path, namespace, text, nodes, facts}, rest}:
      report(
        rest,
        files,
        program,
        known,
        ran,
        Report.add(
          Directives.apply(
            Directives.Linted{path, text, known, ran},
            Utils.append(&2, Lint.Found, Found.in(files, path, []), Found.in(program, path, []))
          ),
          out
        )
      )
    case Nil{}:
      out

# Rendering
# ---------

# Each finding with the edits of its fixes, taken in order from `edits` (empty: none resolved).
def Resolved.of(
  founds: List<&2, Lint.Found>,
  +edits: List<&2, Maybe<&2, List<&2, Fixes.Edit>>>,
  out: List<&2, Resolved>
) -> List<&2, Resolved>:
  match founds:
    case Nil{}:
      List.reverse(&2, Resolved, out)
    case Con{Lint.Found{rule, Lint.Finding{severity, span, message, +fixes}}, rest}:
      +n = Utils.length(&2, Lint.Fix, fixes)
      Resolved.of(
        rest,
        List.drop(&2, Maybe<&2, List<&2, Fixes.Edit>>, edits, n),
        Resolved{
          Lint.Found{rule, Lint.Finding{severity, span, message, fixes}},
          List.take(&2, Maybe<&2, List<&2, Fixes.Edit>>, edits, n)
        }
          <> out
      )

def Edit.places(edits: List<&2, Fixes.Edit>, out: List<&2, Utils.Place>) -> List<&2, Utils.Place>:
  match edits:
    case Nil{}:
      out
    case Con{Fixes.Edit{+path, beg, end, text}, rest}:
      Edit.places(rest, Utils.Place{path, end} <> Utils.Place{path, beg} <> out)

def Edits.places(
  edits: List<&2, Maybe<&2, List<&2, Fixes.Edit>>>,
  out: List<&2, Utils.Place>
) -> List<&2, Utils.Place>:
  match edits:
    case Nil{}:
      out
    case Con{Some{es}, rest}:
      Edits.places(rest, Edit.places(es, out))
    case Con{None{}, rest}:
      Edits.places(rest, out)

# The places a finding shows besides its start, onto `out`: in JSON, its end and its fixes' edits'.
def Shown.more(
  json: Bool,
  path: String,
  end: U32,
  edits: List<&2, Maybe<&2, List<&2, Fixes.Edit>>>,
  out: List<&2, Utils.Place>
) -> List<&2, Utils.Place>:
  match json:
    case False{}:
      out
    case True{}:
      Edits.places(edits, Utils.Place{path, end} <> out)

def Shown.places(
  +json: Bool,
  resolved: List<&2, Resolved>,
  out: List<&2, Utils.Place>
) -> List<&2, Utils.Place>:
  match resolved:
    case Nil{}:
      out
    case Con{
      Resolved{
        Lint.Found{rule, Lint.Finding{severity, Lint.Span{+path, beg, end}, message, fixes}},
        edits
      },
      rest
    }:
      Shown.places(json, rest, Shown.more(json, path, end, edits, Utils.Place{path, beg} <> out))

def Found.line.at(path: String, at: Utils.Position, said: String) -> String:
  match at:
    case Utils.Position{line, column}:
      path ++ ":" ++ U32.show(line) ++ ":" ++ U32.show(column) ++ ": " ++ said

def Found.line(found: Lint.Found, places: Map<&2, Utils.Position>) -> String:
  match found:
    case Lint.Found{rule, Lint.Finding{severity, Lint.Span{+path, beg, end}, message, fixes}}:
      Found.line.at(
        path,
        Utils.Place.at(places, path, beg),
        Lint.Severity.show(severity) ++ " " ++ rule ++ ": " ++ message
      )

def Object.position(at: Utils.Position) -> Json.Json:
  match at:
    case Utils.Position{line, column}:
      Json.JObject{
        [
          Json.JField{"line", Json.JNumber{U32.show((line - 1: U32))}},
          Json.JField{"character", Json.JNumber{U32.show((column - 1: U32))}}
        ]
      }

def Object.range(+places: Map<&2, Utils.Position>, +path: String, beg: U32, end: U32) -> Json.Json:
  Json.JObject{
    [
      Json.JField{"start", Object.position(Utils.Place.at(places, path, beg))},
      Json.JField{"end", Object.position(Utils.Place.at(places, path, end))}
    ]
  }

def Object.edits(
  edits: List<&2, Fixes.Edit>,
  +places: Map<&2, Utils.Position>,
  out: List<&2, Json.Json>
) -> List<&2, Json.Json>:
  match edits:
    case Nil{}:
      List.reverse(&2, Json.Json, out)
    case Con{Fixes.Edit{+path, beg, end, text}, rest}:
      Object.edits(
        rest,
        places,
        Json.JObject{
          [
            Json.JField{"path", Json.JString{path}},
            Json.JField{"range", Object.range(places, path, beg, end)},
            Json.JField{"text", Json.JString{text}}
          ]
        }
          <> out
      )

def Object.fix(
  safe: Bool,
  fix: Lint.Fix,
  edits: List<&2, Fixes.Edit>,
  places: Map<&2, Utils.Position>
) -> Json.Json:
  match fix:
    case Lint.Fix{title, ops}:
      Json.JObject{
        [
          Json.JField{"title", Json.JString{title}},
          Json.JField{"applicability", Json.JString{Bool.pick(String, safe, "safe", "dangerous")}},
          Json.JField{"edits", Json.JArray{Object.edits(edits, places, [])}}
        ]
      }

# The fixes the linter can make, as JSON, onto `out`: `edits` says each one's edits.
def Object.fixes(
  fixes: List<&2, Lint.Fix>,
  edits: List<&2, Maybe<&2, List<&2, Fixes.Edit>>>,
  +places: Map<&2, Utils.Position>,
  +comments: Set(),
  out: List<&2, Json.Json>
) -> List<&2, Json.Json>:
  match fixes edits:
    case Con{+fix, rest} Con{Some{es}, more}:
      Object.fixes(
        rest,
        more,
        places,
        comments,
        Object.fix(Fixes.Fix.safe(fix, comments), fix, es, places) <> out
      )
    case Con{fix, rest} Con{None{}, more}:
      Object.fixes(rest, more, places, comments, out)
    case _ _:
      List.reverse(&2, Json.Json, out)

# `comments` says where a safe fix may write.
def Object.finding(
  resolved: Resolved,
  +places: Map<&2, Utils.Position>,
  comments: Set()
) -> Json.Json:
  match resolved:
    case Resolved{
      Lint.Found{rule, Lint.Finding{severity, Lint.Span{+path, beg, end}, message, fixes}},
      edits
    }:
      Json.JObject{
        [
          Json.JField{"code", Json.JString{rule}},
          Json.JField{"severity", Json.JString{Lint.Severity.show(severity)}},
          Json.JField{"message", Json.JString{message}},
          Json.JField{"path", Json.JString{path}},
          Json.JField{"range", Object.range(places, path, beg, end)},
          Json.JField{"fixes", Json.JArray{Object.fixes(fixes, edits, places, comments, [])}}
        ]
      }

def Shown.one(
  json: Bool,
  resolved: Resolved,
  places: Map<&2, Utils.Position>,
  comments: Set()
) -> Shown:
  match json resolved:
    case False{} Resolved{found, edits}:
      Line{Found.line(found, places)}
    case True{} _:
      Object{Object.finding(resolved, places, comments)}

# The findings as the run shows them (in JSON if `json`), onto `out` (last first): `places` holds where they are, and
# `comments` where a safe fix may write.
def Shown.of(
  +json: Bool,
  resolved: List<&2, Resolved>,
  +places: Map<&2, Utils.Position>,
  +comments: Set(),
  out: List<&2, Shown>
) -> List<&2, Shown>:
  match resolved:
    case Nil{}:
      out
    case Con{r, rest}:
      Shown.of(json, rest, places, comments, Shown.one(json, r, places, comments) <> out)

def Shown.text(shown: Shown) -> String:
  match shown:
    case Line{text}:
      text
    case Object{value}:
      Json.show(value)

def Shown.json(shown: Shown) -> Json.Json:
  match shown:
    case Object{value}:
      value
    case Line{text}:
      Json.JString{text}

def Shown.edits(
  json: Bool,
  founds: List<&2, Lint.Found>,
  declarations: List<&2, Lint.Declaration>,
  sources: List<&2, Lint.Source>
) -> List<&2, Maybe<&2, List<&2, Fixes.Edit>>>:
  match json:
    case False{}:
      []
    case True{}:
      Fixes.edits(Found.fixes(founds, []), declarations, sources)

def Shown.safety(json: Bool, founds: List<&2, Lint.Found>, sources: List<&2, Lint.Source>) -> Set():
  match json:
    case False{}:
      Set.new()
    case True{}:
      Fixes.safety(Found.fixes(founds, []), sources)

# The declarations of the program's files (`sources`), if the run needs them: to show fixes, or to make them.
def Declarations.of(need: Bool, sources: List<&2, Lint.Source>) -> List<&2, Lint.Declaration>:
  match need:
    case True{}:
      Lint.Whole.declarations(Program.Whole.of(Lint.Program{sources}, True{}))
    case False{}:
      []

def Declarations.needed(json: Bool, fixing: Maybe<&2, Bool>) -> Bool:
  match json fixing:
    case False{} None{}:
      False{}
    case _ _:
      True{}

# Ending
# ------

# What linting named files gave: how many findings stay; those to show at the end, and those directives suppressed
# (both last first); whether a file fails the run; and how many fixes the run made.
type Outcome is Data:
  Outcome{
    count: Nat,
    findings: List<&2, Shown>,
    suppressed: List<&2, Shown>,
    failed: Bool,
    fixed: U32
  }

def Outcome.add(a: Outcome, b: Outcome) -> Outcome:
  match a b:
    case Outcome{n, f, s, e, x} Outcome{m, g, t, d, y}:
      Outcome{
        Nat.add(n, m),
        Utils.append(&2, Shown, g, f),
        Utils.append(&2, Shown, t, s),
        e || d,
        (x + y: U32)
      }

def summary.fixed(fixing: Maybe<&2, Bool>, fixed: U32) -> String:
  match fixing:
    case None{}:
      ""
    case _:
      ", " ++ U32.show(fixed) ++ " fixed"

def summary(n: Nat, suppressed: Nat, fixed: String) -> String:
  match suppressed:
    case 0n:
      "bend-lint: " ++ Nat.show(n) ++ " finding(s)" ++ fixed
    case _:
      "bend-lint: "
        ++ Nat.show(n)
        ++ " finding(s), "
        ++ Nat.show(suppressed)
        ++ " suppressed"
        ++ fixed

def say(lines: List<&2, String>) -> IO(Unit):
  match lines:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{h, t}:
      IO.print(String.join(h <> t, "\n"))

def Shown.texts(shown: List<&2, Shown>, out: List<&2, String>) -> List<&2, String>:
  match shown:
    case Nil{}:
      out
    case Con{s, rest}:
      Shown.texts(rest, Shown.text(s) <> out)

def Shown.values(shown: List<&2, Shown>, out: List<&2, Json.Json>) -> List<&2, Json.Json>:
  match shown:
    case Nil{}:
      out
    case Con{s, rest}:
      Shown.values(rest, Shown.json(s) <> out)

# The lines of the findings directives suppressed (last first), if the run shows them and there are some.
def suppressed.lines(show: Bool, shown: List<&2, Shown>) -> List<&2, String>:
  match show shown:
    case True{} Con{s, ss}:
      "bend-lint: suppressed" <> Shown.texts(Con{s, ss}, [])
    case _ _:
      []

def end.json(failed: Bool, summary: String) -> IO(Unit):
  match failed:
    case True{}:
      IO.die(Unit, 1, "bend-lint: FAIL")
    case False{}:
      IO.print_err(summary)

def end(json: Bool, total: Outcome, show: Bool, fixing: Maybe<&2, Bool>) -> IO(Unit):
  match json total:
    case False{} Outcome{n, f, s, True{}, x}:
      do IO<Unit>:
        say(suppressed.lines(show, s))
        IO.die(Unit, 1, "bend-lint: FAIL")
    case False{} Outcome{n, f, +s, False{}, x}:
      do IO<Unit>:
        say(suppressed.lines(show, s))
        IO.print(summary(n, Utils.length(&2, Shown, s), summary.fixed(fixing, x)))
    case True{} Outcome{n, f, +s, +failed, x}:
      do IO<Unit>:
        IO.print(
          Json.show(
            Json.JObject{
              [
                Json.JField{"ok", Bool.pick(Json.Json, failed, Json.JFalse{}, Json.JTrue{})},
                Json.JField{"findings", Json.JArray{Shown.values(f, [])}},
                Json.JField{"suppressed", Json.JArray{Shown.values(s, [])}}
              ]
            }
          )
        )
        end.json(failed, summary(n, Utils.length(&2, Shown, s), summary.fixed(fixing, x)))

# The findings to keep for the end of the run: in JSON, all of them; in text, none, as they are printed already.
def Shown.kept(json: Bool, shown: List<&2, Shown>) -> List<&2, Shown>:
  match json:
    case False{}:
      []
    case True{}:
      shown

# The lines the run prints for a named file as it goes: in text, its findings; in JSON, none.
def Shown.printed(json: Bool, shown: List<&2, Shown>) -> List<&2, String>:
  match json:
    case False{}:
      List.reverse(&2, String, Shown.texts(shown, []))
    case True{}:
      []

# Prints the report in text, then makes the fixes `fixing` allows in `program`'s files: what linting the named file
# gave. It fails if a finding that stays is an error.
def outcome(
  report: Report,
  +json: Bool,
  +fixing: Maybe<&2, Bool>,
  program: Lint.Program
) -> IO(Outcome):
  match report program:
    case Report{kept, suppressed, extra} Lint.Program{+sources}:
      +founds = List.reverse(&2, Lint.Found, kept)
      +all = Utils.append(&2, Lint.Found, founds, List.reverse(&2, Lint.Found, suppressed))
      +declarations = Declarations.of(Declarations.needed(json, fixing), sources)
      +resolved = Resolved.of(all, Shown.edits(json, all, declarations, sources), [])
      +n = Utils.length(&2, Lint.Found, founds)
      +shown = List.reverse(
        &2,
        Shown,
        Shown.of(
          json,
          resolved,
          Utils.places(Fixes.texts(sources, extra), Shown.places(json, resolved, [])),
          Shown.safety(json, all, sources),
          []
        )
      )
      do IO<Outcome>:
        say(Shown.printed(json, List.take(&2, Shown, shown, n)))
        fixed: U32 <- Fixes.apply(fixing, founds, declarations, sources)
        return Outcome{
          n,
          List.reverse(&2, Shown, Shown.kept(json, List.take(&2, Shown, shown, n))),
          List.reverse(&2, Shown, List.drop(&2, Shown, shown, n)),
          Utils.any(~Lint.Found, ~Found.is_error, founds),
          fixed
        }

# CLI
# ===

# How many rounds of questions a run may ask: past it, a rule still asking fails.
def budget() -> Nat:
  64n

# Prints what the jobs found in the linted files, after the report so far (`first`), and makes the fixes; `checks` is
# the number of checks.
def finish(
  linted: List<&2, Lint.Source>,
  +tagged: List<&2, Tagged>,
  checks: Nat,
  modes: List<&2, Utils.Named<Bool>>,
  partial: Bool,
  known: List<&2, String>,
  ran: List<&2, String>,
  json: Bool,
  fixing: Maybe<&2, Bool>,
  program: Lint.Program,
  first: Report
) -> IO(Outcome):
  outcome(
    report(
      linted,
      Tagged.of(tagged, 0, []),
      Merge.program(tagged, checks, modes, partial),
      known,
      ran,
      first
    ),
    json,
    fixing,
    program
  )

# Gives `outcome` once the server frees the checks numbered `checks`.
def forgotten(checks: List<&2, U32>, outcome: Outcome) -> IO(Outcome):
  match checks:
    case Nil{}:
      IO.pure(Outcome, outcome)
    case Con{c, rest}:
      IO.bind(Unit, Outcome, Wire.forget(c), done => forgotten(rest, outcome))

# Lints `linted`, files of the first of `programs` (the checks of the named file, at `path`), with the rules the
# config leaves on, after the report so far (`first`). Program rules run on each check; `partial` says whether an entry
# that reads the named file failed its check.
def lint(
  ~rules: List<&1, Lint.Rule>,
  +linted: List<&2, Lint.Source>,
  path: String,
  +programs: List<&2, Lint.Program>,
  partial: Bool,
  +settings: List<&2, Utils.Named<Config.Setting>>,
  json: Bool,
  fixing: Maybe<&2, Bool>,
  first: Report
) -> IO(Outcome):
  +abouts = About.all(rules, [])
  +on = About.on(abouts, settings, [])
  +declare = Utils.any(~About, ~About.declarations, on)
  IO.bind(
    List<&2, Tagged>,
    Outcome,
    Rounds.go(
      budget(),
      Round.hold(
        Utils.append(
          &1,
          Job,
          File.all(
            ~rules,
            3n,
            Utils.deal(&2, Lint.Source, linted),
            settings,
            Maybe.default(
              &2,
              Lint.Program,
              List.head(&2, Lint.Program, programs),
              Lint.Program{[]}
            ),
            declare
          ),
          Check.jobs.if(
            ~rules,
            Utils.any(~About, ~About.whole, on),
            programs,
            settings,
            path,
            declare
          )
        ),
        [],
        []
      )
    ),
    tagged => finish(
      linted,
      tagged,
      Utils.length(&2, Lint.Program, programs),
      About.modes(abouts, []),
      partial,
      About.ids(abouts, []),
      About.ids(on, []),
      json,
      fixing,
      Maybe.default(&2, Lint.Program, List.head(&2, Lint.Program, programs), Lint.Program{[]}),
      first
    )
  )

def Source.at(
  sources: List<&2, Lint.Source>,
  found: Maybe<&2, Lint.Source>,
  +path: String
) -> Maybe<&2, Lint.Source>:
  match sources found:
    case _ Some{source}:
      Some{source}
    case Nil{} None{}:
      None{}
    case Con{Lint.Source{+p, namespace, text, nodes, facts}, rest} None{}:
      Source.at(
        rest,
        Utils.when(Lint.Source, String.eq(p, path), Lint.Source{p, namespace, text, nodes, facts}),
        path
      )

# Whether to lint the files the named file imports: as the command line says, else as the config says, else not.
def imports(flag: Maybe<&2, Bool>, project: Maybe<&2, Bool>) -> Bool:
  Maybe.default(&2, Bool, Maybe.or(&2, Bool, flag, project), False{})

# The checks of the named file: the programs to lint it in (the first one's file rules run); why the entries that read
# it failed their checks, in order; why its own check failed, if it did (then the program is what it parsed); and the
# checks to free after it: its own.
type Checks is Data:
  Checks{
    programs: List<&2, Lint.Program>,
    entries: List<&2, Program.Failure>,
    own: Maybe<&2, Program.Failure>,
    forget: List<&2, U32>
  }

def Checks.partial(entries: List<&2, Program.Failure>) -> Bool:
  match entries:
    case Nil{}:
      False{}
    case _:
      True{}

def Checks.failures(
  entries: List<&2, Program.Failure>,
  own: Maybe<&2, Program.Failure>
) -> List<&2, Program.Failure>:
  Utils.append(
    &2,
    Program.Failure,
    entries,
    Maybe.default(
      &2,
      List<&2, Program.Failure>,
      Maybe.map(&2, Program.Failure, List<&2, Program.Failure>, f => [f], own),
      []
    )
  )

# The files to lint: the named file (at `path`), or, with `imports`, every own file of its check.
def linted(imports: Bool, path: String, sources: List<&2, Lint.Source>) -> List<&2, Lint.Source>:
  match imports:
    case True{}:
      Program.Program.own(sources)
    case False{}:
      Maybe.default(
        &2,
        List<&2, Lint.Source>,
        Maybe.map(
          &2,
          Lint.Source,
          List<&2, Lint.Source>,
          s => [s],
          Source.at(sources, None{}, path)
        ),
        []
      )

def checked(
  ~rules: List<&1, Lint.Rule>,
  +path: String,
  imports: Bool,
  settings: List<&2, Utils.Named<Config.Setting>>,
  json: Bool,
  fixing: Maybe<&2, Bool>,
  checks: Checks
) -> IO(Outcome):
  match checks:
    case Checks{Con{Lint.Program{+sources}, rest}, +entries, +own, forget}:
      IO.bind(
        Outcome,
        Outcome,
        lint(
          ~rules,
          linted(imports, path, sources),
          path,
          Lint.Program{sources} <> rest,
          Checks.partial(entries),
          About.unchecked(Maybe.is_some(&2, Program.Failure, own), About.all(rules, []), settings),
          json,
          fixing,
          Report.failed(path, Checks.failures(entries, own))
        ),
        outcome => forgotten(forget, outcome)
      )
    case Checks{Nil{}, entries, own, forget}:
      outcome(Report.failed(path, Checks.failures(entries, own)), json, fixing, Lint.Program{[]})

# The named file's own check, as the checks to lint it in, after the failures of its entries. If it fails, the rules
# that need no facts run on what it parsed, if it parsed the files.
def Check.own(entries: List<&2, Program.Failure>, check: Program.Check) -> Checks:
  match check:
    case Program.Passed{p, c}:
      Checks{[p], entries, None{}, [c]}
    case Program.Failed{failure, read, parsed}:
      Checks{
        Maybe.default(
          &2,
          List<&2, Lint.Program>,
          Maybe.map(&2, Lint.Program, List<&2, Lint.Program>, p => [p], parsed),
          []
        ),
        entries,
        Some{failure},
        []
      }

def Check.reads(path: String, +check: Program.Check) -> Bool:
  match check:
    case Program.Passed{Lint.Program{sources}, c}:
      Maybe.is_some(&2, Lint.Source, Source.at(sources, None{}, path))
    case Program.Failed{failure, read, parsed}:
      List.contains(~String, ~String.eq, read, path)

# One check sorted into `checks`: if it reads the named file, its program joins the programs, or its failure joins the
# entries' failures.
def Check.sort.step(reads: Bool, check: Program.Check, checks: Checks) -> Checks:
  match reads check checks:
    case True{} Program.Passed{p, c} Checks{programs, entries, own, forget}:
      Checks{p <> programs, entries, own, forget}
    case True{} Program.Failed{failure, read, parsed} Checks{programs, entries, own, forget}:
      Checks{programs, failure <> entries, own, forget}
    case False{} _ _:
      checks

# The checks that read the named file (at `path`): the programs of those that passed, and why the others failed.
def Check.sort(checks: List<&2, Program.Check>, +path: String, sorted: Checks) -> Checks:
  match checks sorted:
    case Nil{} Checks{programs, entries, own, forget}:
      Checks{
        List.reverse(&2, Lint.Program, programs),
        List.reverse(&2, Program.Failure, entries),
        own,
        forget
      }
    case Con{+c, rest} _:
      Check.sort(rest, path, Check.sort.step(Check.reads(path, c), c, sorted))

def Check.all(
  entries: List<&2, String>,
  +facts: Bool,
  out: List<&2, Program.Check>
) -> IO(List<&2, Program.Check>):
  match entries:
    case Nil{}:
      IO.pure(List<&2, Program.Check>, List.reverse(&2, Program.Check, out))
    case Con{e, rest}:
      IO.bind(
        Program.Check,
        List<&2, Program.Check>,
        Wire.check(e, facts),
        c => Check.all(rest, facts, c <> out)
      )

# The checks to lint the named file in: those of the entries that read it and passed; if none, its own.
def Check.chosen(sorted: Checks, path: String, facts: Bool) -> IO(Checks):
  match sorted:
    case Checks{Nil{}, entries, own, forget}:
      IO.bind(
        Program.Check,
        Checks,
        Wire.check(path, facts),
        c => IO.pure(Checks, Check.own(entries, c))
      )
    case _:
      IO.pure(Checks, sorted)

# The checks to lint the named file (at `path`) in: with `imports` or no entries, its own; else those `Check.chosen`
# picks.
def Check.of(imports: Bool, entries: List<&2, String>, +path: String, +facts: Bool) -> IO(Checks):
  match imports entries:
    case False{} Con{e, es}:
      IO.bind(
        List<&2, Program.Check>,
        Checks,
        Check.all(Con{e, es}, facts, []),
        checks => Check.chosen(Check.sort(checks, path, Checks{[], [], None{}, []}), path, facts)
      )
    case _ _:
      IO.bind(
        Program.Check,
        Checks,
        Wire.check(path, facts),
        c => IO.pure(Checks, Check.own([], c))
      )

def Options.checked(problem: Maybe<&2, String>) -> IO(Unit):
  match problem:
    case Some{why}:
      IO.die(Unit, 2, "bend-lint config: " ++ why)
    case None{}:
      IO.pure(Unit, Unit{})

type Options is Data:
  Options{
    inputs: List<&2, String>,
    imports: Maybe<&2, Bool>,
    fixing: Maybe<&2, Bool>,
    shown: Bool,
    json: Bool
  }

# Stops the run if it lints the imports of more than one file: a run with imports has one root.
def Options.single(imports: Bool, many: Bool) -> IO(Unit):
  match imports many:
    case True{} True{}:
      IO.die(Unit, 2, "bend-lint: --imports takes one file to lint, also from the config")
    case _ _:
      IO.pure(Unit, Unit{})

def settled(
  ~rules: List<&1, Lint.Rule>,
  +path: String,
  +imports: Bool,
  json: Bool,
  fixing: Maybe<&2, Bool>,
  entries: List<&2, String>,
  +settings: List<&2, Utils.Named<Config.Setting>>
) -> IO(Outcome):
  IO.bind(
    Checks,
    Outcome,
    Check.of(
      imports,
      entries,
      path,
      Utils.any(~About, ~About.facts, About.on(About.all(rules, []), settings, []))
    ),
    checks => checked(~rules, path, imports, settings, json, fixing, checks)
  )

# Lints the file at `path` as its config says: `many` says whether the run lints more than one file.
def configured(
  ~rules: List<&1, Lint.Rule>,
  path: String,
  +options: Options,
  many: Bool,
  project: Config.Project
) -> IO(Outcome):
  match options project:
    case Options{inputs, flag, fixing, shown, json} Config.Project{entries, from, +settings}:
      +on = imports(flag, from)
      do IO<Outcome>:
        Options.checked(About.problem(About.all(rules, []), settings))
        Options.single(on, many)
        settled(
          ~rules,
          path,
          on,
          json,
          fixing,
          entries,
          About.settle(About.all(rules, []), settings, [])
        )

type Flag is Data:
  ImportsFlag{on: Bool}
  FixFlag{fixing: Maybe<&2, Bool>}
  ShownFlag{}
  JsonFlag{}

def flags() -> List<&2, Utils.Named<Flag>>:
  [
    Utils.Named{"--imports", ImportsFlag{True{}}},
    Utils.Named{"--no-imports", ImportsFlag{False{}}},
    Utils.Named{"--fix", FixFlag{Some{False{}}}},
    Utils.Named{"--fix-dangerously", FixFlag{Some{True{}}}},
    Utils.Named{"--show-suppressed", ShownFlag{}},
    Utils.Named{"--json", JsonFlag{}}
  ]

def Options.set(flag: Maybe<&2, Flag>, options: Maybe<&2, Options>) -> Maybe<&2, Options>:
  match flag options:
    case Some{ImportsFlag{on}} Some{Options{inputs, imports, fixing, shown, json}}:
      Some{Options{inputs, Some{on}, fixing, shown, json}}
    case Some{FixFlag{set}} Some{Options{inputs, imports, fixing, shown, json}}:
      Some{Options{inputs, imports, set, shown, json}}
    case Some{ShownFlag{}} Some{Options{inputs, imports, fixing, shown, json}}:
      Some{Options{inputs, imports, fixing, True{}, json}}
    case Some{JsonFlag{}} Some{Options{inputs, imports, fixing, shown, json}}:
      Some{Options{inputs, imports, fixing, shown, True{}}}
    case _ _:
      None{}

def Options.input(input: String, options: Maybe<&2, Options>) -> Maybe<&2, Options>:
  match options:
    case Some{Options{inputs, imports, fixing, shown, json}}:
      Some{Options{input <> inputs, imports, fixing, shown, json}}
    case None{}:
      None{}

def Options.arg(flag: Bool, arg: String, options: Maybe<&2, Options>) -> Maybe<&2, Options>:
  match flag:
    case True{}:
      Options.set(Utils.lookup(Flag, arg, flags()), options)
    case False{}:
      Options.input(arg, options)

# The options, once every argument is read: the files in order; none if there are none.
def Options.done(options: Maybe<&2, Options>) -> Maybe<&2, Options>:
  match options:
    case Some{Options{Con{first, more}, imports, fixing, shown, json}}:
      Some{Options{List.reverse(&2, String, Con{first, more}), imports, fixing, shown, json}}
    case _:
      None{}

def Options.read(args: List<String>, options: Maybe<&2, Options>) -> Maybe<&2, Options>:
  match args:
    case Nil{}:
      Options.done(options)
    case Con{+a, rest}:
      Options.read(rest, Options.arg(String.starts_with(a, "--"), a, options))

def options(args: List<String>) -> Maybe<&2, Options>:
  match args:
    case Con{program, rest}:
      Options.read(rest, Some{Options{[], None{}, None{}, False{}, False{}}})
    case Nil{}:
      None{}

def File.lint(
  ~rules: List<&1, Lint.Rule>,
  +path: String,
  options: Options,
  many: Bool
) -> IO(Outcome):
  IO.bind(
    Config.Project,
    Outcome,
    Config.find(path),
    project => configured(~rules, path, options, many, project)
  )

def Options.fixing(options: Options) -> Maybe<&2, Bool>:
  match options:
    case Options{inputs, imports, fixing, shown, json}:
      fixing

def Options.shown(options: Options) -> Bool:
  match options:
    case Options{inputs, imports, fixing, shown, json}:
      shown

def Options.json(options: Options) -> Bool:
  match options:
    case Options{inputs, imports, fixing, shown, json}:
      json

def Files.lint(
  ~rules: List<&1, Lint.Rule>,
  paths: List<&2, String>,
  +options: Options,
  +many: Bool,
  total: Outcome
) -> IO(Unit):
  match paths:
    case Nil{}:
      end(Options.json(options), total, Options.shown(options), Options.fixing(options))
    case Con{path, rest}:
      IO.bind(
        Outcome,
        Unit,
        File.lint(~rules, path, options, many),
        o => Files.lint(~rules, rest, options, many, Outcome.add(total, o))
      )

def checking(~rules: List<&1, Lint.Rule>, options: Maybe<&2, Options>) -> IO(Unit):
  match options:
    case Some{Options{+inputs, flag, fixing, shown, json}}:
      IO.bind(
        List<&2, String>,
        Unit,
        Wire.files(inputs),
        +paths => Files.lint(
          ~rules,
          paths,
          Options{inputs, flag, fixing, shown, json},
          Nat.is_gt(Utils.length(&2, String, paths), 1n),
          Outcome{0n, [], [], False{}, 0}
        )
      )
    case None{}:
      IO.die(
        Unit,
        2,
        "usage: bend-lint [--program <rules program>] <file or glob>... [--imports | --no-imports] [--fix | --fix-dangerously] [--show-suppressed] [--json]"
      )

def run(~rules: List<&1, Lint.Rule>) -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), args => checking(~rules, options(args)))
