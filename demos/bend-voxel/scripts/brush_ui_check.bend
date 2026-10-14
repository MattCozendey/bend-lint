import Base
import ../main.bend as App
import ../render.bend as R
import ../voxel.bend as V
import ./ui_check.bend as UI
import ./flight_ui_check.bend as Flight
import ../deps/bend-ui-test/uitest.bend as UITest

type Snapshot is Data:
	Snapshot{body: V.Snapshot, scene: R.RenderScene, camera: R.Camera, pointer: App.Pointer, looking: Bool}

type Stage is Data:
	Hovered{}
	FreeCut{}
	FreeReset{}
	Background{}
	Captured{}
	CentreCut{}
	Released{}
	BackgroundReset{}

type Session is Data:
	Session{output: String, ref: WindowRef, original: V.Snapshot, expected: Maybe<&2, V.MetricSphere>, before: Image, background: Image, completed: Chan(Bool)}

def Snapshot.built(surface: V.Surface, +scene: R.RenderScene, +camera: R.Camera, +controls: App.Controls, +pointer: App.Pointer, time: Maybe<&2, Nat>, dirty: Bool, td: Nat, fd: Nat, result: Array<U32> & V.Snapshot) -> App.Model & Snapshot:
	(cells, materials) = result
	(App.Model{V.Body{8, cells}, surface, scene, camera, controls, pointer, time, dirty, td, fd}, Snapshot{materials, scene, camera, pointer, App.Controls.capture(controls)})

def Snapshot.take(model: App.Model) -> IO(App.Model & Snapshot):
	match model:
		case App.Model{V.Body{side,cells},surface,scene,camera,controls,pointer,time,dirty,td,fd}:
			IO.pure(App.Model & Snapshot,Snapshot.built(surface,scene,camera,controls,pointer,time,dirty,td,fd,V.Snapshot.of(cells)))
		case App.Model{V.Cuboids{boxes},surface,scene,camera,controls,pointer,time,dirty,td,fd}:
			IO.die(App.Model & Snapshot,1,"The brush oracle requires the cube fixture")

def Snapshot.target(snapshot: Snapshot) -> Maybe<&2, V.MetricSphere>:
	Snapshot{body, scene, camera, pointer, looking} = snapshot
	App.Pointer.sphere(App.Pointer.target(looking, pointer), scene)

def Snapshot.cells(snapshot: V.Snapshot) -> Array<U32>:
	match snapshot:
		case V.Leaf{material}:
			ALeaf{material}
		case V.Node{left, right}:
			ANode{Snapshot.cells(left), Snapshot.cells(right)}

def Snapshot.restore(snapshot: V.Snapshot) -> V.Body:
	V.Body{8, Snapshot.cells(snapshot)}

def Snapshot.body(snapshot: Snapshot) -> V.Body:
	Snapshot{body, scene, camera, pointer, looking} = snapshot
	Snapshot.restore(body)

def Snapshot.pointer(snapshot: Snapshot, x: U32, y: U32, expected_look: Bool) -> Bool:
	Snapshot{body, scene, camera, App.Pointer{ax, ay}, looking} = snapshot
	U32.is_eq(ax, x) && U32.is_eq(ay, y) && U32.is_eq(Bool.to_u32(looking), Bool.to_u32(expected_look))

def Snapshot.show(snapshot: Snapshot) -> String:
	Snapshot{body, scene, camera, App.Pointer{x, y}, looking} = snapshot
	"pointer=" ++ U32.show(x) ++ "," ++ U32.show(y) ++ " looking=" ++ U32.show(Bool.to_u32(looking))

def Sphere.empty(found: Maybe<&2, V.MetricSphere>) -> Bool:
	match found:
		case None{}:
			True{}
		case Some{s}:
			False{}

def Pixels.yellow(depth: Nat, image: Image) -> U32:
	match depth image:
		case 0n Pix{color}:
			Bool.to_u32(U32.is_eq(color, 16776960))
		case 1n++rest Qua{tl, tr, bl, br}:
			(Pixels.yellow(rest, tl) + Pixels.yellow(rest, tr) + Pixels.yellow(rest, bl) + Pixels.yellow(rest, br) : U32)
		case _ _:
			0

def Pixels.equal(depth: Nat, a: Image, b: Image) -> Bool:
	match depth a b:
		case 0n Pix{ac} Pix{bc}:
			U32.is_eq(ac, bc)
		case 1n++rest Qua{at, ar, ab, ad} Qua{bt, br, bb, bd}:
			Pixels.equal(rest, at, bt) && Pixels.equal(rest, ar, br) && Pixels.equal(rest, ab, bb) && Pixels.equal(rest, ad, bd)
		case _ _ _:
			False{}

def Cells.same(a: Array<U32>, b: Array<U32>) -> Bool:
	match a b:
		case ALeaf{ac} ALeaf{bc}:
			U32.is_eq(ac, bc)
		case ANode{al, ar} ANode{bl, br}:
			Cells.same(al, bl) && Cells.same(ar, br)
		case _ _:
			False{}

