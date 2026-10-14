# raster: the frame, and the loop that fills it.
#
# The quadtree is the same four-way split the ray-marching version used -- it
# is still the only place work is divided -- but the leaf is no longer one
# pixel.  A leaf owns a tile of TILE x TILE pixels and the triangles that
# overlap it, filtered down the tree: a node hands each child only the
# triangles whose screen bounding box reaches into it.  That filtering is what
# makes a software rasteriser pay for itself.  A ray marcher evaluates the
# whole scene field once per march step per pixel; here a triangle is tested
# only by the pixels of the tiles it covers, and a pixel is shaded exactly
# once, by the triangle that won it.
#
# Each pixel walks its tile's triangle list and keeps the nearest fragment.
# Walking it once per pixel means the list is used more than once, which in
# Bend is a `+` and a real dup -- cheap because the tile's list is short and
# hot, but it is why the tile is 8x8 and not one pixel: the list has to be
# small enough that duplicating it 64 times costs less than the alternative, a
# much deeper tree whose filtering would touch every triangle at every level.
import Base
import ./color.bend as Color
import ./geo.bend as Geo
import ./rt.bend as Rt
import ./ride.bend as Ride
import ./shade.bend as Shade
import ./trk.bend as Trk


# Everything a leaf needs: the camera, the lights, the headlight switch and the
# clock, so the recursion does not carry five parameters.
type Env is Data:
  Env{cam: Rt.VCam, lts: Shade.Lights, head_on: Bool, t: F32}


# A tile of packed pixels, or four children.  Deliberately not Base's `Image`:
# a leaf here is a tile, not one pixel, because a pixel is far too small a unit
# to carry a triangle list.
type Frame is Data:
  Tile{px: List<&2, U32>}
  Quad{a: Frame, b: Frame, c: Frame, d: Frame}


# The nearest fragment so far, with its depth kept beside it: the fold has to
# compare a candidate against the winner, and reading `iw` out of a `Frag`
# would consume it.  `Bnil` means nothing has been hit yet.
type Best is Data:
  Bnil{}
  Best{iw: F32, frag: Rt.Frag}


# A pixel's barycentric weights and depth, or a miss.
type Hit is Data:
  Miss{}
  Hit{la: F32, lb: F32, lc: F32, iw: F32}


def Tile.side() -> Nat:
  8n


def Tile.levels() -> Nat:
  3n


def Nat.tile.levels(+d: Nat) -> Nat:
  Nat.sub(d, Tile.levels())


# ---- filtering -------------------------------------------------------
# A triangle survives a node only if its screen bounding box reaches into it.
# The box is a field of the projected triangle (Rt.Tri.boxed), so the test is
# one record and four comparisons rather than a rebuild from three vertices.
#
# ---- and the two triangles the box cannot decide ---------------------
# A box is a poor proxy for one shape only: the triangle the near plane cut.
# Its surviving vertex sits at w = near, where the perspective divide sends the
# screen coordinate to roughly 1e4, so a 3 m carriage wall becomes a box
# 17,000 pixels wide.  Such a box reaches every node of the tree; at the frozen
# camera 44 of them were in 62% of the leaf lists, and every pixel of those
# leaves tested 44 triangles that covered none of them.  For a triangle whose
# box is wide in absolute terms -- far wider than any tile -- the box test is
# therefore followed by the triangle's own three edge functions at the node's
# four corners: a node is dropped only when one edge's half-plane contains the
# whole rectangle, which is conservative and cannot drop a covered pixel.
#
# The cost is three edge functions at four corners, and it is paid only by
# triangles whose box is wider than Tri.wide() pixels -- a few dozen, whose
# node count the same test then removes 99% of.
def Tri.wide() -> F32:
  64.0


def Tri.e0(+ax: F32, +ay: F32, +bx: F32, +by: F32, +fx: F32, +fy: F32) -> F32:
  ((bx - ax) * (fy - ay) - (by - ay) * (fx - ax) : F32)


# The edge value scaled by the triangle's area sign, so that "inside" is
# ">= 0" for every edge without a branch on the winding.
def Tri.ec(+ax: F32, +ay: F32, +bx: F32, +by: F32, +fx: F32, +fy: F32,
  +sum: F32) -> F32:
  (Tri.e0(ax, ay, bx, by, fx, fy) * sum : F32)


def Tri.max4(+a: F32, +b: F32, +c: F32, +d: F32) -> F32:
  F32.max(F32.max(a, b), F32.max(c, d))


# One edge: its largest scaled value over the node's rectangle.  The edge
# function is affine, so the maximum over a rectangle is at a corner.
def Tri.edge.mx(+ax: F32, +ay: F32, +bx: F32, +by: F32, +x0: F32, +y0: F32,
  +x1: F32, +y1: F32, +sum: F32) -> F32:
  Tri.max4(Tri.ec(ax, ay, bx, by, x0, y0, sum),
    Tri.ec(ax, ay, bx, by, x1, y0, sum),
    Tri.ec(ax, ay, bx, by, x0, y1, sum),
    Tri.ec(ax, ay, bx, by, x1, y1, sum))


