import Base
import ./core.bend as Core
import ./complex.bend as C
import ./perturbation.bend as P

type Request is Data:
  Render{cxh: F32, cxl: F32, cyh: F32, cyl: F32, step: F32, width: U32, height: U32, root: U32, iterations: U32, phase: F32, origin_x: U32, origin_y: U32}
  Deep{mantissa: F32, exponent: F32, offset_x: F32, offset_y: F32, width: U32, height: U32, root: U32, iterations: U32, phase: F32, reference: P.Reference, origin_x: U32, origin_y: U32}
  Direct{}
  Skip{}
  Stop{}

def Worker.read() -> IO(Request):
  import "./worker-source.c"
  import "./worker.js"

def Worker.write(image: Image) -> IO(Unit):
  import "./worker-source.c"
  import "./worker.js"

def write_pair(pair: Image & P.Reference) -> IO(Unit):
  match pair:
    case (image, reference):
      Worker.write(image)

def respond(request: Request) -> IO(Bool):
  match request:
    case Direct{}:
      do IO<Bool>:
        Worker.write(Pix{0})
        return True{}
    case Skip{}:
      do IO<Bool>:
        Worker.write(Pix{0})
        return True{}
    case Stop{}:
      IO.pure(Bool, False{})
    case Render{cxh, cxl, cyh, cyl, step, width, height, root, iterations, phase, origin_x, origin_y}:
      do IO<Bool>:
        now : Nat <- IO.now()
        Worker.write(Core.region(origin_x, origin_y, width, height, root, C.DS{cxh, cxl}, C.DS{cyh, cyl}, step, U32.to_nat(iterations), phase))
        return True{}
    case Deep{mantissa, exponent, offset_x, offset_y, width, height, root, iterations, phase, reference, origin_x, origin_y}:
      do IO<Bool>:
        now : Nat <- IO.now()
        write_pair(P.region(reference, origin_x, origin_y, width, height, root, mantissa, exponent, offset_x, offset_y, U32.to_nat(iterations), phase))
        return True{}

@unsafe def loop(active: Bool) -> IO(Unit):
  match active:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        request : Request <- Worker.read()
        again : Bool <- respond(request)
        loop(again)

def main() -> IO(Unit):
  loop(True{})
