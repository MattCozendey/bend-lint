# Eldergrove Faire -- saving and loading a park.
#
# A save is a list of words. Each encoder writes its value in front of the
# words that follow it (so no appends are needed), children before the tag
# that assembles them; the loader is a stack machine that reads one tagged
# record at a time and pushes what it builds. Every decode step consumes a
# fixed-size record, so loading a save is a structural walk over the words,
# and LAWS.bend can state (and PROOF.bend prove) that loading a save gives
# back exactly the park that was saved.
import Base
import ./core.bend as C

type Item is Data:
  IQ{q: C.Q}
  IG{gs: List<&2, C.Guest>}
  IR{rs: List<&2, C.Ride>}
  IP{ps: List<&2, C.Piece>}
  IS{ss: List<&2, C.Slot>}
  IT{ts: List<&2, C.Track>}
  IK{p: C.Park}
  IW{ws: List<&2, U32>}
  IF{f: C.Fin}
  IStf{ss: List<&2, C.Staff>}
  IBad{}

def b2u(b: Bool) -> U32:
  match b:
    case True{}:
      1
    case False{}:
      0

def u2b(w: U32) -> Bool:
  U32.is_eq(w, 1)

# Encoders: enc(x, rest) = the words of x, then rest
# ---------------------------------------------------

def Enc.q(q: C.Q, rest: List<&2, U32>) -> List<&2, U32>:
  match q:
    case C.QL{t}:
      C.Tile{h, ter, obj, a, b} = t
      1 <> h <> ter <> obj <> a <> b <> rest
    case C.QN{a, b, c, d}:
      Enc.q(a, Enc.q(b, Enc.q(c, Enc.q(d, 2 <> rest))))

def Enc.guest(g: C.Guest, rest: List<&2, U32>) -> List<&2, U32>:
  C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} = g
  4 <> id <> x <> y <> dir <> st <> tgt <> tmr <> cash <> hu <> th <> en <> na
    <> ha <> lk <> mind <> bl <> rest

def Enc.gs(gs: List<&2, C.Guest>, rest: List<&2, U32>) -> List<&2, U32>:
  match gs:
    case []:
      3 <> rest
    case g <> more:
      Enc.gs(more, Enc.guest(g, rest))

def Enc.ride(r: C.Ride, rest: List<&2, U32>) -> List<&2, U32>:
  C.Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} = r
  6 <> kind <> x <> y <> w <> h <> price <> open <> ph <> tm <> ent <> ex <> qlen <> wmin <> wmax <> total <> earned <> born <> rate <> wear <> rest

def Enc.rs(rs: List<&2, C.Ride>, rest: List<&2, U32>) -> List<&2, U32>:
  match rs:
    case []:
      5 <> rest
    case r <> more:
      Enc.rs(more, Enc.ride(r, rest))

def Enc.piece(p: C.Piece, rest: List<&2, U32>) -> List<&2, U32>:
  C.Piece{x, y, z, kind, dir} = p
  8 <> x <> y <> z <> kind <> dir <> rest

def Enc.ps(ps: List<&2, C.Piece>, rest: List<&2, U32>) -> List<&2, U32>:
  match ps:
    case []:
      7 <> rest
    case p <> more:
      Enc.ps(more, Enc.piece(p, rest))

def Enc.slot(s: C.Slot, rest: List<&2, U32>) -> List<&2, U32>:
  match s:
    case C.Free{a, n, st}:
      10 <> a <> n <> st <> rest
    case C.Held{a, n, st, t}:
      C.Train{id, prog, speed, wait} = t
      11 <> a <> n <> st <> id <> prog <> speed <> wait <> rest

