import Base

type R is Type:
  R{f: U32 -> U32, n: U32}

def R.n(r: R) -> U32:
  match r:
    case R{f, n}:
      n

def leaf() -> R:
  R{x => x, 1}

def both(~a: R, ~b: R) -> R:
  # bend-lint: expect-next performance/template_value_field@information -- reads templates a and b
  R{x => x, (R.n(a) + R.n(b) : U32)}
