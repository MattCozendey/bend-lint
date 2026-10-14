import Base
import ../main.bend as M
import ../voxel.bend as V
import ../render.bend as R
import ../atelier.bend as A
import ../dump.bend as D

def Row(stage: String, start: Nat, finish: Nat) -> IO(Unit):
	IO.print("stage=" ++ stage ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finish, start)))

def Faces(surface: V.Surface) -> List<&2, V.Face>:
	V.Surface{faces} = surface
	faces

def Ground(+shadow: R.ShadowMap) -> R.GroundLighting:
	R.ShadowMap{basis, depths, ground, grid} = shadow
	R.GroundLighting{R.Lighting.ground_field(8n, shadow, 0, 0, 256), ground, grid}

def Init.surface(+cube: Bool, +tile: Nat, fork: Nat, +start: Nat, +a: Nat, result: V.Body & V.Surface) -> IO(M.Model):
	(body, +surface) = result
	do IO<M.Model>:
		+b : Nat <- IO.now()
		+shadow : R.ShadowMap <- IO.pure(R.ShadowMap, R.ShadowMap.build(surface))
		+c : Nat <- IO.now()
		faces : List<&2, R.Illuminated> <- IO.pure(List<&2, R.Illuminated>, R.Lighting.faces(Faces(surface), shadow))
		+d : Nat <- IO.now()
		ground : R.GroundLighting <- IO.pure(R.GroundLighting, Ground(shadow))
		+e : Nat <- IO.now()
		+camera : R.Camera = Bool.pick(R.Camera, cube, R.Camera.initial(), R.Camera.atelier())
		scene : R.RenderScene <- IO.pure(R.RenderScene, R.RenderScene.project(surface, camera, tile, R.LightingCache{shadow, faces, ground}))
		+f : Nat <- IO.now()
		model : M.Model <- IO.pure(M.Model, M.Model{body, surface, scene, camera, M.Controls.initial(), M.Pointer{256, 256}, None{}, False{}, tile, fork})
		finish : Nat <- IO.now()
		Row("body", start, a)
		Row("surface", a, b)
		Row("shadow", b, c)
		Row("face_lighting", c, d)
		Row("ground_lighting", d, e)
		Row("projection", e, f)
		Row("segmented_init", start, finish)
		return model

def Init(+cube: Bool, +tile: Nat, +fork: Nat) -> IO(M.Model):
	do IO<M.Model>:
		+start : Nat <- IO.now()
		body : V.Body <- IO.pure(V.Body, Bool.pick(V.Body, cube, V.Body.solid(3n), A.body()))
		+a : Nat <- IO.now()
		result : V.Body & V.Surface <- IO.pure(V.Body & V.Surface, V.Surface.build(body))
		Init.surface(cube, tile, fork, start, a, result)

def Advance(next: Maybe<M.Model>) -> IO(M.Model):
	match next:
		case Some{model}: IO.pure(M.Model, model)
		case None{}: IO.die(M.Model, 1, "Unexpected close during deterministic flight")

def Update(kind: U32, model: M.Model) -> IO(M.Model):
	match kind:
		case 2: Advance(M.Model.advance([Key{119, True{}}], 16n, model))
		case 3: IO.pure(M.Model, M.Model.demo_cut(M.Model.key(model, 119, False{})))
		case 4: IO.pure(M.Model, M.Model.reset(model))
		case _: IO.pure(M.Model, model)

def Draw(kind: U32, model: M.Model) -> M.Model & Image:
	match kind:
		case 1: M.Model.preview(M.Model.point(model, 226, 224))
		case _: M.Model.view(model)

def Export.drawn(path: String, result: M.Model & Image) -> IO(M.Model):
	(model, image) = result
	do IO<M.Model>:
		D.Dump.ppm(path, image)
		return model

def Name(kind: U32) -> String:
	match kind:
		case 0: "opening"
		case 1: "preview"
		case 2: "flight"
		case 3: "cut"
		case _: "reset"

def Export(output: String, +kind: U32, model: M.Model) -> IO(M.Model):
	match output:
		case SNil{}: IO.pure(M.Model, model)
		case path:
			IO.bind(M.Model & Image, M.Model, IO.pure(M.Model & Image, Draw(kind, model)), Export.drawn(path ++ "/" ++ Name(kind) ++ ".ppm"))

def Frame.shown(kind: U32, index: U32, +a: Nat, +b: Nat, +c: Nat, model: M.Model, shown: Window & Image & List<Event>) -> IO(Window & M.Model):
	(window, image, events) = shown
	do IO<Window & M.Model>:
		+d : Nat <- IO.now()
		Unit <- IO.pure(Unit, Image.drop!(image))
		+e : Nat <- IO.now()
		IO.print("case=" ++ U32.show(kind) ++ " frame=" ++ U32.show(index) ++ " update_ms=" ++ Nat.show(Nat.sub(b, a)) ++ " render_ms=" ++ Nat.show(Nat.sub(c, b)) ++ " present_ms=" ++ Nat.show(Nat.sub(d, c)) ++ " disposal_ms=" ++ Nat.show(Nat.sub(e, d)) ++ " elapsed_ms=" ++ Nat.show(Nat.sub(e, a)))
		return (window, model)

