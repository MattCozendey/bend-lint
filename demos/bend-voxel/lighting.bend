import Base
import ./material.bend as M
import ./voxel.bend as V

# Nine sun-depth comparisons produce ten visibility levels. Encode on the
# host so every execution lane uses the same sRGB integers at pixel leaves.
type Ramp is Data:
	Flat{color: U32}
	Ramp{c0: U32, c1: U32, c2: U32, c3: U32, c4: U32, c5: U32, c6: U32, c7: U32, c8: U32, c9: U32}

type Sides is Data:
	Sides{nx: Ramp, px: Ramp, ny: Ramp, py: Ramp, nz: Ramp, pz: Ramp}

type Palette is Data:
	Palette{foundation: Sides, concrete: Sides, frame: Sides, machinery: Sides}

# Compressed world-space illumination. Uniform regions terminate at Color;
# the renderer samples only its receiver's field, never the sun-depth tree.
type ColorField is Data:
	Color{color: U32}
	ColorQuad{tl: ColorField, tr: ColorField, bl: ColorField, br: ColorField}

def ColorField.join(a: ColorField, b: ColorField, c: ColorField, d: ColorField) -> ColorField:
	match a b c d:
		case Color{+ac} Color{+bc} Color{+cc} Color{+dc}:
			Bool.pick(ColorField, U32.is_eq(ac, bc) && U32.is_eq(ac, cc) && U32.is_eq(ac, dc), Color{ac}, ColorQuad{Color{ac}, Color{bc}, Color{cc}, Color{dc}})
		case +a +b +c +d:
			ColorQuad{a, b, c, d}

def ColorField.read(field: ColorField, +u: F32, +v: F32, right: Bool, bottom: Bool) -> U32:
	match field:
		case Color{color}:
			color
		case ColorQuad{tl, tr, bl, br}:
			match right bottom:
				case False{} False{}:
					ColorField.read(tl, (u * 2.0 : F32), (v * 2.0 : F32), (u >= 0.25 : F32), (v >= 0.25 : F32))
				case True{} False{}:
					ColorField.read(tr, (u * 2.0 - 1.0 : F32), (v * 2.0 : F32), (u >= 0.75 : F32), (v >= 0.25 : F32))
				case False{} True{}:
					ColorField.read(bl, (u * 2.0 : F32), (v * 2.0 - 1.0 : F32), (u >= 0.25 : F32), (v >= 0.75 : F32))
				case True{} True{}:
					ColorField.read(br, (u * 2.0 - 1.0 : F32), (v * 2.0 - 1.0 : F32), (u >= 0.75 : F32), (v >= 0.75 : F32))

def ColorField.sample(field: ColorField, +u: F32, +v: F32) -> U32:
	ColorField.read(field, u, v, (u >= 0.5 : F32), (v >= 0.5 : F32))

def Ramp.constant(+color: U32) -> Ramp:
	Flat{color}

def Ramp.color(ramp: Ramp, visible: U32) -> U32:
	match ramp:
		case Flat{color}:
			color
		case Ramp{c0, c1, c2, c3, c4, c5, c6, c7, c8, c9}:
			match visible:
				case 0:
					c0
				case 1:
					c1
				case 2:
					c2
				case 3:
					c3
				case 4:
					c4
				case 5:
					c5
				case 6:
					c6
				case 7:
					c7
				case 8:
					c8
				case _:
					c9

# The reference is Y-up; this slice is Z-up. Normalize its daylight vector.
def Sun.length() -> F32:
	F32.sqrt((0.45 * 0.45 + 0.35 * 0.35 + 0.82 * 0.82 : F32))

def Sun.cosine(direction: V.Direction) -> F32:
	match direction:
		case V.NegX{}:
			(0.45 / Sun.length() : F32)
		case V.PosY{}:
			(0.35 / Sun.length() : F32)
		case V.PosZ{}:
			(0.82 / Sun.length() : F32)
		case _:
			0.0

def Sky.amount(direction: V.Direction) -> F32:
	match direction:
		case V.NegZ{}:
			0.0
		case V.PosZ{}:
			1.0
		case _:
			0.5

# Daylight coefficients from cf188d2's scene.frag. No night state or work light.
def Day.color(base: M.LinearRgb, +sky: F32, +sun: F32, visible: U32) -> U32:
	M.LinearRgb{r, g, b} = base
	+direct = (sun * U32.to_f32(visible) / 9.0 : F32)
	M.LinearRgb.pack(M.LinearRgb{(r * (0.17 + 0.23 * sky + 0.88 * direct) : F32),
		(g * (0.20 + 0.24 * sky + 0.76 * direct) : F32), (b * (0.27 + 0.21 * sky + 0.61 * direct) : F32)})

def Ramp.build(+base: M.LinearRgb, +direction: V.Direction) -> Ramp:
	+sky = Sky.amount(direction)
	+sun = Sun.cosine(direction)
	Ramp{Day.color(base, sky, sun, 0), Day.color(base, sky, sun, 1), Day.color(base, sky, sun, 2),
		Day.color(base, sky, sun, 3), Day.color(base, sky, sun, 4), Day.color(base, sky, sun, 5),
		Day.color(base, sky, sun, 6), Day.color(base, sky, sun, 7), Day.color(base, sky, sun, 8), Day.color(base, sky, sun, 9)}

def Sides.linear(color: Maybe<&2, M.LinearRgb>) -> Sides:
	match color:
		case None{}:
			+diagnostic = Ramp.constant(16711935)
			Sides{diagnostic, diagnostic, diagnostic, diagnostic, diagnostic, diagnostic}
		case Some{+base}:
			Sides{Ramp.build(base, V.NegX{}), Ramp.build(base, V.PosX{}), Ramp.build(base, V.NegY{}),
				Ramp.build(base, V.PosY{}), Ramp.build(base, V.NegZ{}), Ramp.build(base, V.PosZ{})}

def Sides.build(material: M.Material) -> Sides:
	Sides.linear(M.Oklch.linear(M.Material.oklch(material)))

def Sides.surface(sides: Sides, direction: V.Direction) -> Ramp:
	Sides{nx, px, ny, py, nz, pz} = sides
	match direction:
		case V.NegX{}:
			nx
		case V.PosX{}:
			px
		case V.NegY{}:
			ny
		case V.PosY{}:
			py
		case V.NegZ{}:
			nz
		case V.PosZ{}:
			pz

def Palette.build() -> Palette:
	Palette{Sides.build(M.Foundation{}), Sides.build(M.Concrete{}), Sides.build(M.Frame{}), Sides.build(M.Machinery{})}

def Palette.color(palette: Palette, material: M.Material, direction: V.Direction) -> Ramp:
	Palette{foundation, concrete, frame, machinery} = palette
	match material:
		case M.Foundation{}:
			Sides.surface(foundation, direction)
		case M.Concrete{}:
			Sides.surface(concrete, direction)
		case M.Frame{}:
			Sides.surface(frame, direction)
		case M.Machinery{}:
			Sides.surface(machinery, direction)
		case M.Plaster{}:
			Sides.surface(Sides.build(M.Plaster{}),direction)

def Palette.known(material: Maybe<&2, M.Material>, palette: Palette, direction: V.Direction) -> Ramp:
	match material:
		case None{}:
			Ramp.constant(16711935)
		case Some{m}:
			Palette.color(palette, m, direction)

def Palette.surface(palette: Palette, id: U32, direction: V.Direction) -> Ramp:
	Palette.known(M.Material.read(id), palette, direction)

def Shadow.visible(occluded: Bool) -> U32:
	match occluded:
		case True{}:
			0
		case False{}:
			1
