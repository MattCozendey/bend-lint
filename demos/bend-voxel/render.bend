import Base
import ./voxel.bend as V
import ./material.bend as M
import ./lighting.bend as L

type Vec3 is Data:
	Vec3{x: F32, y: F32, z: F32}

type Camera is Data:
	Camera{eye: Vec3, yaw: F32, pitch: F32}

type Basis is Data:
	Basis{eye: Vec3, right: Vec3, up: Vec3, forward: Vec3, focal: F32, near: F32}

type Bounds is Data:
	Bounds{minx: U32, miny: U32, maxx: U32, maxy: U32}

type Projected is Data:
	Projected{cell: V.Cell, direction: V.Direction, plane_delta: F32, u_eye: F32, v_eye: F32, color: L.Ramp, visibility: L.ColorField, id: U32, bounds: Bounds, width: F32, height: F32, outline: Bool}

type Tiles is Data:
	Tile{x: U32, y: U32, size: U32, faces: List<&2, Projected>}
	Split{tl: Tiles, tr: Tiles, bl: Tiles, br: Tiles}

type RenderScene is Data:
	RenderScene{basis: Basis, tiles: Tiles, face_count: U32, lighting: LightingCache}

type Hit is Data:
	Hit{depth: F32, color: U32, id: U32, cell: Maybe<&2, V.Cell>, direction: V.Direction}

type PendingHit is Data:
	Existing{hit: Hit}
	Selected{depth: F32, id: U32, cell: V.Cell, direction: V.Direction, ramp: L.Ramp, visibility: L.ColorField, u: F32, v: F32, edge: Bool}

type ShadowDepth is Data:
	Resolution{width: U32, image: ShadowDepth}
	Depth{depth: F32}
	DepthQuad{tl: ShadowDepth, tr: ShadowDepth, bl: ShadowDepth, br: ShadowDepth}

type ShadowMap is Data:
	ShadowMap{basis: Basis, depths: ShadowDepth, ground: L.Ramp, grid: L.Ramp}

type Illuminated is Data:
	Illuminated{face: V.Face, visibility: L.ColorField}

type GroundLighting is Data:
	GroundLighting{visibility: L.ColorField, ground: L.Ramp, grid: L.Ramp}

type LightingCache is Data:
	LightingCache{sun: ShadowMap, faces: List<&2, Illuminated>, ground: GroundLighting}

type Ring is Data:
	XY{}
	XZ{}
	YZ{}

type Segment is Data:
	Segment{x0: F32, y0: F32, inverse0: F32, x1: F32, y1: F32, inverse1: F32, bounds: Bounds}

type Marker is Data:
	Marker{sphere: V.MetricSphere, segments: List<&2, Segment>}

def Vec3.add(a: Vec3, b: Vec3) -> Vec3:
	Vec3{ax, ay, az} = a
	Vec3{bx, by, bz} = b
	Vec3{(ax + bx : F32), (ay + by : F32), (az + bz : F32)}

def Vec3.scale(a: Vec3, +scale: F32) -> Vec3:
	Vec3{x, y, z} = a
	Vec3{(x * scale : F32), (y * scale : F32), (z * scale : F32)}

def Vec3.dot(a: Vec3, b: Vec3) -> F32:
	Vec3{ax, ay, az} = a
	Vec3{bx, by, bz} = b
	(ax * bx + ay * by + az * bz : F32)

def Vec3.cross(a: Vec3, b: Vec3) -> Vec3:
	Vec3{+ax, +ay, +az} = a
	Vec3{+bx, +by, +bz} = b
	Vec3{(ay * bz - az * by : F32), (az * bx - ax * bz : F32), (ax * by - ay * bx : F32)}

def Vec3.unit.nonzero(nonzero: Bool, a: Vec3, length: F32) -> Vec3:
	match nonzero:
		case False{}:
			Vec3{0.0, 0.0, 0.0}
		case True{}:
			Vec3.scale(a, (1.0 / F32.sqrt(length) : F32))

def Vec3.unit(a: Vec3, +length: F32) -> Vec3:
	Vec3.unit.nonzero((length > 0.00000001 : F32), a, length)

def Camera.initial() -> Camera:
	Camera{Vec3{18.0, 18.0, 15.0}, (0.0 - 2.35619449 : F32), (0.0 - 0.5070985 : F32)}

def Camera.atelier() -> Camera:
	Camera{Vec3{310.0,(0.0 - 50.0 : F32),110.0}, 1.90401163, (0.0 - 0.30 : F32)}

def Camera.basis(camera: Camera) -> Basis:
	Camera{eye, +yaw, +pitch} = camera
	+cy = F32.cos(yaw)
	+sy = F32.sin(yaw)
	+cp = F32.cos(pitch)
	+sp = F32.sin(pitch)
	Basis{eye, Vec3{sy, (0.0 - cy : F32), 0.0}, Vec3{(0.0 - sp * cy : F32), (0.0 - sp * sy : F32), cp},
		Vec3{(cp * cy : F32), (cp * sy : F32), sp}, 420.0, 0.1}

def Camera.look(camera: Camera, dx: F32, dy: F32) -> Camera:
	Camera{eye, yaw, pitch} = camera
	+angle = (yaw - dx * 0.003 : F32)
	Camera{eye, (angle - 6.28318531 * F32.floor(((angle + 3.14159265) / 6.28318531 : F32)) : F32),
		F32.clamp((pitch - dy * 0.003 : F32), (0.0 - 1.55 : F32), 1.55)}

def Camera.fly.basis(camera: Camera, basis: Basis, forward: F32, right: F32, vertical: F32, elapsed_ms: Nat) -> Camera:
	Camera{eye, yaw, pitch} = camera
	Basis{origin, r, up, f, focal, near} = basis
	+movement = Vec3.add(Vec3.add(Vec3.scale(f, forward), Vec3.scale(r, right)), Vec3{0.0, 0.0, vertical})
	Camera{Vec3.add(eye, Vec3.scale(Vec3.unit(movement, Vec3.dot(movement, movement)),
		(U32.to_f32(U32.from_nat(Nat.min(elapsed_ms, 100n))) * 0.008 : F32))), yaw, pitch}

def Camera.fly(+camera: Camera, forward: F32, right: F32, vertical: F32, elapsed_ms: Nat) -> Camera:
	Camera.fly.basis(camera, Camera.basis(camera), forward, right, vertical, elapsed_ms)

def Camera.equal(a: Camera, b: Camera) -> Bool:
	Camera{Vec3{ax, ay, az}, ayaw, apitch} = a
	Camera{Vec3{bx, by, bz}, byaw, bpitch} = b
	F32.is_eq(ax, bx) && F32.is_eq(ay, by) && F32.is_eq(az, bz) && F32.is_eq(ayaw, byaw) && F32.is_eq(apitch, bpitch)

def Basis.local(+basis: Basis, point: Vec3) -> Vec3:
	Basis{eye, right, up, forward, focal, near} = basis
	+delta = Vec3.add(point, Vec3.scale(eye, (0.0 - 1.0 : F32)))
	Vec3{Vec3.dot(delta, right), Vec3.dot(delta, up), Vec3.dot(delta, forward)}

def Clip.intersection(+low: Vec3, high: Vec3, +near: F32) -> Vec3:
	Vec3{lx, ly, +lz} = low
	Vec3{hx, hy, hz} = high
	+t = ((near - lz) / (hz - lz) : F32)
	Vec3{(lx + (hx - lx) * t : F32), (ly + (hy - ly) * t : F32), near}

def Clip.cross.ordered(ordered: Bool, a: Vec3, b: Vec3, near: F32) -> Vec3:
	match ordered:
		case True{}:
			Clip.intersection(a, b, near)
		case False{}:
			Clip.intersection(b, a, near)

def Clip.cross(+a: Vec3, +b: Vec3, near: F32) -> Vec3:
	Vec3{ax, ay, az} = a
	Vec3{bx, by, bz} = b
	Clip.cross.ordered((az < bz : F32), a, b, near)

def Clip.edge.inside(a_inside: Bool, b_inside: Bool, +a: Vec3, +b: Vec3, +near: F32, rest: List<&2, Vec3>) -> List<&2, Vec3>:
	match a_inside b_inside:
		case True{} True{}:
			b <> rest
		case False{} True{}:
			Clip.cross(a, b, near) <> b <> rest
		case True{} False{}:
			Clip.cross(a, b, near) <> rest
		case False{} False{}:
			rest

