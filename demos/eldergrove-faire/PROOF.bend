# Eldergrove Faire -- the proofs of LAWS.bend.
import Base
import ./core.bend as C
import ./save.bend as S
import ./LAWS.bend as Laws

# Money: every branch of Park.step computes the ledger once and sets the
# gold to the ledger applied to it, so both sides compute to the same term.
# Proof kit
# ---------

# case analysis on any boolean, with the goal as a function of it
def bcase(+b: Bool, -P: Bool -> Type, t: P(True{}), f: P(False{})) -> P(b):
  match b:
    case True{}:
      t
    case False{}:
      f

# Nat arithmetic
def add_zero_r(+a: Nat) -> {Nat.add(a, 0n) == a : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_zero_r(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}

def add_succ_r(+a: Nat, +b: Nat) -> {Nat.add(a, 1n+b) == 1n+Nat.add(a, b) : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_succ_r(p, b) : {1n+Nat.add(p, 1n+b) == 1n+_ : Nat}
      {==}

def add_comm(+a: Nat, +b: Nat) -> {Nat.add(a, b) == Nat.add(b, a) : Nat}:
  match a:
    case 0n:
      %add_zero_r(b) : {_ == Nat.add(b, 0n) : Nat}
      {==}
    case 1n+p:
      %Equal.sym(Nat, Nat.add(b, 1n+p), 1n+Nat.add(b, p), add_succ_r(b, p))
        : {1n+Nat.add(p, b) == _ : Nat}
      %add_comm(p, b) : {1n+Nat.add(p, b) == 1n+_ : Nat}
      {==}

def add_assoc(+a: Nat, +b: Nat, +c: Nat)
  -> {Nat.add(Nat.add(a, b), c) == Nat.add(a, Nat.add(b, c)) : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_assoc(p, b, c) : {1n+Nat.add(Nat.add(p, b), c) == 1n+_ : Nat}
      {==}

def add_assoc_r(+a: Nat, +b: Nat, +c: Nat)
  -> {Nat.add(a, Nat.add(b, c)) == Nat.add(Nat.add(a, b), c) : Nat}:
  Equal.sym(Nat, Nat.add(Nat.add(a, b), c), Nat.add(a, Nat.add(b, c)),
    add_assoc(a, b, c))

# No collisions
# -------------
# A block holds at most one train by construction; these lemmas show each
# stage of Blocks.step keeps the number of trains: advancing trains inside
# their blocks, handing a train to the next block (a swap), the pass along
# the ring, and the ring's rotation.

def cnt_adv(+s: C.Slot, +ps: +List<C.Piece>, +cfg: U32)
  -> {C.Slot.count(C.Slot.adv(s, ps, cfg)) == C.Slot.count(s) : Nat}:
  match s:
    case C.Free{a, n, st}:
      {==}
    case C.Held{a, n, st, t}:
      {==}

def trains_adv(+xs: +List<C.Slot>, +ps: +List<C.Piece>, +cfg: U32)
  -> {C.Blocks.trains(C.Slots.adv(xs, ps, cfg)) == C.Blocks.trains(xs) : Nat}:
  match xs:
    case []:
      {==}
    case s <> rest:
      %cnt_adv(s, ps, cfg) : {Nat.add(C.Slot.count(C.Slot.adv(s, ps, cfg)), C.Blocks.trains(C.Slots.adv(rest, ps, cfg)))
        == Nat.add(_, C.Blocks.trains(rest)) : Nat}
      %trains_adv(rest, ps, cfg) : {Nat.add(C.Slot.count(C.Slot.adv(s, ps, cfg)), C.Blocks.trains(C.Slots.adv(rest, ps, cfg)))
        == Nat.add(C.Slot.count(C.Slot.adv(s, ps, cfg)), _) : Nat}
      {==}

def cnt_pair(+c: C.Slot, +b: C.Slot)
  -> {Nat.add(C.Slot.count(C.Slot.cfst(c, b)), C.Slot.count(C.Slot.csnd(c, b)))
    == Nat.add(C.Slot.count(c), C.Slot.count(b)) : Nat}:
  match c b:
    case C.Held{sa, na, ta, t} C.Free{sb, nb, tb}:
      bcase(C.Train.ready(t, na), r => {Nat.add(C.Slot.count(Bool.pick(C.Slot, r,
        C.Free{sa, na, ta}, C.Held{sa, na, ta, t})), C.Slot.count(Bool.pick(C.Slot, r,
        C.Held{sb, nb, tb, C.Train.enter(t, na, tb)}, C.Free{sb, nb, tb}))) == 1n : Nat},
        {==}, {==})
    case C.Held{sa, na, ta, t} C.Held{sb, nb, tb, u}:
      {==}
    case C.Free{sa, na, ta} C.Held{sb, nb, tb, u}:
      {==}
    case C.Free{sa, na, ta} C.Free{sb, nb, tb}:
      {==}

def trains_pass(+xs: +List<C.Slot>, +c: C.Slot)
  -> {C.Blocks.trains(C.Slots.pass(xs, c)) == Nat.add(C.Slot.count(c), C.Blocks.trains(xs)) : Nat}:
  match xs:
    case []:
      {==}
    case b <> rest:
      +cf = C.Slot.count(C.Slot.cfst(c, b))
      +cs = C.Slot.count(C.Slot.csnd(c, b))
      +r = C.Blocks.trains(rest)
      +lhs = C.Blocks.trains(C.Slots.pass(b <> rest, c))
      %add_assoc(C.Slot.count(c), C.Slot.count(b), r) : {lhs == _ : Nat}
      %cnt_pair(c, b) : {lhs == Nat.add(_, r) : Nat}
      %add_assoc_r(cf, cs, r) : {lhs == _ : Nat}
      %trains_pass(rest, C.Slot.csnd(c, b)) : {lhs == Nat.add(cf, _) : Nat}
      {==}

def trains_app(+xs: +List<C.Slot>, +ys: +List<C.Slot>)
  -> {C.Blocks.trains(List.append(&2, C.Slot, xs, ys))
    == Nat.add(C.Blocks.trains(xs), C.Blocks.trains(ys)) : Nat}:
  match xs:
    case []:
      {==}
    case s <> rest:
      +lhs = C.Blocks.trains(List.append(&2, C.Slot, s <> rest, ys))
      %add_assoc_r(C.Slot.count(s), C.Blocks.trains(rest), C.Blocks.trains(ys)) : {lhs == _ : Nat}
      %trains_app(rest, ys) : {lhs == Nat.add(C.Slot.count(s), _) : Nat}
      {==}

def trains_rot(+xs: +List<C.Slot>)
  -> {C.Blocks.trains(C.Slots.rot(xs)) == C.Blocks.trains(xs) : Nat}:
  match xs:
    case []:
      {==}
    case s <> rest:
      +lhs = C.Blocks.trains(C.Slots.rot(s <> rest))
      %add_comm(C.Blocks.trains(rest), C.Slot.count(s)) : {lhs == _ : Nat}
      %add_zero_r(C.Slot.count(s)) : {lhs == Nat.add(C.Blocks.trains(rest), _) : Nat}
      %trains_app(rest, [s]) : {lhs == _ : Nat}
      {==}

# Money
# -----

def Laws.money_conserved(p, a):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff}:
      match a:
        case C.Tick{}:
          {==}
        case C.Build{tool, x, y, v}:
          {==}
        case C.TrackOp{op}:
          {==}
        case C.RideOp{ride, op}:
          {==}
        case C.ParkOp{op}:
          {==}

# Headcount
# ---------
# A tick steps every guest (the list keeps its length), splits the stepped
# guests into those still here and those who just left (together, all of
# them), and puts the arrivals in front. Builds and track edits leave the
# guests alone.

def glen(gs: +List<C.Guest>) -> Nat:
  List.length(&2, C.Guest, gs)

def len_app(+xs: +List<C.Guest>, +ys: +List<C.Guest>)
  -> {glen(List.append(&2, C.Guest, xs, ys)) == Nat.add(glen(xs), glen(ys)) : Nat}:
  match xs:
    case []:
      {==}
    case x <> r:
      %len_app(r, ys) : {1n+glen(List.append(&2, C.Guest, r, ys)) == 1n+_ : Nat}
      {==}

def len_step(+g: +List<C.Guest>, +q: C.Q, +rs: +List<C.Ride>, +t: U32,
  +pl: +List<C.Board>, +sn: C.Stn, +qs: +List<U32>)
  -> {glen(C.Guests.step(g, q, rs, t, pl, sn, qs)) == glen(g) : Nat}:
  match g:
    case []:
      {==}
    case x <> r:
      %len_step(r, q, rs, t, pl, sn, qs) : {1n+glen(C.Guests.step(r, q, rs, t, pl, sn, qs)) == 1n+_ : Nat}
      {==}

def part_t(+r: +List<C.Guest>,
  ih: {Nat.add(glen(C.Guests.stay(r)), glen(C.Guests.left(r))) == glen(r) : Nat})
  -> {Nat.add(glen(C.Guests.stay(r)), 1n+glen(C.Guests.left(r))) == 1n+glen(r) : Nat}:
  +sl = Nat.add(glen(C.Guests.stay(r)), 1n+glen(C.Guests.left(r)))
  %ih : {sl == 1n+_ : Nat}
  %add_succ_r(glen(C.Guests.stay(r)), glen(C.Guests.left(r))) : {sl == _ : Nat}
  {==}

def part_f(+r: +List<C.Guest>,
  ih: {Nat.add(glen(C.Guests.stay(r)), glen(C.Guests.left(r))) == glen(r) : Nat})
  -> {Nat.add(1n+glen(C.Guests.stay(r)), glen(C.Guests.left(r))) == 1n+glen(r) : Nat}:
  %ih : {1n+Nat.add(glen(C.Guests.stay(r)), glen(C.Guests.left(r))) == 1n+_ : Nat}
  {==}

def part(+m: +List<C.Guest>)
  -> {Nat.add(glen(C.Guests.stay(m)), glen(C.Guests.left(m))) == glen(m) : Nat}:
  match m:
    case []:
      {==}
    case x <> r:
      bcase(C.Guest.gone(x), b => {Nat.add(glen(C.Guests.put(Bool.not(b), x, C.Guests.stay(r))),
        glen(C.Guests.put(b, x, C.Guests.left(r)))) == 1n+glen(r) : Nat},
        part_t(r, part(r)), part_f(r, part(r)))

def hc_tick(+arr: +List<C.Guest>, +g: +List<C.Guest>, +q: C.Q, +rs: +List<C.Ride>,
  +t: U32, +pl: +List<C.Board>, +sn: C.Stn, +qs: +List<U32>)
  -> {Nat.add(glen(List.append(&2, C.Guest, arr, C.Guests.stay(C.Guests.step(g, q, rs, t, pl, sn, qs)))),
    glen(C.Guests.left(C.Guests.step(g, q, rs, t, pl, sn, qs)))) == Nat.add(glen(g), glen(arr)) : Nat}:
  +m = C.Guests.step(g, q, rs, t, pl, sn, qs)
  +st = C.Guests.stay(m)
  +lf = C.Guests.left(m)
  +lhs = Nat.add(glen(List.append(&2, C.Guest, arr, st)), glen(lf))
  %add_comm(glen(arr), glen(g)) : {lhs == _ : Nat}
  %len_step(g, q, rs, t, pl, sn, qs) : {lhs == Nat.add(glen(arr), _) : Nat}
  %part(m) : {lhs == Nat.add(glen(arr), _) : Nat}
  %add_assoc(glen(arr), glen(st), glen(lf)) : {lhs == _ : Nat}
  %len_app(arr, st) : {lhs == Nat.add(_, glen(lf)) : Nat}
  {==}

def Laws.headcount_conserved(p, a):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff}:
      match a:
        case C.Tick{}:
          +sn = C.Stn.all(track)
          hc_tick(C.Guests.arrivals(guests, rides, time, nid, fin), guests, map, rides, time,
            C.Boards.plan(guests, C.Occ.table(guests, rides, sn), map, rides, sn, []), sn,
            C.Queue.list(guests, map, []))
        case C.Build{tool, x, y, v}:
          {==}
        case C.TrackOp{op}:
          {==}
        case C.RideOp{ride, op}:
          {==}
        case C.ParkOp{op}:
          {==}

# Needs
# -----
# Every guest a tick produces went through Guest.clamp (stepped guests and
# new arrivals alike), and the clamp is the very test the law checks. The
# guests who stay are a subset of the stepped ones; builds and track edits
# do not touch guests, so the hypothesis carries over.

def Tt(b: Bool) -> Data:
  match b:
    case True{}:
      Unit
    case False{}:
      Empty

def no_ft(h: {False{} == True{} : Bool}) -> Tt(False{}):
  %Equal.sym(Bool, False{}, True{}, h) : Tt(_)
  Unit{}

def bcase_eq(+b: Bool, -P: Bool -> Type, t: {True{} == b : Bool} -> P(True{}),
  f: {False{} == b : Bool} -> P(False{})) -> P(b):
  match b:
    case True{}:
      t({==})
    case False{}:
      f({==})

def and_l(+a: Bool, -b: Bool, h: {a && b == True{} : Bool}) -> {a == True{} : Bool}:
  match a:
    case True{}:
      {==}
    case False{}:
      Empty.absurd({False{} == True{} : Bool}, no_ft(h))

def and_r(+a: Bool, -b: Bool, h: {a && b == True{} : Bool}) -> {b == True{} : Bool}:
  match a:
    case True{}:
      h
    case False{}:
      Empty.absurd({b == True{} : Bool}, no_ft(h))

def and_i(+a: Bool, +b: Bool, ha: {a == True{} : Bool}, hb: {b == True{} : Bool})
  -> {a && b == True{} : Bool}:
  %Equal.sym(Bool, a, True{}, ha) : {_ && b == True{} : Bool}
  hb

# the clamp: cl255(x) = x when x <= 255, else 255
def le_cl(+x: U32) -> {True{} == U32.is_le(C.cl255(x), 255) : Bool}:
  bcase_eq(U32.is_le(x, 255), c => {True{} == U32.is_le(C.sel(c, x, 255), 255) : Bool},
    e => e, e => {==})

def ok_clamp(+g: C.Guest) -> {Laws.needs_ok(C.Guest.clamp(g)) == True{} : Bool}:
  match g:
    case C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl}:
      %le_cl(hu) : {_ && U32.is_le(C.cl255(th), 255) && U32.is_le(C.cl255(en), 255)
        && U32.is_le(C.cl255(na), 255) && U32.is_le(C.cl255(ha), 255) && U32.is_le(C.cl255(bl), 255) == True{} : Bool}
      %le_cl(th) : {True{} && _ && U32.is_le(C.cl255(en), 255)
        && U32.is_le(C.cl255(na), 255) && U32.is_le(C.cl255(ha), 255) && U32.is_le(C.cl255(bl), 255) == True{} : Bool}
      %le_cl(en) : {True{} && True{} && _
        && U32.is_le(C.cl255(na), 255) && U32.is_le(C.cl255(ha), 255) && U32.is_le(C.cl255(bl), 255) == True{} : Bool}
      %le_cl(na) : {True{} && True{} && True{}
        && _ && U32.is_le(C.cl255(ha), 255) && U32.is_le(C.cl255(bl), 255) == True{} : Bool}
      %le_cl(ha) : {True{} && True{} && True{} && True{} && _ && U32.is_le(C.cl255(bl), 255) == True{} : Bool}
      %le_cl(bl) : {True{} && True{} && True{} && True{} && True{} && _ == True{} : Bool}
      {==}

