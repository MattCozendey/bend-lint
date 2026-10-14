import Base

type Vec is Data:
  Vec{x: F32, y: F32, z: F32}

type Box is Data:
  Box{low: Vec, high: Vec, material: U32}

def build(boxes: List<&2, Box>) -> List<&2, Box>:
  boxes

def Vec.add(a: Vec, b: Vec) -> Vec:
  Vec{x, y, z} = a
  Vec{dx, dy, dz} = b
  Vec{(x + dx : F32), (y + dy : F32), (z + dz : F32)}
