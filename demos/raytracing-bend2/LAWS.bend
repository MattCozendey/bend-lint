# Ray tracer -- the laws: the parallel render returns exactly the rows the
# sequential loop does, in order, and every line holds its w pixels. The
# F32 shading is not claimed: floats are primitives the checker cannot see
# into, so the pixel values stay abstract in every law. The width w is
# abstract too, so the laws hold for any image size.
import Base
import ./main.bend as Ray

# LAW: merging the rows at even positions with the rows at odd positions
# gives back the rows, in order
law split_merge:
  for +ys: List<&2, U32>
  for +w: U32
  for +ns: U32
  for +cam: Ray.Cam
  for +scene: Ray.Scene
  {Ray.interleave(Ray.rows(Ray.evens(ys), w, ns, cam, scene),
    Ray.rows(Ray.odds(ys), w, ns, cam, scene))
    == Ray.rows(ys, w, ns, cam, scene) : Ray.Rows}

# LAW: the fork tree renders the same rows as the sequential loop, in the
# same order, at any depth
law render_is_seq:
  for +d: Nat
  for +ys: List<&2, U32>
  for +w: U32
  for +ns: U32
  for +cam: Ray.Cam
  for +scene: Ray.Scene
  {Ray.render(d, ys, w, ns, cam, scene) == Ray.rows(ys, w, ns, cam, scene)
    : Ray.Rows}

# LAW: a row loop of n steps puts exactly n pixels on top of acc
law row_len:
  for +n: Nat
  for +x: U32
  for +y: U32
  for +ns: U32
  for +cam: Ray.Cam
  for +scene: Ray.Scene
  for +acc: List<&2, U32>
  {Nat.add(n, List.length(&2, U32, acc))
    == List.length(&2, U32, Ray.row(n, x, y, ns, cam, scene, acc)) : Nat}

# LAW: every line holds w pixels
law line_len:
  for +w: U32
  for +y: U32
  for +ns: U32
  for +cam: Ray.Cam
  for +scene: Ray.Scene
  {U32.to_nat(w) == List.length(&2, U32, Ray.line(w, y, ns, cam, scene))
    : Nat}
