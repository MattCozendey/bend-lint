# scale: does a forked tree of work scale when the leaves share a list?
#
# The renderer's tile tree forks four ways at every node and hands each child a
# list filtered out of the parent's -- so the parent's list is a term used
# three or four times, and every child that walks it forces a dup of it.  This
# is the smallest program with the same shape: a binary tree whose leaves
# either do scalar arithmetic on their own copy of a number, or walk a list
# that every leaf in the tree is sharing.
#
# Run both modes at the same wall time on one thread; the difference in the
# 16-thread number is the sharing, not the work.
#
#   NT_MODE=0|1 NT_DEPTH=<levels> NT_N=<leaf work> ./out/scale --threads <n>
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


# ---- the leaf's own work ---------------------------------------------
def Main.work(+n: Nat, +x: F32) -> F32:
  match n:
    case 0n:
      x
    case 1n+k:
      Main.work(k, ((x * 1.0000001 + 0.0000001) : F32))


def Main.walk(xs: List<&2, F32>, +acc: F32) -> F32:
  match xs:
    case []:
      acc
    case y <> rest:
      Main.walk(rest, (acc + y : F32))


# ---- 0: each leaf owns its number ------------------------------------
def Main.tree.s(+d: Nat, +n: Nat, +x: F32) -> F32:
  match d:
    case 0n:
      Main.work(n, x)
    case 1n+e:
      a b = Main.tree.s(e, n, x) Main.tree.s(e, n, (x + 1.0 : F32))
      F32.add(a, b)


# ---- 1: every leaf walks the same list -------------------------------
def Main.tree.l(+d: Nat, +n: Nat, +xs: List<&2, F32>) -> F32:
  match d:
    case 0n:
      Main.walk(xs, Main.work(n, 0.0))
    case 1n+e:
      a b = Main.tree.l(e, n, xs) Main.tree.l(e, n, xs)
      F32.add(a, b)


def Main.list.go(+n: Nat, +i: U32, +acc: List<&2, F32>) -> List<&2, F32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      Main.list.go(p, U32.add(i, 1), (U32.to_f32(i) : F32) <> acc)


# ---- 2: the same, but the tree forks four ways like the tile quadtree --
def Main.tree.q(+d: Nat, +n: Nat, +x: F32) -> F32:
  match d:
    case 0n:
      Main.work(n, x)
    case 1n+e:
      a b c f = Main.tree.q(e, n, x) Main.tree.q(e, n, (x + 1.0 : F32))
        Main.tree.q(e, n, (x + 2.0 : F32)) Main.tree.q(e, n, (x + 3.0 : F32))
      F32.add(F32.add(a, b), F32.add(c, f))


# ---- 3: the leaf's work is done in the fork's argument position ------
# Same tree and same total work as mode 0, but each branch is called with its
# share already computed, the way the renderer hands Frame.build a filtered
# triangle list.  If the argument is evaluated in the parent's ring, the work
# is serialised along the descent and the speedup collapses.
def Main.tree.a(+d: Nat, +n: Nat, +x: F32) -> F32:
  match d:
    case 0n:
      x
    case 1n+e:
      a b = Main.tree.a(e, n, Main.work(n, x))
        Main.tree.a(e, n, Main.work(n, (x + 1.0 : F32)))
      F32.add(a, b)


# ---- 5: the renderer's own shape -------------------------------------
# A four-way tree in which every node hands each child a list filtered out of
# the parent's, so the parent's list is a shared term that four walks consume.
# This is Frame.build exactly; the filter thresholds stand in for the child
# boxes and split the parent list into quarters, the way a screen bounding box
# splits a tile.
def Main.keep1(yes: Bool, +y: F32, +acc: List<&2, F32>) -> List<&2, F32>:
  match yes:
    case True{}:
      y <> acc
    case False{}:
      acc


def Main.filter(ys: List<&2, F32>, +t: F32, +acc: List<&2, F32>)
  -> List<&2, F32>:
  match ys:
    case []:
      acc
    case +y <> rest:
      Main.filter(rest, t, Main.keep1(F32.is_gt(y, t), y, acc))


def Len.f32(xs: List<&2, F32>, +n: Nat) -> Nat:
  match xs:
    case []:
      n
    case _ <> rest:
      Len.f32(rest, Nat.add(n, 1n))


def Main.tree.f(+d: Nat, +xs: List<&2, F32>) -> F32:
  match d:
    case 0n:
      Main.walk(xs, 0.0)
    case 1n+e:
      +n = Len.f32(xs, 0n)
      +q = Nat.div(n, 4n)
      a b c f = Main.tree.f(e, Main.filter(xs, U32.to_f32(U32.from_nat(q)), []))
        Main.tree.f(e, Main.filter(xs,
          U32.to_f32(U32.from_nat(Nat.mul(q, 2n))), []))
        Main.tree.f(e, Main.filter(xs,
          U32.to_f32(U32.from_nat(Nat.mul(q, 3n))), []))
        Main.tree.f(e, Main.filter(xs, (0.0 - 1.0 : F32), []))
      F32.add(F32.add(a, b), F32.add(c, f))


def Main.pick(+mode: U32, +d: Nat, +n: Nat) -> F32:
  match mode:
    case 0:
      Main.tree.s(d, n, 1.0)
    case 2:
      Main.tree.q(Nat.div(d, 2n), n, 1.0)
    case 3:
      Main.tree.a(Nat.mul(d, 3n), n, 1.0)
    case 5:
      Main.tree.f(Nat.div(d, 2n), Main.list.go(Nat.mul(n, 8n), 0, []))
    case _:
      Main.tree.l(d, n, Main.list.go(Nat.mul(n, 4n), 0, []))


def Main.run() -> IO(Unit):
  do IO<Unit>:
    mode : U32 <- Main.env.u32("NT_MODE", 1)
    depth : U32 <- Main.env.u32("NT_DEPTH", 12)
    n : U32 <- Main.env.u32("NT_N", 200)
    IO.print(F32.show(Main.pick(mode, U32.to_nat(depth), U32.to_nat(n)))
      ++ "\n")


def main() -> IO(Unit):
  Main.run()