def Clip.edge(+a: Vec3, +b: Vec3, +near: F32, rest: List<&2, Vec3>) -> List<&2, Vec3>:
	Vec3{ax, ay, az} = a
	Vec3{bx, by, bz} = b
	Clip.edge.inside((az >= near : F32), (bz >= near : F32), a, b, near, rest)

def Bounds.valid(valid: Bool, lx: F32, ly: F32, hx: F32, hy: F32) -> Maybe<&2, Bounds>:
	match valid:
		case False{}:
			None{}
		case True{}:
			Some{Bounds{F32.to_u32(lx), F32.to_u32(ly), F32.to_u32(hx), F32.to_u32(hy)}}

def Bounds.finish(minx: F32, miny: F32, maxx: F32, maxy: F32) -> Maybe<&2, Bounds>:
	+lx = F32.clamp(F32.floor((minx - 1.0 : F32)), 0.0, 512.0)
	+ly = F32.clamp(F32.floor((miny - 1.0 : F32)), 0.0, 512.0)
	+hx = F32.clamp(F32.ceil((maxx + 1.0 : F32)), 0.0, 512.0)
	+hy = F32.clamp(F32.ceil((maxy + 1.0 : F32)), 0.0, 512.0)
	Bounds.valid(((lx < hx) && (ly < hy) : F32), lx, ly, hx, hy)

def Bounds.vertices(vertices: List<&2, Vec3>, +focal: F32, minx: F32, miny: F32, maxx: F32, maxy: F32) -> Maybe<&2, Bounds>:
	match vertices:
		case Nil{}:
			Bounds.finish(minx, miny, maxx, maxy)
		case Con{Vec3{x, y, +z}, rest}:
			+px = (256.0 + focal * x / z : F32)
			+py = (256.0 - focal * y / z : F32)
			Bounds.vertices(rest, focal, F32.min(minx, px), F32.min(miny, py), F32.max(maxx, px), F32.max(maxy, py))

def Bounds.clipped(vertices: List<&2, Vec3>, +focal: F32) -> Maybe<&2, Bounds>:
	match vertices:
		case Nil{}:
			None{}
		case Con{Vec3{x, y, +z}, rest}:
			+px = (256.0 + focal * x / z : F32)
			+py = (256.0 - focal * y / z : F32)
			Bounds.vertices(rest, focal, px, py, px, py)

def Bounds.quad(+basis: Basis, +a: Vec3, +b: Vec3, +c: Vec3, +d: Vec3) -> Maybe<&2, Bounds>:
	Basis{eye, right, up, forward, focal, near} = basis
	+conservative_near = F32.max((near - 0.00001 : F32), 0.000001)
	Bounds.clipped(Clip.edge(a, b, conservative_near, Clip.edge(b, c, conservative_near, Clip.edge(c, d, conservative_near, Clip.edge(d, a, conservative_near, Nil{})))), focal)

def Face.point(direction: V.Direction, +plane: F32, +u: F32, +v: F32) -> Vec3:
	match direction:
		case V.NegX{}:
			Vec3{plane, u, v}
		case V.PosX{}:
			Vec3{plane, u, v}
		case V.NegY{}:
			Vec3{u, plane, v}
		case V.PosY{}:
			Vec3{u, plane, v}
		case _:
			Vec3{u, v, plane}

def Face.coordinates(direction: V.Direction, cell: V.Cell) -> Vec3:
	match direction cell:
		case V.NegX{} V.Cell{+x, +y, +z}:
			Vec3{U32.to_f32(x), U32.to_f32(y), U32.to_f32(z)}
		case V.PosX{} V.Cell{+x, +y, +z}:
			Vec3{U32.to_f32((x + 1 : U32)), U32.to_f32(y), U32.to_f32(z)}
		case V.NegY{} V.Cell{+x, +y, +z}:
			Vec3{U32.to_f32(y), U32.to_f32(x), U32.to_f32(z)}
		case V.PosY{} V.Cell{+x, +y, +z}:
			Vec3{U32.to_f32((y + 1 : U32)), U32.to_f32(x), U32.to_f32(z)}
		case V.NegZ{} V.Cell{+x, +y, +z}:
			Vec3{U32.to_f32(z), U32.to_f32(x), U32.to_f32(y)}
		case V.PosZ{} V.Cell{+x, +y, +z}:
			Vec3{U32.to_f32((z + 1 : U32)), U32.to_f32(x), U32.to_f32(y)}

def Face.axes(direction: V.Direction, point: Vec3) -> Vec3:
	match direction point:
		case V.NegX{} Vec3{x, y, z}:
			Vec3{x, y, z}
		case V.PosX{} Vec3{x, y, z}:
			Vec3{x, y, z}
		case V.NegY{} Vec3{x, y, z}:
			Vec3{y, x, z}
		case V.PosY{} Vec3{x, y, z}:
			Vec3{y, x, z}
		case _ Vec3{x, y, z}:
			Vec3{z, x, y}

def Face.normal(direction: V.Direction) -> Vec3:
	match direction:
		case V.NegX{}:
			Vec3{(0.0 - 1.0 : F32), 0.0, 0.0}
		case V.PosX{}:
			Vec3{1.0, 0.0, 0.0}
		case V.NegY{}:
			Vec3{0.0, (0.0 - 1.0 : F32), 0.0}
		case V.PosY{}:
			Vec3{0.0, 1.0, 0.0}
		case V.NegZ{}:
			Vec3{0.0, 0.0, (0.0 - 1.0 : F32)}
		case V.PosZ{}:
			Vec3{0.0, 0.0, 1.0}

def Face.light(direction: V.Direction) -> M.Light:
	match direction:
		case V.PosZ{}:
			M.Full{}
		case V.NegX{}:
			M.Mid{}
		case V.PosX{}:
			M.Mid{}
		case _:
			M.Low{}

def Projected.bounded(bounds: Maybe<&2, Bounds>, cell: V.Cell, direction: V.Direction, plane: F32, u_eye: F32, v_eye: F32, color: L.Ramp, visibility: L.ColorField, id: U32, width: F32, height: F32, outline: Bool) -> Maybe<&2, Projected>:
	match bounds:
		case None{}:
			None{}
		case Some{b}:
			Some{Projected{cell, direction, plane, u_eye, v_eye, color, visibility, id, b, width, height, outline}}

def Projected.coordinates(+cell: V.Cell, +direction: V.Direction, +basis: Basis, id: U32, color: L.Ramp, visibility: L.ColorField, coordinates: Vec3, axis: Vec3, +width: F32, +height: F32, outline: Bool) -> Maybe<&2, Projected>:
	Vec3{+plane, +u, +v} = coordinates
	Vec3{ep, eu, ev} = axis
	Projected.bounded(Bounds.quad(basis, Basis.local(basis, Face.point(direction, plane, u, v)),
		Basis.local(basis, Face.point(direction, plane, (u + width : F32), v)),
		Basis.local(basis, Face.point(direction, plane, (u + width : F32), (v + height : F32))),
		Basis.local(basis, Face.point(direction, plane, u, (v + height : F32)))),
		cell, direction, (plane - ep : F32), (eu - u : F32), (ev - v : F32), color, visibility, id, width, height, outline)

def Projected.of(+face: V.Face, +basis: Basis, palette: L.Palette, id: U32) -> Maybe<&2, Projected>:
	match face:
		case V.Face{+cell,+direction,material}:
			Basis{eye,right,up,forward,focal,near} = basis
			Projected.coordinates(cell,direction,basis,id,L.Palette.surface(palette,material,direction),L.Color{9},Face.coordinates(direction,cell),Face.axes(direction,eye),U32.to_f32(1),U32.to_f32(1),False{})
		case V.Rectangle{+cell,+direction,material,width,height}:
			Basis{eye,right,up,forward,focal,near} = basis
			Projected.coordinates(cell,direction,basis,id,L.Palette.surface(palette,material,direction),L.Color{9},Face.coordinates(direction,cell),Face.axes(direction,eye),U32.to_f32(width),U32.to_f32(height),False{})

def Projected.add(value: Maybe<&2, Projected>, rest: List<&2, Projected>) -> List<&2, Projected>:
	match value:
		case None{}:
			rest
		case Some{face}:
			face <> rest

