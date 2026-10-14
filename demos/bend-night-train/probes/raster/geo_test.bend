# Checks the shared primitives build and have the triangle counts the demo's
# meshes have: boxMesh 12, coneMesh(7) 7, pineMesh 50, gableMesh 6.
import Base
import ../../src/geo.bend as Geo

def Main.n(xs: List<&2, Geo.Geo>) -> Nat:
  List.length(&2, Geo.Geo, xs)


def Main.m(xs: List<&2, Geo.WTri>) -> Nat:
  List.length(&2, Geo.WTri, xs)


def Main.place() -> List<&2, Geo.WTri>:
  Geo.Geo.place(Geo.G.box(), Geo.Style{2.9, 3.0, 24.0, 0.0, 2.6, 0.0, 0.12, 0.20,
    0.22, 0.0})


def Main.rigid() -> List<&2, Geo.WTri>:
  Geo.WTri.rigid(Main.place(), 0.3, 0.05, 10.0, 3.0, 110.0)


def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("box " ++ Nat.show(Main.n(Geo.G.box())) ++ "\n")
    IO.print("cone " ++ Nat.show(Main.n(Geo.G.cone(7n))) ++ "\n")
    IO.print("pine " ++ Nat.show(Main.n(Geo.G.pine())) ++ "\n")
    IO.print("gable " ++ Nat.show(Main.n(Geo.G.gable())) ++ "\n")
    IO.print("placed " ++ Nat.show(Main.m(Main.place())) ++ "\n")
    IO.print("rigid " ++ Nat.show(Main.m(Main.rigid())) ++ "\n")
