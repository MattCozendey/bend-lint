# FNV-1a over 32-bit words, the checksum the tests and the bench print.
import Base

def Fnv.basis() -> U32:
  2166136261

def Fnv.mix(h: U32, x: U32) -> U32:
  ((h .^. x) * 16777619 : U32)

def Fnv.go(xs: List<&2, U32>, h: U32) -> U32:
  match xs:
    case []:
      h
    case x <> rest:
      Fnv.go(rest, Fnv.mix(h, x))

def Fnv.words(xs: List<&2, U32>) -> U32:
  Fnv.go(xs, Fnv.basis())