def Projected.list(faces: List<&2, V.Face>, +basis: Basis, +palette: L.Palette, +id: U32) -> List<&2, Projected>:
	match faces:
		case Nil{}:
			Nil{}
		case Con{face, rest}:
			Projected.add(Projected.of(face, basis, palette, id), Projected.list(rest, basis, palette, (id + 1 : U32)))

def Projected.overlaps(face: Projected, +x: U32, +y: U32, +size: U32) -> Bool:
	Projected{cell, direction, plane, u_eye, v_eye, color, visibility, id, Bounds{minx, miny, maxx, maxy}, width, height, outline} = face
	((minx < x + size) && (miny < y + size) && (maxx > x) && (maxy > y) : U32)

def Projected.filter(faces: List<&2, Projected>, +x: U32, +y: U32, +size: U32, found: List<&2, Projected>) -> List<&2, Projected>:
	match faces:
		case Nil{}:
			found
		case Con{+face, rest}:
			Projected.filter(rest, x, y, size, Projected.add(Bool.pick(Maybe<&2, Projected>, Projected.overlaps(face, x, y, size), Some{face}, None{}), found))

def Tiles.build(+depth: Nat, +faces: List<&2, Projected>, +x: U32, +y: U32, +size: U32) -> Tiles:
	match depth:
		case 0n:
			Tile{x, y, size, faces}
		case 1n+rest:
			+h = (size / 2 : U32)
			Split{Tiles.build(rest, Projected.filter(faces, x, y, h, Nil{}), x, y, h),
				Tiles.build(rest, Projected.filter(faces, (x + h : U32), y, h, Nil{}), (x + h : U32), y, h),
				Tiles.build(rest, Projected.filter(faces, x, (y + h : U32), h, Nil{}), x, (y + h : U32), h),
				Tiles.build(rest, Projected.filter(faces, (x + h : U32), (y + h : U32), h, Nil{}), (x + h : U32), (y + h : U32), h)}

def Pixel.ray(basis: Basis, x: U32, y: U32) -> Vec3:
	Basis{eye, right, up, forward, +focal, near} = basis
	Vec3.add(forward, Vec3.add(Vec3.scale(right, ((U32.to_f32(x) + 0.5 - 256.0) / focal : F32)),
		Vec3.scale(up, ((256.0 - U32.to_f32(y) - 0.5) / focal : F32))))

def Edge.color(edge: Bool, color: U32) -> U32:
	match edge:
		case True{}:
			5258540
		case False{}:
			color

def Hit.accept(closer: Bool, cell: V.Cell, depth: F32, color: L.Ramp, visibility: L.ColorField, u: F32, v: F32, edge: Bool, id: U32, direction: V.Direction, old: Hit) -> Hit:
	match closer:
		case True{}:
			Hit{depth, Edge.color(edge, L.Ramp.color(color, L.ColorField.sample(visibility, u, v))), id, Some{cell}, direction}
		case False{}:
			old

def Hit.closer(previous_cell: Maybe<&2, V.Cell>, +depth: F32, +previous: F32, id: U32, old_id: U32) -> Bool:
	match previous_cell:
		case None{}:
			True{}
		case Some{cell}:
			((depth < previous : F32) || (F32.is_eq(depth, previous) && (id < old_id : U32)))

def Hit.covered(covered: Bool, +u: F32, +v: F32, cell: V.Cell, +depth: F32, color: L.Ramp, visibility: L.ColorField, +id: U32, direction: V.Direction, outline: Bool, old: Hit) -> Hit:
	match covered:
		case False{}:
			old
		case True{}:
			Hit{+previous, old_color, +old_id, +old_cell, +old_direction} = old
			Hit.accept(Hit.closer(old_cell, depth, previous, id, old_id), cell, depth,
				color, visibility, u, v, outline && ((u < 0.0225) || (v < 0.0225) || (u > 0.9775) || (v > 0.9775) : F32), id, direction, Hit{previous, old_color, old_id, old_cell, old_direction})

def Face.offset(direction: V.Direction, +x: U32, +y: U32, +z: U32, +u: U32, +v: U32) -> V.Cell:
	match direction:
		case V.NegX{}: V.Cell{x,(y + u : U32),(z + v : U32)}
		case V.PosX{}: V.Cell{x,(y + u : U32),(z + v : U32)}
		case V.NegY{}: V.Cell{(x + u : U32),y,(z + v : U32)}
		case V.PosY{}: V.Cell{(x + u : U32),y,(z + v : U32)}
		case _: V.Cell{(x + u : U32),(y + v : U32),z}

def Face.sample_cell(direction: V.Direction, cell: V.Cell, u: F32, v: F32, width: F32, height: F32) -> V.Cell:
	V.Cell{+x,+y,+z} = cell
	+du = F32.to_u32(F32.min(F32.floor(u), (width - 1.0 : F32)))
	+dv = F32.to_u32(F32.min(F32.floor(v), (height - 1.0 : F32)))
	Face.offset(direction, x,y,z,du,dv)

def PendingHit.finish(pending: PendingHit) -> Hit:
	match pending:
		case Existing{hit}:
			hit
		case Selected{depth, id, cell, direction, ramp, visibility, u, v, edge}:
			Hit{depth, Edge.color(edge, L.Ramp.color(ramp, L.ColorField.sample(visibility, u, v))), id, Some{cell}, direction}

def PendingHit.accept(closer: Bool, cell: V.Cell, depth: F32, color: L.Ramp, visibility: L.ColorField, u: F32, v: F32, edge: Bool, id: U32, direction: V.Direction, old: PendingHit) -> PendingHit:
	match closer:
		case True{}:
			Selected{depth, id, cell, direction, color, visibility, u, v, edge}
		case False{}:
			old

def PendingHit.closer(old: PendingHit, depth: F32, id: U32) -> Bool:
	match old:
		case Existing{Hit{previous, old_color, old_id, old_cell, old_direction}}:
			Hit.closer(old_cell, depth, previous, id, old_id)
		case Selected{previous, old_id, cell, direction, ramp, visibility, u, v, edge}:
			Hit.closer(Some{cell}, depth, previous, id, old_id)

def PendingHit.covered(covered: Bool, +u: F32, +v: F32, cell: V.Cell, +depth: F32, color: L.Ramp, visibility: L.ColorField, +id: U32, direction: V.Direction, outline: Bool, +old: PendingHit) -> PendingHit:
	match covered:
		case False{}:
			old
		case True{}:
			PendingHit.accept(PendingHit.closer(old, depth, id), cell, depth,
				color, visibility, u, v, outline && ((u < 0.0225) || (v < 0.0225) || (u > 0.9775) || (v > 0.9775) : F32), id, direction, old)

def PendingHit.intersection(nonparallel: Bool, +denom: F32, plane: F32, u_eye: F32, v_eye: F32, du: F32, dv: F32, +near: F32, +cell: V.Cell, color: L.Ramp, visibility: L.ColorField, id: U32, +direction: V.Direction, +width: F32, +height: F32, outline: Bool, old: PendingHit) -> PendingHit:
	match nonparallel:
		case False{}:
			old
		case True{}:
			+t = (plane / denom : F32)
			+u = ((u_eye + t * du) / width : F32)
			+v = ((v_eye + t * dv) / height : F32)
			PendingHit.covered((F32.is_eq((t - t : F32), 0.0) && ((t >= near) && (u >= 0.0) && (u <= 1.0) && (v >= 0.0) && (v <= 1.0) : F32)), u, v, Face.sample_cell(direction, cell, (u * width : F32), (v * height : F32), width, height), t, color, visibility, id, direction, outline, old)

def PendingHit.axes(face: Projected, axis: Vec3, near: F32, old: PendingHit) -> PendingHit:
	Projected{cell, direction, plane, u_eye, v_eye, color, visibility, id, bounds, width, height, outline} = face
	Vec3{+denom, du, dv} = axis
	PendingHit.intersection(F32.is_ne(denom, 0.0), denom, plane, u_eye, v_eye, du, dv, near, cell, color, visibility, id, direction, width, height, outline, old)

def PendingHit.face(+face: Projected, ray: Vec3, near: F32, old: PendingHit) -> PendingHit:
	Projected{cell, direction, plane, u_eye, v_eye, color, visibility, id, bounds, width, height, outline} = face
	PendingHit.axes(face, Face.axes(direction, ray), near, old)

