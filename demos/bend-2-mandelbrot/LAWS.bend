import Base
import ./perturbation.bend as P
import ./scaled.bend as S
import ./core.bend as Core
import ./complex.bend as C

# Exhausting the finite iteration budget is reported as bounded, never as a
# proof of mathematical membership in the Mandelbrot set.
law exhausted_budget:
  for cr: C.Wide
  for ci: C.Wide
  for zr: C.Wide
  for zi: C.Wide
  for count: U32
  for radius: F32
  {Core.iterate(0n, False{}, cr, ci, zr, zi, count, radius) == Core.Bounded{} : Core.Orbit}

# Once escape has been detected, preserve its iteration and radius even if the
# last fuel unit was consumed. This prevents a last-iteration off-by-one.
law preserve_escape:
  for fuel: Nat
  for cr: C.Wide
  for ci: C.Wide
  for zr: C.Wide
  for zi: C.Wide
  for count: U32
  for radius: F32
  {Core.iterate(fuel, True{}, cr, ci, zr, zi, count, radius) == Core.Escaped{count, radius} : Core.Orbit}

law bounded_is_ink:
  for phase: F32
  {Core.color(Core.Bounded{}, phase) == 330001 : U32}


# The scalable path uses the same explicit finite-budget semantics.
law perturbation_budget:
  for remaining: Nat
  for reference: P.Reference
  for +root: P.Reference
  for zr: F32
  for zi: F32
  for +dc: S.Scaled
  for +delta: S.Scaled
  for count: U32
  for radius: F32
  {P.iterate(0n, remaining, reference, root, False{}, False{}, False{}, zr, zi, dc, delta, count, radius) == P.Bounded{} : P.Outcome}

# A numerical glitch is sent to repair rather than silently painted as a
# bounded point or accepted as a valid escape.
law request_repair:
  for fuel: Nat
  for remaining: Nat
  for reference: P.Reference
  for +root: P.Reference
  for zr: F32
  for zi: F32
  for +dc: S.Scaled
  for +delta: S.Scaled
  for count: U32
  for radius: F32
  {P.iterate(fuel, remaining, reference, root, False{}, True{}, False{}, zr, zi, dc, delta, count, radius) == P.Repair{} : P.Outcome}

# The legacy full-frame path is exactly the region path at the global origin.
law ordinary_region_origin:
  for +width: U32
  for +height: U32
  for +root: U32
  for +cx: C.Wide
  for +cy: C.Wide
  for +step: F32
  for +fuel: Nat
  for +phase: F32
  {Core.frame(width, height, root, cx, cy, step, fuel, phase) == Core.region(0, 0, width, height, root, cx, cy, step, fuel, phase) : Image}

law deep_region_origin:
  for +reference: P.Reference
  for +width: U32
  for +height: U32
  for +root: U32
  for +mantissa: F32
  for +exponent: F32
  for +offset_x: F32
  for +offset_y: F32
  for +fuel: Nat
  for +phase: F32
  {P.frame(reference, width, height, root, mantissa, exponent, offset_x, offset_y, fuel, phase) == P.region(reference, 0, 0, width, height, root, mantissa, exponent, offset_x, offset_y, fuel, phase) : Image & P.Reference}

law float_preserve_escape:
  for fuel: Nat
  for remaining: Nat
  for reference: P.Reference
  for +root: P.Reference
  for zr: F32
  for zi: F32
  for cr: F32
  for ci: F32
  for dr: F32
  for di: F32
  for count: U32
  for radius: F32
  {P.iterate_float(fuel, remaining, reference, root, True{}, False{}, False{}, zr, zi, cr, ci, dr, di, count, radius) == P.Escaped{count, radius} : P.Outcome}

law float_request_repair:
  for fuel: Nat
  for remaining: Nat
  for reference: P.Reference
  for +root: P.Reference
  for zr: F32
  for zi: F32
  for cr: F32
  for ci: F32
  for dr: F32
  for di: F32
  for count: U32
  for radius: F32
  {P.iterate_float(fuel, remaining, reference, root, False{}, True{}, False{}, zr, zi, cr, ci, dr, di, count, radius) == P.Repair{} : P.Outcome}

law float_budget:
  for remaining: Nat
  for reference: P.Reference
  for +root: P.Reference
  for zr: F32
  for zi: F32
  for cr: F32
  for ci: F32
  for dr: F32
  for di: F32
  for count: U32
  for radius: F32
  {P.iterate_float(0n, remaining, reference, root, False{}, False{}, False{}, zr, zi, cr, ci, dr, di, count, radius) == P.Bounded{} : P.Outcome}

# A zero initial delta must preserve even an extremely small parameter offset.
law scaled_start:
  for dc: S.Scaled
  {S.advance(0.0, 0.0, dc, S.zero()) == dc : S.Scaled}
