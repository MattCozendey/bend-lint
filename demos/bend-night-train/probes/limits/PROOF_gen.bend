# The general 4^d law, in its smallest form, runs out of arithmetic lemmas.
#
# `four` is the frame's tile count without the tree: the same four-way nesting
# that `Shape.tiles(Shape.frame(d))` has, and the same induction step.  The step
# needs the hypothesis rewritten inside a four-fold sum, plus x + 0 = x and
# associativity; Base provides no lemmas about Nat at all, and the checker has no
# rewriting, so the step cannot be taken.  docs/laws.md shows where it stops.
import Base

def four(+d: Nat) -> Nat:
  match d:
    case 0n:
      1n
    case 1n+p:
      Nat.add(four(p), Nat.add(four(p), Nat.add(four(p), four(p))))

law four_is_pow:
  for d: Nat
  {four(d) == Nat.pow(4n, d) : Nat}

def four_is_pow(d):
  match d:
    case 0n:
      {==}
    case 1n+p:
      %four_is_pow(p) : {four(p) == Nat.pow(4n, p) : Nat}
      {==}
