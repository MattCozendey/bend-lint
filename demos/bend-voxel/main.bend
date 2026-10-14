import Base
import ./atelier.bend as A
import ./voxel.bend as V
import ./render.bend as R
import ./dump.bend as D

type Mode is Data:
	Interactive{}
	Dump{path: String}
	Benchmark{frames: Nat}

type Options is Data:
	Options{mode: Mode, cut: Bool, tile_depth: Nat, fork_depth: Nat}

type Controls is Data:
	Controls{w: Bool, s: Bool, a: Bool, d: Bool, q: Bool, e: Bool, looking: Bool, grab: Maybe<&2, Bool>}

type Pointer is Data:
	Pointer{x: U32, y: U32}

type Model is Type:
	Model{body: V.Body, surface: V.Surface, scene: R.RenderScene, camera: R.Camera, controls: Controls, pointer: Pointer, previous: Maybe<&2, Nat>, dirty: Bool, tile_depth: Nat, fork_depth: Nat}

def Controls.initial() -> Controls:
	Controls{False{}, False{}, False{}, False{}, False{}, False{}, False{}, None{}}

def Controls.key(code: U32, down: Bool, controls: Controls) -> Controls:
	match code controls:
		case 119 Controls{w, s, a, d, q, e, looking, grab}:
			Controls{down, s, a, d, q, e, looking, grab}
		case 87 Controls{w, s, a, d, q, e, looking, grab}:
			Controls{down, s, a, d, q, e, looking, grab}
		case 115 Controls{w, s, a, d, q, e, looking, grab}:
			Controls{w, down, a, d, q, e, looking, grab}
		case 83 Controls{w, s, a, d, q, e, looking, grab}:
			Controls{w, down, a, d, q, e, looking, grab}
		case 97 Controls{w, s, a, d, q, e, looking, grab}:
			Controls{w, s, down, d, q, e, looking, grab}
		case 65 Controls{w, s, a, d, q, e, looking, grab}:
			Controls{w, s, down, d, q, e, looking, grab}
		case 100 Controls{w, s, a, d, q, e, looking, grab}:
			Controls{w, s, a, down, q, e, looking, grab}
		case 68 Controls{w, s, a, d, q, e, looking, grab}:
			Controls{w, s, a, down, q, e, looking, grab}
		case 113 Controls{w, s, a, d, q, e, looking, grab}:
			Controls{w, s, a, d, down, e, looking, grab}
		case 81 Controls{w, s, a, d, q, e, looking, grab}:
			Controls{w, s, a, d, down, e, looking, grab}
		case 101 Controls{w, s, a, d, q, e, looking, grab}:
			Controls{w, s, a, d, q, down, looking, grab}
		case 69 Controls{w, s, a, d, q, e, looking, grab}:
			Controls{w, s, a, d, q, down, looking, grab}
		case _ _:
			controls

def Controls.look(controls: Controls, +looking: Bool) -> Controls:
	Controls{w, s, a, d, q, e, old, grab} = controls
	Controls{w, s, a, d, q, e, looking, Some{looking}}

def Controls.request(controls: Controls) -> Controls & Maybe<&2, Bool>:
	Controls{w, s, a, d, q, e, looking, grab} = controls
	(Controls{w, s, a, d, q, e, looking, None{}}, grab)

def Controls.capture(controls: Controls) -> Bool:
	Controls{w, s, a, d, q, e, looking, grab} = controls
	looking

def Controls.axis(positive: Bool, negative: Bool) -> F32:
	(U32.to_f32(Bool.to_u32(positive)) - U32.to_f32(Bool.to_u32(negative)) : F32)

def Controls.fly(controls: Controls, camera: R.Camera, elapsed_ms: Nat) -> R.Camera:
	Controls{w, s, a, d, q, e, looking, grab} = controls
	R.Camera.fly(camera, Controls.axis(w, s), Controls.axis(d, a), Controls.axis(e, q), elapsed_ms)

def Model.finish(+camera: R.Camera, +tile_depth: Nat, fork_depth: Nat, result: V.Body & V.Surface) -> Model:
	(body, +surface) = result
	Model{body, surface, R.RenderScene.build(surface, camera, tile_depth), camera, Controls.initial(), Pointer{256, 256}, None{}, False{}, tile_depth, fork_depth}

