# Color: packing a shaded F32 triple into the U32 that Image stores.
import Base

def clamp01(+x: F32) -> F32:
  F32.clamp(x, 0.0, 1.0)

# One channel: clamp, scale to 0..255, round to nearest.  The round is the
# device's own conversion -- WebGL's float-to-unorm8 rounds, it does not
# truncate -- and truncating instead costs half a level on every channel of
# every pixel, which is a bias you can see in a difference map as a uniform
# darkening of the whole frame.
def ch(+x: F32) -> U32:
  F32.to_u32((255.0 * clamp01(x) + 0.5 : F32))

# Pack r,g,b into 0x00RRGGBB, the layout Image/Pix uses.
def pack(+r: F32, +g: F32, +b: F32) -> U32:
  U32.or(
    U32.shln(ch(r), 16n),
    U32.or(U32.shln(ch(g), 8n), ch(b)))

# ---- inspect ---------------------------------------------------------

def red(+c: U32) -> U32:
  U32.and(U32.shrn(c, 16n), 255)

def green(+c: U32) -> U32:
  U32.and(U32.shrn(c, 8n), 255)

def blue(+c: U32) -> U32:
  U32.and(c, 255)
