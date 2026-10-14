# Real sorting operations; compact event trees instead of full-array snapshots.
import Base
import ../shared/grid.bend as G
import ../probability/math.bend as R

type Events is Data:
  NoEvents{}
  Op{kind: U32, a: U32, b: U32}
  Both{left: Events, right: Events}
type Sorted is Data:
  Sorted{array: G.Grid, events: Events}
type Partition is Data:
  Partition{array: G.Grid, events: Events, split: U32}

def value(pattern: Nat, +i: U32, +n: U32, seed: U32) -> U32:
  match pattern:
    case 0n: (1 + R.hash((i .^. R.hash(seed) : U32)) % n : U32)
    case 1n: (n - i : U32)
    case 2n: (i + 1 : U32)
    case _: (1 + R.hash((i .^. R.hash(seed) : U32)) % 5 : U32)

def build(depth: Nat, +offset: U32, +n: U32, +pattern: Nat, +seed: U32) -> G.Grid:
  match depth:
    case 0n: G.Leaf{value(pattern,offset,n,seed)}
    case 1n+ +p:
      G.Branch{build(p,offset,n,pattern,seed),build(p,(offset + (1 << p) : U32),n,pattern,seed)}

def array(r: Sorted) -> G.Grid:
  Sorted{g,events} = r
  g

def events(r: Sorted) -> Events:
  Sorted{g,e} = r
  e

def put(depth: Nat, enabled: Bool, g: G.Grid, +index: U32, +v: U32) -> G.Grid:
  match depth:
    case 0n:
      Bool.pick(G.Grid,enabled,G.Leaf{v},g)
    case 1n+ +p:
      match enabled:
        case False{}: g
        case True{}:
          match g:
            case G.Leaf{word}: G.Leaf{v}
            case G.Branch{left,right}:
              +half = (1 << p : U32)
              G.Branch{put(p,(index < half : U32),left,(index % half : U32),v),put(p,(index >= half : U32),right,(index % half : U32),v)}

def swap(+g: G.Grid, +a: U32, +b: U32, +depth: Nat) -> G.Grid:
  put(depth,True{},put(depth,True{},g,a,G.lookup(depth,g,b)),b,G.lookup(depth,g,a))

def exchange(change: Bool, g: G.Grid, +i: U32, +j: U32, depth: Nat, e: Events) -> Sorted:
  match change:
    case True{}: Sorted{swap(g,i,j,depth),Both{e,Op{1,i,j}}}
    case False{}: Sorted{g,e}

def pass(n: Nat, +g: G.Grid, +i: U32, +depth: Nat, e: Events) -> Sorted:
  match n:
    case 0n: Sorted{g,e}
    case 1n+p:
      +j = (i + 1 : U32)
      +next = exchange((G.lookup(depth,g,i) > G.lookup(depth,g,j) : U32),g,i,j,depth,Both{e,Op{0,i,j}})
      pass(p,array(next),j,depth,events(next))

def bubble(n: Nat, g: G.Grid, +depth: Nat, e: Events) -> Sorted:
  match n:
    case 0n: Sorted{g,e}
    case 1n+ +p:
      +next = pass(p,g,0,depth,e)
      bubble(p,array(next),depth,events(next))

def part_array(p: Partition) -> G.Grid:
  Partition{g,e,split} = p
  g

def part_events(p: Partition) -> Events:
  Partition{g,e,split} = p
  e

def part_split(p: Partition) -> U32:
  Partition{g,e,split} = p
  split

def partition_next(take: Bool, g: G.Grid, +i: U32, +store: U32, depth: Nat, e: Events) -> Partition:
  match take:
    case True{}: Partition{swap(g,i,store,depth),Both{e,Op{1,i,store}},(store + 1 : U32)}
    case False{}: Partition{g,e,store}

def partition(n: Nat, +g: G.Grid, +i: U32, +store: U32, +high: U32, +depth: Nat, e: Events) -> Partition:
  match n:
    case 0n: Partition{swap(g,store,high,depth),Both{e,Op{1,store,high}},store}
    case 1n+p:
      +next = partition_next((G.lookup(depth,g,i) <= G.lookup(depth,g,high) : U32),g,i,store,depth,Both{e,Op{0,i,high}})
      partition(p,part_array(next),(i + 1 : U32),part_split(next),high,depth,part_events(next))

def quick(fuel: Nat, enabled: Bool, g: G.Grid, +lo: U32, +hi: U32, +depth: Nat, e: Events) -> Sorted:
  match fuel:
    case 0n: Sorted{g,e}
    case 1n+ +p:
      match enabled:
        case False{}: Sorted{g,e}
        case True{}:
          +part = partition(U32.to_nat((hi - lo - 1 : U32)),g,lo,lo,(hi - 1 : U32),depth,e)
          +split = part_split(part)
          +left = quick(p,(split > lo + 1 : U32),part_array(part),lo,split,depth,part_events(part))
          quick(p,(hi > split + 2 : U32),array(left),(split + 1 : U32),hi,depth,events(left))

def compared(valid: Bool, e: Events, i: U32, j: U32) -> Events:
  match valid:
    case True{}: Both{e,Op{0,i,j}}
    case False{}: e

# Read both runs from source while writing into a separate persistent tree.
def merge_runs(n: Nat, +source: G.Grid, output: G.Grid, +i: U32, +j: U32, +mid: U32, +hi: U32, +k: U32, +depth: Nat, e: Events) -> Sorted:
  match n:
    case 0n: Sorted{output,e}
    case 1n+p:
      +take = (i < mid : U32) && ((j >= hi : U32) || (G.lookup(depth,source,i) <= G.lookup(depth,source,j) : U32))
      +v = G.lookup(depth,source,Bool.pick(U32,take,i,j))
      merge_runs(p,source,put(depth,True{},output,k,v),Bool.pick(U32,take,(i + 1 : U32),i),Bool.pick(U32,take,j,(j + 1 : U32)),mid,hi,(k + 1 : U32),depth,Both{compared((i < mid : U32) && (j < hi : U32),e,i,j),Op{2,k,v}})

def mergesort(fuel: Nat, enabled: Bool, g: G.Grid, +lo: U32, +hi: U32, +depth: Nat, e: Events) -> Sorted:
  match fuel:
    case 0n: Sorted{g,e}
    case 1n+ +p:
      match enabled:
        case False{}: Sorted{g,e}
        case True{}:
          +mid = ((lo + hi) / 2 : U32)
          +left = mergesort(p,(mid > lo + 1 : U32),g,lo,mid,depth,e)
          +right = mergesort(p,(hi > mid + 1 : U32),array(left),mid,hi,depth,events(left))
          merge_runs(U32.to_nat((hi - lo : U32)),array(right),array(right),lo,mid,mid,hi,lo,depth,Both{events(right),Op{3,lo,hi}})

def sort(kind: Nat, g: G.Grid, +n: U32, depth: Nat) -> Sorted:
  match kind:
    case 0n: quick(U32.to_nat(n),(n > 1 : U32),g,0,n,depth,NoEvents{})
    case 1n: mergesort(U32.to_nat(n),(n > 1 : U32),g,0,n,depth,NoEvents{})
    case _: bubble(U32.to_nat(n),g,depth,NoEvents{})