def Model.init(+tile_depth: Nat, fork_depth: Nat) -> Model:
	Model.finish(R.Camera.atelier(), tile_depth, fork_depth, V.Surface.build(A.body()))

def Model.cube(+tile_depth: Nat, fork_depth: Nat) -> Model:
	Model.finish(R.Camera.initial(), tile_depth, fork_depth, V.Surface.build(V.Body.solid(3n)))

def Body.restored(body: V.Body) -> V.Body:
	match body:
		case V.Body{side,cells}: V.Body.solid(3n)
		case V.Cuboids{boxes}: A.body()

def Model.erased(model: Model, sphere: V.MetricSphere) -> Model:
	Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth} = model
	Model{V.Body.cut(body, sphere), surface, scene, camera, controls, pointer, previous, True{}, tile_depth, fork_depth}

def Model.restored(model: Model) -> Model:
	Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth} = model
	Model{Body.restored(body), surface, scene, camera, controls, pointer, previous, True{}, tile_depth, fork_depth}

def Model.rebuilt(+camera: R.Camera, controls: Controls, pointer: Pointer, previous: Maybe<&2, Nat>, +tile_depth: Nat, fork_depth: Nat, result: V.Body & V.Surface) -> Model:
	(body, +surface) = result
	Model{body, surface, R.RenderScene.build(surface, camera, tile_depth), camera, controls, pointer, previous, False{}, tile_depth, fork_depth}

def Model.refreshed(changed: Bool, model: Model) -> Model:
	match changed model:
		case False{} _:
			model
		case True{} Model{body, +surface, scene, +camera, controls, pointer, previous, dirty, +tile_depth, fork_depth}:
			Model{body, surface, R.RenderScene.reproject(surface, camera, tile_depth, scene), camera, controls, pointer, previous, dirty, tile_depth, fork_depth}

def Model.refresh(changed: Bool, model: Model) -> Model:
	match model:
		case Model{body, surface, scene, camera, controls, pointer, previous, True{}, tile_depth, fork_depth}:
			Model.rebuilt(camera, controls, pointer, previous, tile_depth, fork_depth, V.Surface.build(body))
		case Model{body, surface, scene, camera, controls, pointer, previous, False{}, tile_depth, fork_depth}:
			Model.refreshed(changed, Model{body, surface, scene, camera, controls, pointer, previous, False{}, tile_depth, fork_depth})

def Model.destroy(model: Model, cell: V.Cell) -> Model:
	Model.refresh(False{}, Model.erased(model, V.MetricSphere.brush(V.PointCm.cell(cell))))

def Model.cut(model: Model, sphere: V.MetricSphere) -> Model:
	Model.refresh(False{}, Model.erased(model, sphere))

def Model.reset(model: Model) -> Model:
	Model.refresh(False{}, Model.restored(model))

def Model.drawn(body: V.Body, surface: V.Surface, camera: R.Camera, controls: Controls, pointer: Pointer, previous: Maybe<&2, Nat>, dirty: Bool, tile_depth: Nat, fork_depth: Nat, rendered: Image & R.RenderScene) -> Model & Image:
	(image, scene) = rendered
	(Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth}, image)

def Model.view(model: Model) -> Model & Image:
	Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, +fork_depth} = model
	Model.drawn(body, surface, camera, controls, pointer, previous, dirty, tile_depth, fork_depth, R.RenderScene.image(scene, fork_depth))

def Pointer.target(looking: Bool, pointer: Pointer) -> Pointer:
	match looking:
		case True{}:
			Pointer{256, 256}
		case False{}:
			pointer

def Pointer.sphere(pointer: Pointer, scene: R.RenderScene) -> Maybe<&2, V.MetricSphere>:
	Pointer{x, y} = pointer
	R.RenderScene.target(scene, x, y)

def Model.preview(model: Model) -> Model & Image:
	Model{body, surface, +scene, camera, +controls, +pointer, previous, dirty, tile_depth, +fork_depth} = model
	Model.drawn(body, surface, camera, controls, pointer, previous, dirty, tile_depth, fork_depth,
		R.RenderScene.preview(scene, Pointer.sphere(Pointer.target(Controls.capture(controls), pointer), scene), fork_depth))

def Model.clicked(hit: Maybe<&2, V.MetricSphere>, model: Model) -> Model:
	match hit:
		case None{}:
			model
		case Some{sphere}:
			Model.erased(model, sphere)

