import Base
import ./material.bend as M

type Cell is Data:
	Cell{x: U32, y: U32, z: U32}

type Brush is Data:
	Sphere{center: Cell, radius: U32}

type PointCm is Data:
	PointCm{x: F32, y: F32, z: F32}

type MetricSphere is Data:
	MetricSphere{center: PointCm, radius_cm: F32}

type Cuboid is Data:
	Cuboid{low: Cell, high: Cell, material: U32}

type Body is Type:
	Body{side: U32, cells: Array<U32>}
	Cuboids{boxes: List<&2, Cuboid>}

type Snapshot is Data:
	Leaf{material: U32}
	Node{left: Snapshot, right: Snapshot}

type Direction is Data:
	NegX{}
	PosX{}
	NegY{}
	PosY{}
	NegZ{}
	PosZ{}

type Face is Data:
	Face{cell: Cell, direction: Direction, material: U32}
	Rectangle{cell: Cell, direction: Direction, material: U32, width: U32, height: U32}

type Surface is Data:
	Surface{faces: List<&2, Face>}

def Cell.erase(material: U32, hit: Bool) -> U32:
	match hit:
		case True{}:
			0
		case False{}:
			material

def Face.exposed(solid: Bool, neighbor: Bool) -> Bool:
	Bool.and(solid, Bool.not(neighbor))

def Body.filled(+depth: Nat, material: U32) -> Body:
	Body{U32.pow(2, depth), Array.new(U32, Nat.mul(3n, depth), material)}

def Body.solid(depth: Nat) -> Body:
	Body.filled(depth, M.Material.id(M.Foundation{}))

def Body.empty(depth: Nat) -> Body:
	Body.filled(depth, 0)

def Body.index(side: U32, cell: Cell) -> U32:
	Cell{x, y, z} = cell
	+xside = side
	(x + xside * y + xside * xside * z : U32)

def Cell.at(+side: U32, +index: U32) -> Cell:
	Cell{(index % side : U32), ((index / side) % side : U32), (index / (side * side) : U32)}

def Cell.inside(+side: U32, cell: Cell) -> Bool:
	Cell{x, y, z} = cell
	((x < side) && (y < side) && (z < side) : U32)

def Body.write.valid(inside: Bool, +side: U32, cells: Array<U32>, cell: Cell, material: U32) -> Body:
	match inside:
		case False{}: Body{side,cells}
		case True{}: Body{side,Array.set(U32,cells,Body.index(side,cell),material)}

def Body.write.dense(+side: U32, cells: Array<U32>, +cell: Cell, material: U32) -> Body:
	Body.write.valid(Cell.inside(side,cell),side,cells,cell,material)

def Distance.choose(ordered: Bool, a: U32, b: U32) -> U32:
	match ordered:
		case True{}:
			(a - b : U32)
		case False{}:
			(b - a : U32)

def Distance.axis(+a: U32, +b: U32) -> U32:
	Distance.choose((a >= b : U32), a, b)

def Brush.hits(brush: Brush, cell: Cell) -> Bool:
	Sphere{Cell{cx, cy, cz}, +r} = brush
	Cell{x, y, z} = cell
	+dx = Distance.axis(x, cx)
	+dy = Distance.axis(y, cy)
	+dz = Distance.axis(z, cz)
	(((dx <= r) && (dy <= r) && (dz <= r)) && (dx * dx + dy * dy + dz * dz <= r * r) : U32)

def Voxel.size_cm() -> F32:
	10.0

def PointCm.cell(cell: Cell) -> PointCm:
	Cell{x, y, z} = cell
	+size = Voxel.size_cm()
	PointCm{(size * U32.to_f32(x) + size * 0.5 : F32), (size * U32.to_f32(y) + size * 0.5 : F32), (size * U32.to_f32(z) + size * 0.5 : F32)}

def MetricSphere.brush(center: PointCm) -> MetricSphere:
	MetricSphere{center, 20.0}

