import Base

type Material is Data:
	Foundation{}
	Concrete{}
	Frame{}
	Machinery{}
	Plaster{}

type Oklch is Data:
	Oklch{lightness: F32, chroma: F32, hue_degrees: F32}

type LinearRgb is Data:
	LinearRgb{r: F32, g: F32, b: F32}

type Light is Data:
	Full{}
	Mid{}
	Low{}

type Swatches is Data:
	Swatches{full: U32, mid: U32, low: U32}

type Palette is Data:
	Palette{foundation: Swatches, concrete: Swatches, frame: Swatches, machinery: Swatches}

def Material.id(material: Material) -> U32:
	match material:
		case Foundation{}:
			1
		case Concrete{}:
			2
		case Frame{}:
			3
		case Machinery{}:
			4
		case Plaster{}:
			5

def Material.read(id: U32) -> Maybe<&2, Material>:
	match id:
		case 1:
			Some{Foundation{}}
		case 2:
			Some{Concrete{}}
		case 3:
			Some{Frame{}}
		case 4:
			Some{Machinery{}}
		case 5:
			Some{Plaster{}}
		case _:
			None{}

def Material.oklch(material: Material) -> Oklch:
	match material:
		case Foundation{}:
			Oklch{0.736340, 0.114340, 173.8965}
		case Concrete{}:
			Oklch{0.733411, 0.093103, 66.0436}
		case Frame{}:
			Oklch{0.630974, 0.062930, 239.8232}
		case Machinery{}:
			Oklch{0.723628, 0.119039, 64.7019}
		case Plaster{}:
			Oklch{0.860000, 0.018000, 85.0000}

def Number.finite(+value: F32) -> Bool:
	F32.is_eq((value - value : F32), 0.0)

def Oklch.valid(color: Oklch) -> Bool:
	Oklch{l, +c, h} = color
	Number.finite(l) && Number.finite(c) && Number.finite(h) && (c >= 0.0 : F32)

def Number.cube(+value: F32) -> F32:
	(value * value * value : F32)

# D65 Oklab matrices published at https://bottosson.github.io/posts/oklab/.
def Oklch.raw(color: Oklch) -> LinearRgb:
	Oklch{+lightness, +chroma, hue} = color
	+angle = (hue * 0.017453292519943295 : F32)
	+a = (chroma * F32.cos(angle) : F32)
	+b = (chroma * F32.sin(angle) : F32)
	+l = Number.cube((lightness + 0.3963377774 * a + 0.2158037573 * b : F32))
	+m = Number.cube((lightness - 0.1055613458 * a - 0.0638541728 * b : F32))
	+s = Number.cube((lightness - 0.0894841775 * a - 1.2914855480 * b : F32))
	LinearRgb{(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s : F32),
		(0.0 - 1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s : F32),
		(0.0 - 0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s : F32)}

def LinearRgb.gamut(color: LinearRgb) -> Bool:
	LinearRgb{+r, +g, +b} = color
	Number.finite(r) && Number.finite(g) && Number.finite(b) &&
		((r >= 0.0) && (r <= 1.0) && (g >= 0.0) && (g <= 1.0) && (b >= 0.0) && (b <= 1.0) : F32)

def LinearRgb.clamp(color: LinearRgb) -> LinearRgb:
	LinearRgb{r, g, b} = color
	LinearRgb{F32.clamp(r, 0.0, 1.0), F32.clamp(g, 0.0, 1.0), F32.clamp(b, 0.0, 1.0)}

def Oklch.search(fuel: Nat, +lightness: F32, +hue: F32, +lo: F32, +hi: F32) -> LinearRgb:
	match fuel:
		case 0n:
			LinearRgb.clamp(Oklch.raw(Oklch{lightness, lo, hue}))
		case 1n+rest:
			+mid = ((lo + hi) * 0.5 : F32)
			+inside = LinearRgb.gamut(Oklch.raw(Oklch{lightness, mid, hue}))
			Oklch.search(rest, lightness, hue, Bool.pick(F32, inside, mid, lo), Bool.pick(F32, inside, hi, mid))