def Model.pointed(looking: Bool, model: Model, x: U32, y: U32) -> Model:
	match looking model:
		case True{} _:
			model
		case False{} Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth}:
			Model{body, surface, scene, camera, controls, Pointer{x, y}, previous, dirty, tile_depth, fork_depth}

def Model.point(model: Model, x: U32, y: U32) -> Model:
	Model{body, surface, scene, camera, +controls, pointer, previous, dirty, tile_depth, fork_depth} = model
	Model.pointed(Controls.capture(controls), Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth}, x, y)

def Model.click.pending(model: Model, +x: U32, +y: U32) -> Model:
	Model{body, surface, +scene, camera, +controls, pointer, previous, dirty, tile_depth, fork_depth} = model
	Model.clicked(Pointer.sphere(Pointer.target(Controls.capture(controls), Pointer{x, y}), scene),
		Model.point(Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth}, x, y))

def Model.click(model: Model, x: U32, y: U32) -> Model:
	Model.refresh(False{}, Model.click.pending(model, x, y))

def Model.key(model: Model, code: U32, down: Bool) -> Model:
	Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth} = model
	Model{body, surface, scene, camera, Controls.key(code, down, controls), pointer, previous, dirty, tile_depth, fork_depth}

def Model.capture(model: Model, looking: Bool) -> Model:
	Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth} = model
	Model{body, surface, scene, camera, Controls.look(controls, looking), pointer, previous, dirty, tile_depth, fork_depth}

def Model.button(down: Bool, model: Model, x: U32, y: U32) -> Model:
	match down:
		case True{}:
			Model.capture(Model.point(model, x, y), True{})
		case False{}:
			Model.point(Model.capture(model, False{}), x, y)

def Model.look.active(active: Bool, model: Model, dx: F32, dy: F32) -> Model:
	match active model:
		case False{} _:
			model
		case True{} Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth}:
			Model{body, surface, scene, R.Camera.look(camera, dx, dy), controls, pointer, previous, dirty, tile_depth, fork_depth}

def Model.look(model: Model, dx: F32, dy: F32) -> Model:
	Model{body, surface, scene, camera, +controls, pointer, previous, dirty, tile_depth, fork_depth} = model
	Model.look.active(Controls.capture(controls), Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth}, dx, dy)

def Model.demo_cut(model: Model) -> Model:
	match model:
		case Model{V.Body{side,cells},surface,scene,camera,controls,pointer,previous,dirty,tile_depth,fork_depth}:
			Model.destroy(Model{V.Body{side,cells},surface,scene,camera,controls,pointer,previous,dirty,tile_depth,fork_depth},V.Cell{6,6,6})
		case Model{V.Cuboids{boxes},surface,scene,camera,controls,pointer,previous,dirty,tile_depth,fork_depth}:
			Model.click(Model{V.Cuboids{boxes},surface,scene,camera,controls,pointer,previous,dirty,tile_depth,fork_depth},226,224)

def Model.event(event: Event, model: Model) -> Maybe<Model>:
	match event:
		case Close{}:
			None{}
		case Key{27, True{}}:
			None{}
		case Key{32, True{}}:
			Some{Model.demo_cut(model)}
		case Key{114, True{}}:
			Some{Model.restored(model)}
		case Key{82, True{}}:
			Some{Model.restored(model)}
		case Key{code, down}:
			Some{Model.key(model, code, down)}
		case Mouse{x, y, 1, down}:
			Some{Model.button(down, model, x, y)}
		case Move{x, y}:
			Some{Model.point(model, x, y)}
		case Look{dx, dy}:
			Some{Model.look(model, dx, dy)}
		case Mouse{x, y, 0, True{}}:
			Some{Model.click.pending(model, x, y)}
		case _:
			Some{model}

def Model.events(events: List<Event>, model: Model) -> Maybe<Model>:
	match events:
		case Nil{}:
			Some{model}
		case Con{event, rest}:
			Maybe.bind(&1, Model, Model, Model.event(event, model), m => Model.events(rest, m))

def Model.flown(old_camera: R.Camera, model: Model, +camera: R.Camera) -> Model:
	Model{body, surface, scene, old, controls, pointer, previous, dirty, tile_depth, fork_depth} = model
	Model.refresh(Bool.not(R.Camera.equal(old_camera, camera)), Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth})

