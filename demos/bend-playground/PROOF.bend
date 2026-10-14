import Base
import ./physics.bend as Physics
import ./LAWS.bend as Laws

def Laws.initially_zero(mass):
  {==}

def Laws.stopped_is_unchanged(s):
  {==}

def Laws.impact_counts_once(at_wall, s, dt):
  match at_wall:
    case True{}:
      match s:
        case Physics.State{x, y, v, w, mass, time, count, wall}:
          {==}
    case False{}:
      match s:
        case Physics.State{x, y, v, w, mass, time, count, wall}:
          {==}
