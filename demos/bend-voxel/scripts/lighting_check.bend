import Base
import ../voxel.bend as V
import ../render.bend as R
import ../lighting.bend as L
import ../material.bend as M
import ../dump.bend as D

def Check.require(ok: Bool, message: String) -> IO(Unit):
	match ok:
		case True{}:
			IO.pure(Unit, Unit{})
		case False{}:
			IO.die(Unit, 1, message)

def Cells.add(occupied: Bool, cell: V.Cell, rest: List<&2, V.Cell>) -> List<&2, V.Cell>:
	match occupied:
		case False{}:
			rest
		case True{}:
			cell <> rest

def Cells.read(fuel: Nat, +snapshot: V.Snapshot, +side: U32, +index: U32) -> List<&2, V.Cell>:
	match fuel:
		case 0n:
			Nil{}
		case 1n+rest:
			+cell = V.Cell.at(side, index)
			Cells.add(U32.is_ne(V.Snapshot.read(snapshot, side, cell), 0), cell, Cells.read(rest, snapshot, side, (index + 1 : U32)))

# Independent occupied-cell slab reference: no surface faces, projection
# bounds, tile candidates, or engine ray/face intersection helpers.
def Oracle.accept(intersects: Bool, depth: F32, old: F32) -> F32:
	match intersects:
		case False{}:
			old
		case True{}:
			F32.min(depth, old)

def Oracle.cell(cell: V.Cell, origin: R.Vec3, ray: R.Vec3, old: F32) -> F32:
	V.Cell{x, y, z} = cell
	R.Vec3{+ox, +oy, +oz} = origin
	R.Vec3{+dx, +dy, +dz} = ray
	+fx = U32.to_f32(x)
	+fy = U32.to_f32(y)
	+fz = U32.to_f32(z)
	+xa = ((fx - ox) / dx : F32)
	+xb = ((fx + 1.0 - ox) / dx : F32)
	+ya = ((fy - oy) / dy : F32)
	+yb = ((fy + 1.0 - oy) / dy : F32)
	+za = ((fz - oz) / dz : F32)
	+zb = ((fz + 1.0 - oz) / dz : F32)
	+enter = F32.max(F32.min(xa, xb), F32.max(F32.min(ya, yb), F32.min(za, zb)))
	+leave = F32.min(F32.max(xa, xb), F32.min(F32.max(ya, yb), F32.max(za, zb)))
	Oracle.accept(((enter >= 0.1) && (enter <= leave) : F32), enter, old)

def Oracle.depth(cells: List<&2, V.Cell>, +origin: R.Vec3, +ray: R.Vec3, closest: F32) -> F32:
	match cells:
		case Nil{}:
			closest
		case cell <> rest:
			Oracle.depth(rest, origin, ray, Oracle.cell(cell, origin, ray, closest))

def Oracle.pixel(+cells: List<&2, V.Cell>, +shadow: R.ShadowMap, +x: U32, +y: U32) -> Bool:
	R.ShadowMap{R.Basis{eye, right, up, +forward, +scale, near}, depths, ground, grid} = shadow
	+step = (512.0 / U32.to_f32(R.Shadow.width()) : F32)
	+origin = R.Vec3.add(eye, R.Vec3.add(R.Vec3.scale(right, (((U32.to_f32(x) + 0.5) * step - 256.0) / scale : F32)),
		R.Vec3.scale(up, ((256.0 - (U32.to_f32(y) + 0.5) * step) / scale : F32))))
	+expected = Oracle.depth(cells, origin, forward, 1.0e30)
	+actual = R.Shadow.at(depths, x, y)
	(F32.abs((actual - expected : F32)) <= 0.00003 : F32)

def Oracle.row(fuel: Nat, +cells: List<&2, V.Cell>, +shadow: R.ShadowMap, +x: U32, +y: U32) -> Bool:
	match fuel:
		case 0n:
			True{}
		case 1n+rest:
			Oracle.pixel(cells, shadow, x, y) && Oracle.row(rest, cells, shadow, (x + 1 : U32), y)

def Oracle.rows(fuel: Nat, +cells: List<&2, V.Cell>, +shadow: R.ShadowMap, +y: U32) -> Bool:
	match fuel:
		case 0n:
			True{}
		case 1n+rest:
			Oracle.row(U32.to_nat(R.Shadow.width()), cells, shadow, 0, y) && Oracle.rows(rest, cells, shadow, (y + 1 : U32))

