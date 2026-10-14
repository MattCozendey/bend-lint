# Nuked OPL3 1.8 as Chocolate Doom 3.1.1 ships it (opl/opl3.c), cut to
# what DMX drives in OPL2 mode: the nine two-operator channels of the low
# register array and waveforms 0 to 3. The high array, four-operator
# channels, rhythm mode and OPL3 stereo stay silent there and are left
# out; so is register 0xBD, whose only write, 0, leaves the chip as reset
# leaves it. Signed values are two's complement U32.
import Base
import ./vec.bend as V
import ./fixed.bend as F
import ./opl_tables.bend as T

type Opl.Roms is Data:
  Roms{logsin: V.Vec, exp: V.Vec}

def Opl.roms() -> Opl.Roms:
  Roms{V.Vec.of_list(T.OplTables.logsin(), 256), V.Vec.of_list(T.OplTables.exp(), 256)}

# An operator: its output and the one before, the envelope's level and
# stage (gen: attack 0, decay 1, sustain 2, release 3), its registers,
# mt the frequency multiple (mt[reg_mult]), lvl the attenuation of tl and
# key scaling (reg_tl << 2 plus eg_ksl >> kslshift[reg_ksl]), and the
# phase accumulator.
type Opl.Slot is Data:
  Slot{out: U32, prout: U32, rout: U32, gen: U32, key: U32, am: U32, vib: U32, egt: U32,
    ksr: U32, mt: U32, ksl: U32, tl: U32, lvl: U32, ar: U32, dr: U32, sl: U32, rr: U32,
    wf: U32, phase: U32}

# A channel: its modulator m and carrier c; con 1 adds them, 0 has m
# modulate c.
type Opl.Chan is Data:
  Chan{fnum: U32, block: U32, ksv: U32, fb: U32, con: U32, m: Opl.Slot, c: Opl.Slot}

# The chip: the channels, the sample counter, the envelope clock, the
# tremolo and vibrato positions, note select, and the right side mixed
# last sample, which OPL3_Generate hands out this one.
type Opl.Core is Data:
  Core{chans: List<&2, Opl.Chan>, timer: U32, egtimer: U32, egstate: U32, egadd: U32,
    trempos: U32, vibpos: U32, nts: U32, mix: U32}

type Opl.Write is Data:
  Write{reg: U32, val: U32}

# A write waiting in OPL3_WriteRegBuffered's buffer until the chip sample
# it is due after.
type Opl.Pending is Data:
  Pending{time: U32, write: Opl.Write}

# The chip with its write buffer (count is writebuf_samplecnt, last is
# writebuf_lasttime) and OPL3_GenerateResampled's state: rcnt is
# samplecnt, and the two frames it interpolates between.
type Opl is Data:
  Opl{core: Opl.Core, count: U32, last: U32, pending: List<&2, Opl.Pending>, rcnt: U32,
    oldl: U32, oldr: U32, curl: U32, curr: U32}

# The chip's timers and modulation as every operator reads them in a
# sample.
type Opl.Clock is Data:
  Clock{egadd: U32, egstate: U32, timer: U32, trem: U32, vibpos: U32}

def Opl.at(+xs: List<&2, U32>, +i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, U32.to_nat(i)), 0)

def Opl.mt(+mult: U32) -> U32:
  Opl.at([1, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 20, 24, 24, 30, 30], mult)

def Opl.eg_ksl(+fnum: U32, +block: U32) -> U32:
  +k = (Opl.at([0, 32, 40, 45, 48, 51, 53, 55, 56, 58, 59, 60, 61, 62, 63, 64], (fnum >> 6n : U32)) << 2n : U32)
  +d = ((8 - block : U32) << 5n : U32)
  Bool.pick(U32, U32.is_ge(k, d), (k - d : U32), 0)

# kslshift is {8, 1, 2, 0}.
def Opl.lvl(+tl: U32, +ksl: U32, +fnum: U32, +block: U32) -> U32:
  ((tl << 2n) + U32.shrn(Opl.eg_ksl(fnum, block), U32.to_nat(Opl.at([8, 1, 2, 0], ksl))) : U32)

