import Base
import ../voxel.bend as V

def Dump.faces(faces: List<&2, V.Face>) -> IO(Unit):
	match faces:
		case Nil{}:
			IO.pure(Unit, Unit{})
		case Con{V.Face{cell, direction, material}, rest}:
			do IO<Unit>:
				IO.print("F " ++ V.Cell.show(cell) ++ " " ++ V.Direction.show(direction) ++ " " ++ U32.show(material))
				Dump.faces(rest)
		case V.Rectangle{cell,direction,material,width,height} <> rest:
			IO.die(Unit,1,"The geometry golden requires unit cube faces")

def Dump.cell(material: U32, cell: V.Cell) -> IO(Unit):
	match material:
		case 0:
			IO.pure(Unit, Unit{})
		case m:
			IO.print("C " ++ V.Cell.show(cell) ++ " " ++ U32.show(m))

def Dump.cells(cells: Array<U32>, +side: U32, +base: U32, +span: U32) -> IO(Unit):
	match cells:
		case ALeaf{material}:
			Dump.cell(material, V.Cell.at(side, base))
		case ANode{left, right}:
			do IO<Unit>:
				Dump.cells(left, side, base, (span / 2 : U32))
				Dump.cells(right, side, (base + span / 2 : U32), (span / 2 : U32))

def Dump.result(name: String, result: V.Body & V.Surface) -> IO(Unit):
	match result:
		case (V.Cuboids{boxes},surface): IO.die(Unit,1,"The geometry golden requires the cube fixture")
		case (V.Body{+side,cells},V.Surface{+faces}):
			do IO<Unit>:
				IO.print("BEGIN " ++ name)
				IO.print("COUNT " ++ U32.show(V.Surface.count.faces(faces, 0)))
				Dump.faces(faces)
				Dump.cells(cells, side, 0, (side * side * side : U32))
				IO.print("END")

def Dump.body(name: String, body: V.Body) -> IO(Unit):
	Dump.result(name, V.Surface.build(body))

def Fixture.single() -> V.Body:
	V.Body.write(V.Body.empty(2n), V.Cell{1, 1, 1}, 7)

def Fixture.adjacent() -> V.Body:
	V.Body.write(Fixture.single(), V.Cell{2, 1, 1}, 7)

def Fixture.interior() -> V.Body:
	V.Body.destroy(V.Body.solid(2n), V.Sphere{V.Cell{1, 1, 1}, 0})

def Fixture.cut() -> V.Body:
	V.Body.destroy(V.Body.solid(3n), V.Sphere{V.Cell{6, 6, 6}, 3})

def main() -> IO(Unit):
	do IO<Unit>:
		Dump.body("empty", V.Body.empty(2n))
		Dump.body("single", Fixture.single())
		Dump.body("adjacent", Fixture.adjacent())
		Dump.body("full4", V.Body.solid(2n))
		Dump.body("interior", Fixture.interior())
		Dump.body("repeat", V.Body.destroy(Fixture.interior(), V.Sphere{V.Cell{1, 1, 1}, 0}))
		Dump.body("bounds", V.Body.write(V.Body.write(Fixture.single(), V.Cell{4, 1, 1}, 99), V.Cell{4294967295, 0, 0}, 99))
		Dump.body("far-brush", V.Body.destroy(V.Body.solid(2n), V.Sphere{V.Cell{4294967295, 0, 0}, 1}))
		Dump.body("edges", V.Body.write(V.Body.write(V.Body.empty(2n), V.Cell{0, 1, 1}, 1), V.Cell{3, 1, 1}, 1))
		Dump.body("full8", V.Body.solid(3n))
		Dump.body("cut", Fixture.cut())
		Dump.body("cut-repeat", V.Body.destroy(Fixture.cut(), V.Sphere{V.Cell{6, 6, 6}, 3}))