def PendingHit.scan(faces: List<&2, Projected>, +ray: Vec3, +near: F32, hit: PendingHit) -> PendingHit:
	match faces:
		case Nil{}:
			hit
		case Con{face, rest}:
			PendingHit.scan(rest, ray, near, PendingHit.face(face, ray, near, hit))

def Hit.intersection(nonparallel: Bool, +denom: F32, plane: F32, u_eye: F32, v_eye: F32, du: F32, dv: F32, +near: F32, +cell: V.Cell, color: L.Ramp, visibility: L.ColorField, id: U32, +direction: V.Direction, +width: F32, +height: F32, outline: Bool, old: Hit) -> Hit:
	match nonparallel:
		case False{}:
			old
		case True{}:
			+t = (plane / denom : F32)
			+u = ((u_eye + t * du) / width : F32)
			+v = ((v_eye + t * dv) / height : F32)
			Hit.covered((F32.is_eq((t - t : F32), 0.0) && ((t >= near) && (u >= 0.0) && (u <= 1.0) && (v >= 0.0) && (v <= 1.0) : F32)), u, v, Face.sample_cell(direction, cell, (u * width : F32), (v * height : F32), width, height), t, color, visibility, id, direction, outline, old)

def Hit.axes(face: Projected, axis: Vec3, near: F32, old: Hit) -> Hit:
	Projected{cell, direction, plane, u_eye, v_eye, color, visibility, id, bounds, width, height, outline} = face
	Vec3{+denom, du, dv} = axis
	Hit.intersection(F32.is_ne(denom, 0.0), denom, plane, u_eye, v_eye, du, dv, near, cell, color, visibility, id, direction, width, height, outline, old)

def Hit.face(+face: Projected, ray: Vec3, near: F32, old: Hit) -> Hit:
	Projected{cell, direction, plane, u_eye, v_eye, color, visibility, id, bounds, width, height, outline} = face
	Hit.axes(face, Face.axes(direction, ray), near, old)

def Background.color(floor: Bool, +x: U32, +y: U32) -> U32:
	match floor:
		case False{}:
			(1054752 + (y / 32) * 65793 : U32)
		case True{}:
			Edge.color((((x + 2 * y) % 80 < 2) || ((x + 1024 - 2 * y) % 80 < 2) : U32), 1779504)

def Hit.background(+x: U32, +y: U32) -> Hit:
	Hit{0.0, Background.color(False{}, x, y), 4294967295, None{}, V.PosZ{}}

def Pixel.eager(faces: List<&2, Projected>, +ray: Vec3, +near: F32, hit: Hit) -> Hit:
	match faces:
		case Nil{}:
			hit
		case Con{face, rest}:
			Pixel.eager(rest, ray, near, Hit.face(face, ray, near, hit))

def Pixel.hit(faces: List<&2, Projected>, +ray: Vec3, +near: F32, hit: Hit) -> Hit:
	PendingHit.finish(PendingHit.scan(faces, ray, near, Existing{hit}))

def Pixel.image(hit: Hit) -> Image:
	Hit{depth, color, id, cell, direction} = hit
	Pix{color}

# Shadow resolution is a portable tuning choice, independent of the main
# image's tile/fork decomposition. Keep this depth in 0..9.
# Shadow construction stays sequential; the width uses a flat bit shift.
def Shadow.depth() -> Nat:
	7n

def Shadow.width() -> U32:
	(1 << Shadow.depth() : U32)

def Face.extent_axes(direction: V.Direction, cell: V.Cell, +width: U32, +height: U32) -> U32:
	match direction cell:
		case V.NegX{} V.Cell{x,y,z}: U32.max((x + 1 : U32),U32.max((y + width : U32),(z + height : U32)))
		case V.PosX{} V.Cell{x,y,z}: U32.max((x + 1 : U32),U32.max((y + width : U32),(z + height : U32)))
		case V.NegY{} V.Cell{x,y,z}: U32.max((y + 1 : U32),U32.max((x + width : U32),(z + height : U32)))
		case V.PosY{} V.Cell{x,y,z}: U32.max((y + 1 : U32),U32.max((x + width : U32),(z + height : U32)))
		case _ V.Cell{x,y,z}: U32.max((z + 1 : U32),U32.max((x + width : U32),(y + height : U32)))

def Face.extent(face: V.Face) -> U32:
	match face:
		case V.Face{cell,direction,material}: Face.extent_axes(direction,cell,1,1)
		case V.Rectangle{cell,direction,material,width,height}: Face.extent_axes(direction,cell,width,height)

def Shadow.extent(faces: List<&2,V.Face>, extent: U32) -> U32:
	match faces:
		case Nil{}: extent
		case face <> rest: Shadow.extent(rest,U32.max(extent,Face.extent(face)))

def Shadow.resolution(depths: ShadowDepth) -> U32:
	match depths:
		case Resolution{width,image}: width
		case _: Shadow.width()

def Shadow.basis(+extent: U32) -> Basis:
	+sun = Vec3.scale(Vec3{(0.0 - 0.45 : F32), 0.35, 0.82}, (1.0 / L.Sun.length() : F32))
	+forward = Vec3.scale(sun, (0.0 - 1.0 : F32))
	+r = Vec3.cross(forward, Vec3{0.0, 0.0, 1.0})
	+right = Vec3.unit(r, Vec3.dot(r, r))
	+half = (U32.to_f32(extent) * 0.5 : F32)
	+span = (U32.to_f32(extent) * 2.0 + 2.0 : F32)
	Basis{Vec3.add(Vec3{half, half, half}, Vec3.scale(sun, span)), right, Vec3.cross(right, forward), forward, (512.0 / span : F32), 0.1}

def Shadow.bounds(vertices: List<&2, Vec3>, +scale: F32, minx: F32, miny: F32, maxx: F32, maxy: F32) -> Maybe<&2, Bounds>:
	match vertices:
		case Nil{}:
			Bounds.finish(minx, miny, maxx, maxy)
		case Vec3{x, y, z} <> rest:
			+px = (256.0 + scale * x : F32)
			+py = (256.0 - scale * y : F32)
			Shadow.bounds(rest, scale, F32.min(minx, px), F32.min(miny, py), F32.max(maxx, px), F32.max(maxy, py))

def Shadow.project(+cell: V.Cell, +direction: V.Direction, +width: F32, +height: F32, +basis: Basis, coordinates: Vec3, axis: Vec3) -> Maybe<&2, Projected>:
	Basis{eye,right,up,forward,scale,near} = basis
	Vec3{+plane,+u,+v} = coordinates
	Vec3{ep,eu,ev} = axis
	Projected.bounded(Shadow.bounds([Basis.local(basis,Face.point(direction,plane,u,v)),
		Basis.local(basis,Face.point(direction,plane,(u + width : F32),v)),
		Basis.local(basis,Face.point(direction,plane,(u + width : F32),(v + height : F32))),
		Basis.local(basis,Face.point(direction,plane,u,(v + height : F32)))],scale,512.0,512.0,0.0,0.0),
		cell,direction,(plane - ep : F32),(eu - u : F32),(ev - v : F32),L.Ramp.constant(0),L.Color{9},0,width,height,False{})

def Shadow.of(face: V.Face, +basis: Basis) -> Maybe<&2, Projected>:
	match face:
		case V.Face{+cell,+direction,material}:
			Basis{eye,right,up,forward,scale,near} = basis
			Shadow.project(cell,direction,1.0,1.0,basis,Face.coordinates(direction,cell),Face.axes(direction,eye))
		case V.Rectangle{+cell,+direction,material,width,height}:
			Basis{eye,right,up,forward,scale,near} = basis
			Shadow.project(cell,direction,U32.to_f32(width),U32.to_f32(height),basis,Face.coordinates(direction,cell),Face.axes(direction,eye))

def Shadow.face_hit(cell: V.Cell, +direction: V.Direction, plane: F32, u_eye: F32, v_eye: F32, color: L.Ramp, visibility: L.ColorField, id: U32, bounds: Bounds, width: F32, height: F32, outline: Bool, ray: Vec3, near: F32, hit: Hit, axis: Vec3) -> Hit:
	Vec3{dp, du, dv} = axis
	Hit.axes(Projected{cell, direction, (plane - dp : F32), (u_eye + du : F32), (v_eye + dv : F32), color, visibility, id, bounds, width, height, outline}, Face.axes(direction, ray), near, hit)