def Colors.ordered(+a: U32, +b: U32) -> Bool:
	((a / 65536 <= b / 65536) && (a / 256 % 256 <= b / 256 % 256) && (a % 256 <= b % 256) && (b <= 16777215) : U32)

def Colors.levels(fuel: Nat, +ramp: L.Ramp, +index: U32) -> Bool:
	match fuel:
		case 0n:
			True{}
		case 1n+rest:
			Colors.ordered(L.Ramp.color(ramp, index), L.Ramp.color(ramp, (index + 1 : U32))) && Colors.levels(rest, ramp, (index + 1 : U32))

def Colors.directions(directions: List<&2, V.Direction>, +palette: L.Palette, +material: M.Material) -> Bool:
	match directions:
		case Nil{}:
			True{}
		case +direction <> rest:
			+ramp = L.Palette.color(palette, material, direction)
			Colors.levels(9n, ramp, 0) &&
				Bool.pick(Bool, F32.is_eq(L.Sun.cosine(direction), 0.0), U32.is_eq(L.Ramp.color(ramp, 0), L.Ramp.color(ramp, 9)),
					U32.is_ne(L.Ramp.color(ramp, 0), L.Ramp.color(ramp, 9))) && Colors.directions(rest, palette, material)

def Colors.materials(materials: List<&2, M.Material>, +palette: L.Palette) -> Bool:
	match materials:
		case Nil{}:
			True{}
		case material <> rest:
			Colors.directions([V.NegX{}, V.PosX{}, V.NegY{}, V.PosY{}, V.NegZ{}, V.PosZ{}], palette, material) && Colors.materials(rest, palette)

def Depths.same(a: R.ShadowDepth, b: R.ShadowDepth) -> Bool:
	match a b:
		case R.Depth{ac} R.Depth{bc}:
			U32.is_eq(F32.bits(ac), F32.bits(bc))
		case R.DepthQuad{at, ar, ab, ac} R.DepthQuad{bt, br, bb, bc}:
			Depths.same(at, bt) && Depths.same(ar, br) && Depths.same(ab, bb) && Depths.same(ac, bc)
		case _ _:
			False{}

def Fields.same(a: L.ColorField, b: L.ColorField) -> Bool:
	match a b:
		case L.Color{ac} L.Color{bc}:
			U32.is_eq(ac, bc)
		case L.ColorQuad{at, ar, ab, ac} L.ColorQuad{bt, br, bb, bc}:
			Fields.same(at, bt) && Fields.same(ar, br) && Fields.same(ab, bb) && Fields.same(ac, bc)
		case _ _:
			False{}

def Fields.faces_same(a: List<&2, R.Illuminated>, b: List<&2, R.Illuminated>) -> Bool:
	match a b:
		case Nil{} Nil{}:
			True{}
		case R.Illuminated{face_a, field_a} <> rest_a R.Illuminated{face_b, field_b} <> rest_b:
			Fields.same(field_a, field_b) && Fields.faces_same(rest_a, rest_b)
		case _ _:
			False{}

def Fields.ground_same(a: R.GroundLighting, b: R.GroundLighting) -> Bool:
	R.GroundLighting{field_a, ground_a, grid_a} = a
	R.GroundLighting{field_b, ground_b, grid_b} = b
	Fields.same(field_a, field_b)

type Receiver is Data:
	FaceReceiver{cell: V.Cell, direction: V.Direction}
	RectangleReceiver{cell: V.Cell, direction: V.Direction, width: U32, height: U32}
	GroundReceiver{}

def Receiver.face(direction: V.Direction, coordinates: R.Vec3, +u: F32, +v: F32) -> R.Vec3:
	R.Vec3{plane, base_u, base_v} = coordinates
	R.Face.point(direction, plane, (base_u + u : F32), (base_v + v : F32))

def Receiver.point(receiver: Receiver, +u: F32, +v: F32) -> R.Vec3:
	match receiver:
		case FaceReceiver{cell, +direction}:
			Receiver.face(direction, R.Face.coordinates(direction, cell), u, v)
		case RectangleReceiver{cell,+direction,width,height}:
			Receiver.face(direction,R.Face.coordinates(direction,cell),(u * U32.to_f32(width) : F32),(v * U32.to_f32(height) : F32))
		case GroundReceiver{}:
			R.Vec3{(u * 40.0 - 16.0 : F32), (v * 40.0 - 16.0 : F32), (0.0 - 0.5 : F32)}