def Enc.ss(ss: List<&2, C.Slot>, rest: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case []:
      9 <> rest
    case s <> more:
      Enc.ss(more, Enc.slot(s, rest))

def Enc.track(t: C.Track, rest: List<&2, U32>) -> List<&2, U32>:
  C.Track{ps, open, ss, s, e, cfg, stats} = t
  C.Pose{sx, sy, sz, sd} = s
  C.Pose{ex, ey, ez, ed} = e
  Enc.ps(ps, Enc.ss(ss, 12 <> b2u(open) <> sx <> sy <> sz <> sd <> ex <> ey
    <> ez <> ed <> cfg <> stats <> rest))

def Enc.tks(ts: List<&2, C.Track>, rest: List<&2, U32>) -> List<&2, U32>:
  match ts:
    case []:
      21 <> rest
    case t <> more:
      Enc.tks(more, Enc.track(t, rest))

def Enc.ws(ws: List<&2, U32>, rest: List<&2, U32>) -> List<&2, U32>:
  match ws:
    case []:
      15 <> rest
    case w <> more:
      Enc.ws(more, 16 <> w <> rest)

def Enc.fin(f: C.Fin, rest: List<&2, U32>) -> List<&2, U32>:
  C.Fin{fee, loan, rating, now, last, hist, res} = f
  Enc.ws(now, Enc.ws(last, Enc.ws(hist, 14 <> fee <> loan <> rating <> res <> rest)))

def Enc.staff1(s: C.Staff, rest: List<&2, U32>) -> List<&2, U32>:
  C.Staff{id, x, y, dir, kind, st, tgt, tmr, zone, look} = s
  18 <> id <> x <> y <> dir <> kind <> st <> tgt <> tmr <> zone <> look <> rest

def Enc.stf(ss: List<&2, C.Staff>, rest: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case []:
      17 <> rest
    case s <> more:
      Enc.stf(more, Enc.staff1(s, rest))

def Enc.park(p: C.Park, rest: List<&2, U32>) -> List<&2, U32>:
  C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff} = p
  Enc.q(map, Enc.gs(guests, Enc.rs(rides, Enc.tks(track, Enc.fin(fin, Enc.ws(mess, Enc.stf(staff,
    13 <> cash <> time <> nid <> rest)))))))

def save(p: C.Park) -> List<&2, U32>:
  Enc.park(p, [])

# The loader: pops what a tag assembles
# -------------------------------------

def Pop.qn(st: List<&2, Item>) -> List<&2, Item>:
  match st:
    case IQ{d} <> IQ{c} <> IQ{b} <> IQ{a} <> more:
      IQ{C.QN{a, b, c, d}} <> more
    case _:
      [IBad{}]

def Pop.g(g: C.Guest, st: List<&2, Item>) -> List<&2, Item>:
  match st:
    case IG{gs} <> more:
      IG{g <> gs} <> more
    case _:
      [IBad{}]

def Pop.r(r: C.Ride, st: List<&2, Item>) -> List<&2, Item>:
  match st:
    case IR{rs} <> more:
      IR{r <> rs} <> more
    case _:
      [IBad{}]

def Pop.p(p: C.Piece, st: List<&2, Item>) -> List<&2, Item>:
  match st:
    case IP{ps} <> more:
      IP{p <> ps} <> more
    case _:
      [IBad{}]

def Pop.s(s: C.Slot, st: List<&2, Item>) -> List<&2, Item>:
  match st:
    case IS{ss} <> more:
      IS{s <> ss} <> more
    case _:
      [IBad{}]

def Pop.track(o: Bool, s: C.Pose, e: C.Pose, cfg: U32, stats: U32, st: List<&2, Item>)
  -> List<&2, Item>:
  match st:
    case IS{ss} <> IP{ps} <> IT{ts} <> more:
      IT{C.Track{ps, o, ss, s, e, cfg, stats} <> ts} <> more
    case _:
      [IBad{}]

def Pop.w(w: U32, st: List<&2, Item>) -> List<&2, Item>:
  match st:
    case IW{ws} <> more:
      IW{w <> ws} <> more
    case _:
      [IBad{}]

def Pop.fin(fee: U32, loan: U32, rating: U32, res: U32, st: List<&2, Item>) -> List<&2, Item>:
  match st:
    case IW{hist} <> IW{last} <> IW{now} <> more:
      IF{C.Fin{fee, loan, rating, now, last, hist, res}} <> more
    case _:
      [IBad{}]

def Pop.stf(s: C.Staff, st: List<&2, Item>) -> List<&2, Item>:
  match st:
    case IStf{ss} <> more:
      IStf{s <> ss} <> more
    case _:
      [IBad{}]

def Pop.park(cash: U32, time: U32, nid: U32, st: List<&2, Item>)
  -> List<&2, Item>:
  match st:
    case IStf{ss} <> IW{ms} <> IF{f} <> IT{t} <> IR{rs} <> IG{gs} <> IQ{q} <> more:
      IK{C.Park{q, gs, rs, t, cash, time, nid, f, ms, ss}} <> more
    case _:
      [IBad{}]

def dec(ws: List<&2, U32>, st: List<&2, Item>) -> List<&2, Item>:
  match ws:
    case []:
      st
    case 1 <> h <> ter <> obj <> a <> b <> rest:
      dec(rest, IQ{C.QL{C.Tile{h, ter, obj, a, b}}} <> st)
    case 2 <> rest:
      dec(rest, Pop.qn(st))
    case 3 <> rest:
      dec(rest, IG{[]} <> st)
    case 21 <> rest:
      dec(rest, IT{[]} <> st)
    case 4 <> id <> x <> y <> dir <> s <> tgt <> tmr <> cash <> hu <> th <> en
      <> na <> ha <> lk <> mind <> bl <> rest:
      dec(rest, Pop.g(C.Guest{id, x, y, dir, s, tgt, tmr, cash, hu, th, en, na,
        ha, lk, mind, bl}, st))
    case 5 <> rest:
      dec(rest, IR{[]} <> st)
    case 6 <> kind <> x <> y <> w <> h <> price <> open <> ph <> tm <> ent <> ex <> qlen <> wmin <> wmax <> total <> earned <> born <> rate <> wear <> rest:
      dec(rest, Pop.r(C.Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear}, st))
    case 7 <> rest:
      dec(rest, IP{[]} <> st)
    case 8 <> x <> y <> z <> kind <> dir <> rest:
      dec(rest, Pop.p(C.Piece{x, y, z, kind, dir}, st))
    case 9 <> rest:
      dec(rest, IS{[]} <> st)
    case 10 <> a <> n <> s <> rest:
      dec(rest, Pop.s(C.Free{a, n, s}, st))
    case 11 <> a <> n <> s <> id <> prog <> speed <> wait <> rest:
      dec(rest, Pop.s(C.Held{a, n, s, C.Train{id, prog, speed, wait}}, st))
    case 12 <> o <> sx <> sy <> sz <> sd <> ex <> ey <> ez <> ed <> cfg <> stats <> rest:
      dec(rest, Pop.track(u2b(o), C.Pose{sx, sy, sz, sd}, C.Pose{ex, ey, ez, ed}, cfg, stats,
        st))
    case 13 <> cash <> time <> nid <> rest:
      dec(rest, Pop.park(cash, time, nid, st))
    case 14 <> fee <> loan <> rating <> res <> rest:
      dec(rest, Pop.fin(fee, loan, rating, res, st))
    case 15 <> rest:
      dec(rest, IW{[]} <> st)
    case 16 <> w <> rest:
      dec(rest, Pop.w(w, st))
    case 17 <> rest:
      dec(rest, IStf{[]} <> st)
    case 18 <> f0 <> f1 <> f2 <> f3 <> f4 <> f5 <> f6 <> f7 <> f8 <> f9 <> rest:
      dec(rest, Pop.stf(C.Staff{f0, f1, f2, f3, f4, f5, f6, f7, f8, f9}, st))
    case _:
      [IBad{}]