def Shadow.faces(faces: List<&2, V.Face>, +basis: Basis) -> List<&2, Projected>:
	match faces:
		case Nil{}:
			Nil{}
		case +face <> rest:
			Projected.add(Shadow.of(face, basis), Shadow.faces(rest, basis))

def Shadow.hit(faces: List<&2, Projected>, +delta: Vec3, +ray: Vec3, +near: F32, hit: Hit) -> Hit:
	match faces:
		case Nil{}:
			hit
		case Projected{cell, +direction, plane, u_eye, v_eye, color, visibility, id, bounds, width, height, outline} <> rest:
			Shadow.hit(rest, delta, ray, near, Shadow.face_hit(cell, direction, plane, u_eye, v_eye, color, visibility, id, bounds, width, height, outline, ray, near, hit, Face.axes(direction, delta)))

def Shadow.depth_pixel(hit: Hit) -> ShadowDepth:
	match hit:
		case Hit{depth, color, id, Some{cell}, direction}:
			Depth{depth}
		case Hit{depth, color, id, None{}, direction}:
			Depth{1.0e30}

def Shadow.tile(+depth: Nat, +basis: Basis, +faces: List<&2, Projected>, +x: U32, +y: U32, +size: U32) -> ShadowDepth:
	match depth:
		case 0n:
			Basis{eye, right, up, +forward, +scale, near} = basis
			+half = (U32.to_f32(size) * 0.5 : F32)
			+delta = Vec3.add(Vec3.scale(right, ((U32.to_f32(x) + half - 256.0) / scale : F32)),
				Vec3.scale(up, ((256.0 - U32.to_f32(y) - half) / scale : F32)))
			Shadow.depth_pixel(Shadow.hit(faces, delta, forward, near, Hit.background(0, 0)))
		case 1n+rest:
			+h = (size / 2 : U32)
			DepthQuad{Shadow.tile(rest, basis, faces, x, y, h), Shadow.tile(rest, basis, faces, (x + h : U32), y, h),
				Shadow.tile(rest, basis, faces, x, (y + h : U32), h), Shadow.tile(rest, basis, faces, (x + h : U32), (y + h : U32), h)}

def Shadow.tiles(tiles: Tiles, +basis: Basis, +depth: Nat) -> ShadowDepth:
	match tiles depth:
		case Tile{x, y, size, faces} _:
			Shadow.tile(depth, basis, faces, x, y, size)
		case Split{tl, tr, bl, br} 1n+rest:
			DepthQuad{Shadow.tiles(tl, basis, rest), Shadow.tiles(tr, basis, rest), Shadow.tiles(bl, basis, rest), Shadow.tiles(br, basis, rest)}
		case Split{tl, tr, bl, br} 0n:
			Depth{1.0e30}

def Shadow.configured(depth: Nat, image: ShadowDepth) -> ShadowDepth:
	match depth:
		case 7n: image
		case +n: Resolution{U32.pow(2,n),image}

def ShadowMap.build(surface: V.Surface) -> ShadowMap:
	V.Surface{+faces} = surface
	+extent = Shadow.extent(faces,1)
	+basis = Shadow.basis(extent)
	+depth = Bool.pick(Nat,(extent > 32 : U32),9n,Shadow.depth())
	+tile_depth = Nat.min(4n,depth)
	ShadowMap{basis,Shadow.configured(depth,Shadow.tiles(Tiles.build(tile_depth,Shadow.faces(faces,basis),0,0,512),basis,depth)),
		L.Ramp.build(M.LinearRgb{0.10,0.12,0.15},V.PosZ{}),L.Ramp.build(M.LinearRgb{0.055,0.065,0.08},V.PosZ{})}

def Shadow.read(image: ShadowDepth, +x: U32, +y: U32, +size: U32, right: Bool, bottom: Bool) -> F32:
	match image:
		case Resolution{width,child}:
			Shadow.read(child,x,y,size,right,bottom)
		case Depth{depth}:
			depth
		case DepthQuad{tl, tr, bl, br}:
			match right bottom:
				case False{} False{}:
					Shadow.read(tl, (x % (size / 2) : U32), (y % (size / 2) : U32), (size / 2 : U32), (x % (size / 2) >= size / 4 : U32), (y % (size / 2) >= size / 4 : U32))
				case True{} False{}:
					Shadow.read(tr, (x % (size / 2) : U32), (y % (size / 2) : U32), (size / 2 : U32), (x % (size / 2) >= size / 4 : U32), (y % (size / 2) >= size / 4 : U32))
				case False{} True{}:
					Shadow.read(bl, (x % (size / 2) : U32), (y % (size / 2) : U32), (size / 2 : U32), (x % (size / 2) >= size / 4 : U32), (y % (size / 2) >= size / 4 : U32))
				case True{} True{}:
					Shadow.read(br, (x % (size / 2) : U32), (y % (size / 2) : U32), (size / 2 : U32), (x % (size / 2) >= size / 4 : U32), (y % (size / 2) >= size / 4 : U32))

def Shadow.at(+depths: ShadowDepth, +x: U32, +y: U32) -> F32:
	+size = Shadow.resolution(depths)
	Shadow.read(depths, x, y, size, (x >= size / 2 : U32), (y >= size / 2 : U32))

def Shadow.sample.inside(inside: Bool, depths: ShadowDepth, x: F32, y: F32, depth: F32) -> U32:
	match inside:
		case False{}:
			1
		case True{}:
			L.Shadow.visible((depth > Shadow.at(depths, F32.to_u32(x), F32.to_u32(y)) : F32))

def Shadow.sample(+depths: ShadowDepth, +x: F32, +y: F32, depth: F32) -> U32:
	+width = U32.to_f32(Shadow.resolution(depths))
	Shadow.sample.inside(((x >= 0.0) && (x < width) && (y >= 0.0) && (y < width) : F32), depths, x, y, depth)

# Compare each PCF tap to the receiver's plane at that texel centre. This
# removes slope acne without a large bias that detaches contact shadows.
def Shadow.receiver_sample(depths: ShadowDepth, +x: F32, +y: F32, u: F32, v: F32, depth: F32, sx: F32, sy: F32) -> U32:
	Shadow.sample(depths, x, y, (depth + sx * (x + 0.5 - u) + sy * (y + 0.5 - v) - 0.005 : F32))

def Shadow.visibility.local(shadow: ShadowMap, point: Vec3, normal: Vec3) -> U32:
	ShadowMap{+basis, +depths, ground, grid} = shadow
	Basis{eye, right, up, forward, scale, near} = basis
	Vec3{px, py, +depth} = point
	Vec3{nx, ny, +nz} = normal
	+width = U32.to_f32(Shadow.resolution(depths))
	+u = (width * 0.5 + px * scale * width / 512.0 : F32)
	+v = (width * 0.5 - py * scale * width / 512.0 : F32)
	+x = F32.floor(u)
	+y = F32.floor(v)
	+texel = (512.0 / (scale * width) : F32)
	+sx = (0.0 - nx / nz * texel : F32)
	+sy = (ny / nz * texel : F32)
	(Shadow.receiver_sample(depths, (x - 1.0 : F32), (y - 1.0 : F32), u, v, depth, sx, sy) +
	 Shadow.receiver_sample(depths, x, (y - 1.0 : F32), u, v, depth, sx, sy) +
	 Shadow.receiver_sample(depths, (x + 1.0 : F32), (y - 1.0 : F32), u, v, depth, sx, sy) +
	 Shadow.receiver_sample(depths, (x - 1.0 : F32), y, u, v, depth, sx, sy) +
	 Shadow.receiver_sample(depths, x, y, u, v, depth, sx, sy) +
	 Shadow.receiver_sample(depths, (x + 1.0 : F32), y, u, v, depth, sx, sy) +
	 Shadow.receiver_sample(depths, (x - 1.0 : F32), (y + 1.0 : F32), u, v, depth, sx, sy) +
	 Shadow.receiver_sample(depths, x, (y + 1.0 : F32), u, v, depth, sx, sy) +
	 Shadow.receiver_sample(depths, (x + 1.0 : F32), (y + 1.0 : F32), u, v, depth, sx, sy) : U32)

