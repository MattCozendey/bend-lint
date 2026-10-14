import Base
import ../material.bend as M
import ../lighting.bend as L
import ../voxel.bend as V
import ../render.bend as R
import ../dump.bend as D

def Check.require(ok: Bool, message: String) -> IO(Unit):
	match ok:
		case True{}:
			IO.pure(Unit, Unit{})
		case False{}:
			IO.die(Unit, 1, message)

def Inventory.materials() -> List<&2, M.Material>:
	[M.Foundation{}, M.Concrete{}, M.Frame{}, M.Machinery{}, M.Plaster{}]

def Inventory.directions() -> List<&2, V.Direction>:
	[V.NegX{}, V.PosX{}, V.NegY{}, V.PosY{}, V.NegZ{}, V.PosZ{}]

def Inventory.reference(material: M.Material) -> U32:
	match material:
		case M.Foundation{}:
			4964772
		case M.Concrete{}:
			13737320
		case M.Frame{}:
			6721452
		case M.Machinery{}:
			14259535
		case M.Plaster{}:
			14078148

def Rgb.near(+actual: F32, expected: F32, tolerance: F32) -> Bool:
	(F32.abs((actual - expected : F32)) < tolerance : F32)

# The source's native_geometry.cpp uses 0.002 on unquantized encoded channels.
def Rgb.source(color: M.LinearRgb, +packed: U32) -> Bool:
	M.LinearRgb{r, g, b} = color
	Rgb.near(M.Srgb.channel(r), (U32.to_f32((packed / 65536 % 256 : U32)) / 255.0 : F32), 0.002) &&
		Rgb.near(M.Srgb.channel(g), (U32.to_f32((packed / 256 % 256 : U32)) / 255.0 : F32), 0.002) &&
		Rgb.near(M.Srgb.channel(b), (U32.to_f32((packed % 256 : U32)) / 255.0 : F32), 0.002)

def Rgb.ordered(a: M.LinearRgb, b: M.LinearRgb) -> Bool:
	M.LinearRgb{ar, ag, ab} = a
	M.LinearRgb{br, bg, bb} = b
	((ar < br) && (ag < bg) && (ab < bb) : F32)

def Inventory.numeric(result: Maybe<&2, M.LinearRgb>, +material: M.Material, +palette: M.Palette) -> Bool:
	match result:
		case None{}:
			False{}
		case Some{+base}:
			+mid = M.LinearRgb.shade(base, M.Mid{})
			+low = M.LinearRgb.shade(base, M.Low{})
			M.LinearRgb.gamut(base) && M.LinearRgb.gamut(mid) && M.LinearRgb.gamut(low) &&
				Rgb.source(base, Inventory.reference(material)) && Rgb.ordered(low, mid) && Rgb.ordered(mid, base) &&
				U32.is_eq(M.Palette.color(palette, material, M.Full{}), M.LinearRgb.pack(base)) &&
				U32.is_eq(M.Palette.color(palette, material, M.Mid{}), M.LinearRgb.pack(mid)) &&
				U32.is_eq(M.Palette.color(palette, material, M.Low{}), M.LinearRgb.pack(low))

def Inventory.light(+direction: V.Direction) -> M.Light:
	match direction:
		case V.PosZ{}:
			M.Full{}
		case V.NegX{}:
			M.Mid{}
		case V.PosX{}:
			M.Mid{}
		case _:
			M.Low{}

def Inventory.swatches(directions: List<&2, V.Direction>, +palette: M.Palette, +repeat: M.Palette, +material: M.Material) -> Bool:
	match directions:
		case Nil{}:
			True{}
		case +direction <> rest:
			+color = M.Palette.surface(palette, M.Material.id(material), R.Face.light(direction))
			(color <= 16777215 : U32) && U32.is_ne(color, 5258540) &&
				U32.is_eq(color, M.Palette.color(palette, material, Inventory.light(direction))) &&
				U32.is_eq(color, M.Palette.surface(repeat, M.Material.id(material), R.Face.light(direction))) &&
				Inventory.swatches(rest, palette, repeat, material)

def Inventory.check(materials: List<&2, M.Material>, +palette: M.Palette, +repeat: M.Palette) -> Bool:
	match materials:
		case Nil{}:
			True{}
		case +material <> rest:
			Inventory.swatches(Inventory.directions(), palette, repeat, material) &&
				Inventory.numeric(M.Oklch.linear(M.Material.oklch(material)), material, palette) && Inventory.check(rest, palette, repeat)

