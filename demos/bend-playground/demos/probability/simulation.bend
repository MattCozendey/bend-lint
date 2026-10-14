import Base
import ./math.bend as M

type Samples is Data:
  End{}
  Point{sample: M.Sample, rest: Samples}

type Count is Data:
  Count{hits: U32, failed: U32}

def add(a: Count, b: Count) -> Count:
  Count{h,f} = a
  Count{i,g} = b
  Count{(h + i : U32),(f + g : U32)}

def scored(s: M.Sample) -> Count:
  M.Sample{x,y,dx,dy,hit,valid} = s
  Count{hit,(1 - valid : U32)}

def serial(n: Nat, +index: U32, +needle: Bool, +seed: U32, sum: Count) -> Count:
  match n:
    case 0n:
      sum
    case 1n+p:
      serial(p,(index + 1 : U32),needle,seed,add(sum,scored(M.sample(needle,index,seed))))

# Fork independent chunks; keep the inner arithmetic loop allocation-light.
def count(depth: Nat, +start: U32, +n: U32, +needle: Bool, +seed: U32) -> Count:
  match depth:
    case 0n:
      serial(U32.to_nat(n),start,needle,seed,Count{0,0})
    case 1n+ +p:
      +half = (n / 2 : U32)
      a b = count(p,start,half,needle,seed) count(p,(start + half : U32),(n - half : U32),needle,seed)
      add(a,b)

def preview(n: Nat, +index: U32, +needle: Bool, +seed: U32) -> Samples:
  match n:
    case 0n:
      End{}
    case 1n+p:
      Point{M.sample(needle,index,seed),preview(p,(index + 1 : U32),needle,seed)}

type Replay is Data:
  Batch{n: U32, hits: U32, failed: U32, points: Samples}
  Branch{n: U32, hits: U32, failed: U32, left: Replay, right: Replay}

def total(r: Replay) -> U32:
  match r:
    case Batch{n,hits,failed,points}: n
    case Branch{n,hits,failed,left,right}: n

def hit_count(r: Replay) -> U32:
  match r:
    case Batch{n,hits,failed,points}: hits
    case Branch{n,hits,failed,left,right}: hits

def failures(r: Replay) -> U32:
  match r:
    case Batch{n,hits,failed,points}: failed
    case Branch{n,hits,failed,left,right}: failed

def join(+a: Replay, +b: Replay) -> Replay:
  Branch{(total(a) + total(b) : U32),(hit_count(a) + hit_count(b) : U32),(failures(a) + failures(b) : U32),a,b}

def batch(n: U32, c: Count, points: Samples) -> Replay:
  Count{hits,failed} = c
  Batch{n,hits,failed,points}

# Exactly 256 summary batches, up to eight points or two needles from each.
# Sample count affects arithmetic, not file size or compilation.
def run(depth: Nat, +index: U32, +n: U32, +inner: Nat, +needle: Bool, +seed: U32) -> Replay:
  match depth:
    case 0n:
      +q = (n / 256 : U32)
      +r = (n % 256 : U32)
      +size = (q + Bool.pick(U32,(index < r : U32),1,0) : U32)
      +start = (index * q + U32.min(index,r) : U32)
      batch(size,count(inner,start,size,needle,seed),preview(U32.to_nat(U32.min(size,Bool.pick(U32,needle,2,8))),start,needle,seed))
    case 1n+ +p:
      a b = run(p,index,n,inner,needle,seed) run(p,(index + (1 << p) : U32),n,inner,needle,seed)
      join(a,b)

def point_text(s: M.Sample) -> String:
  M.Sample{x,y,dx,dy,hit,valid} = s
  F32.show(x) ++ " " ++ F32.show(y) ++ " " ++ F32.show(dx) ++ " " ++ F32.show(dy) ++ " " ++ U32.show(hit) ++ " "

def points_text(points: Samples) -> String:
  match points:
    case End{}: ""
    case Point{x,xs}: point_text(x) ++ points_text(xs)

def text(r: Replay, +before_n: U32, +before_hits: U32, +needle: Bool) -> String:
  match r:
    case Batch{n,hits,failed,points}:
      +nn = (before_n + n : U32)
      +hh = (before_hits + hits : U32)
      U32.show(nn) ++ " " ++ U32.show(hh) ++ " " ++ F32.show(M.estimate(needle,nn,hh)) ++ " " ++ points_text(points) ++ "\n"
    case Branch{n,h,failed,+left,right}:
      text(left,before_n,before_hits,needle) ++ text(right,(before_n + total(left) : U32),(before_hits + hit_count(left) : U32),needle)