def Load.fin(st: List<&2, Item>) -> Maybe<&2, C.Park>:
  match st:
    case [IK{p}]:
      Some{p}
    case _:
      None{}

def load(ws: List<&2, U32>) -> Maybe<&2, C.Park>:
  Load.fin(dec(ws, []))

# Bytes on disk: a magic word, then each word little-endian
# ---------------------------------------------------------

def MAGIC() -> U32:
  910313292

def to_bytes(ws: List<&2, U32>) -> List<&2, U32>:
  match ws:
    case []:
      []
    case +w <> rest:
      (w .&. 255 : U32) <> ((w >> 8n) .&. 255 : U32) <> ((w >> 16n) .&. 255 : U32)
        <> (w >> 24n : U32) <> to_bytes(rest)

def of_bytes(bs: List<&2, U32>) -> List<&2, U32>:
  match bs:
    case a <> b <> c <> d <> rest:
      (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32) <> of_bytes(rest)
    case _:
      []

def Save.file(p: C.Park) -> List<&2, U32>:
  to_bytes(MAGIC() <> save(p))

def Load.words(ws: List<&2, U32>) -> Maybe<&2, C.Park>:
  match ws:
    case +m <> rest:
      Bool.pick(Maybe<&2, C.Park>, U32.is_eq(m, MAGIC()), load(rest), None{})
    case _:
      None{}

def Load.file(bs: List<&2, U32>) -> Maybe<&2, C.Park>:
  Load.words(of_bytes(bs))
