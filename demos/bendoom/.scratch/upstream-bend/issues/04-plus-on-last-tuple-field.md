# 04: A `+` on the last name of a three-part pattern breaks the checker

**What is wrong:** Opening a value of three parts with `(mem, g, +l) = w` fails when the `+` is on the last name. The same line with the `+` on the middle name, or with no `+`, works. The error is also misleading: it shows two lines of Bend's own library (`Pair` in `base.bend`) instead of our line, and with two `+` it lists one name twice.

**Where:** Bend's checker, first reproduced on commit e6676b0. Recheck on the current pin before reporting.

**Status:** ready-for-human (report upstream with the program below)

## The program

```python
import Base

type Box is Data:
  Box{v: U32}

def use(a: Array<U32>, +g: Box, +l: Box) -> U32:
  Box{x} = g
  x

def open(w: Array<U32> & Box & Box) -> U32:
  (mem, g, +l) = w
  use(mem, g, l)

def main() -> IO(Unit):
  IO.print(U32.show(open(([0 : U32*2n], Box{1}, Box{2}))))
```

```
Error:
- expected : an annotated term (cannot infer)
- observed : _ => Box
Location: open
143 | def Pair(A, B):
144>|   Sigma<&1, &1, A, _ => B>
```

`(mem, +g, l) = w` and `(mem, g, l) = w` both print `1`.

## What we do about it

Open the value in two steps: `(mem, gl) = w`, then pass `gl` to a def that opens `(+gfx, +level) = gl`. `src/game.bend` does this in `Game.start` and `Game.start.go`.