def Inventory.unknown(directions: List<&2, V.Direction>, +palette: M.Palette, +material: U32) -> Bool:
	match directions:
		case Nil{}:
			True{}
		case direction <> rest:
			U32.is_eq(M.Palette.surface(palette, material, R.Face.light(direction)), 16711935) && Inventory.unknown(rest, palette, material)

def Inventory.text.directions(directions: List<&2, V.Direction>, +palette: M.Palette, +material: M.Material) -> String:
	match directions:
		case Nil{}:
			""
		case +direction <> rest:
			"material=" ++ U32.show(M.Material.id(material)) ++ " direction=" ++ V.Direction.show(direction) ++
				" rgb=" ++ U32.show(M.Palette.surface(palette, M.Material.id(material), R.Face.light(direction))) ++ "\n" ++
				Inventory.text.directions(rest, palette, material)

def Inventory.text(materials: List<&2, M.Material>, +palette: M.Palette) -> String:
	match materials:
		case Nil{}:
			""
		case material <> rest:
			Inventory.text.directions(Inventory.directions(), palette, material) ++ Inventory.text(rest, palette)

def Rgb.fitted(color: M.LinearRgb, original: M.Oklch) -> Bool:
	M.LinearRgb{+r, +g, +b} = color
	M.Oklch{l0, +c0, h0} = original
	+l = F32.pow((0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b : F32), (1.0 / 3.0 : F32))
	+m = F32.pow((0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b : F32), (1.0 / 3.0 : F32))
	+s = F32.pow((0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b : F32), (1.0 / 3.0 : F32))
	+lightness = (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s : F32)
	+a = (1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s : F32)
	+bb = (0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s : F32)
	+angle = (h0 * 0.017453292519943295 : F32)
	+cosine = F32.cos(angle)
	+sine = F32.sin(angle)
	Rgb.near(lightness, F32.clamp(l0, 0.0, 1.0), 0.00002) &&
		((F32.sqrt((a * a + bb * bb : F32)) <= c0 + 0.00002) &&
		(F32.abs((a * sine - bb * cosine : F32)) < 0.00002) &&
		(a * cosine + bb * sine >= 0.0 - 0.00002) : F32)

def Grid.converted(result: Maybe<&2, M.LinearRgb>, +color: M.Oklch) -> Bool:
	match result:
		case None{}:
			False{}
		case Some{+rgb}:
			M.LinearRgb.gamut(rgb) && Rgb.fitted(rgb, color) && (M.LinearRgb.pack(rgb) <= 16777215 : U32)

def Grid.hues(hues: List<&2, F32>, +lightness: F32, +chroma: F32) -> Bool:
	match hues:
		case Nil{}:
			True{}
		case hue <> rest:
			+color = {M.Oklch{lightness, chroma, hue} : M.Oklch}
			Grid.converted(M.Oklch.linear(color), color) && Grid.hues(rest, lightness, chroma)

def Grid.chromas(chromas: List<&2, F32>, +lightness: F32) -> Bool:
	match chromas:
		case Nil{}:
			True{}
		case chroma <> rest:
			Grid.hues([0.0, 30.0, 60.0, 90.0, 120.0, 150.0, 180.0, 210.0, 240.0, 270.0, 300.0, 330.0, 360.0], lightness, chroma) &&
				Grid.chromas(rest, lightness)

def Grid.lightness(values: List<&2, F32>) -> Bool:
	match values:
		case Nil{}:
			True{}
		case lightness <> rest:
			Grid.chromas([0.0, 0.02, 0.1, 0.25, 0.5, 1.0], lightness) && Grid.lightness(rest)

def Grid.rejected(result: Maybe<&2, M.LinearRgb>) -> Bool:
	match result:
		case None{}:
			True{}
		case Some{color}:
			False{}

