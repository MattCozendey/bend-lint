import Base
import ./perturbation.bend as P
import ./scaled.bend as S
import ./LAWS.bend as Laws

def Laws.exhausted_budget(cr, ci, zr, zi, count, radius):
  {==}

def Laws.preserve_escape(fuel, cr, ci, zr, zi, count, radius):
  match fuel:
    case 0n:
      {==}
    case 1n+rest:
      {==}

def Laws.bounded_is_ink(phase):
  {==}

def Laws.perturbation_budget(remaining, reference, root, zr, zi, dc, delta, count, radius):
  match remaining reference:
    case 0n P.RefEnd{}:
      {==}
    case 0n P.RefPoint{r, i, tail}:
      {==}
    case 1n+budget P.RefEnd{}:
      {==}
    case 1n+budget P.RefPoint{r, i, tail}:
      {==}

def Laws.request_repair(fuel, remaining, reference, root, zr, zi, dc, delta, count, radius):
  match fuel remaining reference:
    case 0n 0n P.RefEnd{}:
      {==}
    case 0n 0n P.RefPoint{r, i, tail}:
      {==}
    case 0n 1n+budget P.RefEnd{}:
      {==}
    case 0n 1n+budget P.RefPoint{r, i, tail}:
      {==}
    case 1n+rest 0n P.RefEnd{}:
      {==}
    case 1n+rest 0n P.RefPoint{r, i, tail}:
      {==}
    case 1n+rest 1n+budget P.RefEnd{}:
      {==}
    case 1n+rest 1n+budget P.RefPoint{r, i, tail}:
      {==}


def Laws.ordinary_region_origin(width, height, root, cx, cy, step, fuel, phase):
  {==}

def Laws.deep_region_origin(reference, width, height, root, mantissa, exponent, offset_x, offset_y, fuel, phase):
  {==}

def Laws.float_preserve_escape(fuel, remaining, reference, root, zr, zi, cr, ci, dr, di, count, radius):
  match fuel remaining reference:
    case 0n 0n P.RefEnd{}:
      {==}
    case 0n 0n P.RefPoint{r, i, tail}:
      {==}
    case 0n 1n+budget P.RefEnd{}:
      {==}
    case 0n 1n+budget P.RefPoint{r, i, tail}:
      {==}
    case 1n+rest 0n P.RefEnd{}:
      {==}
    case 1n+rest 0n P.RefPoint{r, i, tail}:
      {==}
    case 1n+rest 1n+budget P.RefEnd{}:
      {==}
    case 1n+rest 1n+budget P.RefPoint{r, i, tail}:
      {==}

def Laws.float_request_repair(fuel, remaining, reference, root, zr, zi, cr, ci, dr, di, count, radius):
  match fuel remaining reference:
    case 0n 0n P.RefEnd{}:
      {==}
    case 0n 0n P.RefPoint{r, i, tail}:
      {==}
    case 0n 1n+budget P.RefEnd{}:
      {==}
    case 0n 1n+budget P.RefPoint{r, i, tail}:
      {==}
    case 1n+rest 0n P.RefEnd{}:
      {==}
    case 1n+rest 0n P.RefPoint{r, i, tail}:
      {==}
    case 1n+rest 1n+budget P.RefEnd{}:
      {==}
    case 1n+rest 1n+budget P.RefPoint{r, i, tail}:
      {==}

def Laws.float_budget(remaining, reference, root, zr, zi, cr, ci, dr, di, count, radius):
  match remaining reference:
    case 0n P.RefEnd{}:
      {==}
    case 0n P.RefPoint{r, i, tail}:
      {==}
    case 1n+budget P.RefEnd{}:
      {==}
    case 1n+budget P.RefPoint{r, i, tail}:
      {==}

def Laws.scaled_start(dc):
  match dc:
    case S.Complex{r, i, exponent}:
      {==}