# Envelope generator
# ------------------

def Opl.reg_rate(reset: Bool, +gen: U32, +egt: U32, +ar: U32, +dr: U32, +rr: U32) -> U32:
  match reset:
    case True{}:
      ar
    case False{}:
      Bool.pick(U32, U32.is_eq(gen, 0), ar, Bool.pick(U32, U32.is_eq(gen, 1), dr,
        Bool.pick(U32, U32.is_eq(gen, 2), Bool.pick(U32, U32.is_eq(egt, 0), rr, 0), rr)))

def Opl.shift.low(+es: U32, +lo: U32) -> U32:
  Bool.pick(U32, U32.is_eq(es, 12), 1, Bool.pick(U32, U32.is_eq(es, 13), ((lo >> 1n) .&. 1 : U32),
    Bool.pick(U32, U32.is_eq(es, 14), (lo .&. 1 : U32), 0)))

# eg_incstep[lo][timer & 3] is bit (timer & 3) of nibble lo of 0x7510.
def Opl.shift.high(+hi: U32, +lo: U32, +timer: U32, +egstate: U32) -> U32:
  +s = ((hi .&. 3) + (U32.shrn(29968, U32.to_nat(((lo << 2n) + (timer .&. 3) : U32))) .&. 1) : U32)
  +t = Bool.pick(U32, U32.is_ge(s, 4), 3, s)
  Bool.pick(U32, U32.is_eq(t, 0), egstate, t)

def Opl.shift(nonzero: Bool, +hi: U32, +lo: U32, +clock: Opl.Clock) -> U32:
  match nonzero:
    case False{}:
      0
    case True{}:
      Clock{+egadd, +egstate, +timer, trem, vibpos} = clock
      Bool.pick(U32, U32.is_lt(hi, 12),
        Bool.pick(U32, U32.is_eq(egstate, 1), Opl.shift.low((hi + egadd : U32), lo), 0),
        Opl.shift.high(hi, lo, timer, egstate))

def Opl.step1(+shift: U32) -> U32:
  Bool.pick(U32, U32.is_eq(shift, 0), 0, U32.shln(1, U32.to_nat((shift - 1 : U32))))

def Opl.inc(+gen: U32, +rout: U32, +key: U32, +sl: U32, +shift: U32, +hi: U32, +quiet: Bool) ->
  U32:
  Bool.pick(U32, U32.is_eq(gen, 0),
    Bool.pick(U32, U32.is_ne(rout, 0) && U32.is_eq(key, 1) && U32.is_ne(shift, 0) && U32.is_ne(hi, 15),
      (U32.shln(U32.not(rout), U32.to_nat(shift)) >> 4n : U32), 0),
    Bool.pick(U32, quiet || (U32.is_eq(gen, 1) && U32.is_eq((rout >> 4n : U32), sl)), 0,
      Opl.step1(shift)))

def Opl.gen(+reset: Bool, +gen: U32, +rout: U32, +key: U32, +sl: U32) -> U32:
  Bool.pick(U32, U32.is_eq(key, 0), 3, Bool.pick(U32, reset, 0,
    Bool.pick(U32, U32.is_eq(gen, 0), Bool.pick(U32, U32.is_eq(rout, 0), 1, 0),
      Bool.pick(U32, U32.is_eq(gen, 1), Bool.pick(U32, U32.is_eq((rout >> 4n : U32), sl), 2, 1),
        gen))))

# Phase generator and waveforms
# -----------------------------

def Opl.vibrange(+fnum: U32, +vibpos: U32) -> U32:
  +r = ((fnum >> 7n) .&. 7 : U32)
  +v = (Bool.pick(U32, U32.is_eq((vibpos .&. 3 : U32), 0), 0,
    Bool.pick(U32, U32.is_eq((vibpos .&. 1 : U32), 1), (r >> 1n : U32), r)) >> 1n : U32)
  Bool.pick(U32, U32.is_eq((vibpos .&. 4 : U32), 4), (0 - v : U32), v)

def Opl.basefreq(+fnum: U32, +block: U32, +vib: U32, +vibpos: U32) -> U32:
  (U32.shln(Bool.pick(U32, U32.is_eq(vib, 1), (fnum + Opl.vibrange(fnum, vibpos) : U32), fnum),
    U32.to_nat(block)) >> 1n : U32)