def Grid.invalid() -> Bool:
	+inf = (1.0 / 0.0 : F32)
	+nan = (0.0 / 0.0 : F32)
	Grid.rejected(M.Oklch.linear(M.Oklch{0.5, (0.0 - 0.01 : F32), 30.0})) &&
		Grid.rejected(M.Oklch.linear(M.Oklch{inf, 0.1, 30.0})) &&
		Grid.rejected(M.Oklch.linear(M.Oklch{0.5, inf, 30.0})) &&
		Grid.rejected(M.Oklch.linear(M.Oklch{0.5, 0.1, inf})) &&
		Grid.rejected(M.Oklch.linear(M.Oklch{nan, 0.1, 30.0})) &&
		Grid.rejected(M.Oklch.linear(M.Oklch{0.5, nan, 30.0})) &&
		Grid.rejected(M.Oklch.linear(M.Oklch{0.5, 0.1, nan}))

def Cell.equal(a: V.Cell, b: V.Cell) -> Bool:
	V.Cell{ax, ay, az} = a
	V.Cell{bx, by, bz} = b
	U32.is_eq(ax, bx) && U32.is_eq(ay, by) && U32.is_eq(az, bz)

def Pick.equal(a: Maybe<&2, V.Cell>, b: Maybe<&2, V.Cell>) -> Bool:
	match a b:
		case None{} None{}:
			True{}
		case Some{x} Some{y}:
			Cell.equal(x, y)
		case _ _:
			False{}

def Pick.occupied(cell: Maybe<&2, V.Cell>) -> Bool:
	match cell:
		case None{}:
			False{}
		case Some{c}:
			True{}

def Projected.color(value: Maybe<&2, R.Projected>, expected: U32) -> Bool:
	match value:
		case None{}:
			False{}
		case Some{R.Projected{cell, direction, plane, u, v, color, visibility, id, bounds,width,height,outline}}:
			U32.is_eq(L.Ramp.color(color, 9), expected)

def Faces.stable(faces: List<&2, V.Face>, +palette: M.Palette, +basis: R.Basis, +moved: R.Basis, +material: U32) -> Bool:
	match faces:
		case Nil{}:
			True{}
		case +face <> rest:
			match face:
				case V.Face{+cell,+direction,id}:
					+daylight = L.Palette.build()
					+color = L.Ramp.color(L.Palette.surface(daylight, material, direction), 9)
					U32.is_eq(id, material) &&
						Projected.color(R.Projected.of(face, basis, daylight, 0), color) &&
						Projected.color(R.Projected.of(face, moved, daylight, 0), color) &&
						Faces.stable(rest, palette, basis, moved, material)
				case V.Rectangle{+cell,+direction,id,width,height}:
					+daylight = L.Palette.build()
					+color = L.Ramp.color(L.Palette.surface(daylight, material, direction), 9)
					U32.is_eq(id, material) &&
						Projected.color(R.Projected.of(face, basis, daylight, 0), color) &&
						Projected.color(R.Projected.of(face, moved, daylight, 0), color) &&
						Faces.stable(rest, palette, basis, moved, material)

def Cells.preserved(fuel: Nat, +snapshot: V.Snapshot, +index: U32, +material: U32) -> Bool:
	match fuel:
		case 0n:
			True{}
		case 1n+rest:
			+cell = V.Cell.at(8, index)
			+wanted = Bool.pick(U32, Cell.equal(cell, V.Cell{1, 1, 1}) || Cell.equal(cell, V.Cell{5, 3, 2}), material, 0)
			U32.is_eq(V.Snapshot.read(snapshot, 8, cell), wanted) && Cells.preserved(rest, snapshot, (index + 1 : U32), material)

def Geometry.snapshot(result: Array<U32> & V.Snapshot, +surface: V.Surface, +material: U32, palette: M.Palette) -> Bool:
	(cells, snapshot) = result
	V.Surface{faces} = surface
	U32.is_eq(V.Surface.count(surface), 12) && Cells.preserved(512n, snapshot, 0, material) &&
		Faces.stable(faces, palette, R.Camera.basis(R.Camera.initial()), R.Camera.basis(R.Camera.look(R.Camera.initial(), 5.0, 7.0)), material)

def Geometry.surface(result: V.Body & V.Surface, material: U32, palette: M.Palette) -> Bool:
	match result:
		case (V.Body{side,cells},surface): Geometry.snapshot(V.Snapshot.of(cells),surface,material,palette)
		case (V.Cuboids{boxes},surface): False{}