# True when one of the triangle's three edges excludes the whole rectangle: the
# edge's scaled value is negative at every corner, so its half-plane misses the
# box and no pixel of the node can be inside the triangle.
def Tri.keep.edges(+x0: F32, +y0: F32, +x1: F32, +y1: F32, +sx1: F32,
  +sy1: F32, +sx2: F32, +sy2: F32, +sx3: F32, +sy3: F32) -> Bool:
  +sum = (Tri.e0(sx1, sy1, sx2, sy2, x0, y0)
    + Tri.e0(sx2, sy2, sx3, sy3, x0, y0)
    + Tri.e0(sx3, sy3, sx1, sy1, x0, y0) : F32)
  Bool.or(F32.is_lt(Tri.edge.mx(sx1, sy1, sx2, sy2, x0, y0, x1, y1, sum), 0.0),
    Bool.or(F32.is_lt(Tri.edge.mx(sx2, sy2, sx3, sy3, x0, y0, x1, y1, sum), 0.0),
      F32.is_lt(Tri.edge.mx(sx3, sy3, sx1, sy1, x0, y0, x1, y1, sum), 0.0)))


def Tri.keep.narrow(wide: Bool, a: Rt.Vtx, b: Rt.Vtx, c: Rt.Vtx, +x0: F32,
  +y0: F32, +x1: F32, +y1: F32) -> Bool:
  match wide:
    case False{}:
      True{}
    case True{}:
      Rt.Vtx{at1, +sx1, +sy1, iw1} = a
      Rt.Vtx{at2, +sx2, +sy2, iw2} = b
      Rt.Vtx{at3, +sx3, +sy3, iw3} = c
      Bool.not(Tri.keep.edges(x0, y0, x1, y1, sx1, sy1, sx2, sy2, sx3, sy3))


def Tri.keep.box(over: Bool, wide: Bool, a: Rt.Vtx, b: Rt.Vtx, c: Rt.Vtx,
  +x0: F32, +y0: F32, +x1: F32, +y1: F32) -> Bool:
  match over:
    case False{}:
      False{}
    case True{}:
      Tri.keep.narrow(wide, a, b, c, x0, y0, x1, y1)


def Tri.keep.at(t: Rt.Tri, +x0: F32, +y0: F32, +x1: F32, +y1: F32) -> Bool:
  Rt.Tri{a, b, c, +bx0, +by0, +bx1, +by1} = t
  +over = Bool.and(F32.is_gt(bx1, x0),
    Bool.and(F32.is_lt(bx0, x1),
      Bool.and(F32.is_gt(by1, y0), F32.is_lt(by0, y1))))
  +wide = Bool.or(F32.is_gt(F32.sub(bx1, bx0), Tri.wide()),
    F32.is_gt(F32.sub(by1, by0), Tri.wide()))
  Tri.keep.box(over, wide, a, b, c, x0, y0, x1, y1)


def Tri.keep1(yes: Bool, t: Rt.Tri, +acc: List<&2, Rt.Tri>)
  -> List<&2, Rt.Tri>:
  match yes:
    case True{}:
      t <> acc
    case False{}:
      acc


def Tri.keep(ts: List<&2, Rt.Tri>, +x0: F32, +y0: F32, +x1: F32, +y1: F32,
  +acc: List<&2, Rt.Tri>) -> List<&2, Rt.Tri>:
  match ts:
    case []:
      acc
    case +t <> rest:
      Tri.keep(rest, x0, y0, x1, y1,
        Tri.keep1(Tri.keep.at(t, x0, y0, x1, y1), t, acc))


def Spr.keep.at(s: Rt.Spr, +x0: F32, +y0: F32, +x1: F32, +y1: F32) -> Bool:
  Rt.Spr{+cx, +cy, +r, +iw, +cr, +cg, +cb, +a, +kind} = s
  Bool.and(F32.is_gt(F32.add(cx, r), x0),
    Bool.and(F32.is_lt((cx - r : F32), x1),
      Bool.and(F32.is_gt(F32.add(cy, r), y0),
        F32.is_lt((cy - r : F32), y1))))


def Spr.keep1(yes: Bool, s: Rt.Spr, +acc: List<&2, Rt.Spr>)
  -> List<&2, Rt.Spr>:
  match yes:
    case True{}:
      s <> acc
    case False{}:
      acc


def Spr.keep(ss: List<&2, Rt.Spr>, +x0: F32, +y0: F32, +x1: F32, +y1: F32,
  +acc: List<&2, Rt.Spr>) -> List<&2, Rt.Spr>:
  match ss:
    case []:
      acc
    case +s <> rest:
      Spr.keep(rest, x0, y0, x1, y1,
        Spr.keep1(Spr.keep.at(s, x0, y0, x1, y1), s, acc))


