# Running rules and printing what they find. A rules program calls `run` with its rules: `Cli.run(~[R.rule()])`.
import Base
import ./directives.bend as Directives
import ./lint.bend as Lint
import ./program.bend as Program
import ./shared.bend as Shared

# Running
# =======

# Each finding of `findings`, tagged with `rule`, onto `out` (last first).
def Found.tag(+rule: String, findings: List<&2, Lint.Finding>, out: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  match findings:
    case Nil{}:
      out
    case Con{f, rest}:
      Found.tag(rule, rest, Lint.Found{rule, f} <> out)

# What each rule finds on `here`, tagged with its id, onto `out` (last first).
def Rule.run_each(rules: List<&1, Lint.Rule>, +here: Lint.Here, out: List<&2, Lint.Found>) -> List<&2, Lint.Found>:
  match rules:
    case Nil{}:
      out
    case Con{Lint.Rule{id, run}, rest}:
      Rule.run_each(rest, here, Found.tag(id, run(here), out))

# Rules dealt into two halves of about the same size, one at a time.
def Rule.deal(rules: List<&1, Lint.Rule>, a: List<&1, Lint.Rule>, b: List<&1, Lint.Rule>) ->
  List<&1, Lint.Rule> & List<&1, Lint.Rule>:
  match rules:
    case Nil{}:
      (a, b)
    case Con{r, rest}:
      Rule.deal(rest, b, r <> a)

# What the rules of both halves find on `here`: each half in parallel, dealt again until `depth` runs out. A half's
# findings come in its rules' order; the halves interleave the rules, so the order is the halves'.
def Rule.run_all(+depth: Nat, halves: List<&1, Lint.Rule> & List<&1, Lint.Rule>, +here: Lint.Here) -> List<&2, Lint.Found>:
  match depth halves:
    case 0n Tuple{a, b}:
      List.reverse(&2, Lint.Found, Rule.run_each(b, here, Rule.run_each(a, here, [])))
    case 1n+d Tuple{a, b}:
      x y = Rule.run_all(d, Rule.deal(a, [], []), here) Rule.run_all(d, Rule.deal(b, [], []), here)
      List.append(&2, Lint.Found, x, y)

# The ids of the rules, in order.
def Rule.ids(rules: List<&1, Lint.Rule>, out: List<&2, String>) -> List<&2, String>:
  match rules:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{Lint.Rule{id, run}, rest}:
      Rule.ids(rest, id <> out)

# Output
# ======

# A finding as a line: path:line:column: severity rule: message.
def Found.show(+text: String, found: Lint.Found) -> String:
  match found:
    case Lint.Found{rule, Lint.Finding{severity, Lint.Span{path, beg, end}, message}}:
      path ++ ":" ++ Shared.position(text, beg) ++ ": " ++ Lint.Severity.show(severity) ++ " " ++ rule ++ ": " ++ message

def Found.lines(+text: String, founds: List<&2, Lint.Found>, out: List<&2, String>) -> List<&2, String>:
  match founds:
    case Nil{}:
      List.reverse(&2, String, out)
    case Con{f, rest}:
      Found.lines(text, rest, Found.show(text, f) <> out)

def Found.is_error(found: Lint.Found) -> Bool:
  match found:
    case Lint.Found{rule, Lint.Finding{Lint.Error{}, span, message}}:
      True{}
    case _:
      False{}

# Prints `lines`, if there are any.
def say(lines: List<&2, String>) -> IO(Unit):
  match lines:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{h, t}:
      IO.print(String.join(h <> t, "\n"))

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

# Prints the findings that stay, of the file whose text is `text`; fails if one is an error.
def print(+text: String, found: Directives.Suppressed) -> IO(Unit):
  match found:
    case Directives.Suppressed{+kept, suppressed}:
      do IO<Unit>:
        say(Found.lines(text, kept, []))
        end(
          List.any(~&2, ~Lint.Found, ~Found.is_error, kept),
          summary(List.length(&2, Lint.Found, kept), List.length(&2, Lint.Found, suppressed))
        )

# CLI
# ===

# Lints the file the check was for: the last it parsed, as its imports come first.
def lint(~rules: List<&1, Lint.Rule>, +program: Lint.Program, root: Maybe<&2, Lint.Source>) -> IO(Unit):
  match root:
    case Some{Lint.Source{+path, namespace, +text, nodes}}:
      print(
        text,
        Directives.apply(
          Rule.ids(rules, []),
          path,
          text,
          Rule.run_all(4n, Rule.deal(rules, [], []), Program.Here.of(program, Lint.Source{path, namespace, text, nodes}))
        )
      )
    case None{}:
      IO.die(Unit, 2, "bend-lint: the check parsed no file")

def checked(~rules: List<&1, Lint.Rule>, +file: String, check: Program.Check) -> IO(Unit):
  match check:
    case Program.Passed{Lint.Program{+sources}}:
      lint(~rules, Lint.Program{sources}, List.last(&2, Lint.Source, sources))
    case Program.Failed{message}:
      do IO<Unit>:
        IO.print(file ++ ": error bend/check: " ++ message)
        IO.die(Unit, 1, "bend-lint: FAIL")

def file(args: List<String>) -> IO(String):
  match args:
    case Con{program, Con{file, rest}}:
      IO.pure(String, file)
    case _:
      IO.die(String, 2, "usage: bun server.ts <program> <file>")

def checking(~rules: List<&1, Lint.Rule>, +file: String) -> IO(Unit):
  IO.bind(Program.Check, Unit, Program.Check.run(file), check => checked(~rules, file, check))

# The command line: lint the named file with `rules`.
def run(~rules: List<&1, Lint.Rule>) -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    f : String <- file(args)
    checking(~rules, f)