def Body.same(a: V.Body, b: V.Body) -> Bool:
	match a b:
		case V.Body{as,ac} V.Body{bs,bc}: U32.is_eq(as,bs) && Cells.same(ac,bc)
		case _ _: False{}

def Sphere.equal(a: Maybe<&2, V.MetricSphere>, b: Maybe<&2, V.MetricSphere>) -> Bool:
	match a b:
		case None{} None{}:
			True{}
		case Some{V.MetricSphere{V.PointCm{ax, ay, az}, ar}} Some{V.MetricSphere{V.PointCm{bx, by, bz}, br}}:
			F32.is_eq(ax, bx) && F32.is_eq(ay, by) && F32.is_eq(az, bz) && F32.is_eq(ar, br)
		case _ _:
			False{}

def Sphere.cut(sphere: Maybe<&2, V.MetricSphere>, body: V.Body) -> V.Body:
	match sphere:
		case None{}:
			body
		case Some{s}:
			V.Body.cut(body, s)

def Native.move(ref: WindowRef, x: U32, y: U32) -> IO(Unit):
	X11WindowRef{display, id} = ref
	Flight.Native.display(display, ["mousemove", "--sync", "--window", U32.show(id), U32.show(x), U32.show(y)])

def Check.preview(snapshot: Snapshot, image: Image, rendered: Image & R.RenderScene) -> IO(Unit):
	(expected, scene) = rendered
	UI.Check.require(Pixels.equal(9n, image, expected), "Native capture differs from actual preview renderer")

def Check.capture_view(+snapshot: Snapshot, +image: Image) -> IO(Unit):
	Snapshot{body, +scene, camera, pointer, looking} = snapshot
	Check.preview(snapshot, image, R.RenderScene.preview(scene, Snapshot.target(snapshot), 5n))

def Check.finish(+ref: WindowRef, completed: Chan(Bool), window: Window, model: App.Model) -> IO(Unit):
	do IO<Unit>:
		IO.try(Unit, UITest.request_close(ref))
		App.Interactive.step(window, model, UI.Check.unclosed)
		alive : Bool <- IO.try(Bool, UITest.alive(ref))
		UI.Check.require(Bool.not(alive), "Brush window survived Close")
		sent : Bool <- Chan.send(Bool, completed, True{})
		UI.Check.require(sent, "Brush completion channel closed early")
		IO.print("PASS native hover, yellow preview, background clearing, complete free/centre click sets, retarget, resets and Close")

def Check.stage(shown: Window & Image, stage: Stage, session: Session, +snapshot: Snapshot, model: App.Model, next: Stage -> Session -> Window -> App.Model -> IO(Unit)) -> IO(Unit):
	(window, +image) = shown
	match stage session:
		case Hovered{} Session{+output, +ref, +original, expected, before, background, completed}:
			do IO<Unit>:
				UI.Check.require(Snapshot.pointer(snapshot, 256, 200, False{}) && Body.same(Snapshot.restore(original), Snapshot.body(snapshot)), "Native hover changed body or missed " ++ Snapshot.show(snapshot))
				UI.Check.require(U32.is_eq(UI.Pixels.at(9n, 256, 200, 512, image), 16776960), "Native selected cell is not yellow")
				Check.capture_view(snapshot, image)
				IO.try(Unit, UITest.click(ref, 256, 200))
				next(FreeCut{}, Session{output, ref, original, Snapshot.target(snapshot), image, background, completed}, window, model)
		case FreeCut{} Session{+output, +ref, +original, +expected, +before, background, completed}:
			do IO<Unit>:
				UI.Check.require(Body.same(Sphere.cut(expected, Snapshot.restore(original)), Snapshot.body(snapshot)), "Native free click differs from complete preview removal set")
				UI.Check.require(Bool.not(Sphere.equal(expected, Snapshot.target(snapshot))), "Native click left stale surface target")
				Check.capture_view(snapshot, image)
				IO.try(Unit, UITest.key(ref, 114))
				next(FreeReset{}, Session{output, ref, original, expected, before, background, completed}, window, model)
		case FreeReset{} Session{+output, +ref, +original, expected, before, background, completed}:
			do IO<Unit>:
				UI.Check.require(Body.same(Snapshot.restore(original), Snapshot.body(snapshot)) && U32.is_eq(UI.Pixels.delta(9n, before, image), 0), "Native reset changed same-hover preview")
				Native.move(ref, 20, 20)
				next(Background{}, Session{output, ref, original, expected, Pix{0}, background, completed}, window, model)
		case Background{} Session{+output, +ref, +original, expected, before, background, completed}:
			do IO<Unit>:
				UI.Check.require(Snapshot.pointer(snapshot, 20, 20, False{}) && Sphere.empty(Snapshot.target(snapshot)) && U32.is_eq(Pixels.yellow(9n, image), 0), "Native background retained preview")
				UI.Check.require(Body.same(Snapshot.restore(original), Snapshot.body(snapshot)), "Background hover changed body")
				Check.capture_view(snapshot, image)
				Flight.Native.button(ref, True{})
				next(Captured{}, Session{output, ref, original, expected, Pix{0}, image, completed}, window, model)
		case Captured{} Session{+output, +ref, +original, expected, before, +background, completed}:
			do IO<Unit>:
				UI.Check.require(Snapshot.pointer(snapshot, 20, 20, True{}) && Bool.not(Sphere.empty(Snapshot.target(snapshot))), "RMB did not switch targeting to centre")
				Check.capture_view(snapshot, image)
				IO.try(Unit, UITest.click(ref, 20, 20))
				next(CentreCut{}, Session{output, ref, original, Snapshot.target(snapshot), image, background, completed}, window, model)
		case CentreCut{} Session{+output, +ref, +original, +expected, before, +background, completed}:
			do IO<Unit>:
				UI.Check.require(Body.same(Sphere.cut(expected, Snapshot.restore(original)), Snapshot.body(snapshot)), "Captured click used event coordinates instead of centre removal set")
				Check.capture_view(snapshot, image)
				Flight.Native.button(ref, False{})
				next(Released{}, Session{output, ref, original, expected, before, background, completed}, window, model)
		case Released{} Session{+output, +ref, +original, expected, before, +background, completed}:
			do IO<Unit>:
				Native.move(ref, 20, 20)
				IO.try(Unit, UITest.key(ref, 114))
				next(BackgroundReset{}, Session{output, ref, original, expected, before, background, completed}, window, model)
		case BackgroundReset{} Session{output, ref, +original, expected, before, background, completed}:
			do IO<Unit>:
				UI.Check.require(Body.same(Snapshot.restore(original), Snapshot.body(snapshot)) && U32.is_eq(UI.Pixels.delta(9n, background, image), 0), "Native centre reset changed free background preview")
				Check.finish(ref, completed, window, model)