def Geometry.identity(+material: U32, palette: M.Palette) -> Bool:
	Geometry.surface(V.Surface.build(V.Body.write(V.Body.write(V.Body.empty(3n), V.Cell{1, 1, 1}, material), V.Cell{5, 3, 2}, material)), material, palette)

def Pick.row(fuel: Nat, +scene: R.RenderScene, +baseline: R.RenderScene, +x: U32, +y: U32) -> Bool:
	match fuel:
		case 0n:
			True{}
		case 1n+rest:
			Pick.equal(R.RenderScene.pick(scene, x, y), R.RenderScene.pick(baseline, x, y)) &&
				Pick.row(rest, scene, baseline, (x + 32 : U32), y)

def Pick.rows(fuel: Nat, +scene: R.RenderScene, +baseline: R.RenderScene, +y: U32) -> Bool:
	match fuel:
		case 0n:
			Pick.occupied(R.RenderScene.pick(scene, 256, 256)) &&
				Pick.equal(R.RenderScene.pick(scene, 256, 256), R.RenderScene.pick(baseline, 256, 256)) &&
				Pick.equal(R.RenderScene.pick(scene, 512, 256), None{})
		case 1n+rest:
			Pick.row(16n, scene, baseline, 0, y) && Pick.rows(rest, scene, baseline, (y + 32 : U32))

def Surface.material(faces: List<&2, V.Face>, +material: U32) -> Bool:
	match faces:
		case Nil{}:
			True{}
		case V.Face{cell, direction, id} <> rest:
			U32.is_eq(id, material) && Surface.material(rest, material)
		case V.Rectangle{cell,direction,id,width,height} <> rest:
			U32.is_eq(id,material) && Surface.material(rest,material)

def Surface.preserved(surface: V.Surface, material: U32) -> Bool:
	V.Surface{faces} = surface
	Surface.material(faces, material)

def Image.quadrant(right: Bool, bottom: Bool, tl: Image, tr: Image, bl: Image, br: Image) -> Image:
	match right bottom:
		case False{} False{}:
			tl
		case True{} False{}:
			tr
		case False{} True{}:
			bl
		case True{} True{}:
			br

def Image.pixel(fuel: Nat, image: Image, +x: U32, +y: U32, +size: U32) -> U32:
	match fuel image:
		case _ Pix{color}:
			color
		case 0n _:
			0
		case 1n+rest Qua{tl, tr, bl, br}:
			+h = (size / 2 : U32)
			Image.pixel(rest, Image.quadrant((x >= h : U32), (y >= h : U32), tl, tr, bl, br), (x % h : U32), (y % h : U32), h)

def Export.images(full: Image & R.RenderScene, cut: Image & R.RenderScene, +material: U32, +output: String) -> IO(Unit):
	(full_image, scene) = full
	(cut_image, carved) = cut
	do IO<Unit>:
		D.Dump.ppm(output ++ "/material-" ++ U32.show(material) ++ "-full.ppm", full_image)
		D.Dump.ppm(output ++ "/material-" ++ U32.show(material) ++ "-cut.ppm", cut_image)
		IO.print("Exported full/cut material=" ++ U32.show(material))

def Export.scenes(result: V.Body & V.Surface, +full: V.Surface, +material: U32, +output: String, +baseline: R.RenderScene, +palette: M.Palette) -> IO(Unit):
	(body, +cut) = result
	+scene = R.RenderScene.build(full, R.Camera.initial(), 4n)
	+carved = R.RenderScene.build(cut, R.Camera.initial(), 4n)
	do IO<Unit>:
		Check.require(Geometry.identity(material, palette), "Cell or face identity/appearance changed for material " ++ U32.show(material))
		Check.require(Surface.preserved(full, material) && Surface.preserved(cut, material), "Surface lost material identity")
		Check.require(Pick.rows(16n, scene, baseline, 0), "Material changed real picking for " ++ U32.show(material))
		Export.images(R.RenderScene.image(scene, 4n), R.RenderScene.image(carved, 4n), material, output)

def Export.cut(result: V.Body & V.Surface, material: U32, output: String, baseline: R.RenderScene, palette: M.Palette) -> IO(Unit):
	(body, full) = result
	Export.scenes(V.Surface.build(V.Body.cut(body, V.MetricSphere.demo())), full, material, output, baseline, palette)