# ---- the pixel's fragment --------------------------------------------
# The three edge functions of the triangle at a pixel.  Their sum is twice the
# signed area -- independent of the pixel -- so "inside" is "all three have the
# same sign as the sum", which needs no branch on the winding, and the
# barycentric weights fall out of the same three numbers divided by the sum.
# Depth is 1/w, which the perspective divide makes linear across the triangle,
# so the weights blend it directly; every other attribute needs the 1/w factor
# the shader carries per vertex.
# The inside test on the three edge functions: all three share the sign of
# their sum, which is twice the signed area.  It is a def of its own because
# the pixel loop reaches it twice -- once for a triangle handed to Tri.hit and
# once from Tri.step, whose fourth comparison pair only narrows the bounding
# box and cannot decide the pixel.
def Tri.inside(+e0: F32, +e1: F32, +e2: F32, +sum: F32) -> Bool:
  Bool.and(F32.is_ge((e0 * sum : F32), 0.0),
    Bool.and(F32.is_ge((e1 * sum : F32), 0.0),
      Bool.and(F32.is_ge((e2 * sum : F32), 0.0),
        F32.is_gt(F32.abs(sum), 0.0))))


def Tri.hit.go(ok: Bool, +e0: F32, +e1: F32, +e2: F32, +sum: F32, +aiw: F32,
  +biw: F32, +ciw: F32) -> Hit:
  match ok:
    case False{}:
      Miss{}
    case True{}:
      +inv = (1.0 / sum : F32)
      +la = (e1 * inv : F32)
      +lb = (e2 * inv : F32)
      +lc = (e0 * inv : F32)
      Hit{la, lb, lc, (la * aiw + lb * biw + lc * ciw : F32)}


def Tri.hit(+fx: F32, +fy: F32, +ax: F32, +ay: F32, +aiw: F32, +bx: F32,
  +by: F32, +biw: F32, +cx: F32, +cy: F32, +ciw: F32) -> Hit:
  +e0 = ((bx - ax) * (fy - ay) - (by - ay) * (fx - ax) : F32)
  +e1 = ((cx - bx) * (fy - by) - (cy - by) * (fx - bx) : F32)
  +e2 = ((ax - cx) * (fy - cy) - (ay - cy) * (fx - cx) : F32)
  +sum = (e0 + e1 + e2 : F32)
  Tri.hit.go(Tri.inside(e0, e1, e2, sum), e0, e1, e2, sum, aiw, biw, ciw)


# One attribute: the perspective-correct blend of the three vertices'.
def Tri.f3(+wa: F32, +wb: F32, +wc: F32, +ia: F32, +ib: F32, +ic: F32, +den: F32,
  +a: F32, +b: F32, +c: F32) -> F32:
  (((wa * ia : F32) * a + (wb * ib : F32) * b + (wc * ic : F32) * c : F32)
    / den : F32)


def Tri.frag(+la: F32, +lb: F32, +lc: F32, +iw: F32, +aiw: F32, +biw: F32,
  +ciw: F32, a: Geo.WVtx, b: Geo.WVtx, c: Geo.WVtx) -> Rt.Frag:
  Geo.WVtx{+ax, +ay, +az, +anx, +any, +anz, +acr, +acg, +acb, +ae} = a
  Geo.WVtx{+bx, +by, +bz, +bnx, +bny, +bnz, +bcr, +bcg, +bcb, +be} = b
  Geo.WVtx{+cx, +cy, +cz, +cnx, +cny, +cnz, +ccr, +ccg, +ccb, +ce} = c
  Rt.Frag{
    Tri.f3(la, lb, lc, aiw, biw, ciw, iw, ax, bx, cx),
    Tri.f3(la, lb, lc, aiw, biw, ciw, iw, ay, by, cy),
    Tri.f3(la, lb, lc, aiw, biw, ciw, iw, az, bz, cz),
    Tri.f3(la, lb, lc, aiw, biw, ciw, iw, anx, bnx, cnx),
    Tri.f3(la, lb, lc, aiw, biw, ciw, iw, any, bny, cny),
    Tri.f3(la, lb, lc, aiw, biw, ciw, iw, anz, bnz, cnz),
    Tri.f3(la, lb, lc, aiw, biw, ciw, iw, acr, bcr, ccr),
    Tri.f3(la, lb, lc, aiw, biw, ciw, iw, acg, bcg, ccg),
    Tri.f3(la, lb, lc, aiw, biw, ciw, iw, acb, bcb, ccb),
    Tri.f3(la, lb, lc, aiw, biw, ciw, iw, ae, be, ce), iw}


# ---- the depth contest -----------------------------------------------
# A candidate fragment against the pixel's incumbent.  `Best` is destructured
# to read its depth, which consumes it, so the losing branch rebuilds the one
# two-field node; the `Frag` inside is only ever referenced, never copied.
#
# The comparison cannot be matched on directly -- `match` only inspects a
# parameter or a pattern binder -- so the Bool is computed where both depths
# are in scope and handed to `Tri.take.win`, and the folds are split so that
# no two of them call each other in a cycle (forward references are illegal).
def Tri.take.new(+la: F32, +lb: F32, +lc: F32, +iw: F32, +aiw: F32, +biw: F32,
  +ciw: F32, at1: Geo.WVtx, at2: Geo.WVtx, at3: Geo.WVtx) -> Best:
  Best{iw, Tri.frag(la, lb, lc, iw, aiw, biw, ciw, at1, at2, at3)}