def Receiver.direction(receiver: Receiver) -> V.Direction:
	match receiver:
		case FaceReceiver{cell, direction}:
			direction
		case RectangleReceiver{cell,direction,width,height}:
			direction
		case GroundReceiver{}:
			V.PosZ{}

# Every cached receiver texel must decode to its original nine-tap sun
# comparison. This validates compression and lookup against the depth path.
def Fields.row(fuel: Nat, +field: L.ColorField, +receiver: Receiver, +shadow: R.ShadowMap, +size: U32, +x: U32, +y: U32) -> Bool:
	match fuel:
		case 0n:
			True{}
		case 1n+rest:
			+u = ((U32.to_f32(x) + 0.5) / U32.to_f32(size) : F32)
			+v = ((U32.to_f32(y) + 0.5) / U32.to_f32(size) : F32)
			U32.is_eq(L.ColorField.sample(field, u, v), R.Shadow.visibility(shadow, Receiver.point(receiver, u, v), Receiver.direction(receiver))) &&
				Fields.row(rest, field, receiver, shadow, size, (x + 1 : U32), y)

def Fields.rows(fuel: Nat, +field: L.ColorField, +receiver: Receiver, +shadow: R.ShadowMap, +size: U32, +y: U32) -> Bool:
	match fuel:
		case 0n:
			True{}
		case 1n+rest:
			Fields.row(U32.to_nat(size), field, receiver, shadow, size, 0, y) && Fields.rows(rest, field, receiver, shadow, size, (y + 1 : U32))

def Fields.faces(faces: List<&2, R.Illuminated>, +shadow: R.ShadowMap) -> Bool:
	match faces:
		case Nil{}:
			True{}
		case R.Illuminated{V.Face{cell, direction, material}, field} <> rest:
			Fields.rows(16n, field, FaceReceiver{cell, direction}, shadow, 16, 0) && Fields.faces(rest, shadow)
		case R.Illuminated{V.Rectangle{cell,direction,material,+width,+height},field} <> rest:
			+depth = U32.to_nat(U32.min(8,U32.max(4,(U32.from_nat(U32.log2(U32.max(width,height))) + 1 : U32))))
			+size = U32.pow(2,depth)
			Fields.rows(U32.to_nat(size),field,RectangleReceiver{cell,direction,width,height},shadow,size,0) && Fields.faces(rest,shadow)

def Fields.cache(cache: R.LightingCache) -> Bool:
	R.LightingCache{+sun, faces, R.GroundLighting{field, ground, grid}} = cache
	Fields.faces(faces, sun) && Fields.rows(256n, field, GroundReceiver{}, sun, 256, 0)

def Scene.fields(scene: R.RenderScene) -> Bool:
	R.RenderScene{basis, tiles, count, cache} = scene
	Fields.cache(cache)

def Cache.same(a: R.RenderScene, b: R.RenderScene) -> Bool:
	R.RenderScene{basis_a, tiles_a, count_a, R.LightingCache{R.ShadowMap{sun_a, depths_a, ground_a, grid_a}, faces_a, lighting_a}} = a
	R.RenderScene{basis_b, tiles_b, count_b, R.LightingCache{R.ShadowMap{sun_b, depths_b, ground_b, grid_b}, faces_b, lighting_b}} = b
	Depths.same(depths_a, depths_b) && Fields.faces_same(faces_a, faces_b) && Fields.ground_same(lighting_a, lighting_b)

def Scene.shadow(scene: R.RenderScene) -> R.ShadowMap:
	R.RenderScene{basis, tiles, count, R.LightingCache{shadow, faces, ground}} = scene
	shadow

def Run.export(result: Image & R.RenderScene, path: String) -> IO(Unit):
	(image, scene) = result
	D.Dump.ppm(path, image)