def MetricSphere.demo() -> MetricSphere:
	MetricSphere.brush(PointCm{65.0, 65.0, 65.0})

def Number.finite(+value: F32) -> Bool:
	F32.is_eq((value - value : F32), 0.0)

def MetricSphere.valid(sphere: MetricSphere) -> Bool:
	MetricSphere{PointCm{x, y, z}, +radius} = sphere
	Number.finite(x) && Number.finite(y) && Number.finite(z) && Number.finite(radius) && (radius >= 0.0 : F32) && Number.finite((radius * radius : F32))

def MetricSphere.distance(sphere: MetricSphere, point: PointCm) -> Bool:
	MetricSphere{PointCm{cx, cy, cz}, +radius} = sphere
	PointCm{x, y, z} = point
	+dx = (x - cx : F32)
	+dy = (y - cy : F32)
	+dz = (z - cz : F32)
	(dx * dx + dy * dy + dz * dz <= radius * radius : F32)

def MetricSphere.contains.valid(valid: Bool, sphere: MetricSphere, cell: Cell) -> Bool:
	match valid:
		case False{}:
			False{}
		case True{}:
			MetricSphere.distance(sphere, PointCm.cell(cell))

def MetricSphere.contains(+sphere: MetricSphere, cell: Cell) -> Bool:
	MetricSphere.contains.valid(MetricSphere.valid(sphere), sphere, cell)

def Body.destroy.leaf(hit: Bool, material: U32) -> Array<U32>:
	ALeaf{Cell.erase(material, hit)}

def Body.destroy.tree(cells: Array<U32>, +side: U32, +brush: Brush, +base: U32, +span: U32) -> Array<U32>:
	match cells:
		case ALeaf{material}:
			Body.destroy.leaf(Brush.hits(brush, Cell.at(side, base)), material)
		case ANode{left, right}:
			+half = (span / 2 : U32)
			ANode{Body.destroy.tree(left, side, brush, base, half),
				Body.destroy.tree(right, side, brush, (base + half : U32), half)}

def Body.destroy.valid(valid: Bool, +side: U32, cells: Array<U32>, brush: Brush) -> Body:
	match valid:
		case False{}: Body{side,cells}
		case True{}: Body{side,Body.destroy.tree(cells,side,brush,0,(side * side * side : U32))}

def Body.destroy.dense(+side: U32, cells: Array<U32>, brush: Brush) -> Body:
	Sphere{+center,+radius} = brush
	Body.destroy.valid((Cell.inside(side,center) && (radius <= side : U32)),side,cells,Sphere{center,radius})

def Body.cut.tree(cells: Array<U32>, +side: U32, +sphere: MetricSphere, +base: U32, +span: U32) -> Array<U32>:
	match cells:
		case ALeaf{material}:
			ALeaf{Cell.erase(material, MetricSphere.contains(sphere, Cell.at(side, base)))}
		case ANode{left, right}:
			+half = (span / 2 : U32)
			ANode{Body.cut.tree(left, side, sphere, base, half), Body.cut.tree(right, side, sphere, (base + half : U32), half)}

def Body.cut.valid(valid: Bool, +side: U32, cells: Array<U32>, sphere: MetricSphere) -> Body:
	match valid:
		case False{}: Body{side,cells}
		case True{}: Body{side,Body.cut.tree(cells,side,sphere,0,(side * side * side : U32))}

def Body.cut.dense(side: U32, cells: Array<U32>, +sphere: MetricSphere) -> Body:
	Body.cut.valid(MetricSphere.valid(sphere),side,cells,sphere)

def Snapshot.join(a: Array<U32> & Snapshot, b: Array<U32> & Snapshot) -> Array<U32> & Snapshot:
	(left, lcopy) = a
	(right, rcopy) = b
	(ANode{left, right}, Node{lcopy, rcopy})