def Tri.take.win(nearer: Bool, +la: F32, +lb: F32, +lc: F32, +iw: F32,
  +biw0: F32, bfrag: Rt.Frag, +aiw: F32, +biw: F32, +ciw: F32,
  at1: Geo.WVtx, at2: Geo.WVtx, at3: Geo.WVtx) -> Best:
  match nearer:
    case True{}:
      Tri.take.new(la, lb, lc, iw, aiw, biw, ciw, at1, at2, at3)
    case False{}:
      Best{biw0, bfrag}


def Tri.take.best(+la: F32, +lb: F32, +lc: F32, +iw: F32, +aiw: F32,
  +biw: F32, +ciw: F32, at1: Geo.WVtx, at2: Geo.WVtx, at3: Geo.WVtx,
  best: Best) -> Best:
  match best:
    case Bnil{}:
      Tri.take.new(la, lb, lc, iw, aiw, biw, ciw, at1, at2, at3)
    case Best{+biw0, bfrag}:
      Tri.take.win(F32.is_gt(iw, biw0), la, lb, lc, iw, biw0, bfrag, aiw, biw, ciw,
        at1, at2, at3)


def Tri.take.hit(h: Hit, +aiw: F32, +biw: F32, +ciw: F32, at1: Geo.WVtx,
  at2: Geo.WVtx, at3: Geo.WVtx, best: Best) -> Best:
  match h:
    case Miss{}:
      best
    case Hit{la, lb, lc, iw}:
      Tri.take.best(la, lb, lc, iw, aiw, biw, ciw, at1, at2, at3, best)


def Tri.step.box(ok: Bool, +fx: F32, +fy: F32, a: Rt.Vtx, b: Rt.Vtx,
  c: Rt.Vtx, best: Best) -> Best:
  match ok:
    case False{}:
      best
    case True{}:
      Rt.Vtx{at1, +sx1, +sy1, +iw1} = a
      Rt.Vtx{at2, +sx2, +sy2, +iw2} = b
      Rt.Vtx{at3, +sx3, +sy3, +iw3} = c
      +e0 = ((sx2 - sx1) * (fy - sy1) - (sy2 - sy1) * (fx - sx1) : F32)
      +e1 = ((sx3 - sx2) * (fy - sy2) - (sy3 - sy2) * (fx - sx2) : F32)
      +e2 = ((sx1 - sx3) * (fy - sy3) - (sy1 - sy3) * (fx - sx3) : F32)
      +sum = ((sx2 - sx1) * (fy - sy1) - (sy2 - sy1) * (fx - sx1)
        + (sx3 - sx2) * (fy - sy2) - (sy3 - sy2) * (fx - sx2)
        + (sx1 - sx3) * (fy - sy3) - (sy1 - sy3) * (fx - sx3) : F32)
      # The bounding box only says the pixel is in the box the triangle's three
      # corners span, which for a triangle seen edge-on -- the near carriage's
      # wall, clipped at the near plane -- is a strip across the whole frame.
      # Without this second test every pixel of that box shades as if it were
      # inside the triangle, with barycentric weights extrapolated far outside.
      Tri.take.hit(Tri.hit.go(Tri.inside(e0, e1, e2, sum), e0, e1, e2, sum, iw1,
        iw2, iw3), iw1, iw2, iw3, at1, at2, at3, best)


# One triangle against one pixel.  The bounding box rejects most pixels of a
# tile with four comparisons on the triangle's own fields -- which is the whole
# reason the tile keeps a list instead of the pixel testing the world -- and
# the vertices are read only by the pair that passes it.
def Tri.step(+fx: F32, +fy: F32, t: Rt.Tri, best: Best) -> Best:
  Rt.Tri{a, b, c, +bx0, +by0, +bx1, +by1} = t
  Tri.step.box(Bool.and(F32.is_ge(fx, bx0),
    Bool.and(F32.is_le(fx, bx1),
      Bool.and(F32.is_ge(fy, by0), F32.is_le(fy, by1)))),
    fx, fy, a, b, c, best)


def Tri.best(ts: List<&2, Rt.Tri>, +fx: F32, +fy: F32, best: Best) -> Best:
  match ts:
    case []:
      best
    case +t <> rest:
      Tri.best(rest, fx, fy, Tri.step(fx, fy, t, best))


# ---- additive billboards ---------------------------------------------
# Stars and glows are the only things drawn without writing depth: a star
# (kind 0) is behind everything, so it shows only where no triangle won the
# pixel, and a glow (kind 1) is depth-tested, so the train still hides a light
# behind it.
# `om` is rebuilt in each branch: a `let` may not precede a `match` on a
# parameter, and `star` is the first parameter.
def Spr.alpha(star: Bool, +d: F32, +a: F32) -> F32:
  match star:
    case True{}:
      +om = (1.0 - d : F32)
      ((F32.pow(om, 3.5) + F32.pow(om, 1.2) * 0.22 : F32) * a : F32)
    case False{}:
      +om = (1.0 - d : F32)
      (F32.pow(om, 2.6) * a : F32)


