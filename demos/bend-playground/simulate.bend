import Base
import ./physics.bend as Physics

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

def print_result(done: Bool, mass: F32, result: Physics.State) -> IO(Unit):
  match done:
    case True{}:
      +count = U32.show(Physics.collisions(result))
      IO.print("mass ratio " ++ F32.show(mass) ++ ": " ++ count ++ " collisions -> pi = " ++ pi_text(count))
    case False{}:
      IO.die(Unit, 1, "Collision budget exhausted; this result is incomplete.")

def report(+mass: F32) -> IO(Unit):
  +result = Physics.run(U32.to_nat(10000), Physics.initial(mass))
  print_result(Physics.finished(result), mass, result)

def all() -> IO(Unit):
  do IO<Unit>:
    report(1.0)
    report(100.0)
    report(10000.0)
    report(1000000.0)

def mass_power(n: Nat) -> F32:
  match n:
    case 0n:
      1.0
    case 1n+p:
      (100.0 * mass_power(p) : F32)

def selected(valid: Bool, digits: U32) -> IO(Unit):
  match valid:
    case True{}:
      report(mass_power(U32.to_nat((digits - 1 : U32))))
    case False{}:
      IO.die(Unit, 2, "PI_DIGITS must be an integer from 1 to 4.")

def parsed(value: Maybe<&2, U32>) -> IO(Unit):
  match value:
    case None{}:
      IO.die(Unit, 2, "PI_DIGITS must be an integer from 1 to 4.")
    case Some{+digits}:
      selected((digits >= 1 : U32) && (digits <= 4 : U32), digits)

def configured(value: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match value:
    case Fail{error}:
      all()
    case Done{text}:
      parsed(U32.read(text))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("Pi from perfectly elastic collisions (small mass = 1)")
    value : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_DIGITS")
    configured(value)