def Snapshot.of(cells: Array<U32>) -> Array<U32> & Snapshot:
	match cells:
		case ALeaf{+material}:
			(ALeaf{material}, Leaf{material})
		case ANode{left, right}:
			Snapshot.join(Snapshot.of(left), Snapshot.of(right))

def Snapshot.get(cells: Snapshot, +index: U32, +span: U32, leftward: Bool) -> U32:
	match cells:
		case Leaf{material}:
			material
		case Node{left, right}:
			match leftward:
				case True{}:
					Snapshot.get(left, index, (span / 2 : U32), (index < span / 4 : U32))
				case False{}:
					+j = (index - span / 2 : U32)
					Snapshot.get(right, j, (span / 2 : U32), (j < span / 4 : U32))

def Snapshot.read.valid(inside: Bool, cells: Snapshot, +side: U32, cell: Cell) -> U32:
	match inside:
		case False{}:
			0
		case True{}:
			+i = Body.index(side, cell)
			+n = (side * side * side : U32)
			Snapshot.get(cells, i, n, (i < n / 2 : U32))

def Snapshot.read(cells: Snapshot, +side: U32, +cell: Cell) -> U32:
	Snapshot.read.valid(Cell.inside(side, cell), cells, side, cell)

def Face.add(exposed: Bool, face: Face, faces: List<&2, Face>) -> List<&2, Face>:
	match exposed:
		case True{}:
			face <> faces
		case False{}:
			faces

def Surface.cell(material: U32, +snapshot: Snapshot, +side: U32, +cell: Cell, faces: List<&2, Face>) -> List<&2, Face>:
	match material:
		case 0:
			faces
		case +m:
			Cell{+x, +y, +z} = cell
			faces = Face.add(Face.exposed(True{}, U32.is_ne(Snapshot.read(snapshot, side, Cell{(x - 1 : U32), y, z}), 0)), Face{cell, NegX{}, m}, faces)
			faces = Face.add(Face.exposed(True{}, U32.is_ne(Snapshot.read(snapshot, side, Cell{(x + 1 : U32), y, z}), 0)), Face{cell, PosX{}, m}, faces)
			faces = Face.add(Face.exposed(True{}, U32.is_ne(Snapshot.read(snapshot, side, Cell{x, (y - 1 : U32), z}), 0)), Face{cell, NegY{}, m}, faces)
			faces = Face.add(Face.exposed(True{}, U32.is_ne(Snapshot.read(snapshot, side, Cell{x, (y + 1 : U32), z}), 0)), Face{cell, PosY{}, m}, faces)
			faces = Face.add(Face.exposed(True{}, U32.is_ne(Snapshot.read(snapshot, side, Cell{x, y, (z - 1 : U32)}), 0)), Face{cell, NegZ{}, m}, faces)
			Face.add(Face.exposed(True{}, U32.is_ne(Snapshot.read(snapshot, side, Cell{x, y, (z + 1 : U32)}), 0)), Face{cell, PosZ{}, m}, faces)

def Surface.scan(fuel: Nat, +snapshot: Snapshot, +side: U32, +index: U32, faces: List<&2, Face>) -> List<&2, Face>:
	match fuel:
		case 0n:
			faces
		case 1n+rest:
			+cell = Cell.at(side, index)
			Surface.scan(rest, snapshot, side, (index + 1 : U32),
				Surface.cell(Snapshot.read(snapshot, side, cell), snapshot, side, cell, faces))

def Surface.finish(+side: U32, result: Array<U32> & Snapshot) -> Body & Surface:
	(cells, snapshot) = result
	(Body{side, cells}, Surface{Surface.scan(U32.to_nat((side * side * side : U32)), snapshot, side, 0, Nil{})})

def Face.width(face: Face) -> U32:
	match face:
		case Face{cell,direction,material}: 1
		case Rectangle{cell,direction,material,width,height}: width

def Face.height(face: Face) -> U32:
	match face:
		case Face{cell,direction,material}: 1
		case Rectangle{cell,direction,material,width,height}: height

