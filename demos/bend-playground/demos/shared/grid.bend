import Base

# A reusable, persistent binary tree. Life stores 32 cells in each leaf;
# the renderer stores one RGB pixel. Forks are also parallel work boundaries.
type Grid is Data:
  Leaf{word: U32}
  Branch{left: Grid, right: Grid}

def first(g: Grid) -> U32:
  match g:
    case Leaf{word}:
      word
    case Branch{left, right}:
      first(left)

def pick(g: Grid, leftward: Bool) -> Grid:
  match g:
    case Leaf{word}:
      Leaf{word}
    case Branch{left, right}:
      Bool.pick(Grid, leftward, left, right)

def lookup(depth: Nat, g: Grid, +index: U32) -> U32:
  match depth:
    case 0n:
      first(g)
    case 1n+ +p:
      +half = U32.shln(1, p)
      lookup(p, pick(g, (index < half : U32)), (index .&. (half - 1) : U32))

def text(g: Grid) -> String:
  match g:
    case Leaf{word}:
      U32.show(word) ++ " "
    case Branch{left, right}:
      text(left) ++ text(right)

def checksum(g: Grid) -> U32:
  match g:
    case Leaf{word}:
      word
    case Branch{left, right}:
      (checksum(left) + checksum(right) : U32)