def all_app(+xs: +List<C.Guest>, +ys: +List<C.Guest>,
  +hx: {Laws.all_needs_ok(xs) == True{} : Bool}, hy: {Laws.all_needs_ok(ys) == True{} : Bool})
  -> {Laws.all_needs_ok(List.append(&2, C.Guest, xs, ys)) == True{} : Bool}:
  match xs:
    case []:
      hy
    case x <> r:
      and_i(Laws.needs_ok(x), Laws.all_needs_ok(List.append(&2, C.Guest, r, ys)),
        and_l(Laws.needs_ok(x), Laws.all_needs_ok(r), hx),
        all_app(r, ys, and_r(Laws.needs_ok(x), Laws.all_needs_ok(r), hx), hy))

def all_stay_t(+x: C.Guest, +r: +List<C.Guest>,
  ih: {Laws.all_needs_ok(C.Guests.stay(r)) == True{} : Bool})
  -> {Laws.all_needs_ok(C.Guests.put(False{}, x, C.Guests.stay(r))) == True{} : Bool}:
  ih

def all_stay_f(+x: C.Guest, +r: +List<C.Guest>, hx: {Laws.needs_ok(x) == True{} : Bool},
  ih: {Laws.all_needs_ok(C.Guests.stay(r)) == True{} : Bool})
  -> {Laws.all_needs_ok(C.Guests.put(True{}, x, C.Guests.stay(r))) == True{} : Bool}:
  and_i(Laws.needs_ok(x), Laws.all_needs_ok(C.Guests.stay(r)), hx, ih)

def all_stay(+m: +List<C.Guest>, +h: {Laws.all_needs_ok(m) == True{} : Bool})
  -> {Laws.all_needs_ok(C.Guests.stay(m)) == True{} : Bool}:
  match m:
    case []:
      {==}
    case x <> r:
      +ih = all_stay(r, and_r(Laws.needs_ok(x), Laws.all_needs_ok(r), h))
      bcase(C.Guest.gone(x), b => {Laws.all_needs_ok(C.Guests.put(Bool.not(b), x,
        C.Guests.stay(r))) == True{} : Bool},
        all_stay_t(x, r, ih),
        all_stay_f(x, r, and_l(Laws.needs_ok(x), Laws.all_needs_ok(r), h), ih))

def all_step(+g: +List<C.Guest>, +q: C.Q, +rs: +List<C.Ride>, +t: U32,
  +pl: +List<C.Board>, +sn: C.Stn, +qs: +List<U32>)
  -> {Laws.all_needs_ok(C.Guests.step(g, q, rs, t, pl, sn, qs)) == True{} : Bool}:
  match g:
    case []:
      {==}
    case x <> r:
      and_i(Laws.needs_ok(C.Guest.step(x, q, rs, t, pl, sn, qs)),
        Laws.all_needs_ok(C.Guests.step(r, q, rs, t, pl, sn, qs)),
        ok_clamp(C.Guest.needs(C.Guest.move(x, q, rs, t, pl, sn, qs), t)), all_step(r, q, rs, t, pl, sn, qs))

def all_arrive(+go: Bool, +id: U32, +t: U32, +fee: U32)
  -> {Laws.all_needs_ok(C.Guests.arrive(go, id, t, fee)) == True{} : Bool}:
  match go:
    case True{}:
      and_i(Laws.needs_ok(C.Guest.new(id, t, fee)), True{}, ok_clamp(C.Guest.raw(id, t, fee)), {==})
    case False{}:
      {==}

def Laws.needs_bounded(p, a, h):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff}:
      match a:
        case C.Tick{}:
          +sn = C.Stn.all(track)
          +pl = C.Boards.plan(guests, C.Occ.table(guests, rides, sn), map, rides, sn, [])
          +m = C.Guests.step(guests, map, rides, time, pl, sn, C.Queue.list(guests, map, []))
          all_app(C.Guests.arrivals(guests, rides, time, nid, fin), C.Guests.stay(m),
            all_arrive(C.Guests.come(guests, rides, time, fin), nid, time, U32.min(C.Fin.fee(fin), 40)),
            all_stay(m, all_step(guests, map, rides, time, pl, sn, C.Queue.list(guests, map, []))))
        case C.Build{tool, x, y, v}:
          h
        case C.TrackOp{op}:
          h
        case C.RideOp{ride, op}:
          h
        case C.ParkOp{op}:
          h

# The coaster runs only on a closed circuit
# ----------------------------------------
# A tick moves trains but never touches `open` or the pieces; building only
# ever starts a track closed; editing a track closes it; and opening sets
# `open` to the circuit check itself -- so "not open, or closed" survives.

def excl(+b: Bool) -> {Bool.not(b) || b == True{} : Bool}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

# "(a and b) and c" implies b, and implies c: every place that opens a
# track sets `open` to (a and closed) and live
def nimp_b(+a: Bool, +b: Bool, +c: Bool) -> {Bool.not((a && b) && c) || b == True{} : Bool}:
  match a:
    case True{}:
      match b:
        case True{}:
          match c:
            case True{}:
              {==}
            case False{}:
              {==}
        case False{}:
          match c:
            case True{}:
              {==}
            case False{}:
              {==}
    case False{}:
      match b:
        case True{}:
          {==}
        case False{}:
          {==}

def nimp_c(+a: Bool, +b: Bool, +c: Bool) -> {Bool.not((a && b) && c) || c == True{} : Bool}:
  match a:
    case True{}:
      match b:
        case True{}:
          match c:
            case True{}:
              {==}
            case False{}:
              {==}
        case False{}:
          match c:
            case True{}:
              {==}
            case False{}:
              {==}
    case False{}:
      match c:
        case True{}:
          {==}
        case False{}:
          {==}

