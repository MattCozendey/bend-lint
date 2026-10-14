# share: does the quadtree's filter scale, and is the parent list the reason?
#
# The renderer's tree hands the parent's triangle list to all four children, so
# one list is a term used four times at every node.  Two shapes produce the
# same four child lists:
#
#   mode 7  four keeps per node: `filter(parent, box_k)` in each branch's
#           argument position, exactly as the renderer writes it today.  The
#           parent's list is consumed four times.
#   mode 8  one pass per node: walk the parent's list once and prepend each
#           element into every child bucket it passes.  The parent's list is
#           consumed once and each bucket is a list of its own.
#
# Same tree, same element count in the leaves, same leaf work.  Run both at
# one thread and at many; the difference in how the two scale is the cost of
# the share, and nothing else.
#
#   NT_MODE=7|8 NT_DEPTH=<levels> NT_N=<list/8> ./out/share --threads <n>
import Base


def Main.env.u32.maybe(m: Maybe<&2, U32>, +dflt: U32) -> IO(U32):
  match m:
    case None{}:
      IO.pure(U32, dflt)
    case Some{v}:
      IO.pure(U32, v)


def Main.env.u32.pick(r: Result<&1, &1, U32 & String, String>, +dflt: U32)
  -> IO(U32):
  match r:
    case Fail{e}:
      IO.pure(U32, dflt)
    case Done{value}:
      Main.env.u32.maybe(U32.read(value), dflt)


def Main.env.u32(name: String, +dflt: U32) -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    Main.env.u32.pick(r, dflt)


# ---- the leaves' work -------------------------------------------------
def Work.walk(xs: List<&2, F32>, +acc: F32) -> F32:
  match xs:
    case []:
      acc
    case y <> rest:
      Work.walk(rest, (acc + y : F32))


# ---- mode 7: four keeps per node --------------------------------------
def Keep.one(yes: Bool, +y: F32, +acc: List<&2, F32>) -> List<&2, F32>:
  match yes:
    case True{}:
      y <> acc
    case False{}:
      acc


def Keep.filter(ys: List<&2, F32>, +t: F32, +acc: List<&2, F32>)
  -> List<&2, F32>:
  match ys:
    case []:
      acc
    case +y <> rest:
      Keep.filter(rest, t, Keep.one(F32.is_gt(y, t), y, acc))


def Tree.seven(+d: Nat, +xs: List<&2, F32>, +t0: F32, +t1: F32, +t2: F32,
  +t3: F32) -> F32:
  match d:
    case 0n:
      Work.walk(xs, 0.0)
    case 1n+e:
      a b c f = Tree.seven(e, Keep.filter(xs, t0, []), t0, t1, t2, t3)
        Tree.seven(e, Keep.filter(xs, t1, []), t0, t1, t2, t3)
        Tree.seven(e, Keep.filter(xs, t2, []), t0, t1, t2, t3)
        Tree.seven(e, Keep.filter(xs, t3, []), t0, t1, t2, t3)
      F32.add(F32.add(a, b), F32.add(c, f))


# ---- mode 8: one pass per node, four buckets --------------------------
type Quad is Data:
  Quad{a: List<&2, F32>, b: List<&2, F32>, c: List<&2, F32>, d: List<&2, F32>}


def Quad.put(yes: Bool, +y: F32, +acc: List<&2, F32>) -> List<&2, F32>:
  match yes:
    case True{}:
      y <> acc
    case False{}:
      acc


def Quad.bin(ys: List<&2, F32>, +t0: F32, +t1: F32, +t2: F32, +t3: F32,
  +q: Quad) -> Quad:
  match ys:
    case []:
      q
    case +y <> rest:
      Quad{a, b, c, d} = q
      Quad.bin(rest, t0, t1, t2, t3,
        Quad{Quad.put(F32.is_gt(y, t0), y, a), Quad.put(F32.is_gt(y, t1), y, b),
          Quad.put(F32.is_gt(y, t2), y, c), Quad.put(F32.is_gt(y, t3), y, d)})


# A node holds the four lists of the four siblings at its level -- the same
# four lists mode 7's four branches would each be filtering -- and bins each of
# them once into the four below.  The Quad arrives as a parameter, so its
# fields are a match away; the four lists inside it are each consumed once.
def Tree.eight(+d: Nat, +q: Quad, +t0: F32, +t1: F32, +t2: F32, +t3: F32)
  -> F32:
  match d:
    case 0n:
      Quad{a, b, c, f} = q
      F32.add(F32.add(Work.walk(a, 0.0), Work.walk(b, 0.0)),
        F32.add(Work.walk(c, 0.0), Work.walk(f, 0.0)))
    case 1n+e:
      Quad{a, b, c, f} = q
      p q2 r s = Tree.eight(e, Quad.bin(a, t0, t1, t2, t3, Quad{[], [], [], []}),
          t0, t1, t2, t3)
        Tree.eight(e, Quad.bin(b, t0, t1, t2, t3, Quad{[], [], [], []}), t0, t1,
          t2, t3)
        Tree.eight(e, Quad.bin(c, t0, t1, t2, t3, Quad{[], [], [], []}), t0, t1,
          t2, t3)
        Tree.eight(e, Quad.bin(f, t0, t1, t2, t3, Quad{[], [], [], []}), t0, t1,
          t2, t3)
      F32.add(F32.add(p, q2), F32.add(r, s))


# ---- the list ---------------------------------------------------------
def Main.list.go(+n: Nat, +i: U32, +acc: List<&2, F32>) -> List<&2, F32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      Main.list.go(p, U32.add(i, 1), (U32.to_f32(i) : F32) <> acc)


# The thresholds are fractions of the list's length, so the four buckets hold
# the same elements in both modes.
def Main.yard(+n: Nat) -> List<&2, F32>:
  Main.list.go(Nat.mul(n, 8n), 0, [])


def Main.pick(+mode: U32, +d: Nat, +n: Nat) -> F32:
  match mode:
    case 8:
      Tree.eight(Nat.div(d, 2n), Quad{Main.yard(n), Main.yard(n), Main.yard(n),
        Main.yard(n)}, 0.9, 0.6, 0.3, (0.0 - 1.0 : F32))
    case _:
      Tree.seven(Nat.div(d, 2n), Main.yard(n), 0.9, 0.6, 0.3,
        (0.0 - 1.0 : F32))


def Main.run() -> IO(Unit):
  do IO<Unit>:
    mode : U32 <- Main.env.u32("NT_MODE", 7)
    depth : U32 <- Main.env.u32("NT_DEPTH", 12)
    n : U32 <- Main.env.u32("NT_N", 200)
    IO.print(F32.show(Main.pick(mode, U32.to_nat(depth), U32.to_nat(n))) ++ "\n")


def main() -> IO(Unit):
  Main.run()
