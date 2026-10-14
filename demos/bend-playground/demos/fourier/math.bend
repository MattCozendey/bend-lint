import Base

type Point is Data:
  Point{x: F32, y: F32}
type Coefficient is Data:
  Coefficient{re: F32, im: F32, frequency: F32, amplitude: F32}

def sum(points: List<Point>, +k: F32, +size: F32, +i: F32, re: F32, im: F32) -> Point:
  match points:
    case []: Point{re,im}
    case Point{+x,+y} <> rest:
      +angle = (6.283185307 * k * i / size : F32)
      +c = F32.cos(angle)
      +s = F32.sin(angle)
      sum(rest,k,size,(i + 1.0 : F32),(re + x * c + y * s : F32),(im + y * c - x * s : F32))

def coefficient(p: Point, +k: F32, +size: F32) -> Coefficient:
  Point{x,y} = p
  +re = (x / size : F32)
  +im = (y / size : F32)
  Coefficient{re,im,Bool.pick(F32,(k > size / 2.0 : F32),(k - size : F32),k),F32.sqrt((re * re + im * im : F32))}

def dft(points: List<Point>, +k: F32, +size: F32) -> Coefficient:
  coefficient(sum(points,k,size,0.0,0.0,0.0),k,size)

def rotate(c: Coefficient, time: F32) -> Point:
  Coefficient{+re,+im,frequency,amplitude} = c
  +angle = (frequency * time : F32)
  +cs = F32.cos(angle)
  +sn = F32.sin(angle)
  Point{(re * cs - im * sn : F32),(re * sn + im * cs : F32)}

# Square-wave Fourier series: odd harmonics with amplitude 4/(pi*n).
def harmonic(index: U32) -> Coefficient:
  +n = U32.to_f32((2 * index + 1 : U32))
  +amplitude = (4.0 / (3.141592653589793 * n) : F32)
  Coefficient{amplitude,0.0,n,amplitude}

def px(p: Point) -> F32:
  Point{x,y} = p
  x

def py(p: Point) -> F32:
  Point{x,y} = p
  y

def amplitude(c: Coefficient) -> F32:
  Coefficient{re,im,f,a} = c
  a

type Step is Data:
  Step{cx: F32, cy: F32, radius: F32, x: F32, y: F32}

def endpoint(coefficients: List<&2, Coefficient>, +time: F32, x: F32, y: F32) -> Point:
  match coefficients:
    case []: Point{x,y}
    case c <> rest:
      +v = rotate(c,time)
      endpoint(rest,time,(x + px(v) : F32),(y + py(v) : F32))

def chain(coefficients: List<&2, Coefficient>, +time: F32, +x: F32, +y: F32) -> List<&2, Step>:
  match coefficients:
    case []: []
    case +c <> rest:
      +v = rotate(c,time)
      +u = (x + px(v) : F32)
      +w = (y + py(v) : F32)
      Step{x,y,amplitude(c),u,w} <> chain(rest,time,u,w)