def circ_tick(+t: C.Track, h: {Laws.circuit_ok(t) == True{} : Bool})
  -> {Laws.circuit_ok(C.Track.tick(t)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e, cfg, stats}:
      match open:
        case True{}:
          +st2 = C.Test.watch(C.Blocks.step(bs, ps, cfg), stats)
          nimp_b(Bool.not(C.Test.testing(stats) && Bool.not(C.Test.testing(st2))),
            C.Track.closed(C.Track{ps, False{}, [], s, e, cfg, stats}), C.Test.live(st2))
        case False{}:
          {==}

def circ_cfg(+t: C.Track, +op: U32) -> {Laws.circuit_ok(C.Track.setcfg(t, op)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e, cfg, stats}:
      {==}

def circ_toggle(+t: C.Track) -> {Laws.circuit_ok(C.Track.toggle(t)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e, cfg, stats}:
      match open:
        case True{}:
          {==}
        case False{}:
          nimp_b(True{}, C.Track.closed(C.Track{ps, False{}, [], s, e, cfg, stats}), C.Test.live(stats))

def circ_test(+t: C.Track) -> {Laws.circuit_ok(C.Track.test(t)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e, cfg, stats}:
      nimp_b(True{}, C.Track.closed(C.Track{ps, False{}, [], s, e, cfg, 0}),
        C.Test.live((1 .|. (C.Dry.fail(C.Dry.run(ps, cfg)) << 2n) : U32)))

def circ_pretest(+t: C.Track) -> {Laws.circuit_ok(C.Track.pretest(t)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e, cfg, stats}:
      {==}

def circ_edit(+t: C.Track, +op: U32) -> {Laws.circuit_ok(C.Track.edit(t, op)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e, cfg, stats}:
      +pc = {C.Piece{C.Pose.x(e), C.Pose.y(e), C.Pose.z(e), op, C.Pose.d(e)} : C.Piece}
      bcase(C.Piece.adds(op), b => {Laws.circuit_ok(Bool.pick(C.Track, b,
        C.Track{List.append(&2, C.Piece, ps, [pc]), False{}, [], s, C.Piece.exit(pc), cfg, 0},
        C.Track{C.Pieces.init(ps), False{}, [], s, C.Piece.pose(C.Pieces.last(ps)), cfg, 0}))
        == True{} : Bool}, {==}, {==})

def circ_cut(+t: C.Track, +from: U32) -> {Laws.circuit_ok(C.Track.cut(t, from)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e, cfg, stats}:
      {==}

def circ_recheck(+t: C.Track, h: {Laws.circuit_ok(t) == True{} : Bool}) -> {Laws.circuit_ok(C.Track.recheck(t)) == True{} : Bool}:
  bcase(C.Track.closed(t) && U32.is_eq(C.Dry.fail(C.Dry.run(C.Track.pieces(t), C.Track.cfg(t))), 255),
    b => {Laws.circuit_ok(Bool.pick(C.Track, b, C.Track.test(t), t)) == True{} : Bool}, circ_test(t), h)

def circ_op(+t: C.Track, +op: U32, +ix: U32, +ok: Bool, h: {Laws.circuit_ok(t) == True{} : Bool})
  -> {Laws.circuit_ok(C.Track.op(t, op, ix, ok)) == True{} : Bool}:
  match ok:
    case True{}:
      +rest = Bool.pick(C.Track, (op >= 16 : U32), C.Track.recheck(C.Track.setcfg(t, op)), C.Track.recheck(C.Track.edit(t, op)))
      +cut = Bool.pick(C.Track, U32.is_eq(op, 26) || U32.is_eq(op, 27), C.Track.recheck(C.Track.cut(t, C.TrackOp.from(op, ix))), rest)
      +pre = Bool.pick(C.Track, U32.is_eq(op, 25), C.Track.pretest(t), cut)
      +tst = Bool.pick(C.Track, U32.is_eq(op, 24), C.Track.test(t), pre)
      bcase(U32.is_eq(op, 8), b => {Laws.circuit_ok(Bool.pick(C.Track, b, C.Track.toggle(t), tst)) == True{} : Bool},
        circ_toggle(t),
        bcase(U32.is_eq(op, 24), b => {Laws.circuit_ok(Bool.pick(C.Track, b, C.Track.test(t), pre)) == True{} : Bool},
          circ_test(t),
          bcase(U32.is_eq(op, 25), b => {Laws.circuit_ok(Bool.pick(C.Track, b, C.Track.pretest(t), cut)) == True{} : Bool},
            circ_pretest(t),
            bcase(U32.is_eq(op, 26) || U32.is_eq(op, 27), b => {Laws.circuit_ok(Bool.pick(C.Track, b, C.Track.recheck(C.Track.cut(t, C.TrackOp.from(op, ix))), rest)) == True{} : Bool},
              circ_recheck(C.Track.cut(t, C.TrackOp.from(op, ix)), circ_cut(t, C.TrackOp.from(op, ix))),
              bcase((op >= 16 : U32), b => {Laws.circuit_ok(Bool.pick(C.Track, b, C.Track.recheck(C.Track.setcfg(t, op)), C.Track.recheck(C.Track.edit(t, op)))) == True{} : Bool},
                circ_recheck(C.Track.setcfg(t, op), circ_cfg(t, op)), circ_recheck(C.Track.edit(t, op), circ_edit(t, op)))))))
    case False{}:
      h

def circs_tick(+ts: +List<C.Track>, +h: {Laws.circuits_ok(ts) == True{} : Bool})
  -> {Laws.circuits_ok(C.Tracks.tick(ts)) == True{} : Bool}:
  match ts:
    case []:
      {==}
    case t <> rest:
      and_i(Laws.circuit_ok(C.Track.tick(t)), Laws.circuits_ok(C.Tracks.tick(rest)),
        circ_tick(t, and_l(Laws.circuit_ok(t), Laws.circuits_ok(rest), h)),
        circs_tick(rest, and_r(Laws.circuit_ok(t), Laws.circuits_ok(rest), h)))

def circs_app(+xs: +List<C.Track>, +ys: +List<C.Track>,
  +hx: {Laws.circuits_ok(xs) == True{} : Bool}, +hy: {Laws.circuits_ok(ys) == True{} : Bool})
  -> {Laws.circuits_ok(List.append(&2, C.Track, xs, ys)) == True{} : Bool}:
  match xs:
    case []:
      hy
    case x <> rest:
      and_i(Laws.circuit_ok(x), Laws.circuits_ok(List.append(&2, C.Track, rest, ys)),
        and_l(Laws.circuit_ok(x), Laws.circuits_ok(rest), hx),
        circs_app(rest, ys, and_r(Laws.circuit_ok(x), Laws.circuits_ok(rest), hx), hy))

def circs_build(+ok: Bool, +q: C.Q, +ts: +List<C.Track>, +tool: U32, +x: U32, +y: U32,
  +v: U32, +h: {Laws.circuits_ok(ts) == True{} : Bool})
  -> {Laws.circuits_ok(C.Build.track(ok, q, ts, tool, x, y, v)) == True{} : Bool}:
  match ok:
    case True{}:
      bcase(U32.is_eq(tool, 10), b => {Laws.circuits_ok(Bool.pick(+List<C.Track>, b,
        List.append(&2, C.Track, ts, [C.Track.begin(q, x, y, v)]), ts)) == True{} : Bool},
        circs_app(ts, [C.Track.begin(q, x, y, v)], h, {==}), h)
    case False{}:
      h

def circs_get(+ts: +List<C.Track>, +k: U32, +h: {Laws.circuits_ok(ts) == True{} : Bool})
  -> {Laws.circuit_ok(C.Tracks.get(ts, k)) == True{} : Bool}:
  match ts:
    case []:
      {==}
    case t <> rest:
      bcase(U32.is_eq(k, 0), b => {Laws.circuit_ok(Bool.pick(C.Track, b, t, C.Tracks.get(rest, (k - 1 : U32)))) == True{} : Bool},
        and_l(Laws.circuit_ok(t), Laws.circuits_ok(rest), h),
        circs_get(rest, (k - 1 : U32), and_r(Laws.circuit_ok(t), Laws.circuits_ok(rest), h)))

def circs_set(+ts: +List<C.Track>, +k: U32, +t2: C.Track, +h: {Laws.circuits_ok(ts) == True{} : Bool},
  +h2: {Laws.circuit_ok(t2) == True{} : Bool})
  -> {Laws.circuits_ok(C.Tracks.set(ts, k, t2)) == True{} : Bool}:
  match ts:
    case []:
      {==}
    case t <> rest:
      and_i(Laws.circuit_ok(Bool.pick(C.Track, U32.is_eq(k, 0), t2, t)), Laws.circuits_ok(C.Tracks.set(rest, (k - 1 : U32), t2)),
        bcase(U32.is_eq(k, 0), b => {Laws.circuit_ok(Bool.pick(C.Track, b, t2, t)) == True{} : Bool},
          h2, and_l(Laws.circuit_ok(t), Laws.circuits_ok(rest), h)),
        circs_set(rest, (k - 1 : U32), t2, and_r(Laws.circuit_ok(t), Laws.circuits_ok(rest), h), h2))

def circs_op(+ts: +List<C.Track>, +k: U32, +code: U32, +ix: U32, +ok: Bool, +h: {Laws.circuits_ok(ts) == True{} : Bool})
  -> {Laws.circuits_ok(C.Tracks.set(ts, k, C.Track.op(C.Tracks.get(ts, k), code, ix, ok))) == True{} : Bool}:
  circs_set(ts, k, C.Track.op(C.Tracks.get(ts, k), code, ix, ok), h, circ_op(C.Tracks.get(ts, k), code, ix, ok, circs_get(ts, k, h)))

def Laws.coaster_on_circuit(p, a, h):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff}:
      match a:
        case C.Tick{}:
          circs_tick(track, h)
        case C.Build{tool, x, y, v}:
          circs_build(C.Build.ok(map, track, cash, tool, x, y), map, track, tool, x, y, v, h)
        case C.TrackOp{op}:
          +k = C.TrackOp.k(op)
          +code = (op .&. 31 : U32)
          +trk = C.Tracks.get(track, k)
          +ok = C.TrackOp.ok(map, trk, cash, code) && (k < C.len32(C.Track, track) : U32)
          circs_op(track, k, code, C.TrackOp.idx(op), ok, h)
        case C.RideOp{ride, op}:
          h
        case C.ParkOp{op}:
          h

# A coaster carries trains only when tested
# ------------------------------------------
# Same shape as the circuit law: a tick keeps `open` only while the test
# (or its pass) stands, opening and testing set `open` to a check that
# includes it, and edits close the track.

def tst_tick(+t: C.Track, h: {Laws.tested_ok(t) == True{} : Bool})
  -> {Laws.tested_ok(C.Track.tick(t)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e, cfg, stats}:
      match open:
        case True{}:
          +st2 = C.Test.watch(C.Blocks.step(bs, ps, cfg), stats)
          nimp_c(Bool.not(C.Test.testing(stats) && Bool.not(C.Test.testing(st2))),
            C.Track.closed(C.Track{ps, False{}, [], s, e, cfg, stats}), C.Test.live(st2))
        case False{}:
          {==}

def tst_toggle(+t: C.Track) -> {Laws.tested_ok(C.Track.toggle(t)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e, cfg, stats}:
      match open:
        case True{}:
          {==}
        case False{}:
          nimp_c(True{}, C.Track.closed(C.Track{ps, False{}, [], s, e, cfg, stats}), C.Test.live(stats))

def tst_test(+t: C.Track) -> {Laws.tested_ok(C.Track.test(t)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e, cfg, stats}:
      nimp_c(True{}, C.Track.closed(C.Track{ps, False{}, [], s, e, cfg, 0}),
        C.Test.live((1 .|. (C.Dry.fail(C.Dry.run(ps, cfg)) << 2n) : U32)))

def tst_pretest(+t: C.Track) -> {Laws.tested_ok(C.Track.pretest(t)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e, cfg, stats}:
      {==}

def tst_cfg(+t: C.Track, +op: U32) -> {Laws.tested_ok(C.Track.setcfg(t, op)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e, cfg, stats}:
      {==}

def tst_edit(+t: C.Track, +op: U32) -> {Laws.tested_ok(C.Track.edit(t, op)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e, cfg, stats}:
      +pc = {C.Piece{C.Pose.x(e), C.Pose.y(e), C.Pose.z(e), op, C.Pose.d(e)} : C.Piece}
      bcase(C.Piece.adds(op), b => {Laws.tested_ok(Bool.pick(C.Track, b,
        C.Track{List.append(&2, C.Piece, ps, [pc]), False{}, [], s, C.Piece.exit(pc), cfg, 0},
        C.Track{C.Pieces.init(ps), False{}, [], s, C.Piece.pose(C.Pieces.last(ps)), cfg, 0}))
        == True{} : Bool}, {==}, {==})

def tst_cut(+t: C.Track, +from: U32) -> {Laws.tested_ok(C.Track.cut(t, from)) == True{} : Bool}:
  match t:
    case C.Track{ps, open, bs, s, e, cfg, stats}:
      {==}

def tst_recheck(+t: C.Track, h: {Laws.tested_ok(t) == True{} : Bool}) -> {Laws.tested_ok(C.Track.recheck(t)) == True{} : Bool}:
  bcase(C.Track.closed(t) && U32.is_eq(C.Dry.fail(C.Dry.run(C.Track.pieces(t), C.Track.cfg(t))), 255),
    b => {Laws.tested_ok(Bool.pick(C.Track, b, C.Track.test(t), t)) == True{} : Bool}, tst_test(t), h)

def tst_op(+t: C.Track, +op: U32, +ix: U32, +ok: Bool, h: {Laws.tested_ok(t) == True{} : Bool})
  -> {Laws.tested_ok(C.Track.op(t, op, ix, ok)) == True{} : Bool}:
  match ok:
    case True{}:
      +rest = Bool.pick(C.Track, (op >= 16 : U32), C.Track.recheck(C.Track.setcfg(t, op)), C.Track.recheck(C.Track.edit(t, op)))
      +cut = Bool.pick(C.Track, U32.is_eq(op, 26) || U32.is_eq(op, 27), C.Track.recheck(C.Track.cut(t, C.TrackOp.from(op, ix))), rest)
      +pre = Bool.pick(C.Track, U32.is_eq(op, 25), C.Track.pretest(t), cut)
      +tst = Bool.pick(C.Track, U32.is_eq(op, 24), C.Track.test(t), pre)
      bcase(U32.is_eq(op, 8), b => {Laws.tested_ok(Bool.pick(C.Track, b, C.Track.toggle(t), tst)) == True{} : Bool},
        tst_toggle(t),
        bcase(U32.is_eq(op, 24), b => {Laws.tested_ok(Bool.pick(C.Track, b, C.Track.test(t), pre)) == True{} : Bool},
          tst_test(t),
          bcase(U32.is_eq(op, 25), b => {Laws.tested_ok(Bool.pick(C.Track, b, C.Track.pretest(t), cut)) == True{} : Bool},
            tst_pretest(t),
            bcase(U32.is_eq(op, 26) || U32.is_eq(op, 27), b => {Laws.tested_ok(Bool.pick(C.Track, b, C.Track.recheck(C.Track.cut(t, C.TrackOp.from(op, ix))), rest)) == True{} : Bool},
              tst_recheck(C.Track.cut(t, C.TrackOp.from(op, ix)), tst_cut(t, C.TrackOp.from(op, ix))),
              bcase((op >= 16 : U32), b => {Laws.tested_ok(Bool.pick(C.Track, b, C.Track.recheck(C.Track.setcfg(t, op)), C.Track.recheck(C.Track.edit(t, op)))) == True{} : Bool},
                tst_recheck(C.Track.setcfg(t, op), tst_cfg(t, op)), tst_recheck(C.Track.edit(t, op), tst_edit(t, op)))))))
    case False{}:
      h

def tsts_tick(+ts: +List<C.Track>, +h: {Laws.tests_ok(ts) == True{} : Bool})
  -> {Laws.tests_ok(C.Tracks.tick(ts)) == True{} : Bool}:
  match ts:
    case []:
      {==}
    case t <> rest:
      and_i(Laws.tested_ok(C.Track.tick(t)), Laws.tests_ok(C.Tracks.tick(rest)),
        tst_tick(t, and_l(Laws.tested_ok(t), Laws.tests_ok(rest), h)),
        tsts_tick(rest, and_r(Laws.tested_ok(t), Laws.tests_ok(rest), h)))

def tsts_app(+xs: +List<C.Track>, +ys: +List<C.Track>,
  +hx: {Laws.tests_ok(xs) == True{} : Bool}, +hy: {Laws.tests_ok(ys) == True{} : Bool})
  -> {Laws.tests_ok(List.append(&2, C.Track, xs, ys)) == True{} : Bool}:
  match xs:
    case []:
      hy
    case x <> rest:
      and_i(Laws.tested_ok(x), Laws.tests_ok(List.append(&2, C.Track, rest, ys)),
        and_l(Laws.tested_ok(x), Laws.tests_ok(rest), hx),
        tsts_app(rest, ys, and_r(Laws.tested_ok(x), Laws.tests_ok(rest), hx), hy))

def tsts_build(+ok: Bool, +q: C.Q, +ts: +List<C.Track>, +tool: U32, +x: U32, +y: U32,
  +v: U32, +h: {Laws.tests_ok(ts) == True{} : Bool})
  -> {Laws.tests_ok(C.Build.track(ok, q, ts, tool, x, y, v)) == True{} : Bool}:
  match ok:
    case True{}:
      bcase(U32.is_eq(tool, 10), b => {Laws.tests_ok(Bool.pick(+List<C.Track>, b,
        List.append(&2, C.Track, ts, [C.Track.begin(q, x, y, v)]), ts)) == True{} : Bool},
        tsts_app(ts, [C.Track.begin(q, x, y, v)], h, {==}), h)
    case False{}:
      h

def tsts_get(+ts: +List<C.Track>, +k: U32, +h: {Laws.tests_ok(ts) == True{} : Bool})
  -> {Laws.tested_ok(C.Tracks.get(ts, k)) == True{} : Bool}:
  match ts:
    case []:
      {==}
    case t <> rest:
      bcase(U32.is_eq(k, 0), b => {Laws.tested_ok(Bool.pick(C.Track, b, t, C.Tracks.get(rest, (k - 1 : U32)))) == True{} : Bool},
        and_l(Laws.tested_ok(t), Laws.tests_ok(rest), h),
        tsts_get(rest, (k - 1 : U32), and_r(Laws.tested_ok(t), Laws.tests_ok(rest), h)))

def tsts_set(+ts: +List<C.Track>, +k: U32, +t2: C.Track, +h: {Laws.tests_ok(ts) == True{} : Bool},
  +h2: {Laws.tested_ok(t2) == True{} : Bool})
  -> {Laws.tests_ok(C.Tracks.set(ts, k, t2)) == True{} : Bool}:
  match ts:
    case []:
      {==}
    case t <> rest:
      and_i(Laws.tested_ok(Bool.pick(C.Track, U32.is_eq(k, 0), t2, t)), Laws.tests_ok(C.Tracks.set(rest, (k - 1 : U32), t2)),
        bcase(U32.is_eq(k, 0), b => {Laws.tested_ok(Bool.pick(C.Track, b, t2, t)) == True{} : Bool},
          h2, and_l(Laws.tested_ok(t), Laws.tests_ok(rest), h)),
        tsts_set(rest, (k - 1 : U32), t2, and_r(Laws.tested_ok(t), Laws.tests_ok(rest), h), h2))

def tsts_op(+ts: +List<C.Track>, +k: U32, +code: U32, +ix: U32, +ok: Bool, +h: {Laws.tests_ok(ts) == True{} : Bool})
  -> {Laws.tests_ok(C.Tracks.set(ts, k, C.Track.op(C.Tracks.get(ts, k), code, ix, ok))) == True{} : Bool}:
  tsts_set(ts, k, C.Track.op(C.Tracks.get(ts, k), code, ix, ok), h, tst_op(C.Tracks.get(ts, k), code, ix, ok, tsts_get(ts, k, h)))

def Laws.open_only_tested(p, a, h):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff}:
      match a:
        case C.Tick{}:
          tsts_tick(track, h)
        case C.Build{tool, x, y, v}:
          tsts_build(C.Build.ok(map, track, cash, tool, x, y), map, track, tool, x, y, v, h)
        case C.TrackOp{op}:
          +k = C.TrackOp.k(op)
          +code = (op .&. 31 : U32)
          +trk = C.Tracks.get(track, k)
          +ok = C.TrackOp.ok(map, trk, cash, code) && (k < C.len32(C.Track, track) : U32)
          tsts_op(track, k, code, C.TrackOp.idx(op), ok, h)
        case C.RideOp{ride, op}:
          h
        case C.ParkOp{op}:
          h

def Laws.no_collisions(blocks, pieces, cfg):
  match blocks:
    case []:
      {==}
    case s <> rest:
      +a1 = C.Slot.adv(s, pieces, cfg)
      +ar = C.Slots.adv(rest, pieces, cfg)
      +lhs = C.Blocks.trains(C.Blocks.step(s <> rest, pieces, cfg))
      %trains_adv(rest, pieces, cfg) : {lhs == Nat.add(C.Slot.count(s), _) : Nat}
      %cnt_adv(s, pieces, cfg) : {lhs == Nat.add(_, C.Blocks.trains(ar)) : Nat}
      %trains_pass(ar, a1) : {lhs == _ : Nat}
      %trains_rot(C.Slots.pass(ar, a1)) : {lhs == _ : Nat}
      {==}

# Saves
# -----
# Decoding the words of a value, followed by anything, pushes the value and
# carries on with what follows. Each lemma is an induction over the value;
# the save of a park chains them, and the final stack is just the park.

def rt_q(+q: C.Q, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.q(q, rest), st) == S.dec(rest, S.IQ{q} <> st) : List<&2, S.Item>}:
  match q:
    case C.QL{t}:
      match t:
        case C.Tile{h, ter, obj, a, b}:
          {==}
    case C.QN{a, b, c, d}:
      +r3 = S.Enc.q(d, 2 <> rest)
      +r2 = S.Enc.q(c, r3)
      +r1 = S.Enc.q(b, r2)
      +s1 = {S.IQ{a} <> st : List<&2, S.Item>}
      +s2 = {S.IQ{b} <> s1 : List<&2, S.Item>}
      +s3 = {S.IQ{c} <> s2 : List<&2, S.Item>}
      +lhs = S.dec(S.Enc.q(C.QN{a, b, c, d}, rest), st)
      %rt_q(d, 2 <> rest, s3) : {lhs == _ : List<&2, S.Item>}
      %rt_q(c, r3, s2) : {lhs == _ : List<&2, S.Item>}
      %rt_q(b, r2, s1) : {lhs == _ : List<&2, S.Item>}
      %rt_q(a, r1, st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_guest(+g: C.Guest, +rest: List<&2, U32>, +more: List<&2, C.Guest>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.guest(g, rest), S.IG{more} <> st) == S.dec(rest, S.IG{g <> more} <> st) : List<&2, S.Item>}:
  match g:
    case C.Guest{id, x, y, dir, gs, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl}:
      {==}

def rt_ride(+r: C.Ride, +rest: List<&2, U32>, +more: List<&2, C.Ride>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.ride(r, rest), S.IR{more} <> st) == S.dec(rest, S.IR{r <> more} <> st) : List<&2, S.Item>}:
  match r:
    case C.Ride{kind, x, y, w, h, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear}:
      {==}

def rt_piece(+p: C.Piece, +rest: List<&2, U32>, +more: List<&2, C.Piece>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.piece(p, rest), S.IP{more} <> st) == S.dec(rest, S.IP{p <> more} <> st) : List<&2, S.Item>}:
  match p:
    case C.Piece{x, y, z, kind, dir}:
      {==}

def rt_slot(+s: C.Slot, +rest: List<&2, U32>, +more: List<&2, C.Slot>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.slot(s, rest), S.IS{more} <> st) == S.dec(rest, S.IS{s <> more} <> st) : List<&2, S.Item>}:
  match s:
    case C.Free{a, n, k}:
      {==}
    case C.Held{a, n, k, t}:
      match t:
        case C.Train{id, prog, speed, wait}:
          {==}

def rt_gs(+xs: List<&2, C.Guest>, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.gs(xs, rest), st) == S.dec(rest, S.IG{xs} <> st) : List<&2, S.Item>}:
  match xs:
    case []:
      {==}
    case x <> more:
      +lhs = S.dec(S.Enc.gs(x <> more, rest), st)
      %rt_guest(x, rest, more, st) : {lhs == _ : List<&2, S.Item>}
      %rt_gs(more, S.Enc.guest(x, rest), st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_rs(+xs: List<&2, C.Ride>, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.rs(xs, rest), st) == S.dec(rest, S.IR{xs} <> st) : List<&2, S.Item>}:
  match xs:
    case []:
      {==}
    case x <> more:
      +lhs = S.dec(S.Enc.rs(x <> more, rest), st)
      %rt_ride(x, rest, more, st) : {lhs == _ : List<&2, S.Item>}
      %rt_rs(more, S.Enc.ride(x, rest), st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_ps(+xs: List<&2, C.Piece>, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.ps(xs, rest), st) == S.dec(rest, S.IP{xs} <> st) : List<&2, S.Item>}:
  match xs:
    case []:
      {==}
    case x <> more:
      +lhs = S.dec(S.Enc.ps(x <> more, rest), st)
      %rt_piece(x, rest, more, st) : {lhs == _ : List<&2, S.Item>}
      %rt_ps(more, S.Enc.piece(x, rest), st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_ss(+xs: List<&2, C.Slot>, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.ss(xs, rest), st) == S.dec(rest, S.IS{xs} <> st) : List<&2, S.Item>}:
  match xs:
    case []:
      {==}
    case x <> more:
      +lhs = S.dec(S.Enc.ss(x <> more, rest), st)
      %rt_slot(x, rest, more, st) : {lhs == _ : List<&2, S.Item>}
      %rt_ss(more, S.Enc.slot(x, rest), st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_track_go(+ps: List<&2, C.Piece>, +open: Bool, +ss: List<&2, C.Slot>,
  +sx: U32, +sy: U32, +sz: U32, +sd: U32, +ex: U32, +ey: U32, +ez: U32, +ed: U32, +cfg: U32, +stats: U32,
  +rest: List<&2, U32>, +more: List<&2, C.Track>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.track(C.Track{ps, open, ss, C.Pose{sx, sy, sz, sd}, C.Pose{ex, ey, ez, ed}, cfg, stats}, rest), S.IT{more} <> st)
    == S.dec(rest, S.IT{C.Track{ps, open, ss, C.Pose{sx, sy, sz, sd}, C.Pose{ex, ey, ez, ed}, cfg, stats} <> more} <> st) : List<&2, S.Item>}:
  match open:
    case True{}:
      +r12 = {12 <> 1 <> sx <> sy <> sz <> sd <> ex <> ey <> ez <> ed <> cfg <> stats <> rest : List<&2, U32>}
      +lhs = S.dec(S.Enc.track(C.Track{ps, True{}, ss, C.Pose{sx, sy, sz, sd}, C.Pose{ex, ey, ez, ed}, cfg, stats}, rest), S.IT{more} <> st)
      %rt_ss(ss, r12, S.IP{ps} <> S.IT{more} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_ps(ps, S.Enc.ss(ss, r12), S.IT{more} <> st) : {lhs == _ : List<&2, S.Item>}
      {==}
    case False{}:
      +r12 = {12 <> 0 <> sx <> sy <> sz <> sd <> ex <> ey <> ez <> ed <> cfg <> stats <> rest : List<&2, U32>}
      +lhs = S.dec(S.Enc.track(C.Track{ps, False{}, ss, C.Pose{sx, sy, sz, sd}, C.Pose{ex, ey, ez, ed}, cfg, stats}, rest), S.IT{more} <> st)
      %rt_ss(ss, r12, S.IP{ps} <> S.IT{more} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_ps(ps, S.Enc.ss(ss, r12), S.IT{more} <> st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_track(+t: C.Track, +rest: List<&2, U32>, +more: List<&2, C.Track>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.track(t, rest), S.IT{more} <> st) == S.dec(rest, S.IT{t <> more} <> st) : List<&2, S.Item>}:
  match t:
    case C.Track{ps, open, ss, s, e, cfg, stats}:
      match s:
        case C.Pose{sx, sy, sz, sd}:
          match e:
            case C.Pose{ex, ey, ez, ed}:
              rt_track_go(ps, open, ss, sx, sy, sz, sd, ex, ey, ez, ed, cfg, stats, rest, more, st)

def rt_tks(+xs: List<&2, C.Track>, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.tks(xs, rest), st) == S.dec(rest, S.IT{xs} <> st) : List<&2, S.Item>}:
  match xs:
    case []:
      {==}
    case x <> more:
      +lhs = S.dec(S.Enc.tks(x <> more, rest), st)
      %rt_track(x, rest, more, st) : {lhs == _ : List<&2, S.Item>}
      %rt_tks(more, S.Enc.track(x, rest), st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_w(+w: U32, +rest: List<&2, U32>, +more: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(16 <> w <> rest, S.IW{more} <> st) == S.dec(rest, S.IW{w <> more} <> st) : List<&2, S.Item>}:
  {==}

def rt_ws(+xs: List<&2, U32>, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.ws(xs, rest), st) == S.dec(rest, S.IW{xs} <> st) : List<&2, S.Item>}:
  match xs:
    case []:
      {==}
    case x <> more:
      +lhs = S.dec(S.Enc.ws(x <> more, rest), st)
      %rt_w(x, rest, more, st) : {lhs == _ : List<&2, S.Item>}
      %rt_ws(more, 16 <> x <> rest, st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_fin(+f: C.Fin, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.fin(f, rest), st) == S.dec(rest, S.IF{f} <> st) : List<&2, S.Item>}:
  match f:
    case C.Fin{fee, loan, rating, now, last, hist, res}:
      +r14 = {14 <> fee <> loan <> rating <> res <> rest : List<&2, U32>}
      +rh = S.Enc.ws(hist, r14)
      +rl = S.Enc.ws(last, rh)
      +lhs = S.dec(S.Enc.fin(C.Fin{fee, loan, rating, now, last, hist, res}, rest), st)
      %rt_ws(hist, r14, S.IW{last} <> S.IW{now} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_ws(last, rh, S.IW{now} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_ws(now, rl, st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_staff(+s: C.Staff, +rest: List<&2, U32>, +more: List<&2, C.Staff>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.staff1(s, rest), S.IStf{more} <> st) == S.dec(rest, S.IStf{s <> more} <> st) : List<&2, S.Item>}:
  match s:
    case C.Staff{id, x, y, dir, kind, st, tgt, tmr, zone, look}:
      {==}

def rt_stf(+xs: List<&2, C.Staff>, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.stf(xs, rest), st) == S.dec(rest, S.IStf{xs} <> st) : List<&2, S.Item>}:
  match xs:
    case []:
      {==}
    case x <> more:
      +lhs = S.dec(S.Enc.stf(x <> more, rest), st)
      %rt_staff(x, rest, more, st) : {lhs == _ : List<&2, S.Item>}
      %rt_stf(more, S.Enc.staff1(x, rest), st) : {lhs == _ : List<&2, S.Item>}
      {==}

def rt_park(+p: C.Park, +rest: List<&2, U32>, +st: List<&2, S.Item>)
  -> {S.dec(S.Enc.park(p, rest), st) == S.dec(rest, S.IK{p} <> st) : List<&2, S.Item>}:
  match p:
    case C.Park{q, gs, rs, t, cash, time, nid, fin, mess, staff}:
      +r13 = {13 <> cash <> time <> nid <> rest : List<&2, U32>}
      +rsf = S.Enc.stf(staff, r13)
      +rm = S.Enc.ws(mess, rsf)
      +rf = S.Enc.fin(fin, rm)
      +rt = S.Enc.tks(t, rf)
      +rr = S.Enc.rs(rs, rt)
      +rg = S.Enc.gs(gs, rr)
      +lhs = S.dec(S.Enc.park(C.Park{q, gs, rs, t, cash, time, nid, fin, mess, staff}, rest), st)
      %rt_stf(staff, r13, S.IW{mess} <> S.IF{fin} <> S.IT{t} <> S.IR{rs} <> S.IG{gs} <> S.IQ{q} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_ws(mess, rsf, S.IF{fin} <> S.IT{t} <> S.IR{rs} <> S.IG{gs} <> S.IQ{q} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_fin(fin, rm, S.IT{t} <> S.IR{rs} <> S.IG{gs} <> S.IQ{q} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_tks(t, rf, S.IR{rs} <> S.IG{gs} <> S.IQ{q} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_rs(rs, rt, S.IG{gs} <> S.IQ{q} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_gs(gs, rr, S.IQ{q} <> st) : {lhs == _ : List<&2, S.Item>}
      %rt_q(q, rg, st) : {lhs == _ : List<&2, S.Item>}
      {==}

def Laws.save_load_roundtrip(p):
  %Equal.sym(List<&2, S.Item>, S.dec(S.Enc.park(p, []), []), S.dec([], S.IK{p} <> []), rt_park(p, [], []))
    : {S.Load.fin(_) == Some{p} : Maybe<&2, C.Park>}
  {==}

# Capacity: Seat.first is a chain of Seat.pick steps, each taking seat k only
# when k < cap, so whatever it returns is NONE or below cap; Boards.put drops
# NONE; the plan only ever adds such boards to its accumulator.
def or_r(+a: Bool, +b: Bool, hb: {b == True{} : Bool}) -> {a || b == True{} : Bool}:
  match a:
    case True{}:
      {==}
    case False{}:
      hb

def or_f(+a: Bool, +b: Bool, e: {False{} == a : Bool}, h: {a || b == True{} : Bool})
  -> {b == True{} : Bool}:
  %Equal.sym(Bool, False{}, a, e) : {_ || b == True{} : Bool}
  h

# P(s): s is NONE, or below cap and not yet handed out by the plan acc
def pick_ok(+m0: U32, +m1: U32, +acc: +List<C.Board>, +r: U32, +cap: U32, +k: U32, +rest: U32,
  +hr: {U32.is_eq(rest, C.NONE()) || (U32.is_lt(rest, cap) && Bool.not(C.Boards.taken(acc, r, rest))) == True{} : Bool})
  -> {U32.is_eq(C.Seat.pick(m0, m1, acc, r, cap, k, rest), C.NONE()) || (U32.is_lt(C.Seat.pick(m0, m1, acc, r, cap, k, rest), cap) && Bool.not(C.Boards.taken(acc, r, C.Seat.pick(m0, m1, acc, r, cap, k, rest)))) == True{} : Bool}:
  bcase_eq(C.Seat.open(m0, m1, k) && (U32.is_lt(k, cap) && Bool.not(C.Boards.taken(acc, r, k))),
    c => {U32.is_eq(C.sel(c, k, rest), C.NONE()) || (U32.is_lt(C.sel(c, k, rest), cap) && Bool.not(C.Boards.taken(acc, r, C.sel(c, k, rest)))) == True{} : Bool},
    e => or_r(U32.is_eq(k, C.NONE()), U32.is_lt(k, cap) && Bool.not(C.Boards.taken(acc, r, k)),
      and_r(C.Seat.open(m0, m1, k), U32.is_lt(k, cap) && Bool.not(C.Boards.taken(acc, r, k)),
        Equal.sym(Bool, True{}, C.Seat.open(m0, m1, k) && (U32.is_lt(k, cap) && Bool.not(C.Boards.taken(acc, r, k))), e))),
    e => hr)

# the scan: every step is a pick, so by induction the scan is NONE or a good seat
def scan_ok(+n: Nat, +m0: U32, +m1: U32, +acc: +List<C.Board>, +r: U32, +cap: U32, +k: U32)
  -> {U32.is_eq(C.Seat.scan(n, m0, m1, acc, r, cap, k), C.NONE()) || (U32.is_lt(C.Seat.scan(n, m0, m1, acc, r, cap, k), cap) && Bool.not(C.Boards.taken(acc, r, C.Seat.scan(n, m0, m1, acc, r, cap, k)))) == True{} : Bool}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      pick_ok(m0, m1, acc, r, cap, k, C.Seat.scan(p, m0, m1, acc, r, cap, (k + 1 : U32)), scan_ok(p, m0, m1, acc, r, cap, (k + 1 : U32)))

def seat_ok(+occ: +List<U32>, +acc: +List<C.Board>, +r: U32, +cap: U32)
  -> {U32.is_eq(C.Seat.free(occ, acc, r, cap), C.NONE()) || (U32.is_lt(C.Seat.free(occ, acc, r, cap), cap) && Bool.not(C.Boards.taken(acc, r, C.Seat.free(occ, acc, r, cap)))) == True{} : Bool}:
  scan_ok(U32.to_nat(U32.min(cap, 64)), C.Tab.at(occ, (r * 2 : U32)), C.Tab.at(occ, (r * 2 + 1 : U32)), acc, r, cap, 0)

def put_ok(+s: U32, +id: U32, +r: U32, +rs: +List<C.Ride>, +sn: C.Stn, +acc: +List<C.Board>,
  +hs: {U32.is_eq(s, C.NONE()) || (U32.is_lt(s, C.Ride.cap(C.Rides.get(rs, r), sn))
    && Bool.not(C.Boards.taken(acc, r, s))) == True{} : Bool},
  +h: {Laws.all_boards_ok(rs, sn, acc) == True{} : Bool})
  -> {Laws.all_boards_ok(rs, sn, C.Boards.put(s, id, r, acc)) == True{} : Bool}:
  +cap = C.Ride.cap(C.Rides.get(rs, r), sn)
  bcase_eq(U32.is_eq(s, C.NONE()),
    c => {Laws.all_boards_ok(rs, sn, Bool.pick(+List<C.Board>, c, acc, C.Board{id, r, s} <> acc)) == True{} : Bool},
    e => h,
    e => and_i(U32.is_lt(s, cap), Laws.all_boards_ok(rs, sn, acc),
      and_l(U32.is_lt(s, cap), Bool.not(C.Boards.taken(acc, r, s)),
        or_f(U32.is_eq(s, C.NONE()), U32.is_lt(s, cap) && Bool.not(C.Boards.taken(acc, r, s)), e, hs)), h))

def try_ok(+want: Bool, +g: C.Guest, +occ: +List<U32>, +rs: +List<C.Ride>, +sn: C.Stn,
  +acc: +List<C.Board>, +h: {Laws.all_boards_ok(rs, sn, acc) == True{} : Bool})
  -> {Laws.all_boards_ok(rs, sn, C.Boards.try(want, g, occ, rs, sn, acc)) == True{} : Bool}:
  match want:
    case True{}:
      +r = C.Guest.tgt(g)
      +cap = C.Ride.cap(C.Rides.get(rs, r), sn)
      put_ok(C.Seat.free(occ, acc, r, cap), C.Guest.id(g), r, rs, sn, acc,
        seat_ok(occ, acc, r, cap), h)
    case False{}:
      h

def plan_ok(+gs: +List<C.Guest>, +occ: +List<U32>, +q: C.Q, +rs: +List<C.Ride>, +sn: C.Stn,
  +acc: +List<C.Board>, +h: {Laws.all_boards_ok(rs, sn, acc) == True{} : Bool})
  -> {Laws.all_boards_ok(rs, sn, C.Boards.plan(gs, occ, q, rs, sn, acc)) == True{} : Bool}:
  match gs:
    case []:
      h
    case g <> rest:
      plan_ok(rest, occ, q, rs, sn, C.Boards.try(C.Guest.wants(g, q, rs, sn), g, occ, rs, sn, acc),
        try_ok(C.Guest.wants(g, q, rs, sn), g, occ, rs, sn, acc, h))

def Laws.capacity_respected(gs, occ, q, rs, stn):
  plan_ok(gs, occ, q, rs, stn, [], {==})

# Riders: a rider's tick is Guest.off, which sets st to 0 (got off) or 1
# (still riding) -- never 3 (gone) -- and the needs and clamp keep st.
def riders_one(+id: U32, +x: U32, +y: U32, +dir: U32, +tgt: U32, +tmr: U32, +cash: U32,
  +hu: U32, +th: U32, +en: U32, +na: U32, +ha: U32, +lk: U32, +mind: U32, +bl: U32, +q: C.Q, +rs: +List<C.Ride>,
  +t: U32, +pl: +List<C.Board>, +sn: C.Stn, +qs: +List<U32>)
  -> {C.Guest.gone(C.Guest.step(C.Guest{id, x, y, dir, 1, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl},
    q, rs, t, pl, sn, qs)) == False{} : Bool}:
  bcase(C.Guest.done(tmr, dir, tgt, rs, sn),
    b => {C.Guest.gone(C.Guest.clamp(C.Guest.needs(C.Guest.off(b, id, x, y, dir, tgt, tmr, cash,
      hu, th, en, na, ha, lk, mind, bl, q, rs, t), t))) == False{} : Bool},
    {==}, {==})

def Laws.riders_conserved(g, q, rs, t, plan, stn, qs, h):
  match g:
    case C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl}:
      %Equal.sym(U32, st, 1, h) : {C.Guest.gone(C.Guest.step(C.Guest{id, x, y, dir, _, tgt, tmr, cash,
        hu, th, en, na, ha, lk, mind, bl}, q, rs, t, plan, stn, qs)) == False{} : Bool}
      riders_one(id, x, y, dir, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl, q, rs, t, plan, stn, qs)

# Boarding only while loading: Guest.wants puts Ride.loading first, so a
# guest the plan seats has a loading ride; the plan keeps that for every
# board it adds (the same shape as capacity).
def load_put(+s: U32, +id: U32, +r: U32, +rs: +List<C.Ride>, +sn: C.Stn, +acc: +List<C.Board>,
  +hl: {C.Ride.loading(C.Rides.get(rs, r), sn) == True{} : Bool},
  +h: {Laws.all_boards_loading(rs, sn, acc) == True{} : Bool})
  -> {Laws.all_boards_loading(rs, sn, C.Boards.put(s, id, r, acc)) == True{} : Bool}:
  bcase_eq(U32.is_eq(s, C.NONE()),
    c => {Laws.all_boards_loading(rs, sn, Bool.pick(+List<C.Board>, c, acc, C.Board{id, r, s} <> acc)) == True{} : Bool},
    e => h,
    e => and_i(C.Ride.loading(C.Rides.get(rs, r), sn), Laws.all_boards_loading(rs, sn, acc), hl, h))

def load_try(+want: Bool, +g: C.Guest, +occ: +List<U32>, +rs: +List<C.Ride>, +sn: C.Stn,
  +acc: +List<C.Board>, +h: {Laws.all_boards_loading(rs, sn, acc) == True{} : Bool},
  hw: {want == True{} : Bool} -> {C.Ride.loading(C.Rides.get(rs, C.Guest.tgt(g)), sn) == True{} : Bool})
  -> {Laws.all_boards_loading(rs, sn, C.Boards.try(want, g, occ, rs, sn, acc)) == True{} : Bool}:
  match want:
    case True{}:
      +r = C.Guest.tgt(g)
      +cap = C.Ride.cap(C.Rides.get(rs, r), sn)
      load_put(C.Seat.free(occ, acc, r, cap), C.Guest.id(g), r, rs, sn, acc, hw({==}), h)
    case False{}:
      h

def load_plan(+gs: +List<C.Guest>, +occ: +List<U32>, +q: C.Q, +rs: +List<C.Ride>, +sn: C.Stn,
  +acc: +List<C.Board>, +h: {Laws.all_boards_loading(rs, sn, acc) == True{} : Bool})
  -> {Laws.all_boards_loading(rs, sn, C.Boards.plan(gs, occ, q, rs, sn, acc)) == True{} : Bool}:
  match gs:
    case []:
      h
    case g <> rest:
      match g:
        case C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl}:
          +gg = {C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl} : C.Guest}
          load_plan(rest, occ, q, rs, sn, C.Boards.try(C.Guest.wants(gg, q, rs, sn), gg, occ, rs, sn, acc),
            load_try(C.Guest.wants(gg, q, rs, sn), gg, occ, rs, sn, acc, h,
              e => and_l(C.Ride.loading(C.Rides.get(rs, tgt), sn),
                C.Guest.ready(C.Rides.get(rs, tgt), st, tgt, x, y, cash), e)))

def Laws.board_only_when_loading(gs, occ, q, rs, stn):
  load_plan(gs, occ, q, rs, stn, [], {==})

# Riding until unloading: a rider's tick is Guest.off(Guest.done(...)), and
# Guest.done is Ride.unloading; while that is False, Guest.off keeps st at 1.
def Laws.ride_until_unloading(g, q, rs, t, plan, stn, qs, h, u):
  match g:
    case C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl}:
      %Equal.sym(U32, st, 1, h) : {C.Guest.st(C.Guest.step(C.Guest{id, x, y, dir, _, tgt, tmr, cash,
        hu, th, en, na, ha, lk, mind, bl}, q, rs, t, plan, stn, qs)) == 1 : U32}
      %Equal.sym(Bool, C.Ride.unloading(C.Rides.get(rs, tgt), stn, dir, tmr), False{}, u)
        : {C.Guest.st(C.Guest.clamp(C.Guest.needs(C.Guest.off(_, id, x, y, dir, tgt, tmr, cash,
          hu, th, en, na, ha, lk, mind, bl, q, rs, t), t))) == 1 : U32}
      {==}

# Seats: every seat the plan hands out passed "not taken by acc" (P above),
# and the law's taken is the plan's own check, so each new board is distinct
# from all before it.
def taken_eq(+bs: +List<C.Board>, +r: U32, +s: U32)
  -> {Laws.taken(bs, r, s) == C.Boards.taken(bs, r, s) : Bool}:
  match bs:
    case []:
      {==}
    case b <> rest:
      match b:
        case C.Board{g, ride, seat}:
          %Equal.sym(Bool, Laws.taken(rest, r, s), C.Boards.taken(rest, r, s), taken_eq(rest, r, s))
            : {(U32.is_eq(ride, r) && U32.is_eq(seat, s)) || _
              == (U32.is_eq(ride, r) && U32.is_eq(seat, s)) || C.Boards.taken(rest, r, s) : Bool}
          {==}

def uniq_new(+s: U32, +r: U32, +cap: U32, +acc: +List<C.Board>, +e: {False{} == U32.is_eq(s, C.NONE()) : Bool},
  +hs: {U32.is_eq(s, C.NONE()) || (U32.is_lt(s, cap) && Bool.not(C.Boards.taken(acc, r, s))) == True{} : Bool})
  -> {Bool.not(Laws.taken(acc, r, s)) == True{} : Bool}:
  %Equal.sym(Bool, Laws.taken(acc, r, s), C.Boards.taken(acc, r, s), taken_eq(acc, r, s))
    : {Bool.not(_) == True{} : Bool}
  and_r(U32.is_lt(s, cap), Bool.not(C.Boards.taken(acc, r, s)),
    or_f(U32.is_eq(s, C.NONE()), U32.is_lt(s, cap) && Bool.not(C.Boards.taken(acc, r, s)), e, hs))

def uniq_put(+s: U32, +id: U32, +r: U32, +cap: U32, +acc: +List<C.Board>,
  +hs: {U32.is_eq(s, C.NONE()) || (U32.is_lt(s, cap) && Bool.not(C.Boards.taken(acc, r, s))) == True{} : Bool},
  +h: {Laws.distinct(acc) == True{} : Bool})
  -> {Laws.distinct(C.Boards.put(s, id, r, acc)) == True{} : Bool}:
  bcase_eq(U32.is_eq(s, C.NONE()),
    c => {Laws.distinct(Bool.pick(+List<C.Board>, c, acc, C.Board{id, r, s} <> acc)) == True{} : Bool},
    e => h,
    e => and_i(Bool.not(Laws.taken(acc, r, s)), Laws.distinct(acc), uniq_new(s, r, cap, acc, e, hs), h))

def uniq_try(+want: Bool, +g: C.Guest, +occ: +List<U32>, +rs: +List<C.Ride>, +sn: C.Stn,
  +acc: +List<C.Board>, +h: {Laws.distinct(acc) == True{} : Bool})
  -> {Laws.distinct(C.Boards.try(want, g, occ, rs, sn, acc)) == True{} : Bool}:
  match want:
    case True{}:
      +r = C.Guest.tgt(g)
      +cap = C.Ride.cap(C.Rides.get(rs, r), sn)
      uniq_put(C.Seat.free(occ, acc, r, cap), C.Guest.id(g), r, cap, acc,
        seat_ok(occ, acc, r, cap), h)
    case False{}:
      h

def uniq_plan(+gs: +List<C.Guest>, +occ: +List<U32>, +q: C.Q, +rs: +List<C.Ride>, +sn: C.Stn,
  +acc: +List<C.Board>, +h: {Laws.distinct(acc) == True{} : Bool})
  -> {Laws.distinct(C.Boards.plan(gs, occ, q, rs, sn, acc)) == True{} : Bool}:
  match gs:
    case []:
      h
    case g <> rest:
      uniq_plan(rest, occ, q, rs, sn, C.Boards.try(C.Guest.wants(g, q, rs, sn), g, occ, rs, sn, acc),
        uniq_try(C.Guest.wants(g, q, rs, sn), g, occ, rs, sn, acc, h))

def Laws.seats_unique(gs, occ, q, rs, stn):
  uniq_plan(gs, occ, q, rs, stn, [], {==})

# Purchases: Guest.wants puts Guest.affords (price <= gold) right after
# Ride.loading, and Guest.board pays with Guest.pay, which takes exactly the
# price whenever it is affordable.
def Laws.purchase_is_transfer(g, q, rs, seat, stn, h):
  match g:
    case C.Guest{id, x, y, dir, st, tgt, tmr, cash, hu, th, en, na, ha, lk, mind, bl}:
      +rd = C.Rides.get(rs, tgt)
      +hp = and_l(C.Guest.affords(rd, cash), C.Guest.at_ride(rd, st, tgt, x, y),
        and_r(C.Ride.loading(rd, stn), C.Guest.ready(rd, st, tgt, x, y, cash), h))
      %Equal.sym(Bool, U32.is_le(C.Ride.price(rd), cash), True{}, hp)
        : {C.sel(_, (cash - C.Ride.price(rd) : U32), 0) == (cash - C.Ride.price(rd) : U32) : U32}
      {==}

# Prices: every price a step can make passes through Price.cap (or keeps an
# old price); the entry fee through Fee.cap.
def cap_ok(+v: U32) -> {U32.is_le(C.Price.cap(v), 20) == True{} : Bool}:
  bcase_eq(U32.is_le(v, 20), c => {U32.is_le(C.sel(c, v, 20), 20) == True{} : Bool},
    e => Equal.sym(Bool, True{}, U32.is_le(v, 20), e), e => {==})

def fee_cap_ok(+v: U32) -> {U32.is_le(C.Fee.cap(v), 40) == True{} : Bool}:
  bcase_eq(U32.is_le(v, 40), c => {U32.is_le(C.sel(c, v, 40), 40) == True{} : Bool},
    e => Equal.sym(Bool, True{}, U32.is_le(v, 40), e), e => {==})

def tick_ok(+rs: +List<C.Ride>, +idx: U32, +q: C.Q, +ps: +List<C.Track>, +occ: +List<U32>,
  +plan: +List<C.Board>, +qt: +List<U32>, +fr: Bool, +t: U32, +fx: +List<U32>, +h: {Laws.prices_ok(rs) == True{} : Bool})
  -> {Laws.prices_ok(C.Rides.tick(rs, idx, q, ps, occ, plan, qt, fr, t, fx)) == True{} : Bool}:
  match rs:
    case []:
      {==}
    case r <> rest:
      match r:
        case C.Ride{kind, x, y, w, hh, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear}:
          and_i(U32.is_le(price, 20), Laws.prices_ok(C.Rides.tick(rest, (idx + 1 : U32), q, ps, occ, plan, qt, fr, t, fx)),
            and_l(U32.is_le(price, 20), Laws.prices_ok(rest), h),
            tick_ok(rest, (idx + 1 : U32), q, ps, occ, plan, qt, fr, t, fx, and_r(U32.is_le(price, 20), Laws.prices_ok(rest), h)))

def coaster_ok(+rs: +List<C.Ride>, +k: U32, +op: U32, +h: {Laws.prices_ok(rs) == True{} : Bool})
  -> {Laws.prices_ok(C.Rides.coaster(rs, k, op)) == True{} : Bool}:
  match rs:
    case []:
      {==}
    case r <> rest:
      match r:
        case C.Ride{kind, x, y, w, hh, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear}:
          and_i(U32.is_le(price, 20), Laws.prices_ok(C.Rides.coaster(rest, k, op)),
            and_l(U32.is_le(price, 20), Laws.prices_ok(rest), h),
            coaster_ok(rest, k, op, and_r(U32.is_le(price, 20), Laws.prices_ok(rest), h)))

def set_ok(+rs: +List<C.Ride>, +i: U32, +op: U32, +h: {Laws.prices_ok(rs) == True{} : Bool})
  -> {Laws.prices_ok(C.Rides.set(rs, i, op)) == True{} : Bool}:
  match rs:
    case []:
      {==}
    case r <> rest:
      match r:
        case C.Ride{kind, x, y, w, hh, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear}:
          +rr = {C.Ride{kind, x, y, w, hh, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} : C.Ride}
          +tail = set_ok(rest, (i - 1 : U32), op, and_r(U32.is_le(price, 20), Laws.prices_ok(rest), h))
          bcase(U32.is_eq(i, 0),
            c => {Laws.prices_ok(Bool.pick(C.Ride, c, C.Ride.set(rr, op), rr) <> C.Rides.set(rest, (i - 1 : U32), op)) == True{} : Bool},
            and_i(U32.is_le(C.Ride.price(C.Ride.set(rr, op)), 20), Laws.prices_ok(C.Rides.set(rest, (i - 1 : U32), op)),
              cap_ok(C.sel(U32.is_eq(op, 1), (price + 1 : U32), C.sel(U32.is_eq(op, 2), C.sub0(price, 1), price))), tail),
            and_i(U32.is_le(price, 20), Laws.prices_ok(C.Rides.set(rest, (i - 1 : U32), op)),
              and_l(U32.is_le(price, 20), Laws.prices_ok(rest), h), tail))

def kill_ok(+rs: +List<C.Ride>, +i: U32, +h: {Laws.prices_ok(rs) == True{} : Bool})
  -> {Laws.prices_ok(C.Rides.kill(rs, i)) == True{} : Bool}:
  match rs:
    case []:
      {==}
    case r <> rest:
      match r:
        case C.Ride{kind, x, y, w, hh, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear}:
          +rr = {C.Ride{kind, x, y, w, hh, price, open, ph, tm, ent, ex, qlen, wmin, wmax, total, earned, born, rate, wear} : C.Ride}
          +hp = and_l(U32.is_le(price, 20), Laws.prices_ok(rest), h)
          +tail = kill_ok(rest, (i - 1 : U32), and_r(U32.is_le(price, 20), Laws.prices_ok(rest), h))
          bcase(U32.is_eq(i, 0),
            c => {Laws.prices_ok(Bool.pick(C.Ride, c, C.Ride.killed(rr), rr) <> C.Rides.kill(rest, (i - 1 : U32))) == True{} : Bool},
            and_i(U32.is_le(price, 20), Laws.prices_ok(C.Rides.kill(rest, (i - 1 : U32))), hp, tail),
            and_i(U32.is_le(price, 20), Laws.prices_ok(C.Rides.kill(rest, (i - 1 : U32))), hp, tail))

def app_ok(+rs: +List<C.Ride>, +n: C.Ride, +h: {Laws.prices_ok(rs) == True{} : Bool},
  +hn: {U32.is_le(C.Ride.price(n), 20) == True{} : Bool})
  -> {Laws.prices_ok(List.append(&2, C.Ride, rs, [n])) == True{} : Bool}:
  match rs:
    case []:
      and_i(U32.is_le(C.Ride.price(n), 20), True{}, hn, {==})
    case r <> rest:
      and_i(U32.is_le(C.Ride.price(r), 20), Laws.prices_ok(List.append(&2, C.Ride, rest, [n])),
        and_l(U32.is_le(C.Ride.price(r), 20), Laws.prices_ok(rest), h),
        app_ok(rest, n, and_r(U32.is_le(C.Ride.price(r), 20), Laws.prices_ok(rest), h), hn))

def new_ok(+k: U32, +x: U32, +y: U32, +s: U32, +o: U32, +t: U32)
  -> {U32.is_le(C.Ride.price(C.Ride.new(k, x, y, s, o, t)), 20) == True{} : Bool}:
  cap_ok(C.Ride.fee(k))

def build_ok(+ok: Bool, +q: C.Q, +rs: +List<C.Ride>, +tool: U32, +x: U32, +y: U32, +time: U32, +nt: U32,
  +h: {Laws.prices_ok(rs) == True{} : Bool})
  -> {Laws.prices_ok(C.Build.rides(ok, q, rs, tool, x, y, time, nt)) == True{} : Bool}:
  match ok:
    case True{}:
      +t = C.Land.get(q, x, y)
      +k = C.Tool.kind(tool)
      +s = C.Ride.size(k)
      +coast = Bool.pick(+List<C.Ride>, U32.is_eq(tool, 10), List.append(&2, C.Ride, rs, [C.Ride.coaster(x, y, nt, time)]), rs)
      +add = Bool.pick(+List<C.Ride>, Bool.not(U32.is_eq(k, 0)),
        List.append(&2, C.Ride, rs, [C.Ride.new(k, x, y, s, 1, time)]), coast)
      bcase(U32.is_eq(tool, 9) && U32.is_eq(C.Tile.obj(t), 3),
        c => {Laws.prices_ok(Bool.pick(+List<C.Ride>, c, C.Rides.kill(rs, C.Tile.a(t)), add)) == True{} : Bool},
        kill_ok(rs, C.Tile.a(t), h),
        bcase(Bool.not(U32.is_eq(k, 0)),
          c => {Laws.prices_ok(Bool.pick(+List<C.Ride>, c, List.append(&2, C.Ride, rs, [C.Ride.new(k, x, y, s, 1, time)]), coast)) == True{} : Bool},
          app_ok(rs, C.Ride.new(k, x, y, s, 1, time), h, new_ok(k, x, y, s, 1, time)),
          bcase(U32.is_eq(tool, 10),
            c => {Laws.prices_ok(Bool.pick(+List<C.Ride>, c, List.append(&2, C.Ride, rs, [C.Ride.coaster(x, y, nt, time)]), rs)) == True{} : Bool},
            app_ok(rs, C.Ride.coaster(x, y, nt, time), h, cap_ok(C.Ride.fee(5))),
            h)))
    case False{}:
      h

def pb_go(+a: C.Act, +map: C.Q, +guests: +List<C.Guest>, +rides: +List<C.Ride>, +track: +List<C.Track>,
  +cash: U32, +time: U32, +nid: U32, +fee: U32, +loan: U32, +rating: U32, +now: +List<U32>,
  +last: +List<U32>, +hist: +List<U32>, +res: U32, +mess: +List<U32>, +staff: +List<C.Staff>,
  +h: {Laws.prices_ok(rides) && U32.is_le(fee, 40) == True{} : Bool})
  -> {Laws.park_prices_ok(C.Out.park(C.Park.step(C.Park{map, guests, rides, track, cash, time, nid,
    C.Fin{fee, loan, rating, now, last, hist, res}, mess, staff}, a))) == True{} : Bool}:
  match a:
    case C.Tick{}:
      +sn = C.Stn.all(track)
      +occ = C.Occ.table(guests, rides, sn)
      +pl = C.Boards.plan(guests, occ, map, rides, sn, [])
      +fr = U32.is_eq((time .&. 15 : U32), 0)
      +qt = C.Qlen.fill_if(fr, guests, map, C.len32(C.Ride, rides))
      and_i(Laws.prices_ok(C.Rides.tick(rides, 0, map, track, occ, pl, qt, fr, time, C.Staff.fixing(staff))), U32.is_le(fee, 40),
        tick_ok(rides, 0, map, track, occ, pl, qt, fr, time, C.Staff.fixing(staff), and_l(Laws.prices_ok(rides), U32.is_le(fee, 40), h)), and_r(Laws.prices_ok(rides), U32.is_le(fee, 40), h))
    case C.Build{tool, x, y, v}:
      and_i(Laws.prices_ok(C.Build.rides(C.Build.ok(map, track, cash, tool, x, y), map, rides, tool, x, y, time, C.len32(C.Track, track))),
        U32.is_le(fee, 40), build_ok(C.Build.ok(map, track, cash, tool, x, y), map, rides, tool, x, y, time, C.len32(C.Track, track), and_l(Laws.prices_ok(rides), U32.is_le(fee, 40), h)), and_r(Laws.prices_ok(rides), U32.is_le(fee, 40), h))
    case C.TrackOp{op}:
      +k = C.TrackOp.k(op)
      +code = (op .&. 31 : U32)
      +trk = C.Tracks.get(track, k)
      +ok = C.TrackOp.ok(map, trk, cash, code) && (k < C.len32(C.Track, track) : U32)
      +trk2 = C.Track.op(trk, code, C.TrackOp.idx(op), ok)
      +fl = C.sel(ok && U32.is_eq(code, 27), 2, C.sel(C.Track.open(trk2) && C.Test.passed(C.Track.stats(trk2)), 1, 0))
      and_i(Laws.prices_ok(C.Rides.coaster(rides, k, fl)), U32.is_le(fee, 40),
        coaster_ok(rides, k, fl, and_l(Laws.prices_ok(rides), U32.is_le(fee, 40), h)), and_r(Laws.prices_ok(rides), U32.is_le(fee, 40), h))
    case C.RideOp{ride, op}:
      and_i(Laws.prices_ok(C.Rides.set(rides, ride, op)), U32.is_le(fee, 40), set_ok(rides, ride, op, and_l(Laws.prices_ok(rides), U32.is_le(fee, 40), h)), and_r(Laws.prices_ok(rides), U32.is_le(fee, 40), h))
    case C.ParkOp{op}:
      +f2 = C.sel(U32.is_eq(op, 0), (fee + 1 : U32), C.sel(U32.is_eq(op, 1), C.sub0(fee, 1), fee))
      and_i(Laws.prices_ok(rides), U32.is_le(C.Fee.cap(f2), 40), and_l(Laws.prices_ok(rides), U32.is_le(fee, 40), h), fee_cap_ok(f2))

def Laws.prices_bounded(p, a, h):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff}:
      match fin:
        case C.Fin{fee, loan, rating, now, last, hist, res}:
          pb_go(a, map, guests, rides, track, cash, time, nid, fee, loan, rating, now, last, hist, res, mess, staff, h)

# Litter: a tick's mess is the drops put in front of what wasn't swept, and
# the kept and swept pieces split the old mess between them (as the guests
# who stay and leave do); other steps leave the mess alone.
def mlen_app(+xs: +List<U32>, +ys: +List<U32>)
  -> {Laws.mcount(List.append(&2, U32, xs, ys)) == Nat.add(Laws.mcount(xs), Laws.mcount(ys)) : Nat}:
  match xs:
    case []:
      {==}
    case x <> r:
      %mlen_app(r, ys) : {1n+Laws.mcount(List.append(&2, U32, r, ys)) == 1n+_ : Nat}
      {==}

def mpart_t(+r: +List<U32>, +ss: +List<C.Staff>,
  ih: {Nat.add(Laws.mcount(C.Mess.kept(r, ss)), Laws.mcount(C.Mess.swept(r, ss))) == Laws.mcount(r) : Nat})
  -> {Nat.add(Laws.mcount(C.Mess.kept(r, ss)), 1n+Laws.mcount(C.Mess.swept(r, ss))) == 1n+Laws.mcount(r) : Nat}:
  +sl = Nat.add(Laws.mcount(C.Mess.kept(r, ss)), 1n+Laws.mcount(C.Mess.swept(r, ss)))
  %ih : {sl == 1n+_ : Nat}
  %add_succ_r(Laws.mcount(C.Mess.kept(r, ss)), Laws.mcount(C.Mess.swept(r, ss))) : {sl == _ : Nat}
  {==}

def mpart_f(+r: +List<U32>, +ss: +List<C.Staff>,
  ih: {Nat.add(Laws.mcount(C.Mess.kept(r, ss)), Laws.mcount(C.Mess.swept(r, ss))) == Laws.mcount(r) : Nat})
  -> {Nat.add(1n+Laws.mcount(C.Mess.kept(r, ss)), Laws.mcount(C.Mess.swept(r, ss))) == 1n+Laws.mcount(r) : Nat}:
  %ih : {1n+Nat.add(Laws.mcount(C.Mess.kept(r, ss)), Laws.mcount(C.Mess.swept(r, ss))) == 1n+_ : Nat}
  {==}

def mpart(+ms: +List<U32>, +ss: +List<C.Staff>)
  -> {Nat.add(Laws.mcount(C.Mess.kept(ms, ss)), Laws.mcount(C.Mess.swept(ms, ss))) == Laws.mcount(ms) : Nat}:
  match ms:
    case []:
      {==}
    case m <> r:
      bcase(C.Mess.sweeps(m, ss), b => {Nat.add(Laws.mcount(C.Mess.put(Bool.not(b), m, C.Mess.kept(r, ss))),
        Laws.mcount(C.Mess.put(b, m, C.Mess.swept(r, ss)))) == 1n+Laws.mcount(r) : Nat},
        mpart_t(r, ss, mpart(r, ss)), mpart_f(r, ss, mpart(r, ss)))

def mc_tick(+d: +List<U32>, +ms: +List<U32>, +ss: +List<C.Staff>)
  -> {Nat.add(Laws.mcount(List.append(&2, U32, d, C.Mess.kept(ms, ss))), Laws.mcount(C.Mess.swept(ms, ss)))
    == Nat.add(Laws.mcount(ms), Laws.mcount(d)) : Nat}:
  +k = C.Mess.kept(ms, ss)
  +sw = C.Mess.swept(ms, ss)
  +lhs = Nat.add(Laws.mcount(List.append(&2, U32, d, k)), Laws.mcount(sw))
  %add_comm(Laws.mcount(d), Laws.mcount(ms)) : {lhs == _ : Nat}
  %mpart(ms, ss) : {lhs == Nat.add(Laws.mcount(d), _) : Nat}
  %add_assoc(Laws.mcount(d), Laws.mcount(k), Laws.mcount(sw)) : {lhs == _ : Nat}
  %mlen_app(d, k) : {lhs == Nat.add(_, Laws.mcount(sw)) : Nat}
  {==}

def Laws.litter_accounted(p, a):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff}:
      match a:
        case C.Tick{}:
          +sn = C.Stn.all(track)
          +pl = C.Boards.plan(guests, C.Occ.table(guests, rides, sn), map, rides, sn, [])
          mc_tick(C.Mess.drops(C.Mess.events(guests, pl, map, time), (C.len32(U32, mess) < 600 : U32)), mess, staff)
        case C.Build{tool, x, y, v}:
          {==}
        case C.TrackOp{op}:
          {==}
        case C.RideOp{ride, op}:
          {==}
        case C.ParkOp{op}:
          {==}

# Wages
# -----
# Only one entry any step books has kind 11: the monthly wage bill in
# Ledger.tick. Sales and fees are gains; upkeep (2), construction (3),
# loans repaid (9) and interest (10) are other kinds. So the wage list of a
# step's ledger is that bill, or nothing.
def wl_upkeep(+rs: +List<C.Ride>) -> {Laws.wage_list(C.Ledger.upkeep(rs)) == [] : List<U32>}:
  match rs:
    case []:
      {==}
    case r <> rest:
      bcase(Bool.not(U32.is_eq(C.Ride.kind(r), 0)),
        b => {Laws.wage_list(C.Ledger.put(b, C.Spend{2, C.Ride.upkeep(C.Ride.kind(r))}, C.Ledger.upkeep(rest))) == [] : List<U32>},
        wl_upkeep(rest), wl_upkeep(rest))

def wl_sales(+pl: +List<C.Board>, +rs: +List<C.Ride>, +ys: +List<C.Txn>)
  -> {Laws.wage_list(List.append(&2, C.Txn, C.Ledger.sales(pl, rs), ys)) == Laws.wage_list(ys) : List<U32>}:
  match pl:
    case []:
      {==}
    case b <> rest:
      match b:
        case C.Board{g, ride, seat}:
          wl_sales(rest, rs, ys)

# the bill itself: there when there is one
def wl_bill(+w: Bool, +v: U32, +rs: +List<C.Ride>)
  -> {Laws.wage_list(C.Ledger.put(w, C.Spend{11, v}, C.Ledger.upkeep(rs))) == Bool.pick(List<U32>, w, [v], []) : List<U32>}:
  bcase(w, b => {Laws.wage_list(C.Ledger.put(b, C.Spend{11, v}, C.Ledger.upkeep(rs))) == Bool.pick(List<U32>, b, [v], []) : List<U32>},
    %Equal.sym(List<U32>, Laws.wage_list(C.Ledger.upkeep(rs)), [], wl_upkeep(rs)) : {v <> _ == [v] : List<U32>}
    {==},
    wl_upkeep(rs))

def wl_mid(+cr: Bool, +rc: U32, +w: Bool, +v: U32, +rs: +List<C.Ride>)
  -> {Laws.wage_list(C.Ledger.put(cr, C.Spend{12, rc}, C.Ledger.put(w, C.Spend{11, v}, C.Ledger.upkeep(rs))))
      == Bool.pick(List<U32>, w, [v], []) : List<U32>}:
  bcase(cr, b => {Laws.wage_list(C.Ledger.put(b, C.Spend{12, rc}, C.Ledger.put(w, C.Spend{11, v}, C.Ledger.upkeep(rs))))
      == Bool.pick(List<U32>, w, [v], []) : List<U32>},
    wl_bill(w, v, rs), wl_bill(w, v, rs))

def wl_month(+c: Bool, +i: U32, +cr: Bool, +rc: U32, +w: Bool, +v: U32, +rs: +List<C.Ride>)
  -> {Laws.wage_list(C.Ledger.put(c, C.Spend{10, i}, C.Ledger.put(cr, C.Spend{12, rc}, C.Ledger.put(w, C.Spend{11, v}, C.Ledger.upkeep(rs)))))
      == Bool.pick(List<U32>, w, [v], []) : List<U32>}:
  bcase(c, b => {Laws.wage_list(C.Ledger.put(b, C.Spend{10, i}, C.Ledger.put(cr, C.Spend{12, rc}, C.Ledger.put(w, C.Spend{11, v}, C.Ledger.upkeep(rs)))))
      == Bool.pick(List<U32>, w, [v], []) : List<U32>},
    wl_mid(cr, rc, w, v, rs), wl_mid(cr, rc, w, v, rs))

def wl_fees(+c: Bool, +f: U32, +ys: +List<C.Txn>)
  -> {Laws.wage_list(C.Ledger.put(c, C.Gain{7, f}, ys)) == Laws.wage_list(ys) : List<U32>}:
  bcase(c, b => {Laws.wage_list(C.Ledger.put(b, C.Gain{7, f}, ys)) == Laws.wage_list(ys) : List<U32>}, {==}, {==})

def wl_tick(+gs: +List<C.Guest>, +rs: +List<C.Ride>, +t: U32, +pl: +List<C.Board>, +narr: U32, +f: C.Fin,
  +ss: +List<C.Staff>)
  -> {Laws.wage_list(C.Ledger.tick(gs, rs, t, pl, narr, f, ss))
      == Bool.pick(List<U32>, U32.is_eq((t % 3600 : U32), 0) && (t > 0 : U32) && Bool.not(U32.is_eq(C.Staff.wages(ss), 0)),
        [C.Staff.wages(ss)], []) : List<U32>}:
  +fees = (narr * U32.min(C.Fin.fee(f), 40) : U32)
  +i = (C.Fin.loan(f) / 80 : U32)
  +w = Bool.not(U32.is_eq(C.Staff.wages(ss), 0))
  +rc = C.Res.cost(C.Fin.res(f))
  +inner = C.Ledger.put(Bool.not(U32.is_eq(i, 0)), C.Spend{10, i}, C.Ledger.put(Bool.not(U32.is_eq(rc, 0)), C.Spend{12, rc},
    C.Ledger.put(w, C.Spend{11, C.Staff.wages(ss)}, C.Ledger.upkeep(rs))))
  bcase(U32.is_eq((t % 3600 : U32), 0) && (t > 0 : U32),
    m => {Laws.wage_list(C.Ledger.put(Bool.not(U32.is_eq(fees, 0)), C.Gain{7, fees},
        List.append(&2, C.Txn, C.Ledger.sales(pl, rs), Bool.pick(+List<C.Txn>, m, inner, []))))
      == Bool.pick(List<U32>, m && w, [C.Staff.wages(ss)], []) : List<U32>},
    %Equal.sym(List<U32>, Laws.wage_list(C.Ledger.put(Bool.not(U32.is_eq(fees, 0)), C.Gain{7, fees}, List.append(&2, C.Txn, C.Ledger.sales(pl, rs), inner))),
        Laws.wage_list(List.append(&2, C.Txn, C.Ledger.sales(pl, rs), inner)),
        wl_fees(Bool.not(U32.is_eq(fees, 0)), fees, List.append(&2, C.Txn, C.Ledger.sales(pl, rs), inner))) : {_ == Bool.pick(List<U32>, w, [C.Staff.wages(ss)], []) : List<U32>}
    %Equal.sym(List<U32>, Laws.wage_list(List.append(&2, C.Txn, C.Ledger.sales(pl, rs), inner)), Laws.wage_list(inner),
        wl_sales(pl, rs, inner)) : {_ == Bool.pick(List<U32>, w, [C.Staff.wages(ss)], []) : List<U32>}
    wl_month(Bool.not(U32.is_eq(i, 0)), i, Bool.not(U32.is_eq(rc, 0)), rc, w, C.Staff.wages(ss), rs),
    %Equal.sym(List<U32>, Laws.wage_list(C.Ledger.put(Bool.not(U32.is_eq(fees, 0)), C.Gain{7, fees}, List.append(&2, C.Txn, C.Ledger.sales(pl, rs), []))),
        Laws.wage_list(List.append(&2, C.Txn, C.Ledger.sales(pl, rs), [])),
        wl_fees(Bool.not(U32.is_eq(fees, 0)), fees, List.append(&2, C.Txn, C.Ledger.sales(pl, rs), []))) : {_ == [] : List<U32>}
    wl_sales(pl, rs, []))

def wl_build(+ok: Bool, +q: C.Q, +rs: +List<C.Ride>, +tool: U32, +x: U32, +y: U32)
  -> {Laws.wage_list(C.Build.ledger(ok, q, rs, tool, x, y)) == [] : List<U32>}:
  match ok:
    case True{}:
      bcase(U32.is_eq(tool, 9),
        b => {Laws.wage_list(Bool.pick(+List<C.Txn>, b, [C.Gain{4, C.Build.refund(q, rs, x, y)}], [C.Spend{3, C.Build.cost(tool)}])) == [] : List<U32>},
        {==}, {==})
    case False{}:
      {==}

def wl_track(+ok: Bool, +op: U32, +last: U32, +refund: U32) -> {Laws.wage_list(C.TrackOp.ledger(ok, op, last, refund)) == [] : List<U32>}:
  match ok:
    case True{}:
      +cut = Bool.pick(+List<C.Txn>, U32.is_eq(op, 26) || U32.is_eq(op, 27), [C.Gain{4, refund}], [])
      +del = Bool.pick(+List<C.Txn>, U32.is_eq(op, 7), [C.Gain{4, (C.Piece.cost(last) >> 1n : U32)}], cut)
      bcase(C.Piece.adds(op),
        b => {Laws.wage_list(Bool.pick(+List<C.Txn>, b, [C.Spend{3, C.Piece.cost(op)}], del)) == [] : List<U32>},
        {==},
        bcase(U32.is_eq(op, 7), b => {Laws.wage_list(Bool.pick(+List<C.Txn>, b, [C.Gain{4, (C.Piece.cost(last) >> 1n : U32)}], cut)) == [] : List<U32>},
          {==},
          bcase(U32.is_eq(op, 26) || U32.is_eq(op, 27), b => {Laws.wage_list(Bool.pick(+List<C.Txn>, b, [C.Gain{4, refund}], [])) == [] : List<U32>},
            {==}, {==})))
    case False{}:
      {==}

def wl_loans(+b: Bool, +r: Bool)
  -> {Laws.wage_list(Bool.pick(+List<C.Txn>, b, [C.Gain{8, 1000}], Bool.pick(+List<C.Txn>, r, [C.Spend{9, 1000}], []))) == [] : List<U32>}:
  bcase(b, c => {Laws.wage_list(Bool.pick(+List<C.Txn>, c, [C.Gain{8, 1000}], Bool.pick(+List<C.Txn>, r, [C.Spend{9, 1000}], []))) == [] : List<U32>},
    {==},
    bcase(r, c => {Laws.wage_list(Bool.pick(+List<C.Txn>, c, [C.Spend{9, 1000}], [])) == [] : List<U32>}, {==}, {==}))

def Laws.wages_booked(p, a):
  match p:
    case C.Park{map, guests, rides, track, cash, time, nid, fin, mess, staff}:
      match a:
        case C.Tick{}:
          +sn = C.Stn.all(track)
          +pl = C.Boards.plan(guests, C.Occ.table(guests, rides, sn), map, rides, sn, [])
          wl_tick(guests, rides, time, pl, C.len32(C.Guest, C.Guests.arrivals(guests, rides, time, nid, fin)), fin, staff)
        case C.Build{tool, x, y, v}:
          wl_build(C.Build.ok(map, track, cash, tool, x, y), map, rides, tool, x, y)
        case C.TrackOp{op}:
          wl_track(C.TrackOp.ok(map, C.Tracks.get(track, C.TrackOp.k(op)), cash, (op .&. 31 : U32)) && (C.TrackOp.k(op) < C.len32(C.Track, track) : U32), (op .&. 31 : U32),
            C.Piece.kind(C.Pieces.last(C.Track.pieces(C.Tracks.get(track, C.TrackOp.k(op))))),
            C.TrackOp.refund(C.Tracks.get(track, C.TrackOp.k(op)), (op .&. 31 : U32), C.TrackOp.idx(op)))
        case C.RideOp{ride, op}:
          {==}
        case C.ParkOp{op}:
          wl_loans(U32.is_eq(op, 2) && (C.Fin.loan(fin) + 1000 <= 20000 : U32),
            U32.is_eq(op, 3) && (C.Fin.loan(fin) >= 1000 : U32) && Bool.not(C.neg(cash)) && (cash >= 1000 : U32))
