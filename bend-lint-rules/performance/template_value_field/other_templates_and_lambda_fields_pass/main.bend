import Base

type R is Type:
  R{f: U32 -> U32, n: U32}

def R.n(r: R) -> U32:
  match r:
    case R{f, n}:
      n

def leaf() -> R:
  R{x => x, 1}

type Box is Data:
  Box{n: U32}

def lift(~g: U32 -> U32) -> R:
  R{x => g(x), g(3)}

def width(~w: U32) -> R:
  R{x => x, (w * 2 : U32)}

def count(~a: R) -> Box:
  Box{R.n(a)}

def wrap(~a: R) -> R:
  R{x => (x + R.n(a) : U32), 1}

def later(~a: R) -> U32 -> R:
  y => R{x => x, R.n(a)}
