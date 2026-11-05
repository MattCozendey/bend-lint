import Base
import ./leaf.bend as Leaf

type Box<a, -A: Kind(a)> is Kind(a):
  Box{val: A, n_2: U32}

type Box.OP is Data:
  Word32{}

def Both(-A: Type, -B: Type) -> Type:
  A & B

def Fam(F: @-x: U32 -> Type) -> Type:
  F(1)

def Box.from_u32(n: U32) -> U32:
  n

def keep(-T: Data, _x: T) -> T:
  _x

law add_zero:
  for x: U32
  U32

def add_zero(x):
  x

def main() -> U32:
  Leaf.one()