def Frame.drawn(kind: U32, index: U32, a: Nat, b: Nat, window: Window, drawn: M.Model & Image) -> IO(Window & M.Model):
	(model, image) = drawn
	do IO<Window & M.Model>:
		c : Nat <- IO.now()
		shown : Window & Image & List<Event> <- Window.frame(window, image)
		Frame.shown(kind, index, a, b, c, model, shown)

def Frame(+kind: U32, index: U32, window: Window, model: M.Model) -> IO(Window & M.Model):
	do IO<Window & M.Model>:
		a : Nat <- IO.now()
		model : M.Model <- Update(kind, model)
		b : Nat <- IO.now()
		drawn : M.Model & Image <- IO.pure(M.Model & Image, Draw(kind, model))
		Frame.drawn(kind, index, a, b, window, drawn)

def Frames(fuel: Nat, +kind: U32, +index: U32, state: Window & M.Model) -> IO(Window & M.Model):
	match fuel:
		case 0n: IO.pure(Window & M.Model, state)
		case 1n+rest:
			(window, model) = state
			IO.bind(Window & M.Model, Window & M.Model, Frame(kind, index, window, model), next => Frames(rest, kind, (index + 1 : U32), next))

def Export.state(+output: String, kind: U32, state: Window & M.Model) -> IO(Window & M.Model):
	(window, model) = state
	do IO<Window & M.Model>:
		model : M.Model <- Export(output, kind, model)
		return (window, model)

def Cases(fuel: Nat, +kind: U32, +frames: Nat, +output: String, state: Window & M.Model) -> IO(Unit):
	match fuel:
		case 0n:
			(window, model) = state
			Window.close(window)
		case 1n+rest:
			do IO<Unit>:
				state : Window & M.Model <- Frames(Bool.pick(Nat, (kind < 3 : U32), frames, 1n), kind, 0, state)
				state : Window & M.Model <- Export.state(output, kind, state)
				Cases(rest, (kind + 1 : U32), frames, output, state)

def Drop(model: M.Model) -> Unit:
	Unit{}

def Run(+args: List<&2, String>) -> IO(Unit):
	+cube = M.Options.has(args, "--cube")
	+tile = M.Options.depth(M.Options.flag(args, "--tile-depth", False{}), 6)
	+fork = M.Options.depth(M.Options.flag(args, "--fork-depth", False{}), 6)
	frames = U32.to_nat(M.Options.number(M.Options.flag(args, "--frames", False{}), 12))
	output = Maybe.default(&2, String, M.Options.flag(args, "--output", False{}), "")
	do IO<Unit>:
		IO.print("Diagnostic reconstruction; timing can differ from production native --bench. Cases 0=cached 1=preview 2=flight 3=cut 4=reset. --output requires an existing directory.")
		IO.print("tile_depth=" ++ Nat.show(tile) ++ " fork_depth=" ++ Nat.show(fork))
		a : Nat <- IO.now()
		model : M.Model <- IO.pure(M.Model, M.Model.selected(cube, False{}, tile, fork))
		b : Nat <- IO.now()
		Row("full_init", a, b)
		Unit <- IO.pure(Unit, Drop(model))
		model : M.Model <- Init(cube, tile, fork)
		window : Window <- IO.try(Window, Window.open("Bend frame profile", 512, 512))
		Cases(5n, 0, frames, output, (window, model))

def Steady.loop(fuel: Nat, state: Window & M.Model) -> IO(Window & M.Model):
	match fuel:
		case 0n: IO.pure(Window & M.Model, state)
		case 1n+rest:
			(window, model) = state
			IO.bind(Window & M.Model, Window & M.Model, M.Bench.frame(window, M.Model.view(model)), next => Steady.loop(rest, next))

def Steady(+frames: Nat, model: M.Model) -> IO(Unit):
	do IO<Unit>:
		IO.print("Native cached-frame benchmark; excludes initialization and eight warm-up frames. No edits or camera movement.")
		window : Window <- IO.try(Window, Window.open("Bend cached frame profile", 512, 512))
		warm : Window & M.Model <- Steady.loop(8n, (window, model))
		start : Nat <- IO.now()
		finished : Window & M.Model <- Steady.loop(frames, warm)
		finish : Nat <- IO.now()
		M.Bench.close(finished)
		IO.print("frames=" ++ Nat.show(frames) ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finish, start)))

def Select(bench: Maybe<&2, String>, +args: List<&2, String>) -> IO(Unit):
	match bench:
		case None{}: Run(args)
		case Some{frames}:
			Steady(U32.to_nat(M.Options.number(Some{frames}, 24)), M.Model.selected(M.Options.has(args, "--cube"), False{}, M.Options.depth(M.Options.flag(args, "--tile-depth", False{}), 6), M.Options.depth(M.Options.flag(args, "--fork-depth", False{}), 6)))

def Arguments(+args: List<&2, String>) -> IO(Unit):
	Select(M.Options.flag(args, "--bench", False{}), args)

def main() -> IO(Unit):
	IO.bind(List<String>, Unit, IO.args(), args => Arguments(M.Options.args(args)))
