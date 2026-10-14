import Base
import ./accelerated.bend as A

# The compute template chooses CPU or GPU at the entry point.
def decimal_tail(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{h, t}:
      SCon{'.', SCon{h, t}}

def pi_text(s: String) -> String:
  match s:
    case SNil{}:
      "0"
    case SCon{h, t}:
      SCon{h, decimal_tail(t)}

def report(~compute: Nat -> Nat, +digits: U32) -> IO(Unit):
  +count = Nat.show(compute(U32.to_nat((digits - 1 : U32))))
  IO.print(U32.show(digits) ++ " digits: " ++ count ++ " collisions -> pi = " ++ pi_text(count))

def experimental_notice(unverified: Bool) -> IO(Unit):
  match unverified:
    case True{}:
      IO.print_err("Results above 12 digits are unverified; fixed precision and integer overflow may affect the calculation.")
    case False{}:
      IO.pure(Unit, Unit{})

def selected(~compute: Nat -> Nat, valid: Bool, +digits: U32) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        experimental_notice((digits > 12 : U32))
        report(~compute, digits)
    case False{}:
      IO.die(Unit, 2, "PI_DIGITS must be a positive integer.")

def parsed(~compute: Nat -> Nat, value: Maybe<&2, U32>) -> IO(Unit):
  match value:
    case None{}:
      IO.die(Unit, 2, "PI_DIGITS must be a positive integer.")
    case Some{+digits}:
      selected(~compute, (digits >= 1 : U32), digits)

def configured(~compute: Nat -> Nat, value: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match value:
    case Fail{error}:
      report(~compute, 10)
    case Done{text}:
      parsed(~compute, U32.read(text))

def start(~compute: Nat -> Nat) -> IO(Unit):
  do IO<Unit>:
    IO.print("Pi from composed collision transformations (two-float precision)")
    value : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_DIGITS")
    configured(~compute, value)

def main() -> IO(Unit):
  start(~(n => A.count(n)))