def Opl.exp(+roms: Opl.Roms, +level: U32) -> U32:
  Roms{logsin, +exp} = roms
  +l = Bool.pick(U32, U32.is_gt(level, 8191), 8191, level)
  U32.shrn((V.Vec.get(exp, (l .&. 255 : U32)) << 1n : U32), U32.to_nat((l >> 8n : U32)))

# The quarter wave's index: mirrored in the second quarter, except in
# waveform 3, whose second quarter is silent.
def Opl.index(+wf: U32, +p: U32) -> U32:
  Bool.pick(U32, U32.is_ne(wf, 3) && U32.is_eq((p .&. 256 : U32), 256),
    ((p .&. 255) .^. 255 : U32), (p .&. 255 : U32))

def Opl.wave(+roms: Opl.Roms, +wf: U32, +p: U32, +env: U32) -> U32:
  Roms{+logsin, exp} = roms
  +x = Opl.exp(roms, (V.Vec.get(logsin, Opl.index(wf, p)) + (env << 3n) : U32))
  +half = U32.is_eq((p .&. 512 : U32), 512)
  Bool.pick(U32, U32.is_eq(wf, 0), Bool.pick(U32, half, U32.not(x), x),
    Bool.pick(U32, U32.is_eq(wf, 1), Bool.pick(U32, half, 0, x),
      Bool.pick(U32, U32.is_eq(wf, 2), x, Bool.pick(U32, U32.is_eq((p .&. 256 : U32), 256), 0, x))))

# Operators and channels
# ----------------------

def Opl.tremolo(+pos: U32) -> U32:
  Bool.pick(U32, U32.is_lt(pos, 105), (pos >> 4n : U32), ((210 - pos : U32) >> 4n : U32))

# One operator's sample: OPL3_EnvelopeCalc, OPL3_PhaseGenerate and
# OPL3_SlotGenerate, pm being the phase modulation its channel feeds it.
def Opl.Slot.step(+roms: Opl.Roms, +clock: Opl.Clock, +fnum: U32, +block: U32, +ksv: U32, pm: U32,
  s: Opl.Slot) -> Opl.Slot:
  Clock{egadd, egstate, timer, trem, vibpos} = clock
  Slot{out, prout, +rout, +gen, +key, +am, +vib, +egt, +ksr, +mt, ksl, tl, +lvl, +ar, +dr, +sl, +rr,
    +wf, +phase} = s
  +reset = U32.is_eq(key, 1) && U32.is_eq(gen, 3)
  +reg = Opl.reg_rate(reset, gen, egt, ar, dr, rr)
  +rate = (Bool.pick(U32, U32.is_eq(ksr, 1), ksv, (ksv >> 2n : U32)) + (reg << 2n) : U32)
  +hi = Bool.pick(U32, U32.is_gt((rate >> 2n : U32), 15), 15, (rate >> 2n : U32))
  +shift = Opl.shift(U32.is_ne(reg, 0), hi, (rate .&. 3 : U32), clock)
  +off = U32.is_eq((rout .&. 504 : U32), 504)
  +start = Bool.pick(U32, reset && U32.is_eq(hi, 15), 0,
    Bool.pick(U32, U32.is_ne(gen, 0) && Bool.not(reset) && off, 511, rout))
  Slot{Opl.wave(roms, wf, ((phase >> 9n) + pm .&. 1023 : U32), (rout + lvl + (am * trem) : U32)),
    out, ((start + Opl.inc(gen, rout, key, sl, shift, hi, off || reset)) .&. 511 : U32),
    Opl.gen(reset, gen, rout, key, sl), key, am, vib, egt, ksr, mt, ksl, tl, lvl, ar, dr, sl, rr, wf,
    (Bool.pick(U32, reset, 0, phase) + ((Opl.basefreq(fnum, block, vib, vibpos) * mt) >> 1n) : U32)}

def Opl.out(+s: Opl.Slot) -> U32:
  Slot{out, prout, rout, gen, key, am, vib, egt, ksr, mt, ksl, tl, lvl, ar, dr, sl, rr, wf, phase} = s
  out