def Run.snapshot(result: Array<U32> & V.Snapshot, +side: U32, +surface: V.Surface, +name: String, +output: String) -> IO(Unit):
	(cells, snapshot) = result
	+scene = R.RenderScene.build(surface, R.Camera.initial(), 5n)
	+opposite = {R.Camera{R.Vec3{(0.0 - 8.0 : F32), 16.0, 12.0}, (0.0 - 0.78539816 : F32), (0.0 - 0.44051066 : F32)} : R.Camera}
	+reprojected = R.RenderScene.reproject(surface, opposite, 5n, scene)
	+shadow = Scene.shadow(scene)
	do IO<Unit>:
		Check.require(Oracle.rows(U32.to_nat(R.Shadow.width()), Cells.read(U32.to_nat((side * side * side : U32)), snapshot, side, 0), shadow, 0), name ++ ": sun map disagrees with occupied-cell slab reference")
		Check.require(Scene.fields(scene), name ++ ": illumination fields do not preserve sun visibility")
		Check.require(Cache.same(scene, reprojected), name ++ ": camera movement rebuilt or changed sun depths")
		Check.require(U32.is_eq(R.Shadow.visibility(shadow, R.Vec3{100.0, 100.0, 100.0}, V.PosZ{}), 9), "Shadow-map border is not fully lit")
		Run.export(R.RenderScene.image(reprojected, 5n), output ++ "/" ++ name ++ "-opposite.ppm")
		IO.print(name ++ ": all " ++ U32.show((R.Shadow.width() * R.Shadow.width() : U32)) ++ " sun texels match occupied cells; camera cache preserved")

def Run.body(result: V.Body & V.Surface, name: String, output: String) -> IO(Unit):
	match result:
		case (V.Body{+side,cells},surface): Run.snapshot(V.Snapshot.of(cells),side,surface,name,output)
		case (V.Cuboids{boxes},surface): IO.die(Unit,1,"The occupied-cell oracle requires the cube fixture")

# A convex solid cannot shadow its own sun-facing planes. Cover their whole
# extent, including near the edges where filtered depth taps cross faces.
def Convex.row(fuel: Nat, +shadow: R.ShadowMap, +direction: V.Direction, +plane: F32, +x: U32, +y: U32) -> Bool:
	match fuel:
		case 0n:
			True{}
		case 1n+rest:
			U32.is_eq(R.Shadow.visibility(shadow, R.Face.point(direction, plane, ((U32.to_f32(x) + 0.5) * 0.125 : F32),
				((U32.to_f32(y) + 0.5) * 0.125 : F32)), direction), 9) && Convex.row(rest, shadow, direction, plane, (x + 1 : U32), y)

def Convex.rows(fuel: Nat, +shadow: R.ShadowMap, +direction: V.Direction, +plane: F32, +y: U32) -> Bool:
	match fuel:
		case 0n:
			True{}
		case 1n+rest:
			Convex.row(64n, shadow, direction, plane, 0, y) && Convex.rows(rest, shadow, direction, plane, (y + 1 : U32))

def Convex.surface(surface: V.Surface) -> Bool:
	+shadow = R.ShadowMap.build(surface)
	Convex.rows(64n, shadow, V.NegX{}, 0.0, 0) && Convex.rows(64n, shadow, V.PosY{}, 8.0, 0) && Convex.rows(64n, shadow, V.PosZ{}, 8.0, 0)

def Convex.body(result: V.Body & V.Surface) -> Bool:
	(body, surface) = result
	Convex.surface(surface)

def Run.output(+output: String) -> IO(Unit):
	+palette = L.Palette.build()
	do IO<Unit>:
		Check.require(Colors.materials([M.Foundation{}, M.Concrete{}, M.Frame{}, M.Machinery{}], palette), "Daylight channels must be bounded and monotone across all materials, directions and visibility levels")
		Check.require(Convex.body(V.Surface.build(V.Body.solid(3n))), "Convex body's sun-facing planes contain self-shadow acne")
		Run.body(V.Surface.build(V.Body.solid(3n)), "full", output)
		Run.body(V.Surface.build(V.Body.cut(V.Body.solid(3n), V.MetricSphere.demo())), "cut", output)
		Run.body(V.Surface.build(V.Body.empty(3n)), "empty", output)
		IO.print("Lighting runtime properties passed.")

def Run.args(args: List<String>) -> IO(Unit):
	match args:
		case program <> "--output" <> output <> Nil{}:
			Run.output(output)
		case _:
			IO.die(Unit, 2, "Usage: lighting-check --output EXISTING_DIRECTORY")

def main() -> IO(Unit):
	IO.bind(List<String>, Unit, IO.args(), Run.args)