def Shadow.receiver(+shadow: ShadowMap, point: Vec3, +normal: Vec3) -> U32:
	ShadowMap{+basis, depths, ground, grid} = shadow
	Basis{eye, right, up, forward, scale, near} = basis
	Shadow.visibility.local(shadow, Basis.local(basis, point), Vec3{Vec3.dot(normal, right), Vec3.dot(normal, up), Vec3.dot(normal, forward)})

def Shadow.visibility.sunny(sunny: Bool, shadow: ShadowMap, point: Vec3, direction: V.Direction) -> U32:
	match sunny:
		case False{}:
			9
		case True{}:
			Shadow.receiver(shadow, point, Face.normal(direction))

def Shadow.visibility(shadow: ShadowMap, point: Vec3, +direction: V.Direction) -> U32:
	Shadow.visibility.sunny((L.Sun.cosine(direction) > 0.0 : F32), shadow, point, direction)

def Lighting.face_point(shadow: ShadowMap, +direction: V.Direction, coordinates: Vec3, u_offset: F32, v_offset: F32) -> L.ColorField:
	Vec3{plane, u, v} = coordinates
	L.Color{Shadow.visibility(shadow, Face.point(direction, plane, (u + u_offset : F32), (v + v_offset : F32)), direction)}

def Lighting.face_field(+depth: Nat, +shadow: ShadowMap, +cell: V.Cell, +direction: V.Direction, +width: F32, +height: F32, +resolution: F32, +x: U32, +y: U32, +size: U32) -> L.ColorField:
	match depth:
		case 0n:
			Lighting.face_point(shadow, direction, Face.coordinates(direction, cell), ((U32.to_f32(x) + 0.5) * width / resolution : F32), ((U32.to_f32(y) + 0.5) * height / resolution : F32))
		case 1n+rest:
			+h = (size / 2 : U32)
			L.ColorField.join(Lighting.face_field(rest, shadow, cell, direction, width, height, resolution, x, y, h),
				Lighting.face_field(rest, shadow, cell, direction, width, height, resolution, (x + h : U32), y, h),
				Lighting.face_field(rest, shadow, cell, direction, width, height, resolution, x, (y + h : U32), h),
				Lighting.face_field(rest, shadow, cell, direction, width, height, resolution, (x + h : U32), (y + h : U32), h))

def Lighting.face_sunny(sunny: Bool, shadow: ShadowMap, cell: V.Cell, direction: V.Direction, +width: F32, +height: F32) -> L.ColorField:
	match sunny:
		case False{}:
			L.Color{9}
		case True{}:
			+depth = U32.to_nat(U32.min(8,U32.max(4,(U32.from_nat(U32.log2(F32.to_u32(F32.max(width,height)))) + 1 : U32))))
			+resolution = U32.pow(2,depth)
			Lighting.face_field(depth, shadow, cell, direction, width, height, U32.to_f32(resolution), 0, 0, resolution)

def Lighting.faces(faces: List<&2, V.Face>, +shadow: ShadowMap) -> List<&2, Illuminated>:
	match faces:
		case Nil{}:
			Nil{}
		case +face <> rest:
			match face:
				case V.Face{cell, +direction, material}:
					Illuminated{face, Lighting.face_sunny((L.Sun.cosine(direction) > 0.0 : F32), shadow, cell, direction, U32.to_f32(V.Face.width(face)), U32.to_f32(V.Face.height(face)))} <> Lighting.faces(rest, shadow)
				case V.Rectangle{cell, +direction, material, width0, height0}:
					Illuminated{face, Lighting.face_sunny((L.Sun.cosine(direction) > 0.0 : F32), shadow, cell, direction, U32.to_f32(V.Face.width(face)), U32.to_f32(V.Face.height(face)))} <> Lighting.faces(rest, shadow)

def Lighting.ground_field(+depth: Nat, +shadow: ShadowMap, +x: U32, +y: U32, +size: U32) -> L.ColorField:
	match depth:
		case 0n:
			L.Color{Shadow.visibility(shadow, Vec3{((U32.to_f32(x) + 0.5) * 40.0 / 256.0 - 16.0 : F32),
				((U32.to_f32(y) + 0.5) * 40.0 / 256.0 - 16.0 : F32), (0.0 - 0.5 : F32)}, V.PosZ{})}
		case 1n+rest:
			+h = (size / 2 : U32)
			L.ColorField.join(Lighting.ground_field(rest, shadow, x, y, h), Lighting.ground_field(rest, shadow, (x + h : U32), y, h),
				Lighting.ground_field(rest, shadow, x, (y + h : U32), h), Lighting.ground_field(rest, shadow, (x + h : U32), (y + h : U32), h))

def LightingCache.finish(+surface: V.Surface, +shadow: ShadowMap) -> LightingCache:
	V.Surface{faces} = surface
	ShadowMap{basis, depths, ground, grid} = shadow
	LightingCache{shadow, Lighting.faces(faces, shadow), GroundLighting{Lighting.ground_field(8n, shadow, 0, 0, 256), ground, grid}}

def LightingCache.ground(cache: LightingCache) -> GroundLighting:
	LightingCache{sun, faces, ground} = cache
	ground

def LightingCache.build(+surface: V.Surface) -> LightingCache:
	LightingCache.finish(surface, ShadowMap.build(surface))

def Projected.illuminated(face: Illuminated, +basis: Basis, palette: L.Palette, id: U32) -> Maybe<&2, Projected>:
	match face:
		case Illuminated{V.Face{+cell,+direction,material},visibility}:
			Basis{eye,right,up,forward,focal,near} = basis
			Projected.coordinates(cell,direction,basis,id,L.Palette.surface(palette,material,direction),visibility,Face.coordinates(direction,cell),Face.axes(direction,eye),U32.to_f32(1),U32.to_f32(1),False{})
		case Illuminated{V.Rectangle{+cell,+direction,material,width,height},visibility}:
			Basis{eye,right,up,forward,focal,near} = basis
			Projected.coordinates(cell,direction,basis,id,L.Palette.surface(palette,material,direction),visibility,Face.coordinates(direction,cell),Face.axes(direction,eye),U32.to_f32(width),U32.to_f32(height),False{})

def Projected.illuminated_list(faces: List<&2, Illuminated>, +basis: Basis, +palette: L.Palette, +id: U32) -> List<&2, Projected>:
	match faces:
		case Nil{}:
			Nil{}
		case face <> rest:
			Projected.add(Projected.illuminated(face, basis, palette, id), Projected.illuminated_list(rest, basis, palette, (id + 1 : U32)))

def RenderScene.project(surface: V.Surface, camera: Camera, tile_depth: Nat, +lighting: LightingCache) -> RenderScene:
	LightingCache{sun, faces, ground} = lighting
	+basis = Camera.basis(camera)
	+palette = L.Palette.build()
	RenderScene{basis, Tiles.build(tile_depth, Projected.illuminated_list(faces, basis, palette, 0), 0, 0, 512), V.Surface.count(surface), lighting}

def RenderScene.build(+surface: V.Surface, camera: Camera, tile_depth: Nat) -> RenderScene:
	RenderScene.project(surface, camera, tile_depth, LightingCache.build(surface))

def RenderScene.reproject(surface: V.Surface, camera: Camera, tile_depth: Nat, scene: RenderScene) -> RenderScene:
	RenderScene{basis, tiles, face_count, lighting} = scene
	RenderScene.project(surface, camera, tile_depth, lighting)

def Segment.bounded(bounds: Maybe<&2, Bounds>, x0: F32, y0: F32, inverse0: F32, x1: F32, y1: F32, inverse1: F32) -> Maybe<&2, Segment>:
	match bounds:
		case None{}:
			None{}
		case Some{b}:
			Some{Segment{x0, y0, inverse0, x1, y1, inverse1, b}}

def Segment.project(a: Vec3, b: Vec3, +focal: F32) -> Maybe<&2, Segment>:
	Vec3{ax, ay, +az} = a
	Vec3{bx, by, +bz} = b
	+x0 = (256.0 + focal * ax / az : F32)
	+y0 = (256.0 - focal * ay / az : F32)
	+x1 = (256.0 + focal * bx / bz : F32)
	+y1 = (256.0 - focal * by / bz : F32)
	Segment.bounded(Bounds.finish(F32.min(x0, x1), F32.min(y0, y1), F32.max(x0, x1), F32.max(y0, y1)), x0, y0, (1.0 / az : F32), x1, y1, (1.0 / bz : F32))