# OPL3_SlotCalcFB. Only the low ten bits reach a waveform, so the shift
# needs no sign.
def Opl.fbmod(+fb: U32, +s: Opl.Slot) -> U32:
  Slot{+out, prout, rout, gen, key, am, vib, egt, ksr, mt, ksl, tl, lvl, ar, dr, sl, rr, wf, phase} = s
  Bool.pick(U32, U32.is_eq(fb, 0), 0, U32.shrn((prout + out : U32), U32.to_nat((9 - fb : U32))))

def Opl.accm(+con: U32, +m: U32, +c: U32) -> U32:
  Bool.pick(U32, U32.is_eq(con, 1), (m + c : U32), c)

# A channel's sample and its share of both mixes. OPL3_Generate mixes the
# left after slots 0 to 14 and before 15 to 17, the carriers of channels
# 6 to 8, so a late channel's left takes its carrier's last output.
type Opl.Out is Data:
  Out{chan: Opl.Chan, l: U32, r: U32}

def Opl.Chan.step(+roms: Opl.Roms, +clock: Opl.Clock, +late: Bool, ch: Opl.Chan) -> Opl.Out:
  Chan{+fnum, +block, +ksv, +fb, +con, +m, +c} = ch
  +m2 = Opl.Slot.step(roms, clock, fnum, block, ksv, Opl.fbmod(fb, m), m)
  +c2 = Opl.Slot.step(roms, clock, fnum, block, ksv, Bool.pick(U32, U32.is_eq(con, 1), 0, Opl.out(m2)), c)
  +r = Opl.accm(con, Opl.out(m2), Opl.out(c2))
  Out{Chan{fnum, block, ksv, fb, con, m2, c2},
    Bool.pick(U32, late, Opl.accm(con, Opl.out(m2), Opl.out(c)), r), r}

type Opl.Mixed is Data:
  Mixed{chans: List<&2, Opl.Chan>, l: U32, r: U32}

def Opl.mix.cons(o: Opl.Out, rest: Opl.Mixed) -> Opl.Mixed:
  Out{ch, l, r} = o
  Mixed{cs, ml, mr} = rest
  Mixed{ch <> cs, (l + ml : U32), (r + mr : U32)}

def Opl.mix(chans: List<&2, Opl.Chan>, +roms: Opl.Roms, +clock: Opl.Clock, +i: U32) -> Opl.Mixed:
  match chans:
    case []:
      Mixed{[], 0, 0}
    case ch <> rest:
      Opl.mix.cons(Opl.Chan.step(roms, clock, U32.is_ge(i, 6), ch), Opl.mix(rest, roms, clock, (i + 1 : U32)))

def Opl.clip(+x: U32) -> U32:
  Bool.pick(U32, F.Fixed.gt(x, 32767), 32767, Bool.pick(U32, F.Fixed.lt(x, 4294934528), 4294934528, x))

# The envelope clock's step for the next sample: one more than the index
# of eg_timer's lowest set bit, 0 past bit 12 or when it is zero.
def Opl.egadd.go(n: Nat, set: Bool, +x: U32, +i: U32) -> U32:
  match n set:
    case 0n _:
      0
    case 1n+m True{}:
      (i + 1 : U32)
    case 1n+m False{}:
      Opl.egadd.go(m, U32.is_eq((U32.shrn(x, U32.to_nat((i + 1 : U32))) .&. 1 : U32), 1), x, (i + 1 : U32))

def Opl.egadd(+x: U32) -> U32:
  Opl.egadd.go(13n, U32.is_eq((x .&. 1 : U32), 1), x, 0)

# OPL3_Generate: this sample's left and the last one's right.
type Opl.Sample is Data:
  Sample{core: Opl.Core, l: U32, r: U32}

