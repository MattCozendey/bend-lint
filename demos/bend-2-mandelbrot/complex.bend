import Base

# Double-single arithmetic: non-overlapping high/low F32 pairs.
type Wide is Data:
  DS{hi: F32, lo: F32}

def wide(+v: F32) -> Wide:
  DS{v, 0.0}

def add(a: Wide, b: Wide) -> Wide:
  DS{+ah, al} = a
  DS{+bh, bl} = b
  +s = (ah + bh : F32)
  +v = (s - ah : F32)
  +e = ((ah - (s - v)) + (bh - v) + al + bl : F32)
  +h = (s + e : F32)
  DS{h, (e - (h - s) : F32)}

def neg(a: Wide) -> Wide:
  DS{ah, al} = a
  DS{F32.neg(ah), F32.neg(al)}

def sub(a: Wide, b: Wide) -> Wide:
  add(a, neg(b))

def mul(a: Wide, b: Wide) -> Wide:
  DS{+ah, +al} = a
  DS{+bh, +bl} = b
  +p = (ah * bh : F32)
  +ca = (4097.0 * ah : F32)
  +cb = (4097.0 * bh : F32)
  +a1 = (ca - (ca - ah) : F32)
  +b1 = (cb - (cb - bh) : F32)
  +a2 = (ah - a1 : F32)
  +b2 = (bh - b1 : F32)
  +e = (((a1 * b1 - p) + a1 * b2 + a2 * b1) + a2 * b2 + ah * bl + al * bh : F32)
  +h = (p + e : F32)
  DS{h, (e - (h - p) : F32)}

def value(a: Wide) -> F32:
  DS{ah, al} = a
  (ah + al : F32)