def Stage.name(stage: Stage) -> String:
	match stage:
		case Hovered{}: "hovered"
		case FreeCut{}: "free-cut"
		case FreeReset{}: "free-reset"
		case Background{}: "background"
		case Captured{}: "captured"
		case CentreCut{}: "centre-cut"
		case Released{}: "released"
		case BackgroundReset{}: "background-reset"

def Check.run(+stage: Stage, +session: Session, window: Window, taken: App.Model & Snapshot, next: Stage -> Session -> Window -> App.Model -> IO(Unit)) -> IO(Unit):
	Session{output, ref, original, expected, before, background, completed} = session
	(model, snapshot) = taken
	IO.bind(Window & Image, Unit, Flight.Flight.capture(output, Stage.name(stage), window), shown => Check.stage(shown, stage, session, snapshot, model, next))

def Check.loop(fuel: Nat, stage: Stage, session: Session, window: Window, model: App.Model) -> IO(Unit):
	match fuel:
		case 0n:
			do IO<Unit>:
				Window.close(window)
				IO.die(Unit, 1, "Brush UI frame budget exhausted")
		case 1n+rest:
			UI.Check.frames(3n, window, model, w => m => IO.bind(App.Model & Snapshot,Unit,Snapshot.take(m),snapshot => Check.run(stage,session,w,snapshot,s => c => ww => mm => Check.loop(rest,s,c,ww,mm))))

def Check.ready(output: String, completed: Chan(Bool), taken: App.Model & Snapshot, exported: Window & WindowRef) -> IO(Unit):
	(model, Snapshot{body, scene, camera, pointer, looking}) = taken
	(window, +ref) = exported
	do IO<Unit>:
		Flight.Native.send(ref, ["mouseup", "3"])
		Flight.Native.focus(ref)
		Native.move(ref, 40, 40)
		UI.Check.frames(2n, window, model, w => m => IO.bind(Unit, Unit, Native.move(ref, 256, 200), _ => Check.loop(9n, Hovered{}, Session{output, ref, body, None{}, Pix{0}, Pix{0}, completed}, w, m)))

def Check.start(+output: String) -> IO(Unit):
	do IO<Unit>:
		UI.Check.mkdir(output)
		+completed : Chan(Bool) <- Chan.new(Bool, 1)
		window : Window <- IO.try(Window, Window.open("Bend Voxel Rewrite | native metric brush check", 512, 512))
		UI.Check.frames(2n, window, App.Model.cube(5n, 5n), w => m => IO.bind(Window & WindowRef, Unit, UI.Reference.export(w), exported => IO.bind(App.Model & Snapshot,Unit,Snapshot.take(m),snapshot => Check.ready(output,completed,snapshot,exported))))
		Chan.close(Bool, completed)
		finished : Maybe<Bool> <- Chan.recv(Bool, completed)
		UI.Check.require(Maybe.default(&1, Bool, finished, False{}), "Native brush check did not complete")

def main() -> IO(Unit):
	do IO<Unit>:
		args : List<String> <- IO.args()
		Check.start(Maybe.default(&2, String, App.Options.flag(App.Options.args(args), "--output", False{}), ".audit/screenshots/brush-ui"))