def Opl.generate.fin(+timer: U32, +egtimer: U32, +egstate: U32, +trempos: U32, +vibpos: U32,
  nts: U32, mix: U32, m: Opl.Mixed) -> Opl.Sample:
  Mixed{chans, l, r} = m
  Sample{Core{chans, (timer + 1 : U32), (egtimer + egstate : U32), (egstate .^. 1 : U32),
    Opl.egadd(egtimer),
    Bool.pick(U32, U32.is_eq((timer .&. 63 : U32), 63), ((trempos + 1) % 210 : U32), trempos),
    Bool.pick(U32, U32.is_eq((timer .&. 1023 : U32), 1023), ((vibpos + 1) .&. 7 : U32), vibpos),
    nts, r}, Opl.clip(l), Opl.clip(mix)}

def Opl.generate(+roms: Opl.Roms, core: Opl.Core) -> Opl.Sample:
  Core{chans, +timer, +egtimer, +egstate, egadd, +trempos, +vibpos, nts, mix} = core
  Opl.generate.fin(timer, egtimer, egstate, trempos, vibpos, nts, mix,
    Opl.mix(chans, roms, Clock{egadd, egstate, timer, Opl.tremolo(trempos), vibpos}, 0))

# Register writes
# ---------------

# The operator registers a slot write reaches, by reg >> 5: 1 is 0x20,
# 2 is 0x40, 3 is 0x60, 4 is 0x80 and 7 is 0xE0.
def Opl.Slot.write(+reg: U32, +val: U32, +fnum: U32, +block: U32, s: Opl.Slot) -> Opl.Slot:
  Slot{out, prout, rout, gen, key, +am, +vib, +egt, +ksr, +mt, +ksl, +tl, +lvl, +ar, +dr, +sl, +rr, +wf,
    phase} = s
  +k = (reg >> 5n : U32)
  +kslv = (val >> 6n : U32)
  +tlv = (val .&. 63 : U32)
  +hi = (val >> 4n : U32)
  +lo = (val .&. 15 : U32)
  Slot{out, prout, rout, gen, key,
    Bool.pick(U32, U32.is_eq(k, 1), ((val >> 7n) .&. 1 : U32), am),
    Bool.pick(U32, U32.is_eq(k, 1), ((val >> 6n) .&. 1 : U32), vib),
    Bool.pick(U32, U32.is_eq(k, 1), ((val >> 5n) .&. 1 : U32), egt),
    Bool.pick(U32, U32.is_eq(k, 1), (hi .&. 1 : U32), ksr),
    Bool.pick(U32, U32.is_eq(k, 1), Opl.mt(lo), mt),
    Bool.pick(U32, U32.is_eq(k, 2), kslv, ksl),
    Bool.pick(U32, U32.is_eq(k, 2), tlv, tl),
    Bool.pick(U32, U32.is_eq(k, 2), Opl.lvl(tlv, kslv, fnum, block), lvl),
    Bool.pick(U32, U32.is_eq(k, 3), hi, ar),
    Bool.pick(U32, U32.is_eq(k, 3), lo, dr),
    Bool.pick(U32, U32.is_eq(k, 4), Bool.pick(U32, U32.is_eq(hi, 15), 31, hi), sl),
    Bool.pick(U32, U32.is_eq(k, 4), lo, rr),
    Bool.pick(U32, U32.is_eq(k, 7), (val .&. 3 : U32), wf),
    phase}

# A new frequency and block: the key scale level follows, and a B0 write
# also keys the channel on or off.
def Opl.Slot.freq(+fnum: U32, +block: U32, +key: U32, s: Opl.Slot) -> Opl.Slot:
  Slot{out, prout, rout, gen, k, am, vib, egt, ksr, mt, +ksl, +tl, lvl, ar, dr, sl, rr, wf, phase} = s
  Slot{out, prout, rout, gen, key, am, vib, egt, ksr, mt, ksl, tl, Opl.lvl(tl, ksl, fnum, block), ar, dr,
    sl, rr, wf, phase}

def Opl.key(+s: Opl.Slot) -> U32:
  Slot{out, prout, rout, gen, key, am, vib, egt, ksr, mt, ksl, tl, lvl, ar, dr, sl, rr, wf, phase} = s
  key