def Spr.gate(star: Bool, hit: Bool, +iw: F32, +hiw: F32) -> Bool:
  match star:
    case True{}:
      Bool.not(hit)
    case False{}:
      match hit:
        case True{}:
          F32.is_ge(iw, hiw)
        case False{}:
          True{}


def Spr.tint(yes: Bool, +cr: F32, +cg: F32, +cb: F32, +al: F32, acc: Shade.RGB)
  -> Shade.RGB:
  match yes:
    case False{}:
      acc
    case True{}:
      Shade.Rgb.tint(acc, cr, cg, cb, al)


def Spr.one.in(visible: Bool, +n: F32, +star: Bool, +hit: Bool, +iw: F32,
  +hiw: F32, +cr: F32, +cg: F32, +cb: F32, +a: F32, acc: Shade.RGB)
  -> Shade.RGB:
  match visible:
    case False{}:
      acc
    case True{}:
      Spr.tint(Spr.gate(star, hit, iw, hiw), cr, cg, cb,
        Spr.alpha(star, F32.sqrt(n), a), acc)


def Spr.one(s: Rt.Spr, +fx: F32, +fy: F32, +hit: Bool, +hiw: F32,
  acc: Shade.RGB) -> Shade.RGB:
  Rt.Spr{+cx, +cy, +r, +iw, +cr, +cg, +cb, +a, +kind} = s
  +dx = (fx - cx : F32)
  +dy = (fy - cy : F32)
  +q = (dx * dx + dy * dy : F32)
  +r2 = (r * r : F32)
  Spr.one.in(Bool.and(F32.is_gt(r2, 0.0), F32.is_le(q, r2)), (q / r2 : F32),
    U32.is_eq(kind, 0), hit, iw, hiw, cr, cg, cb, a, acc)


def Spr.all(ss: List<&2, Rt.Spr>, +fx: F32, +fy: F32, +hit: Bool, +hiw: F32,
  acc: Shade.RGB) -> Shade.RGB:
  match ss:
    case []:
      acc
    case +s <> rest:
      Spr.all(rest, fx, fy, hit, hiw, Spr.one(s, fx, fy, hit, hiw, acc))


def Pk(rgb: Shade.RGB) -> U32:
  Shade.RGB{r, g, b} = rgb
  Color.pack(r, g, b)