def Segment.clipped(a_inside: Bool, b_inside: Bool, +a: Vec3, +b: Vec3, +near: F32, focal: F32) -> Maybe<&2, Segment>:
	match a_inside b_inside:
		case True{} True{}:
			Segment.project(a, b, focal)
		case False{} True{}:
			Segment.project(Clip.cross(a, b, near), b, focal)
		case True{} False{}:
			Segment.project(a, Clip.cross(a, b, near), focal)
		case False{} False{}:
			None{}

def Segment.of(+a: Vec3, +b: Vec3, basis: Basis) -> Maybe<&2, Segment>:
	Vec3{ax, ay, +az} = a
	Vec3{bx, by, +bz} = b
	Basis{eye, right, up, forward, focal, +near} = basis
	Segment.clipped((az >= near : F32), (bz >= near : F32), a, b, near, focal)

def Segment.add(segment: Maybe<&2, Segment>, rest: List<&2, Segment>) -> List<&2, Segment>:
	match segment:
		case None{}:
			rest
		case Some{s}:
			s <> rest

def Ring.offset(ring: Ring, c: F32, s: F32) -> Vec3:
	match ring:
		case XY{}:
			Vec3{c, s, 0.0}
		case XZ{}:
			Vec3{c, 0.0, s}
		case YZ{}:
			Vec3{0.0, c, s}

def Ring.point(+ring: Ring, centre: Vec3, +radius: F32, +index: U32) -> Vec3:
	+angle = (U32.to_f32(index) * 0.1963495408 : F32)
	Vec3.add(centre, Ring.offset(ring, (radius * F32.cos(angle) : F32), (radius * F32.sin(angle) : F32)))

def Ring.segments(fuel: Nat, +index: U32, +ring: Ring, +centre: Vec3, +radius: F32, +basis: Basis, segments: List<&2, Segment>) -> List<&2, Segment>:
	match fuel:
		case 0n:
			segments
		case 1n+rest:
			Ring.segments(rest, (index + 1 : U32), ring, centre, radius, basis,
				Segment.add(Segment.of(Basis.local(basis, Ring.point(ring, centre, radius, index)), Basis.local(basis, Ring.point(ring, centre, radius, (index + 1 : U32))), basis), segments))

def Marker.valid(valid: Bool, +sphere: V.MetricSphere, +basis: Basis) -> Maybe<&2, Marker>:
	match valid sphere:
		case False{} _:
			None{}
		case True{} V.MetricSphere{V.PointCm{x, y, z}, radius}:
			+size = V.Voxel.size_cm()
			+centre = {Vec3{(x / size : F32), (y / size : F32), (z / size : F32)} : Vec3}
			+r = (radius / size : F32)
			Some{Marker{sphere, Ring.segments(32n, 0, XY{}, centre, r, basis,
				Ring.segments(32n, 0, XZ{}, centre, r, basis, Ring.segments(32n, 0, YZ{}, centre, r, basis, Nil{})))}}

def Marker.prepare(sphere: Maybe<&2, V.MetricSphere>, basis: Basis) -> Maybe<&2, Marker>:
	match sphere:
		case None{}:
			None{}
		case Some{+s}:
			Marker.valid(V.MetricSphere.valid(s), s, basis)

def Segment.overlaps(segment: Segment, +x: U32, +y: U32, +size: U32) -> Bool:
	Segment{x0, y0, inverse0, x1, y1, inverse1, Bounds{minx, miny, maxx, maxy}} = segment
	((minx < x + size) && (miny < y + size) && (maxx > x) && (maxy > y) : U32)

def Segment.filter(segments: List<&2, Segment>, +x: U32, +y: U32, +size: U32, found: List<&2, Segment>) -> List<&2, Segment>:
	match segments:
		case Nil{}:
			found
		case Con{+segment, rest}:
			Segment.filter(rest, x, y, size, Segment.add(Bool.pick(Maybe<&2, Segment>, Segment.overlaps(segment, x, y, size), Some{segment}, None{}), found))

def Marker.filter(preview: Maybe<&2, Marker>, x: U32, y: U32, size: U32) -> Maybe<&2, Marker>:
	match preview:
		case None{}:
			None{}
		case Some{Marker{sphere, segments}}:
			Some{Marker{sphere, Segment.filter(segments, x, y, size, Nil{})}}

def Preview.cell(selected: Bool, color: U32) -> U32:
	match selected:
		case False{}:
			color
		case True{}:
			Bool.pick(U32, U32.is_eq(color, 5258540), 7366400, 16776960)

def Preview.tint(cell: Maybe<&2, V.Cell>, sphere: V.MetricSphere, color: U32) -> U32:
	match cell:
		case None{}:
			color
		case Some{c}:
			Preview.cell(V.MetricSphere.contains(sphere, c), color)

def Wire.visible(cell: Maybe<&2, V.Cell>, +depth: F32, world_depth: F32, +near: F32) -> Bool:
	match cell:
		case None{}:
			(depth >= near : F32)
		case Some{c}:
			((depth >= near) && (depth <= world_depth + 0.0001) : F32)

def Wire.covered(covered: Bool, inverse: F32, near: F32, world_depth: F32, cell: Maybe<&2, V.Cell>) -> Bool:
	match covered:
		case False{}:
			False{}
		case True{}:
			Wire.visible(cell, (1.0 / inverse : F32), world_depth, near)

def Wire.position(nondegenerate: Bool, dot: F32, squared: F32) -> F32:
	match nondegenerate:
		case False{}:
			0.0
		case True{}:
			F32.clamp((dot / squared : F32), 0.0, 1.0)

def Wire.segment(segment: Segment, +x: F32, +y: F32, near: F32, world_depth: F32, cell: Maybe<&2, V.Cell>) -> Bool:
	Segment{+x0, +y0, +inverse0, x1, y1, inverse1, bounds} = segment
	+dx = (x1 - x0 : F32)
	+dy = (y1 - y0 : F32)
	+squared = (dx * dx + dy * dy : F32)
	+t = Wire.position((squared > 0.0 : F32), ((x - x0) * dx + (y - y0) * dy : F32), squared)
	+ex = (x - x0 - t * dx : F32)
	+ey = (y - y0 - t * dy : F32)
	Wire.covered((ex * ex + ey * ey <= 0.5625 : F32), (inverse0 + t * (inverse1 - inverse0) : F32), near, world_depth, cell)

def Wire.segments(segments: List<&2, Segment>, +x: F32, +y: F32, +near: F32, +world_depth: F32, +cell: Maybe<&2, V.Cell>) -> Bool:
	match segments:
		case Nil{}:
			False{}
		case Con{segment, rest}:
			Wire.segment(segment, x, y, near, world_depth, cell) || Wire.segments(rest, x, y, near, world_depth, cell)

def Preview.pixel(preview: Maybe<&2, Marker>, near: F32, x: U32, y: U32, hit: Hit) -> Image:
	match preview:
		case None{}:
			Pixel.image(hit)
		case Some{Marker{sphere, segments}}:
			Hit{depth, color, id, +cell, direction} = hit
			Pix{Bool.pick(U32, Wire.segments(segments, (U32.to_f32(x) + 0.5 : F32), (U32.to_f32(y) + 0.5 : F32), near, depth, cell), 16776960, Preview.tint(cell, sphere, color))}

# The ground receives daylight and shadows, but is presentation geometry:
# it never becomes a voxel hit or a destruction target.
def Ground.color(inside: Bool, +point: Vec3, +lighting: GroundLighting, fallback: U32) -> U32:
	match inside:
		case False{}:
			fallback
		case True{}:
			Vec3{+x, +y, z} = point
			GroundLighting{visibility, ground, grid} = lighting
			+gx = (x * 0.5 - F32.floor((x * 0.5 : F32)) : F32)
			+gy = (y * 0.5 - F32.floor((y * 0.5 : F32)) : F32)
			L.Ramp.color(Bool.pick(L.Ramp, ((gx < 0.0125) || (gx > 0.9875) || (gy < 0.0125) || (gy > 0.9875) : F32), grid, ground), L.ColorField.sample(visibility, ((x + 16.0) / 40.0 : F32), ((y + 16.0) / 40.0 : F32)))