def Opl.Chan.freq(+fnum: U32, +block: U32, +nts: U32, fb: U32, con: U32, km: U32, kc: U32,
  m: Opl.Slot, c: Opl.Slot) -> Opl.Chan:
  Chan{fnum, block, ((block << 1n) .|. (U32.shrn(fnum, U32.to_nat((9 - nts : U32))) .&. 1) : U32), fb,
    con, Opl.Slot.freq(fnum, block, km, m), Opl.Slot.freq(fnum, block, kc, c)}

# A write to one channel: A0, B0 and C0 are the channel's own, the rest
# its modulator's or, from the fourth slot of a group of six, its
# carrier's.
def Opl.Chan.write.go(a0: Bool, b0: Bool, c0: Bool, car: Bool, +reg: U32, +val: U32, +nts: U32,
  ch: Opl.Chan) -> Opl.Chan:
  match a0 b0 c0 car:
    case True{} _ _ _:
      Chan{+fnum, block, ksv, fb, con, +m, +c} = ch
      Opl.Chan.freq(((fnum .&. 768) .|. val : U32), block, nts, fb, con, Opl.key(m), Opl.key(c), m, c)
    case False{} True{} _ _:
      Chan{fnum, block, ksv, fb, con, m, c} = ch
      +on = ((val >> 5n) .&. 1 : U32)
      Opl.Chan.freq(((fnum .&. 255) .|. ((val .&. 3) << 8n) : U32), ((val >> 2n) .&. 7 : U32), nts,
        fb, con, on, on, m, c)
    case False{} False{} True{} _:
      Chan{fnum, block, ksv, fb, con, m, c} = ch
      Chan{fnum, block, ksv, ((val .&. 14) >> 1n : U32), (val .&. 1 : U32), m, c}
    case False{} False{} False{} True{}:
      Chan{+fnum, +block, ksv, fb, con, m, c} = ch
      Chan{fnum, block, ksv, fb, con, m, Opl.Slot.write(reg, val, fnum, block, c)}
    case False{} False{} False{} False{}:
      Chan{+fnum, +block, ksv, fb, con, m, c} = ch
      Chan{fnum, block, ksv, fb, con, Opl.Slot.write(reg, val, fnum, block, m), c}

def Opl.Chan.write(+reg: U32, +val: U32, +nts: U32, ch: Opl.Chan) -> Opl.Chan:
  +k = (reg >> 4n : U32)
  Opl.Chan.write.go(U32.is_eq(k, 10), U32.is_eq(k, 11), U32.is_eq(k, 12), U32.is_ge((reg .&. 7 : U32), 3),
    reg, val, nts, ch)

# The channel a register reaches, if any: OPL3_WriteReg's ad_slot and
# channel decoding for the low array.
def Opl.target(+reg: U32) -> Maybe<&2, U32>:
  +k = (reg >> 4n : U32)
  +r = (reg .&. 31 : U32)
  +slot = U32.is_lt(r, 22) && U32.is_lt((r .&. 7 : U32), 6)
  +chan = U32.is_ge(k, 10) && U32.is_le(k, 12) && U32.is_lt((reg .&. 15 : U32), 9)
  Bool.pick(Maybe<&2, U32>, (U32.is_ge(k, 2) && U32.is_le(k, 9)) || U32.is_ge(k, 14),
    Bool.pick(Maybe<&2, U32>, slot, Some{(((r >> 3n) * 3) + ((r .&. 7) % 3) : U32)}, None{}),
    Bool.pick(Maybe<&2, U32>, chan, Some{(reg .&. 15 : U32)}, None{}))

def Opl.write.at(chans: List<&2, Opl.Chan>, n: Nat, +reg: U32, +val: U32, +nts: U32) ->
  List<&2, Opl.Chan>:
  match chans n:
    case [] _:
      []
    case ch <> rest 0n:
      Opl.Chan.write(reg, val, nts, ch) <> rest
    case ch <> rest 1n+i:
      ch <> Opl.write.at(rest, i, reg, val, nts)

def Opl.write.to(chans: List<&2, Opl.Chan>, target: Maybe<&2, U32>, +reg: U32, +val: U32, +nts: U32) ->
  List<&2, Opl.Chan>:
  match target:
    case None{}:
      chans
    case Some{i}:
      Opl.write.at(chans, U32.to_nat(i), reg, val, nts)

