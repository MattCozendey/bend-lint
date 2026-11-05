import Base

def earlier() -> Nat:
  1n

def main() -> Nat:
  earlier()

@unsafe
def u() -> Nat:
  later()

def v?() -> Nat:
  later()

def later() -> Nat:
  1n