def Cuboid.surface(box: Cuboid, tail: List<&2,Face>) -> List<&2,Face>:
	Cuboid{Cell{+x,+y,+z},Cell{+hx,+hy,+hz},+m} = box
	+dx = (hx - x : U32)
	+dy = (hy - y : U32)
	+dz = (hz - z : U32)
	Rectangle{Cell{x,y,z},NegX{},m,dy,dz} <>
	Rectangle{Cell{(hx - 1 : U32),y,z},PosX{},m,dy,dz} <>
	Rectangle{Cell{x,y,z},NegY{},m,dx,dz} <>
	Rectangle{Cell{x,(hy - 1 : U32),z},PosY{},m,dx,dz} <>
	Rectangle{Cell{x,y,z},NegZ{},m,dx,dy} <>
	Rectangle{Cell{x,y,(hz - 1 : U32)},PosZ{},m,dx,dy} <> tail

def Cuboids.surface(boxes: List<&2,Cuboid>) -> List<&2,Face>:
	match boxes:
		case Nil{}: Nil{}
		case box <> rest: Cuboid.surface(box,Cuboids.surface(rest))

def Surface.build.dense(+side: U32, cells: Array<U32>) -> Body & Surface:
	Surface.finish(side,Snapshot.of(cells))

def Direction.show(direction: Direction) -> String:
	match direction:
		case NegX{}:
			"-x"
		case PosX{}:
			"+x"
		case NegY{}:
			"-y"
		case PosY{}:
			"+y"
		case NegZ{}:
			"-z"
		case PosZ{}:
			"+z"

def Cell.show(cell: Cell) -> String:
	Cell{x, y, z} = cell
	U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z)

def Surface.count.faces(faces: List<&2, Face>, n: U32) -> U32:
	match faces:
		case Nil{}:
			n
		case Con{face, rest}:
			Surface.count.faces(rest, (n + 1 : U32))

def Surface.count(surface: Surface) -> U32:
	Surface{faces} = surface
	Surface.count.faces(faces, 0)


def Cuboid.overlaps(box: Cuboid, sphere: MetricSphere) -> Bool:
	Cuboid{Cell{x,y,z},Cell{hx,hy,hz},m} = box
	MetricSphere{+point,radius} = sphere
	PointCm{+cx,+cy,+cz} = point
	+size = Voxel.size_cm()
	MetricSphere.distance(sphere,PointCm{
		F32.clamp(cx,((U32.to_f32(x) + 0.5) * size : F32),((U32.to_f32(hx) - 0.5) * size : F32)),
		F32.clamp(cy,((U32.to_f32(y) + 0.5) * size : F32),((U32.to_f32(hy) - 0.5) * size : F32)),
		F32.clamp(cz,((U32.to_f32(z) + 0.5) * size : F32),((U32.to_f32(hz) - 0.5) * size : F32))})

def Cuboid.half(box: Cuboid, axis: U32, upper: Bool) -> Cuboid:
	match box axis:
		case Cuboid{Cell{+x,+y,+z},Cell{+hx,+hy,+hz},+m} 0:
			+mid = (x + (hx - x) / 2 : U32)
			Bool.pick(Cuboid,upper,Cuboid{Cell{x,y,z},Cell{mid,hy,hz},m},Cuboid{Cell{mid,y,z},Cell{hx,hy,hz},m})
		case Cuboid{Cell{+x,+y,+z},Cell{+hx,+hy,+hz},+m} 1:
			+mid = (y + (hy - y) / 2 : U32)
			Bool.pick(Cuboid,upper,Cuboid{Cell{x,y,z},Cell{hx,mid,hz},m},Cuboid{Cell{x,mid,z},Cell{hx,hy,hz},m})
		case Cuboid{Cell{+x,+y,+z},Cell{+hx,+hy,+hz},+m} _:
			+mid = (z + (hz - z) / 2 : U32)
			Bool.pick(Cuboid,upper,Cuboid{Cell{x,y,z},Cell{hx,hy,mid},m},Cuboid{Cell{x,y,mid},Cell{hx,hy,hz},m})