def Export.material(+material: U32, output: String, baseline: R.RenderScene, palette: M.Palette) -> IO(Unit):
	Export.cut(V.Surface.build(V.Body.filled(3n, material)), material, output, baseline, palette)

def Export.known(materials: List<&2, M.Material>, +output: String, +baseline: R.RenderScene, +palette: M.Palette) -> IO(Unit):
	match materials:
		case Nil{}:
			IO.pure(Unit, Unit{})
		case material <> rest:
			do IO<Unit>:
				Export.material(M.Material.id(material), output, baseline, palette)
				Export.known(rest, output, baseline, palette)

def Export.unknown.image(result: Image & R.RenderScene, +material: U32, output: String) -> IO(Unit):
	(+image, scene) = result
	do IO<Unit>:
		Check.require(U32.is_eq(Image.pixel(9n, image, 256, 256, 512), 16711935), "Unknown material is not visibly diagnostic magenta")
		D.Dump.ppm(output ++ "/material-" ++ U32.show(material) ++ "-full.ppm", image)
		IO.print("Unknown material preserved and visible=" ++ U32.show(material))

def Export.unknown.surface(result: V.Body & V.Surface, +material: U32, +palette: M.Palette, +baseline: R.RenderScene, +output: String) -> IO(Unit):
	(body, +surface) = result
	+scene = R.RenderScene.build(surface, R.Camera.initial(), 4n)
	do IO<Unit>:
		Check.require(Inventory.unknown(Inventory.directions(), palette, material), "Unknown material must be magenta on every direction")
		Check.require(Geometry.identity(material, palette) && Surface.preserved(surface, material), "Unknown material lost occupied geometry")
		Check.require(Pick.rows(16n, scene, baseline, 0), "Unknown material changed real picking")
		Export.unknown.image(R.RenderScene.image(scene, 4n), material, output)

def Export.unknown(+material: U32, palette: M.Palette, baseline: R.RenderScene, output: String) -> IO(Unit):
	Export.unknown.surface(V.Surface.build(V.Body.filled(3n, material)), material, palette, baseline, output)

def Evidence.write(path: String, text: String) -> IO(Unit):
	do IO<Unit>:
		file : File <- IO.try(File, File.open(path, "w"))
		result : File & Result<&1, &1, U32 & String, Unit> <- File.write(file, text)
		file : File <- D.Dump.written(result)
		File.close(file)

def Scene.of(result: V.Body & V.Surface) -> R.RenderScene:
	(body, surface) = result
	R.RenderScene.build(surface, R.Camera.initial(), 4n)

def Run.inventory(valid: Bool, +text: String, +palette: M.Palette, +output: String) -> IO(Unit):
	+baseline = Scene.of(V.Surface.build(V.Body.solid(3n)))
	do IO<Unit>:
		Check.require(valid, "Authored inventory, source tolerance, lighting, packing or repeatability failed")
		Check.require(Grid.lightness([(0.0 - 0.25 : F32), 0.0, 0.125, 0.25, 0.5, 0.75, 0.875, 1.0, 1.25]) && Grid.invalid(),
			"OKLCH gamut, retained lightness/hue, chroma reduction or invalid-input domain failed")
		Check.require(U32.is_eq(M.Palette.surface(palette, 0, M.Full{}), 0), "Empty material query must be black")
		IO.write(text)
		Evidence.write(output ++ "/swatches.txt", text)
		IO.print("Runtime numeric evidence passed for 5 materials, 6 directions and 702 gamut/achromatic colors.")
		Export.known(Inventory.materials(), output, baseline, palette)
		Export.unknown(7, palette, baseline, output)
		Export.unknown(4294967295, palette, baseline, output)
		IO.print("Material evidence passed. Picking matched on 256 screen samples plus center and outside bounds for each ID.")

def Run.output(output: String) -> IO(Unit):
	+palette = M.Palette.build()
	Run.inventory(Inventory.check(Inventory.materials(), palette, M.Palette.build()), Inventory.text(Inventory.materials(), palette), palette, output)

def Run.args(args: List<String>) -> IO(Unit):
	match args:
		case program <> "--output" <> output <> Nil{}:
			Run.output(output)
		case _:
			IO.die(Unit, 2, "Usage: material-check --output EXISTING_DIRECTORY")

def main() -> IO(Unit):
	IO.bind(List<String>, Unit, IO.args(), Run.args)