# The mean of four channel values, rounded to nearest.  F32 would work too, but
# the samples are already unorm8 and the integer form is exact, so the average
# of four identical samples returns the value it started with.
def Px.q(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  U32.shrn(U32.add(U32.add(a, b), U32.add(U32.add(c, d), 2)), 2n)


def Px.avg4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  U32.or(
    U32.shln(Px.q(Color.red(a), Color.red(b), Color.red(c), Color.red(d)), 16n),
    U32.or(
      U32.shln(Px.q(Color.green(a), Color.green(b), Color.green(c),
        Color.green(d)), 8n),
      Px.q(Color.blue(a), Color.blue(b), Color.blue(c), Color.blue(d))))


# ---- one pixel -------------------------------------------------------
def Tile.px.shade(+iw: F32, frag: Rt.Frag, +fx: F32, +fy: F32,
  ss: List<&2, Rt.Spr>, env: Env) -> U32:
  Env{cam, lts, head_on, t} = env
  Pk(Spr.all(ss, fx, fy, True{}, iw, Shade.Sh.v(frag, cam, lts, head_on)))


def Tile.px.sky(+fx: F32, +fy: F32, ss: List<&2, Rt.Spr>, env: Env) -> U32:
  Env{cam, lts, head_on, t} = env
  Pk(Spr.all(ss, fx, fy, False{}, 0.0, Shade.Sky.rgb(Rt.VCam.ray(cam, fx, fy), t)))


def Tile.px.at(best: Best, +fx: F32, +fy: F32, ss: List<&2, Rt.Spr>, env: Env)
  -> U32:
  match best:
    case Bnil{}:
      Tile.px.sky(fx, fy, ss, env)
    case Best{iw, frag}:
      Tile.px.shade(iw, frag, fx, fy, ss, env)


# One sample, at the pixel's origin plus an offset.
def Tile.px.s(+x: F32, +y: F32, +dx: F32, +dy: F32, +tris: List<&2, Rt.Tri>,
  +ss: List<&2, Rt.Spr>, +env: Env) -> U32:
  +fx = (x + dx : F32)
  +fy = (y + dy : F32)
  Tile.px.at(Tri.best(tris, fx, fy, Bnil{}), fx, fy, ss, env)


# A pixel is four samples on its quadrant centres, averaged.
#
# The demo asks WebGL for `antialias: true`, which is 4x MSAA, and the reference
# frame carries the sub-pixel coverage that comes with it.  Sampling the pixel
# centre alone, which is what this did, leaves every geometric edge hard: pixels
# within two of an edge carry about two thirds of the frame's error against the
# reference, while the geometry itself is already in the right place -- an
# integer-shift search across the strong edges moves them by nothing.  Four
# quadrant samples resolve an edge to the same five coverage levels 4x MSAA
# does, and for the same reason: what an edge pixel is missing is not a better
# sample position but more of them.
#
# Costing four samples per pixel is affordable here only because the per-pixel
# pass is a small part of a frame -- about 50 ns a pixel against a fixed scene
# cost of a tenth of a second -- so doubling the image's accuracy quadruples the
# smaller term.
def Tile.px(+px: U32, +py: U32, +tris: List<&2, Rt.Tri>, +ss: List<&2, Rt.Spr>,
  +env: Env) -> U32:
  +x = U32.to_f32(px)
  +y = U32.to_f32(py)
  Px.avg4(
    Tile.px.s(x, y, 0.25, 0.25, tris, ss, env),
    Tile.px.s(x, y, 0.75, 0.25, tris, ss, env),
    Tile.px.s(x, y, 0.25, 0.75, tris, ss, env),
    Tile.px.s(x, y, 0.75, 0.75, tris, ss, env))


# Rows and tiles are filled bottom-up and right-to-left, so consing as the
# counter falls leaves each list in reading order with no reversal and no
# append.
def Tile.row.go(+i: Nat, +x: U32, +y: U32, +tris: List<&2, Rt.Tri>,
  +ss: List<&2, Rt.Spr>, +env: Env, +acc: List<&2, U32>) -> List<&2, U32>:
  match i:
    case 0n:
      acc
    case 1n+k:
      Tile.row.go(k, U32.sub(x, 1), y, tris, ss, env,
        Tile.px(x, y, tris, ss, env) <> acc)


def Tile.row(+x: U32, +y: U32, +tris: List<&2, Rt.Tri>, +ss: List<&2, Rt.Spr>,
  +env: Env) -> List<&2, U32>:
  Tile.row.go(Tile.side(), U32.add(x, U32.from_nat(Nat.sub(Tile.side(), 1n))), y,
    tris, ss, env, [])


def Tile.rows(+j: Nat, +x: U32, +y: U32, +tris: List<&2, Rt.Tri>,
  +ss: List<&2, Rt.Spr>, +env: Env, +acc: List<&2, List<&2, U32>>)
  -> List<&2, List<&2, U32>>:
  match j:
    case 0n:
      acc
    case 1n+k:
      Tile.rows(k, x, U32.sub(y, 1), tris, ss, env,
        Tile.row(x, y, tris, ss, env) <> acc)


def Frame.tile(+x: U32, +y: U32, +tris: List<&2, Rt.Tri>,
  +ss: List<&2, Rt.Spr>, +env: Env) -> Frame:
  # `y` is the tile's top row; the fold walks down from the bottom one and
  # prepends, so the concatenated list comes back top-to-bottom.
  Tile{List.concat(&2, U32,
    Tile.rows(Tile.side(), x,
      U32.add(y, U32.from_nat(Nat.sub(Tile.side(), 1n))), tris, ss, env, []))}


# ---- the quadtree ----------------------------------------------------
# One node of the tree.  `x`, `y`, `size` are the node's pixel square; the four
# floats are the same square in screen coordinates, and they are what the
# filter tests, so a node is handed a list already pruned to it and prunes it
# again to each of its four children.
#
# Where the filter sits is not cosmetic.  Read the other way -- each branch of
# the fork called with `keep(parent_list, child_box)`, the filter in the
# argument position, which is the obvious way to write it -- the whole tree's
# filtering nests inside the level above it: `keep(keep(keep(keep ...)))`, and
# a fork's arguments belong to the caller.  A branch that filters its own list
# is a branch that owns that work.
def Frame.build(+d: Nat, +x: U32, +y: U32, +size: U32, +lx: F32, +ly: F32,
  +rx: F32, +ry: F32, +tris: List<&2, Rt.Tri>, +ss: List<&2, Rt.Spr>,
  +env: Env) -> Frame:
  match d:
    case 0n:
      +ft = Tri.keep(tris, lx, ly, rx, ry, [])
      +fs = Spr.keep(ss, lx, ly, rx, ry, [])
      Frame.tile(x, y, ft, fs, env)
    case 1n+k:
      +ft = Tri.keep(tris, lx, ly, rx, ry, [])
      +fs = Spr.keep(ss, lx, ly, rx, ry, [])
      +h = U32.shrn(size, 1n)
      +x1 = U32.add(x, h)
      +y1 = U32.add(y, h)
      +mx = U32.to_f32(x1)
      +my = U32.to_f32(y1)
      a b c f = Frame.build(k, x, y, h, lx, ly, mx, my, ft, fs, env)
        Frame.build(k, x1, y, h, mx, ly, rx, my, ft, fs, env)
        Frame.build(k, x, y1, h, lx, my, mx, ry, ft, fs, env)
        Frame.build(k, x1, y1, h, mx, my, rx, ry, ft, fs, env)
      Quad{a, b, c, f}


# ---- the entry point -------------------------------------------------
# `d` is the frame's depth, so the frame is 2^d pixels square.  The geometry
# arrives already in world space for this `s`; projecting it is the first thing
# that happens here.
# `gs` is the ground and `ws` is everything else, kept apart because the cull
# treats them differently: the ground's back faces are dropped, the rest are
# not.  Culling the rest is what the demo does -- it enables `CULL_FACE` for
# everything but the track -- but it is measured to be *worse* here (0.0021 ->
# 0.0050 MAE against the reference), so the winding of the consist and the
# instanced meshes is not the demo's and both of their faces have to be drawn
# to land on the same picture.  See docs/journal.md.
def Raster.frame(+d: Nat, +s: F32, +side: F32, +hgt: F32, +yaw: F32,
  +pitch: F32, +gs: List<&2, Geo.WTri>, +ws: List<&2, Geo.WTri>,
  +lts: Shade.Lights, +ss: List<&2, Rt.Spr>, +t: F32, +head_on: Bool) -> Frame:
  +w = U32.shln(1, d)
  +cam = Rt.VCam.ride(w, w, s, side, hgt, yaw, pitch)
  +tris = List.append(&2, Rt.Tri, Rt.Tri.emit(Rt.Tri.cull(gs, cam, []), cam),
    Rt.Tri.emit(ws, cam))
  # the glow layer needs where the ride began, not only where it is now: the
  # smoke's first puffs were born there.  The camera moves at the demo's own
  # speed, so the origin is t seconds back along the line.
  +sprs = List.append(&2, Rt.Spr,
    Ride.Ride.glows(cam, s, (s - Ride.Ride.speed() * t : F32), head_on, t),
    List.append(&2, Rt.Spr, Shade.Stars.list(cam, t), ss))
  Frame.build(Nat.tile.levels(d), 0, 0, w, 0.0, 0.0, U32.to_f32(w),
    U32.to_f32(w), tris, sprs, Env{cam, lts, head_on, t})


# The same frame, but the geometry stays chunked: the projection of each piece
# rides its own worker (Rt.Tri.emit.chunks) instead of the serial soup walk.
# `gcs` is the ground's four chunks and `cs` the rest, split the same way
# Raster.frame splits its two lists, and for the same reason.
def Raster.frame.chunks(+d: Nat, +s: F32, +side: F32, +hgt: F32,
  +yaw: F32, +pitch: F32, +gcs: List<&2, List<&2, Geo.WTri>>,
  cs: List<&2, List<&2, Geo.WTri>>, +lts: Shade.Lights, +ss: List<&2, Rt.Spr>,
  +t: F32, +head_on: Bool) -> Frame:
  +w = U32.shln(1, d)
  +cam = Rt.VCam.ride(w, w, s, side, hgt, yaw, pitch)
  +tris = List.append(&2, Rt.Tri,
    Rt.Tri.emit.chunks(Rt.Tri.cull.chunks(gcs, cam, []), cam),
    Rt.Tri.emit.chunks(cs, cam))
  +sprs = List.append(&2, Rt.Spr,
    Ride.Ride.glows(cam, s, (s - Ride.Ride.speed() * t : F32), head_on, t),
    List.append(&2, Rt.Spr, Shade.Stars.list(cam, t), ss))
  Frame.build(Nat.tile.levels(d), 0, 0, w, 0.0, 0.0, U32.to_f32(w),
    U32.to_f32(w), tris, sprs, Env{cam, lts, head_on, t})


# ---- reading the frame back ------------------------------------------
# A tile holds its TILE x TILE pixels row-major, so a row of the image is one
# row out of each tile the row crosses: the walk stops at the tile instead of
# at the pixel, and only the leaf knows the stride.
#
# A pixel's text.  Color.ch clamps every channel to 0..255, so three cases
# cover a channel exactly and the digits are consed straight onto the rest of
# the pixel -- no channel string is built and then copied by `++`, and no
# counter walks ten digits to find two.  Going through U32.show instead costs
# about four times as much per pixel, which the live view pays on every pixel
# of every frame.
#
# The two comparisons are passed in as parameters because a match may only
# scrutinise one, and `v` is duplicable because every arm reads it.
def Px.dig.one(+v: U32, tail: String) -> String:
  SCon{Chr{U32.add(48, v)}, tail}


def Px.dig.two(+v: U32, tail: String) -> String:
  SCon{Chr{U32.add(48, U32.div(v, 10))}, Px.dig.one(U32.mod(v, 10), tail)}


def Px.dig.three(+v: U32, tail: String) -> String:
  SCon{Chr{U32.add(48, U32.div(v, 100))}, Px.dig.two(U32.mod(v, 100), tail)}


def Px.dig(+h3: Bool, +h2: Bool, +v: U32, tail: String) -> String:
  match h3:
    case True{}:
      Px.dig.three(v, tail)
    case False{}:
      match h2:
        case True{}:
          Px.dig.two(v, tail)
        case False{}:
          Px.dig.one(v, tail)


def Px.digits(+v: U32, tail: String) -> String:
  Px.dig(U32.is_ge(v, 100), U32.is_ge(v, 10), v, tail)


# `tail` is what follows the pixel's own text, so a tile's pixels can be strung
# together in one right-to-left pass: each pixel conses its characters onto the
# text of the pixels after it, and nothing is ever copied.  Building a string
# per pixel and joining them afterwards -- List.reverse plus String.concat, the
# obvious way -- allocates about twice as many cons cells for the same bytes,
# and the live view pays that on every pixel of every frame.
def Px.show(+c: U32, tail: String) -> String:
  Px.digits(Color.red(c),
    SCon{Chr{32}, Px.digits(Color.green(c),
      SCon{Chr{32}, Px.digits(Color.blue(c),
        SCon{Chr{10}, tail})} )})


# A tile's eight pixels, then whatever follows them.  The pixels are consumed
# from the left while their text is built from the right, so the recursive call
# is the argument that carries the rest of the row and each pixel conses
# straight onto it.
def Tile.text(+xs: List<&2, U32>, tail: String) -> String:
  match xs:
    case []:
      tail
    case h <> rest:
      Px.show(h, Tile.text(rest, tail))


# A row leaves the tree as its tile strings, left to right -- not as one string.
# Joining the two halves with `++` at every level, which is the obvious way to
# write it, rebuilds the whole row once per level: nine copies of a 512-pixel
# row per scanline, 27 MB of cons cells per frame, and that concatenation was
# three times the cost of rendering the frame.  Handing back the pieces costs
# only the list spine, and the two callers below each pay for one copy of the
# row's text and no more.
#
# `half` is the pixel height of one child, so `top` says which pair of children
# the row falls through; both are parameters because a match may only inspect a
# parameter and no let may precede it.
def Frame.texts(+k: Nat, fr: Frame, +y: U32, +half: U32, top: Bool)
  -> List<&2, String>:
  match k:
    case 0n:
      match fr:
        case Tile{px}:
          [Tile.text(List.take(&2, U32,
            List.drop(&2, U32, px,
              U32.to_nat(U32.mul(y, U32.from_nat(Tile.side())))),
            Tile.side()), "")]
        case Quad{a, b, c, d}:
          []
    case 1n+e:
      match fr:
        case Tile{px}:
          []
        case Quad{a, b, c, d}:
          match top:
            case True{}:
              +h2 = U32.shrn(half, 1n)
              +up = U32.is_lt(y, h2)
              List.append(&2, String, Frame.texts(e, a, y, h2, up),
                Frame.texts(e, b, y, h2, up))
            case False{}:
              +h2 = U32.shrn(half, 1n)
              +yy = (y - half : U32)
              +up = U32.is_lt(yy, h2)
              List.append(&2, String, Frame.texts(e, c, yy, h2, up),
                Frame.texts(e, d, yy, h2, up))


def Raster.row.tiles(+d: Nat, fr: Frame, +y: U32) -> List<&2, String>:
  +w = U32.shln(1, d)
  +half = U32.shrn(w, 1n)
  Frame.texts(Nat.tile.levels(d), fr, y, half, U32.is_lt(y, half))


def Raster.text.row(+d: Nat, fr: Frame, +y: U32) -> String:
  String.concat(Raster.row.tiles(d, fr, y))


# The live view's row: the same pieces, written one at a time.  A tile's text
# goes straight to stdout, so the row is never assembled -- the concatenation
# above would copy it, which is the cost this exists to avoid.
def Raster.emit.tiles(ts: List<&2, String>) -> IO(Unit):
  match ts:
    case []:
      IO.pure(Unit, Unit{})
    case h <> rest:
      do IO<Unit>:
        IO.write(h)
        Raster.emit.tiles(rest)


def Raster.emit.row(+d: Nat, fr: Frame, +y: U32) -> IO(Unit):
  Raster.emit.tiles(Raster.row.tiles(d, fr, y))


# ---- checksum --------------------------------------------------------
# An order-independent digest: every leaf contributes a mixed hash of its
# packed pixel and the tree folds them with a wrapping sum.  Addition commutes,
# so a flipped or transposed frame hashes the same -- a cheap equality test for
# a render against itself, not a fingerprint of the picture.
#
# The fold has to be a sum, not an XOR.  The first version XOR-ed the four
# quadrant sub-folds, which let them cancel: three materially different builds
# produced one checksum, so the gate that should have caught a changed frame
# stayed quiet.  Summing mixed per-pixel hashes cannot cancel; what is left is
# the ordinary 2^-32 collision.
def Frame.hash1(+c: U32) -> U32:
  +x = U32.mul(U32.xor(c, 2246822519), 2654435761)
  U32.xor(x, U32.shrn(x, 15n))


def Frame.hash.list(xs: List<&2, U32>, +acc: U32) -> U32:
  match xs:
    case []:
      acc
    case h <> rest:
      Frame.hash.list(rest, U32.add(acc, Frame.hash1(h)))


def Frame.sum(+k: Nat, fr: Frame, +acc: U32) -> U32:
  match k:
    case 0n:
      match fr:
        case Tile{px}:
          Frame.hash.list(px, acc)
        case Quad{a, b, c, d}:
          acc
    case 1n+e:
      match fr:
        case Tile{px}:
          acc
        case Quad{a, b, c, d}:
          Frame.sum(e, a,
            Frame.sum(e, b, Frame.sum(e, c, Frame.sum(e, d, acc))))


def Raster.digest(+d: Nat, fr: Frame) -> U32:
  Frame.sum(Nat.tile.levels(d), fr, 0)
