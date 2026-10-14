# A sound lump as Chocolate Doom 3.1.1 loads it (CacheSFX in
# src/i_sdlsound.c) and expands it to 44100 Hz (ExpandSoundData_SDL).
# At 11025, 22050 and 44100 Hz, the rates ConvertibleRatio lets through,
# the expansion is SDL's converter, which in the nixpkgs build is
# sdl2-compat handing the whole sound to an SDL 3.4.14 audio stream:
# unsigned bytes made floats, resampled as mono by twelve taps around
# each source sample (ResampleFrame_Generic_SSE), doubled to stereo and
# made 16-bit. Both sides of Chocolate Doom's chunk hold the same
# sample, so the expansion here is mono. Any other rate takes Chocolate
# Doom's nearest-sample loop, which nothing E1M1 starts needs, so such a
# sound has no run.
import Base
import ./bytes.bend as B
import ./wad.bend as W
import ./sfx_taps.bend as T

# A lump's rate and the bytes Chocolate Doom plays, counted.
type Sfx.Sound is Data:
  Sound{rate: U32, count: U32, bytes: List<&2, U32>}

# An expansion under way: the taps of each frame a source sample makes,
# the source from five samples before the next one, and the source
# samples left.
type Sfx.Run is Data:
  Run{rows: List<&2, List<&2, F32>>, xs: List<&2, F32>, left: U32}

# The lump reader
# ---------------

# CacheSFX's checks on a lump of size bytes: format 3, and a length that
# fits after the 8-byte header and is over 48.
def Sfx.played(+size: U32, format: U32, +length: U32) -> Bool:
  U32.is_ge(size, 8) && U32.is_eq(format, 3) && U32.is_le(length, (size - 8 : U32)) && U32.is_gt(length, 48)

def Sfx.read.fin(rate: U32, count: U32, p: Array<U32> & List<&2, U32>) -> Array<U32> & Maybe<&2, Sfx.Sound>:
  (a, bytes) = p
  (a, Some{Sound{rate, count, bytes}})

# DMX skips the first 16 and the last 16 bytes of the length.
def Sfx.read.bytes(ok: Bool, a: Array<U32>, pos: U32, rate: U32, +length: U32) ->
  Array<U32> & Maybe<&2, Sfx.Sound>:
  match ok:
    case False{}:
      (a, None{})
    case True{}:
      Sfx.read.fin(rate, (length - 32 : U32), B.Bytes.list(a, (pos + 24 : U32), (length - 32 : U32)))

def Sfx.read.cut(+pos: U32, size: U32, format: U32, rate: U32, p: Array<U32> & U32) ->
  Array<U32> & Maybe<&2, Sfx.Sound>:
  (a, +length) = p
  Sfx.read.bytes(Sfx.played(size, format, length), a, pos, rate, length)

def Sfx.read.length(+pos: U32, size: U32, format: U32, p: Array<U32> & U32) ->
  Array<U32> & Maybe<&2, Sfx.Sound>:
  (a, rate) = p
  Sfx.read.cut(pos, size, format, rate, B.Bytes.u32(a, (pos + 4 : U32)))

def Sfx.read.rate(+pos: U32, size: U32, p: Array<U32> & U32) -> Array<U32> & Maybe<&2, Sfx.Sound>:
  (a, format) = p
  Sfx.read.length(pos, size, format, B.Bytes.u16(a, (pos + 2 : U32)))

def Sfx.read.at(a: Array<U32>, at: U32 & U32) -> Array<U32> & Maybe<&2, Sfx.Sound>:
  (+pos, size) = at
  Sfx.read.rate(pos, size, B.Bytes.u16(a, pos))

# The sound in the first lump called name, or none for a lump CacheSFX
# refuses; a missing lump has size 0, which it refuses.
def Sfx.read(a: Array<U32>, +lumps: List<&2, W.Wad.Lump>, +name: String) -> Array<U32> & Maybe<&2, Sfx.Sound>:
  Sfx.read.at(a, W.Wad.find(lumps, name))

# The expansion
# -------------

# SDL_Convert_U8_to_F32: (b - 128) / 128, exact.
def Sfx.float(b: U32) -> F32:
  ((U32.to_f32(b) - 128.0 : F32) / 128.0 : F32)

def Sfx.floats(bytes: List<&2, U32>, acc: List<&2, F32>) -> List<&2, F32>:
  match bytes:
    case []:
      List.reverse(&2, F32, acc)
    case b <> rest:
      Sfx.floats(rest, Sfx.float(b) <> acc)

