import Base
import ./kinds.bend as K

def R.n(r: K.R) -> U32:
  match r:
    case K.R{f, n}:
      n

def both(~a: K.R, ~b: K.R) -> K.R:
  # bend-lint: expect-next performance/template_value_field@information -- reads templates a and b
  K.R{x => x, (R.n(a) + R.n(b) : U32)}