def Cuboid.axis(box: Cuboid) -> U32:
	Cuboid{Cell{x,y,z},Cell{hx,hy,hz},m} = box
	+dx = (hx - x : U32)
	+dy = (hy - y : U32)
	+dz = (hz - z : U32)
	Bool.pick(U32,((dx >= dy) && (dx >= dz) : U32),0,Bool.pick(U32,(dy >= dz : U32),1,2))

def Cuboid.single(box: Cuboid) -> Bool:
	Cuboid{Cell{x,y,z},Cell{hx,hy,hz},m} = box
	U32.is_eq((hx - x : U32),1) && U32.is_eq((hy - y : U32),1) && U32.is_eq((hz - z : U32),1)

def Cuboid.cut(+fuel: Nat, overlaps: Bool, single: Bool, +box: Cuboid, +sphere: MetricSphere, tail: List<&2,Cuboid>) -> List<&2,Cuboid>:
	match fuel overlaps single:
		case _ False{} _: box <> tail
		case _ True{} True{}: tail
		case 0n True{} False{}: box <> tail
		case 1n+rest True{} False{}:
			+a = Cuboid.half(box,Cuboid.axis(box),True{})
			+b = Cuboid.half(box,Cuboid.axis(box),False{})
			Cuboid.cut(rest,Cuboid.overlaps(a,sphere),Cuboid.single(a),a,sphere,
				Cuboid.cut(rest,Cuboid.overlaps(b,sphere),Cuboid.single(b),b,sphere,tail))

def Cuboids.cut(boxes: List<&2,Cuboid>, +sphere: MetricSphere) -> List<&2,Cuboid>:
	match boxes:
		case Nil{}: Nil{}
		case +box <> rest:
			Cuboid.cut(96n,Cuboid.overlaps(box,sphere),Cuboid.single(box),box,sphere,Cuboids.cut(rest,sphere))

def Body.cut.checked(valid: Bool, boxes: List<&2,Cuboid>, sphere: MetricSphere) -> Body:
	match valid:
		case False{}: Cuboids{boxes}
		case True{}: Cuboids{Cuboids.cut(boxes,sphere)}

def Body.cut(body: Body, +sphere: MetricSphere) -> Body:
	match body:
		case Body{side,cells}: Body.cut.dense(side,cells,sphere)
		case Cuboids{boxes}: Body.cut.checked(MetricSphere.valid(sphere),boxes,sphere)

def Cuboids.insert(boxes: List<&2,Cuboid>, cell: Cell, material: U32) -> Body:
	match cell material:
		case _ 0: Cuboids{boxes}
		case Cell{+x,+y,+z} +m:
			Cuboids{Cuboid{Cell{x,y,z},Cell{(x + 1 : U32),(y + 1 : U32),(z + 1 : U32)},m} <> boxes}

def Body.write(body: Body, +cell: Cell, material: U32) -> Body:
	match body:
		case Body{side,cells}: Body.write.dense(side,cells,cell,material)
		case Cuboids{boxes}:
			Cuboids.insert(Cuboids.cut(boxes,MetricSphere{PointCm.cell(cell),0.0}),cell,material)

def Body.destroy(body: Body, brush: Brush) -> Body:
	match body:
		case Body{side,cells}: Body.destroy.dense(side,cells,brush)
		case Cuboids{boxes}:
			Sphere{cell,radius} = brush
			Body.cut(Cuboids{boxes},MetricSphere{PointCm.cell(cell),(U32.to_f32(radius) * Voxel.size_cm() : F32)})

def Surface.build(body: Body) -> Body & Surface:
	match body:
		case Body{side,cells}: Surface.build.dense(side,cells)
		case Cuboids{+boxes}: (Cuboids{boxes},Surface{Cuboids.surface(boxes)})