def Model.flight(old_camera: R.Camera, elapsed_ms: Nat, model: Model) -> Model:
	Model{body, surface, scene, +camera, +controls, pointer, previous, dirty, tile_depth, fork_depth} = model
	Model.flown(old_camera, Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth}, Controls.fly(controls, camera, elapsed_ms))

def Model.advanced(old_camera: R.Camera, elapsed_ms: Nat, next: Maybe<Model>) -> Maybe<Model>:
	match next:
		case None{}:
			None{}
		case Some{model}:
			Some{Model.flight(old_camera, elapsed_ms, model)}

def Model.advance(events: List<Event>, elapsed_ms: Nat, model: Model) -> Maybe<Model>:
	Model{body, surface, scene, +camera, controls, pointer, previous, dirty, tile_depth, fork_depth} = model
	Model.advanced(camera, elapsed_ms, Model.events(events, Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth}))

def Clock.elapsed(previous: Maybe<&2, Nat>, now: Nat) -> Nat:
	match previous:
		case None{}:
			0n
		case Some{before}:
			Nat.min(Nat.sub(now, before), 100n)

def Model.at(events: List<Event>, +now: Nat, model: Model) -> Maybe<Model>:
	Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth} = model
	Model.advance(events, Clock.elapsed(previous, now), Model{body, surface, scene, camera, controls, pointer, Some{now}, dirty, tile_depth, fork_depth})

def Model.tick(events: List<Event>, model: Model) -> IO(Maybe<Model>):
	do IO<Maybe<Model>>:
		now : Nat <- IO.now()
		return Model.at(events, now, model)

def Interactive.request(request: Maybe<&2, Bool>, window: Window, model: Model, rest: Window -> Model -> IO(Unit)) -> IO(Unit):
	match request:
		case None{}:
			App.step(Model, App{Model.preview, Model.tick}, window, model, rest)
		case Some{looking}:
			do IO<Unit>:
				window : Window <- Window.grab(window, looking)
				App.step(Model, App{Model.preview, Model.tick}, window, model, rest)

def Interactive.controls(window: Window, model: Model, rest: Window -> Model -> IO(Unit), requested: Controls & Maybe<&2, Bool>) -> IO(Unit):
	Model{body, surface, scene, camera, old_controls, pointer, previous, dirty, tile_depth, fork_depth} = model
	(controls, request) = requested
	Interactive.request(request, window, Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth}, rest)

def Interactive.step(window: Window, model: Model, rest: Window -> Model -> IO(Unit)) -> IO(Unit):
	Model{body, surface, scene, camera, +controls, pointer, previous, dirty, tile_depth, fork_depth} = model
	Interactive.controls(window, Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth}, rest, Controls.request(controls))

def Interactive.loop(fuel: Nat, window: Window, model: Model) -> IO(Unit):
	match fuel:
		case 0n:
			Window.close(window)
		case 1n+remaining:
			Interactive.step(window, model, w => m => Interactive.loop(remaining, w, m))

def Interactive.run(model: Model) -> IO(Unit):
	do IO<Unit>:
		window : Window <- IO.try(Window, Window.open("Bend Voxel Rewrite | WASD Q/E fly | RMB look | Space cut | click carve | R reset | Esc exit", 512, 512))
		Interactive.loop(4294967295n, window, model)

def Options.args(args: List<String>) -> List<&2, String>:
	match args:
		case Nil{}:
			Nil{}
		case Con{arg, rest}:
			arg <> Options.args(rest)

def Options.flag(args: List<&2, String>, +flag: String, found: Bool) -> Maybe<&2, String>:
	match args:
		case Nil{}:
			None{}
		case Con{+arg, rest}:
			match found:
				case True{}:
					Some{arg}
				case False{}:
					Options.flag(rest, flag, String.eq(arg, flag))

def Options.has(args: List<&2, String>, +flag: String) -> Bool:
	match args:
		case Nil{}:
			False{}
		case Con{arg, rest}:
			Bool.or(String.eq(arg, flag), Options.has(rest, flag))

def Options.number(value: Maybe<&2, String>, fallback: U32) -> U32:
	match value:
		case None{}:
			fallback
		case Some{text}:
			Maybe.default(&2, U32, U32.read(text), fallback)

def Options.mode(dump: Maybe<&2, String>, bench: Maybe<&2, String>) -> Mode:
	match dump:
		case Some{path}:
			Dump{path}
		case None{}:
			match bench:
				case Some{n}:
					Benchmark{U32.to_nat(Maybe.default(&2, U32, U32.read(n), 60))}
				case None{}:
					Interactive{}