def Oklch.fit(inside: Bool, color: Oklch, raw: LinearRgb) -> LinearRgb:
	match inside:
		case True{}:
			raw
		case False{}:
			Oklch{l, c, h} = color
			Oklch.search(24n, l, h, 0.0, c)

def Oklch.checked(valid: Bool, color: Oklch) -> Maybe<&2, LinearRgb>:
	match valid color:
		case False{} _:
			None{}
		case True{} Oklch{l, c, h}:
			+bounded = {Oklch{F32.clamp(l, 0.0, 1.0), c, h} : Oklch}
			+raw = Oklch.raw(bounded)
			Some{Oklch.fit(LinearRgb.gamut(raw), bounded, raw)}

def Oklch.linear(+color: Oklch) -> Maybe<&2, LinearRgb>:
	Oklch.checked(Oklch.valid(color), color)

def Light.amount(light: Light) -> F32:
	match light:
		case Full{}:
			1.0
		case Mid{}:
			0.58
		case Low{}:
			0.35

def LinearRgb.shade(color: LinearRgb, light: Light) -> LinearRgb:
	LinearRgb{r, g, b} = color
	+amount = Light.amount(light)
	LinearRgb{(r * amount : F32), (g * amount : F32), (b * amount : F32)}

def Srgb.transfer(low: Bool, value: F32) -> F32:
	match low:
		case True{}:
			(12.92 * value : F32)
		case False{}:
			(1.055 * F32.pow(value, (1.0 / 2.4 : F32)) - 0.055 : F32)

def Srgb.channel(value: F32) -> F32:
	+bounded = F32.clamp(value, 0.0, 1.0)
	Srgb.transfer((bounded <= 0.0031308 : F32), bounded)

# The source vertex path floors encoded channels before packing 0xRRGGBB.
def Srgb.byte(value: F32) -> U32:
	F32.to_u32(F32.floor((Srgb.channel(value) * 255.0 : F32)))

def LinearRgb.pack(color: LinearRgb) -> U32:
	LinearRgb{r, g, b} = color
	((Srgb.byte(r) << 16n) .|. (Srgb.byte(g) << 8n) .|. Srgb.byte(b) : U32)

def Swatches.linear(color: Maybe<&2, LinearRgb>) -> Swatches:
	match color:
		case None{}:
			Swatches{16711935, 16711935, 16711935}
		case Some{+base}:
			Swatches{LinearRgb.pack(LinearRgb.shade(base, Full{})),
				LinearRgb.pack(LinearRgb.shade(base, Mid{})), LinearRgb.pack(LinearRgb.shade(base, Low{}))}

def Swatches.build(material: Material) -> Swatches:
	Swatches.linear(Oklch.linear(Material.oklch(material)))

def Swatches.color(swatches: Swatches, light: Light) -> U32:
	Swatches{full, mid, low} = swatches
	match light:
		case Full{}:
			full
		case Mid{}:
			mid
		case Low{}:
			low

def Palette.build() -> Palette:
	Palette{Swatches.build(Foundation{}), Swatches.build(Concrete{}), Swatches.build(Frame{}), Swatches.build(Machinery{})}

def Palette.color(palette: Palette, material: Material, light: Light) -> U32:
	Palette{foundation, concrete, frame, machinery} = palette
	match material:
		case Foundation{}:
			Swatches.color(foundation, light)
		case Concrete{}:
			Swatches.color(concrete, light)
		case Frame{}:
			Swatches.color(frame, light)
		case Machinery{}:
			Swatches.color(machinery, light)
		case Plaster{}:
			Swatches.color(Swatches.build(Plaster{}),light)

def Palette.known(material: Maybe<&2, Material>, palette: Palette, id: U32, light: Light) -> U32:
	match material:
		case None{}:
			Bool.pick(U32, U32.is_eq(id, 0), 0, 16711935)
		case Some{m}:
			Palette.color(palette, m, light)

def Palette.surface(palette: Palette, +id: U32, light: Light) -> U32:
	Palette.known(Material.read(id), palette, id, light)

def foundation() -> U32:
	Material.id(Foundation{})

def concrete() -> U32:
	Material.id(Concrete{})

def frame() -> U32:
	Material.id(Frame{})

def machinery() -> U32:
	Material.id(Machinery{})

def plaster() -> U32:
	Material.id(Plaster{})