# OPL3_WriteReg.
def Opl.write(core: Opl.Core, w: Opl.Write) -> Opl.Core:
  Core{chans, timer, egtimer, egstate, egadd, trempos, vibpos, +nts, mix} = core
  Write{+reg, +val} = w
  Core{Opl.write.to(chans, Opl.target(reg), reg, val, nts), timer, egtimer, egstate, egadd, trempos,
    vibpos, Bool.pick(U32, U32.is_eq(reg, 8), ((val >> 6n) .&. 1 : U32), nts), mix}

# The write buffer
# ----------------

def Opl.due(+count: U32, ws: List<&2, Opl.Pending>) -> Bool:
  match ws:
    case []:
      False{}
    case w <> rest:
      Pending{time, write} = w
      U32.is_le(time, count)

type Opl.Flushed is Data:
  Flushed{core: Opl.Core, pending: List<&2, Opl.Pending>}

def Opl.flush.one(core: Opl.Core, w: Opl.Pending) -> Opl.Core:
  Pending{time, write} = w
  Opl.write(core, write)

# The writes due by the sample just generated, applied in order.
def Opl.flush(pending: List<&2, Opl.Pending>, due: Bool, core: Opl.Core, +count: U32) -> Opl.Flushed:
  match pending due:
    case [] _:
      Flushed{core, []}
    case w <> rest False{}:
      Flushed{core, w <> rest}
    case w <> +rest True{}:
      Opl.flush(rest, Opl.due(count, rest), Opl.flush.one(core, w), count)

def Opl.stamp(ws: List<&2, Opl.Write>, +t: U32) -> List<&2, Opl.Pending>:
  match ws:
    case []:
      []
    case w <> rest:
      Pending{t, w} <> Opl.stamp(rest, (t + 2 : U32))

def Opl.pending(+o: Opl) -> List<&2, Opl.Pending>:
  Opl{core, count, last, pending, rcnt, oldl, oldr, curl, curr} = o
  pending

def Opl.spill.one(pending: List<&2, Opl.Pending>, o: Opl) -> Opl:
  match pending:
    case []:
      o
    case Pending{+time, write} <> rest:
      Opl{core, count, last, old, rcnt, oldl, oldr, curl, curr} = o
      Opl{Opl.write(core, write), time, last, rest, rcnt, oldl, oldr, curl, curr}

# The buffer holds 1024 writes. A write that finds it full has the
# oldest applied at once, and the sample count moves to that write's
# time (opl3.c:1344).
def Opl.spill(n: Nat, +o: Opl) -> Opl:
  match n:
    case 0n:
      o
    case 1n+m:
      Opl.spill(m, Opl.spill.one(Opl.pending(o), o))

# OPL3_WriteRegBuffered for writes made together: the first is due at the
# later of two samples after the last one queued and the sample about to
# be generated, each next two samples on. A spill moves the count no
# further than the last write queued, so it moves no write's time.
def Opl.queue(+ws: List<&2, Opl.Write>, o: Opl) -> Opl:
  Opl{core, +count, +last, pending, rcnt, oldl, oldr, curl, curr} = o
  +t = U32.max((last + 2 : U32), count)
  +n = U32.from_nat(List.length(&2, Opl.Write, ws))
  +all = List.append(&2, Opl.Pending, pending, Opl.stamp(ws, t))
  Opl.spill(U32.to_nat((U32.max(U32.from_nat(List.length(&2, Opl.Pending, all)), 1024) - 1024 : U32)),
    Opl{core, count, Bool.pick(U32, U32.is_eq(n, 0), last, (t + (n - 1) * 2 : U32)), all, rcnt, oldl, oldr, curl,
      curr})

# Resampling
# ----------

# OPL3_GenerateResampled's rateratio, 44100 << 10 over 49716.
def Opl.ratio() -> U32:
  908

def Opl.tick.done(+count: U32, last: U32, rcnt: U32, oldl: U32, oldr: U32, l: U32, r: U32,
  f: Opl.Flushed) -> Opl:
  Flushed{core, pending} = f
  Opl{core, (count + 1 : U32), last, pending, (rcnt - Opl.ratio() : U32), oldl, oldr, l, r}

