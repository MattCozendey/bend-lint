# Ray tracer -- the proofs. split_merge: induction on the rows, two at a
# time. render_is_seq: induction on the depth; a node splits into the
# even and the odd rows, each is sequential by induction, and split_merge
# puts them back together. row_len: induction on the loop count.
import Base
import ./main.bend as Ray
import ./LAWS.bend as Laws

def add_zero(a: Nat) -> {a == Nat.add(a, 0n) : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_zero(p) : {1n+p == 1n+_ : Nat}
      {==}

def add_succ(a: Nat, -b: Nat) -> {1n+Nat.add(a, b) == Nat.add(a, 1n+b) : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_succ(p, b) : {2n+Nat.add(p, b) == 1n+_ : Nat}
      {==}

def Laws.split_merge(ys, w, ns, cam, scene):
  match ys:
    case []:
      {==}
    case x <> []:
      {==}
    case x <> y <> t:
      %Laws.split_merge(t, w, ns, cam, scene) :
        {Ray.RCon{Ray.line(w, x, ns, cam, scene),
          Ray.RCon{Ray.line(w, y, ns, cam, scene),
            Ray.interleave(Ray.rows(Ray.evens(t), w, ns, cam, scene),
              Ray.rows(Ray.odds(t), w, ns, cam, scene))}}
          == Ray.RCon{Ray.line(w, x, ns, cam, scene),
            Ray.RCon{Ray.line(w, y, ns, cam, scene), _}} : Ray.Rows}
      {==}

def Laws.render_is_seq(d, ys, w, ns, cam, scene):
  match d:
    case 0n:
      {==}
    case 1n++p:
      %Laws.split_merge(ys, w, ns, cam, scene) :
        {Ray.interleave(Ray.render(p, Ray.evens(ys), w, ns, cam, scene),
          Ray.render(p, Ray.odds(ys), w, ns, cam, scene)) == _ : Ray.Rows}
      %Laws.render_is_seq(p, Ray.evens(ys), w, ns, cam, scene) :
        {Ray.interleave(Ray.render(p, Ray.evens(ys), w, ns, cam, scene),
          Ray.render(p, Ray.odds(ys), w, ns, cam, scene))
          == Ray.interleave(_, Ray.rows(Ray.odds(ys), w, ns, cam, scene))
          : Ray.Rows}
      %Laws.render_is_seq(p, Ray.odds(ys), w, ns, cam, scene) :
        {Ray.interleave(Ray.render(p, Ray.evens(ys), w, ns, cam, scene),
          Ray.render(p, Ray.odds(ys), w, ns, cam, scene))
          == Ray.interleave(Ray.render(p, Ray.evens(ys), w, ns, cam, scene), _)
          : Ray.Rows}
      {==}

def Laws.row_len(n, x, y, ns, cam, scene, acc):
  match n:
    case 0n:
      {==}
    case 1n+k:
      %Laws.row_len(k, U32.sub(x, 1), y, ns, cam, scene,
        Ray.pixel(U32.sub(x, 1), y, ns, cam, scene) <> acc) :
        {1n+Nat.add(k, List.length(&2, U32, acc)) == _ : Nat}
      add_succ(k, List.length(&2, U32, acc))

def Laws.line_len(w, y, ns, cam, scene):
  %Laws.row_len(U32.to_nat(w), w, y, ns, cam, scene, []) :
    {U32.to_nat(w) == _ : Nat}
  add_zero(U32.to_nat(w))