# Each tap times its sample. Past the sound's end SDL pads with silence,
# whose products are zero.
def Sfx.mul(row: List<&2, F32>, xs: List<&2, F32>) -> List<&2, F32>:
  match row xs:
    case [] _:
      []
    case t <> tr Nil{}:
      0.0 <> Sfx.mul(tr, [])
    case t <> tr x <> xr:
      (t * x : F32) <> Sfx.mul(tr, xr)

# Twelve products added as ResampleFrame_Generic_SSE adds them: three
# vectors of four summed lane by lane, then lanes 0 and 1, lanes 2 and
# 3, and the two sums. libSDL3 holds no fused multiply-add.
def Sfx.sum(ps: List<&2, F32>) -> F32:
  match ps:
    case a0 <> a1 <> a2 <> a3 <> b0 <> b1 <> b2 <> b3 <> c0 <> c1 <> c2 <> c3 <> rest:
      ((((a0 + b0 : F32) + c0 : F32) + ((a1 + b1 : F32) + c1 : F32) : F32)
        + (((a2 + b2 : F32) + c2 : F32) + ((a3 + b3 : F32) + c3 : F32) : F32) : F32)
    case _:
      0.0

# SDL_Convert_F32_to_S16_SSE2: x + 257 rounds x to the nearest 1 / 32768,
# ties to even, and the result's bits less 256's are the sample plus
# 32768, which packs_epi32 clamps to 16 bits. The sample is returned as
# its 16 bits.
def Sfx.sample(x: F32) -> U32:
  (F32.to_u32(F32.clamp((((x + 257.0 : F32) - 256.0 : F32) * 32768.0 : F32), 0.0, 65535.0)) .^. 32768 : U32)

# The frames one source sample makes, before tail.
def Sfx.frames(rows: List<&2, List<&2, F32>>, +xs: List<&2, F32>, tail: List<&2, U32>) -> List<&2, U32>:
  match rows:
    case []:
      tail
    case row <> rest:
      Sfx.sample(Sfx.sum(Sfx.mul(row, xs))) <> Sfx.frames(rest, xs, tail)

def Sfx.piece(n: Nat, +rows: List<&2, List<&2, F32>>, xs: List<&2, F32>) -> List<&2, U32>:
  match n xs:
    case 0n _:
      []
    case 1n+m Nil{}:
      []
    case 1n+m +x <> +rest:
      Sfx.frames(rows, x <> rest, Sfx.piece(m, rows, rest))

# The source samples a piece covers: few enough that a piece's recursion
# is safe on the JS lane.
def Sfx.step(+left: U32) -> U32:
  U32.min(left, 1024)

# The pieces a run has left.
def Sfx.pieces(r: Sfx.Run) -> Nat:
  Run{rows, xs, left} = r
  U32.to_nat(((left + 1023) / 1024 : U32))

# The run's next piece: 16-bit samples at 44100 Hz, as many for each
# source sample as the run has rows.
def Sfx.out(r: Sfx.Run) -> List<&2, U32>:
  Run{rows, xs, left} = r
  Sfx.piece(U32.to_nat(Sfx.step(left)), rows, xs)

# The run past that piece.
def Sfx.next(r: Sfx.Run) -> Sfx.Run:
  Run{rows, xs, +left} = r
  Run{rows, List.drop(&2, F32, xs, U32.to_nat(Sfx.step(left))), (left - Sfx.step(left) : U32)}

# The resampler's phase advances by 8 * rate / 44100 a frame, and the
# table holds the even phases, so a frame's row is every rate / 11025th.
def Sfx.rows(rows: List<&2, List<&2, F32>>, +every: U32, +i: U32) -> List<&2, List<&2, F32>>:
  match rows:
    case []:
      []
    case row <> rest:
      List.filter.put(List<&2, F32>, row, Sfx.rows(rest, every, (i + 1 : U32)), U32.is_zero((i % every : U32)))

def Sfx.run.at(ok: Bool, rate: U32, count: U32, bytes: List<&2, U32>) -> Maybe<&2, Sfx.Run>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Some{Run{Sfx.rows(T.SfxTaps.rows(), (rate / 11025 : U32), 0),
        Sfx.floats(128 <> 128 <> 128 <> 128 <> 128 <> bytes, []), count}}

# A sound's expansion from its first sample, the five before it silence
# as SDL's history is, or none at a rate SDL's converter is not given.
def Sfx.run(s: Sfx.Sound) -> Maybe<&2, Sfx.Run>:
  Sound{+rate, count, bytes} = s
  Sfx.run.at(U32.is_eq(rate, 11025) || U32.is_eq(rate, 22050) || U32.is_eq(rate, 44100), rate, count, bytes)