def Opl.tick.fin(+count: U32, last: U32, +pending: List<&2, Opl.Pending>, rcnt: U32, oldl: U32,
  oldr: U32, s: Opl.Sample) -> Opl:
  Sample{core, l, r} = s
  Opl.tick.done(count, last, rcnt, oldl, oldr, l, r,
    Opl.flush(pending, Opl.due(count, pending), core, count))

# One chip sample, if the resampler is due one.
def Opl.tick(due: Bool, +roms: Opl.Roms, o: Opl) -> Opl:
  match due:
    case False{}:
      o
    case True{}:
      Opl{core, count, last, pending, rcnt, oldl, oldr, curl, curr} = o
      Opl.tick.fin(count, last, pending, rcnt, curl, curr, Opl.generate(roms, core))

def Opl.ready(+o: Opl) -> Bool:
  Opl{core, count, last, pending, rcnt, oldl, oldr, curl, curr} = o
  U32.is_ge(rcnt, Opl.ratio())

# C's signed division by the rate ratio, toward zero.
def Opl.lerp(+old: U32, +cur: U32, +rcnt: U32) -> U32:
  +x = ((old * (Opl.ratio() - rcnt)) + (cur * rcnt) : U32)
  Bool.pick(U32, F.Fixed.is_neg(x), (0 - ((0 - x) / Opl.ratio()) : U32), (x / Opl.ratio() : U32))

# An output frame: its left and right as 16-bit two's complement, left in
# the low half.
type Opl.Frame is Data:
  Frame{opl: Opl, lr: U32}

def Opl.frame.out(o: Opl) -> Opl.Frame:
  Opl{core, count, last, pending, +rcnt, +oldl, +oldr, +curl, +curr} = o
  Frame{Opl{core, count, last, pending, (rcnt + 1024 : U32), oldl, oldr, curl, curr},
    ((Opl.lerp(oldl, curl, rcnt) .&. 65535) .|. (Opl.lerp(oldr, curr, rcnt) << 16n) : U32)}

# OPL3_GenerateResampled: at most two chip samples a frame.
def Opl.frame(+roms: Opl.Roms, +o: Opl) -> Opl.Frame:
  +o1 = Opl.tick(Opl.ready(o), roms, o)
  +o2 = Opl.tick(Opl.ready(o1), roms, o1)
  Opl.frame.out(o2)

type Opl.Frames is Data:
  Frames{opl: Opl, out: List<&2, U32>}

def Opl.frames.put(out: List<&2, U32>, f: Opl.Frame) -> Opl.Frames:
  Frame{opl, lr} = f
  Frames{opl, lr <> out}

def Opl.frames.step(+roms: Opl.Roms, st: Opl.Frames) -> Opl.Frames:
  Frames{opl, out} = st
  Opl.frames.put(out, Opl.frame(roms, opl))

# n more frames, the latest first.
def Opl.frames(n: Nat, +roms: Opl.Roms, st: Opl.Frames) -> Opl.Frames:
  match n:
    case 0n:
      st
    case 1n+m:
      Opl.frames(m, roms, Opl.frames.step(roms, st))

def Opl.Slot.reset() -> Opl.Slot:
  Slot{0, 0, 511, 3, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0}

# OPL3_Reset.
def Opl.reset() -> Opl:
  Opl{Core{List.replicate(Opl.Chan, 9n, Chan{0, 0, 0, 0, 0, Opl.Slot.reset(), Opl.Slot.reset()}),
    0, 0, 0, 0, 0, 0, 0, 0}, 0, 0, [], 0, 0, 0, 0, 0}

def Opl.Frames.out(f: Opl.Frames) -> List<&2, U32>:
  Frames{opl, out} = f
  out

def Opl.Frames.clear(f: Opl.Frames) -> Opl.Frames:
  Frames{opl, out} = f
  Frames{opl, []}

def Opl.Frames.queue(+ws: List<&2, Opl.Write>, f: Opl.Frames) -> Opl.Frames:
  Frames{opl, out} = f
  Frames{Opl.queue(ws, opl), out}