def Ground.point(+point: Vec3, lighting: GroundLighting, fallback: U32) -> U32:
	Vec3{+x, +y, z} = point
	Ground.color(((x >= 0.0 - 16.0) && (x <= 24.0) && (y >= 0.0 - 16.0) && (y <= 24.0) : F32), point, lighting, fallback)

def Ground.ray(facing: Bool, +eye: Vec3, +ray: Vec3, lighting: GroundLighting, fallback: U32) -> U32:
	match facing:
		case False{}:
			fallback
		case True{}:
			Vec3{x, y, z} = eye
			Vec3{dx, dy, dz} = ray
			Ground.point(Vec3.add(eye, Vec3.scale(ray, ((0.0 - 0.5 - z) / dz : F32))), lighting, fallback)

def Pixel.shaded(hit: Hit, lighting: GroundLighting, basis: Basis, +ray: Vec3) -> Hit:
	match hit:
		case Hit{depth, color, id, None{}, direction}:
			Basis{+eye, right, up, forward, focal, near} = basis
			Vec3{ex, ey, ez} = eye
			Vec3{dx, dy, dz} = ray
			Hit{depth, Ground.ray(((ez > 0.0 - 0.5) && (dz < 0.0) : F32), eye, ray, lighting, color), id, None{}, direction}
		case Hit{depth, color, id, Some{cell}, direction}:
			Hit{depth, color, id, Some{cell}, direction}

def Pixel.present(lighting: GroundLighting, +basis: Basis, ray: Vec3, preview: Maybe<&2, Marker>, x: U32, y: U32, hit: Hit) -> Image:
	Basis{eye, right, up, forward, focal, near} = basis
	Preview.pixel(preview, near, x, y, Pixel.shaded(hit, lighting, basis, ray))

def Tile.image(+depth: Nat, +lighting: GroundLighting, +basis: Basis, +preview: Maybe<&2, Marker>, +faces: List<&2, Projected>, +x: U32, +y: U32, +size: U32) -> Image:
	match depth:
		case 0n:
			Basis{eye, right, up, forward, focal, +near} = basis
			+ray = Pixel.ray(basis, x, y)
			Pixel.present(lighting, basis, ray, preview, x, y, Pixel.hit(faces, ray, near, Hit.background(x, y)))
		case 1n+rest:
			+h = (size / 2 : U32)
			Qua{Tile.image(rest, lighting, basis, preview, faces, x, y, h), Tile.image(rest, lighting, basis, preview, faces, (x + h : U32), y, h),
				Tile.image(rest, lighting, basis, preview, faces, x, (y + h : U32), h), Tile.image(rest, lighting, basis, preview, faces, (x + h : U32), (y + h : U32), h)}

def Tiles.image.seq(+lighting: GroundLighting, +basis: Basis, +preview: Maybe<&2, Marker>, tiles: Tiles) -> Image:
	match tiles:
		case Tile{+x, +y, +size, faces}:
			Tile.image(U32.log2(size), lighting, basis, Marker.filter(preview, x, y, size), faces, x, y, size)
		case Split{tl, tr, bl, br}:
			Qua{Tiles.image.seq(lighting, basis, preview, tl), Tiles.image.seq(lighting, basis, preview, tr), Tiles.image.seq(lighting, basis, preview, bl), Tiles.image.seq(lighting, basis, preview, br)}

def Tiles.image(+fork_depth: Nat, +lighting: GroundLighting, +basis: Basis, +preview: Maybe<&2, Marker>, tiles: Tiles) -> Image:
	match fork_depth:
		case 0n:
			Tiles.image.seq(lighting, basis, preview, tiles)
		case 1n+rest:
			match tiles:
				case Tile{+x, +y, +size, faces}:
					Tile.image(U32.log2(size), lighting, basis, Marker.filter(preview, x, y, size), faces, x, y, size)
				case Split{tl, tr, bl, br}:
					a b c d = Tiles.image(rest, lighting, basis, preview, tl) Tiles.image(rest, lighting, basis, preview, tr) Tiles.image(rest, lighting, basis, preview, bl) Tiles.image(rest, lighting, basis, preview, br)
					Qua{a, b, c, d}

def RenderScene.image(+scene: RenderScene, fork_depth: Nat) -> Image & RenderScene:
	RenderScene{basis, tiles, face_count, cache} = scene
	(Tiles.image!(fork_depth, LightingCache.ground(cache), basis, None{}, tiles), scene)

def RenderScene.preview(+scene: RenderScene, sphere: Maybe<&2, V.MetricSphere>, fork_depth: Nat) -> Image & RenderScene:
	RenderScene{+basis, tiles, face_count, cache} = scene
	(Tiles.image!(fork_depth, LightingCache.ground(cache), basis, Marker.prepare(sphere, basis), tiles), scene)

def Hit.cell(hit: Hit) -> Maybe<&2, V.Cell>:
	Hit{depth, color, id, cell, direction} = hit
	cell

def Tiles.hit(tiles: Tiles, +ray: Vec3, +near: F32, +x: U32, +y: U32, +size: U32, right: Bool, bottom: Bool) -> Hit:
	match tiles:
		case Tile{tx, ty, tile_size, faces}:
			Pixel.hit(faces, ray, near, Hit.background(x, y))
		case Split{tl, tr, bl, br}:
			match right bottom:
				case False{} False{}:
					Tiles.hit(tl, ray, near, x, y, (size / 2 : U32), (x % (size / 2) >= size / 4 : U32), (y % (size / 2) >= size / 4 : U32))
				case True{} False{}:
					Tiles.hit(tr, ray, near, x, y, (size / 2 : U32), (x % (size / 2) >= size / 4 : U32), (y % (size / 2) >= size / 4 : U32))
				case False{} True{}:
					Tiles.hit(bl, ray, near, x, y, (size / 2 : U32), (x % (size / 2) >= size / 4 : U32), (y % (size / 2) >= size / 4 : U32))
				case True{} True{}:
					Tiles.hit(br, ray, near, x, y, (size / 2 : U32), (x % (size / 2) >= size / 4 : U32), (y % (size / 2) >= size / 4 : U32))

def RenderScene.pick.valid(valid: Bool, scene: RenderScene, +x: U32, +y: U32) -> Maybe<&2, V.Cell>:
	match valid:
		case False{}:
			None{}
		case True{}:
			RenderScene{+basis, tiles, face_count, cache} = scene
			Basis{eye, right, up, forward, focal, near} = basis
			Hit.cell(Tiles.hit(tiles, Pixel.ray(basis, x, y), near, x, y, 512, (x >= 256 : U32), (y >= 256 : U32)))

def RenderScene.pick(scene: RenderScene, +x: U32, +y: U32) -> Maybe<&2, V.Cell>:
	RenderScene.pick.valid(((x < 512) && (y < 512) : U32), scene, x, y)

def Hit.point(point: Vec3) -> V.MetricSphere:
	Vec3{x, y, z} = point
	+size = V.Voxel.size_cm()
	V.MetricSphere.brush(V.PointCm{(size * x : F32), (size * y : F32), (size * z : F32)})

def Hit.target(hit: Hit, basis: Basis, ray: Vec3) -> Maybe<&2, V.MetricSphere>:
	match hit:
		case Hit{depth, color, id, None{}, direction}:
			None{}
		case Hit{depth, color, id, Some{cell}, direction}:
			Basis{eye, right, up, forward, focal, near} = basis
			Some{Hit.point(Vec3.add(eye, Vec3.scale(ray, depth)))}

def RenderScene.target.valid(valid: Bool, scene: RenderScene, +x: U32, +y: U32) -> Maybe<&2, V.MetricSphere>:
	match valid scene:
		case False{} _:
			None{}
		case True{} RenderScene{+basis, tiles, face_count, cache}:
			Basis{eye, right, up, forward, focal, near} = basis
			+ray = Pixel.ray(basis, x, y)
			Hit.target(Tiles.hit(tiles, ray, near, x, y, 512, (x >= 256 : U32), (y >= 256 : U32)), basis, ray)

def RenderScene.target(scene: RenderScene, +x: U32, +y: U32) -> Maybe<&2, V.MetricSphere>:
	RenderScene.target.valid(((x < 512) && (y < 512) : U32), scene, x, y)