def Options.clamp(valid: Bool, n: U32, fallback: U32) -> U32:
	match valid:
		case True{}:
			n
		case False{}:
			fallback

def Options.depth(value: Maybe<&2, String>, +fallback: U32) -> Nat:
	+n = Options.number(value, fallback)
	U32.to_nat(Options.clamp((n <= 9 : U32), n, fallback))

def Options.parse(+args: List<&2, String>) -> Options:
	Options{Options.mode(Options.flag(args, "--dump", False{}), Options.flag(args, "--bench", False{})), Options.has(args, "--cut"),
		Options.depth(Options.flag(args, "--tile-depth", False{}), 6), Options.depth(Options.flag(args, "--fork-depth", False{}), 6)}

def Model.initial(cut: Bool, tile_depth: Nat, fork_depth: Nat) -> Model:
	match cut:
		case False{}:
			Model.init(tile_depth, fork_depth)
		case True{}:
			Model.click(Model.init(tile_depth, fork_depth),226,224)

def Run.dump(path: String, drawn: Model & Image) -> IO(Unit):
	(model, image) = drawn
	D.Dump.ppm(path, image)

def Bench.edit(frame: U32, model: Model) -> Model:
	match frame:
		case 8:
			Model.demo_cut(model)
		case 16:
			Model.reset(model)
		case _:
			model

def Bench.shown(shown: Window & Image & List<Event>) -> IO(Window):
	(window, image, events) = shown
	do IO<Window>:
		Unit <- IO.pure(Unit, Image.drop!(image))
		return window

def Bench.frame(window: Window, drawn: Model & Image) -> IO(Window & Model):
	(model, image) = drawn
	do IO<Window & Model>:
		shown : Window & Image & List<Event> <- Window.frame(window, image)
		window : Window <- Bench.shown(shown)
		return (window, model)

def Bench.loop(fuel: Nat, +frame: U32, state: Window & Model) -> IO(Window & Model):
	match fuel:
		case 0n:
			IO.pure(Window & Model, state)
		case 1n+rest:
			(window, model) = state
			do IO<Window & Model>:
				model : Model = Bench.edit((frame % 24 : U32), model)
				barrier : Nat <- IO.now()
				result : Window & Model <- Bench.frame(window, Model.view(model))
				Bench.loop(rest, (frame + 1 : U32), result)

def Bench.close(state: Window & Model) -> IO(Unit):
	(window, model) = state
	Window.close(window)

def Bench.run(+frames: Nat, model: Model) -> IO(Unit):
	do IO<Unit>:
		window : Window <- IO.try(Window, Window.open("Bend Voxel Rewrite | benchmark", 512, 512))
		warm : Window & Model <- Bench.loop(8n, 0, (window, model))
		start : Nat <- IO.now()
		finished : Window & Model <- Bench.loop(frames, 8, warm)
		finish : Nat <- IO.now()
		Bench.close(finished)
		IO.print("frames=" ++ Nat.show(frames) ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finish, start)))

def Model.selected(cube: Bool, cut: Bool, tile_depth: Nat, fork_depth: Nat) -> Model:
	match cube cut:
		case False{} _: Model.initial(cut,tile_depth,fork_depth)
		case True{} False{}: Model.cube(tile_depth,fork_depth)
		case True{} True{}: Model.destroy(Model.cube(tile_depth,fork_depth),V.Cell{6,6,6})

def Run.mode(mode: Mode, model: Model) -> IO(Unit):
	match mode:
		case Dump{path}:
			do IO<Unit>:
				barrier : Nat <- IO.now()
				Run.dump(path, Model.view(model))
		case Benchmark{frames}:
			Bench.run(frames, model)
		case Interactive{}:
			Interactive.run(model)

def Run.options(options: Options, cube: Bool) -> IO(Unit):
	Options{mode, cut, tile_depth, fork_depth} = options
	Run.mode(mode, Model.selected(cube, cut, tile_depth, fork_depth))

def Run.args(+args: List<&2,String>) -> IO(Unit):
	Run.options(Options.parse(args),Options.has(args,"--cube"))

def main() -> IO(Unit):
	do IO<Unit>:
		args : List<String> <- IO.args()
		Run.args(Options.args(args))
