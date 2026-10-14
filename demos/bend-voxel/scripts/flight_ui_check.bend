import Base
import ../main.bend as App
import ../render.bend as R
import ../dump.bend as D
import ./ui_check.bend as UI
import ./ui_capture.bend as C
import ../deps/bend-ui-test/uitest.bend as UITest

def Native.result(result: U32 & (String & String)) -> IO(Unit):
	(status, streams) = result
	(stdout, stderr) = streams
	UI.Check.require(U32.is_eq(status, 0), "xdotool failed " ++ stderr)

def Native.display(display: String, args: List<String>) -> IO(Unit):
	IO.bind(U32 & (String & String), Unit, IO.try(U32 & (String & String), Process.run("env", List.append(&1, String, ["DISPLAY=" ++ display, "xdotool"], args), "", 4096, 3000)), Native.result)

def Native.send(ref: WindowRef, args: List<String>) -> IO(Unit):
	X11WindowRef{display, id} = ref
	Native.display(display, args)

def Native.key(ref: WindowRef, down: Bool, code: U32) -> IO(Unit):
	X11WindowRef{display, id} = ref
	Native.display(display, [Bool.pick(String, down, "keydown", "keyup"), "--window", U32.show(id), SCon{Chr{code}, SNil{}}])

def Native.focus(ref: WindowRef) -> IO(Unit):
	X11WindowRef{+display, +id} = ref
	do IO<Unit>:
		Native.display(display, ["windowraise", U32.show(id)])
		Native.display(display, ["windowfocus", "--sync", U32.show(id)])
		Native.display(display, ["mousemove", "--window", U32.show(id), "256", "256"])

def Native.button(ref: WindowRef, down: Bool) -> IO(Unit):
	X11WindowRef{display, id} = ref
	Native.display(display, [Bool.pick(String, down, "mousedown", "mouseup"), "--window", U32.show(id), "3"])

def Native.motion(ref: WindowRef) -> IO(Unit):
	Native.send(ref, ["mousemove_relative", "--", "40", "20"])

def Flight.snapshot(model: App.Model) -> App.Model & R.Camera:
	App.Model{body, surface, scene, +camera, controls, pointer, previous, dirty, tile_depth, fork_depth} = model
	(App.Model{body, surface, scene, camera, controls, pointer, previous, dirty, tile_depth, fork_depth}, camera)

def Flight.direction.axis(code: U32, basis: R.Basis) -> R.Vec3:
	match code basis:
		case 119 R.Basis{eye, right, up, forward, focal, near}:
			forward
		case 115 R.Basis{eye, right, up, forward, focal, near}:
			R.Vec3.scale(forward, (0.0 - 1.0 : F32))
		case 97 R.Basis{eye, right, up, forward, focal, near}:
			R.Vec3.scale(right, (0.0 - 1.0 : F32))
		case 100 R.Basis{eye, right, up, forward, focal, near}:
			right
		case 113 _:
			R.Vec3{0.0, 0.0, (0.0 - 1.0 : F32)}
		case _ _:
			R.Vec3{0.0, 0.0, 1.0}

def Flight.direction(code: U32, camera: R.Camera) -> R.Vec3:
	Flight.direction.axis(code, R.Camera.basis(camera))

def Flight.displacement(previous: R.Camera, current: R.Camera) -> R.Vec3:
	R.Camera{old, oldyaw, oldpitch} = previous
	R.Camera{eye, yaw, pitch} = current
	R.Vec3.add(eye, R.Vec3.scale(old, (0.0 - 1.0 : F32)))

def Flight.moved(+previous: R.Camera, +current: R.Camera, code: U32) -> Bool:
	+delta = Flight.displacement(previous, current)
	+expected = Flight.direction(code, previous)
	((R.Vec3.dot(delta, delta) > 0.0001 : F32) && (R.Vec3.dot(R.Vec3.unit(delta, R.Vec3.dot(delta, delta)), R.Vec3.unit(expected, R.Vec3.dot(expected, expected))) > 0.999 : F32))

def Flight.converted(+output: String, name: String, window: Window, converted: Result<&2, &2, String, Image>) -> IO(Window & Image):
	match converted:
		case Fail{message}:
			do IO<Window & Image>:
				Window.close(window)
				IO.die(Window & Image, 1, message)
		case Done{+image}:
			do IO<Window & Image>:
				D.Dump.ppm(output ++ "/" ++ name ++ ".ppm", image)
				return (window, image)

def Flight.captured(+output: String, name: String, captured: Window & Result<&1, &1, U32 & String, Capture>) -> IO(Window & Image):
	match captured:
		case (window, Done{capture}):
			Flight.converted(output, name, window, C.Capture.image(capture))
		case (window, Fail{(code, message)}):
			do IO<Window & Image>:
				Window.close(window)
				IO.die(Window & Image, code, message)

def Flight.capture(+output: String, name: String, window: Window) -> IO(Window & Image):
	IO.bind(Window & Result<&1, &1, U32 & String, Capture>, Window & Image, Window.capture(window), c => Flight.captured(output, name, c))

def Flight.close(+ref: WindowRef, completed: Chan(Bool), window: Window, model: App.Model) -> IO(Unit):
	do IO<Unit>:
		IO.try(Unit, UITest.key(ref, 27))
		App.Interactive.step(window, model, UI.Check.unclosed)
		alive : Bool <- IO.try(Bool, UITest.alive(ref))
		UI.Check.require(Bool.not(alive), "Native flight window survived Escape")
		sent : Bool <- Chan.send(Bool, completed, True{})
		UI.Check.require(sent, "Native flight completion channel closed early")
		IO.print("PASS native WASDQE holds/releases, RMB relative look, released motion, flight carve, reset pose and Escape")

def Flight.closed_image(before: Image, model: App.Model, shown: Window & Image, finish: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	(window, image) = shown
	do IO<Unit>:
		UI.Check.require(U32.is_eq(UI.Pixels.delta(9n, before, image), 0), "Native reset after flight did not restore the visible body")
		finish(window, model)

def Flight.reset_checked(+output: String, expected: R.Camera, before: Image, window: Window, snapshot: App.Model & R.Camera, finish: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	(model, camera) = snapshot
	do IO<Unit>:
		UI.Check.require(R.Camera.equal(expected, camera), "Native R reset changed flight camera")
		IO.bind(Window & Image, Unit, Flight.capture(output, "reset-after-flight", window), shown => Flight.closed_image(before, model, shown, finish))

def Flight.carved(+output: String, ref: WindowRef, expected: R.Camera, +before: Image, model: App.Model, shown: Window & Image, finish: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	(window, image) = shown
	do IO<Unit>:
		UI.Check.require((UI.Pixels.delta(9n, before, image) > 100 : U32), "Native primary click after flight did not carve")
		IO.try(Unit, UITest.key(ref, 114))
		UI.Check.frames(3n, window, model, w => m => Flight.reset_checked(output, expected, before, w, Flight.snapshot(m), finish))

def Flight.carve(+output: String, +ref: WindowRef, expected: R.Camera, model: App.Model, shown: Window & Image, finish: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	(window, image) = shown
	do IO<Unit>:
		IO.try(Unit, UITest.click(ref, 256, 256))
		UI.Check.frames(3n, window, model, w => m => IO.bind(Window & Image, Unit, Flight.capture(output, "carved-after-flight", w), shown => Flight.carved(output, ref, expected, image, m, shown, finish)))

def Flight.released_look(+output: String, +ref: WindowRef, +expected: R.Camera, window: Window, snapshot: App.Model & R.Camera, finish: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	(model, camera) = snapshot
	do IO<Unit>:
		UI.Check.require(R.Camera.equal(expected, camera), "Uncaptured native mouse motion changed view")
		Native.focus(ref)
		UI.Check.frames(2n, window, model, w => m => IO.bind(Window & Image, Unit, Flight.capture(output, "released-look", w), shown => Flight.carve(output, ref, expected, m, shown, finish)))

def Flight.look_released(+output: String, +ref: WindowRef, expected: R.Camera, window: Window, model: App.Model, finish: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	do IO<Unit>:
		Native.motion(ref)
		UI.Check.frames(3n, window, model, w => m => Flight.released_look(output, ref, expected, w, Flight.snapshot(m), finish))

def Flight.looked_image(+output: String, +ref: WindowRef, expected: R.Camera, model: App.Model, shown: Window & Image, finish: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	(window, image) = shown
	do IO<Unit>:
		Native.button(ref, False{})
		UI.Check.frames(2n, window, model, w => m => Flight.look_released(output, ref, expected, w, m, finish))

def Flight.look_delta(previous: R.Camera, current: R.Camera) -> Bool:
	R.Camera{old_eye, old_yaw, old_pitch} = previous
	R.Camera{eye, yaw, pitch} = current
	((F32.abs((yaw - old_yaw + 0.12 : F32)) < 0.00002) && (F32.abs((pitch - old_pitch + 0.06 : F32)) < 0.00002) : F32)

def Flight.looked(+output: String, ref: WindowRef, previous: R.Camera, window: Window, snapshot: App.Model & R.Camera, finish: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	(model, +camera) = snapshot
	do IO<Unit>:
		UI.Check.require(Flight.look_delta(previous, camera), "Captured native 40,20 mouse motion did not apply its relative look")
		IO.bind(Window & Image, Unit, Flight.capture(output, "captured-look", window), shown => Flight.looked_image(output, ref, camera, model, shown, finish))

def Flight.look_motion(+output: String, +ref: WindowRef, previous: R.Camera, window: Window, model: App.Model, finish: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	App.Model{body, surface, scene, camera, +controls, pointer, time, dirty, tile_depth, fork_depth} = model
	do IO<Unit>:
		UI.Check.require(App.Controls.capture(controls), "Native RMB press did not reach the app reducer")
		Native.motion(ref)
		UI.Check.frames(3n, window, App.Model{body, surface, scene, camera, controls, pointer, time, dirty, tile_depth, fork_depth}, w => m => Flight.looked(output, ref, previous, w, Flight.snapshot(m), finish))

def Flight.look_ready(+output: String, +ref: WindowRef, snapshot: App.Model & R.Camera, shown: Window & Image, finish: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	(model, camera) = snapshot
	(window, image) = shown
	do IO<Unit>:
		Native.focus(ref)
		Native.button(ref, False{})
		Native.button(ref, True{})
		UI.Check.frames(2n, window, model, w => m => Flight.look_motion(output, ref, camera, w, m, finish))

def Flight.look(+output: String, ref: WindowRef, window: Window, snapshot: App.Model & R.Camera, finish: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	IO.bind(Window & Image, Unit, Flight.capture(output, "before-look", window), shown => Flight.look_ready(output, ref, snapshot, shown, finish))

def Flight.idle(expected: R.Camera, before: Image, snapshot: App.Model & R.Camera, shown: Window & Image, next_stage: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	(next, camera) = snapshot
	(window, image) = shown
	do IO<Unit>:
		UI.Check.require(R.Camera.equal(expected, camera) && U32.is_eq(UI.Pixels.delta(9n, before, image), 0), "Released native flight key kept moving")
		next_stage(window, next)

def Flight.release_image(+output: String, +expected: R.Camera, model: App.Model, shown: Window & Image, next_stage: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	(window, before) = shown
	UI.Check.frames(2n, window, model, w => m => IO.bind(Window & Image, Unit, Flight.capture(output, "idle", w), shown => Flight.idle(expected, before, Flight.snapshot(m), shown, next_stage)))

def Flight.released(+output: String, +expected: R.Camera, window: Window, snapshot: App.Model & R.Camera, next_stage: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	(model, camera) = snapshot
	do IO<Unit>:
		UI.Check.require(R.Camera.equal(expected, camera), "Native keyup did not stop movement")
		IO.bind(Window & Image, Unit, Flight.capture(output, "released", window), shown => Flight.release_image(output, expected, model, shown, next_stage))

def Flight.held(+code: U32, +output: String, ref: WindowRef, previous: R.Camera, window: Window, snapshot: App.Model & R.Camera, next_stage: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	(model, +camera) = snapshot
	do IO<Unit>:
		UI.Check.require(Flight.moved(previous, camera, code), "Native held key did not fly in its expected direction " ++ U32.show(code))
		Native.key(ref, False{}, code)
		UI.Check.frames(3n, window, model, w => m => Flight.released(output, camera, w, Flight.snapshot(m), next_stage))

def Flight.key(+code: U32, +output: String, +ref: WindowRef, window: Window, snapshot: App.Model & R.Camera, next_stage: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	(model, camera) = snapshot
	+directory = output ++ "/key-" ++ U32.show(code)
	do IO<Unit>:
		UI.Check.mkdir(directory)
		Native.key(ref, True{}, code)
		UI.Check.frames(4n, window, model, w => m => Flight.held(code, directory, ref, camera, w, Flight.snapshot(m), next_stage))

def Flight.keys(keys: List<&2, U32>, +output: String, +ref: WindowRef, window: Window, model: App.Model, finish: Window -> App.Model -> IO(Unit)) -> IO(Unit):
	match keys:
		case Nil{}:
			Flight.look(output, ref, window, Flight.snapshot(model), finish)
		case Con{code, rest}:
			Flight.key(code, output, ref, window, Flight.snapshot(model), w => m => Flight.keys(rest, output, ref, w, m, finish))

def Flight.ready(output: String, completed: Chan(Bool), model: App.Model, exported: Window & WindowRef) -> IO(Unit):
	(window, +ref) = exported
	do IO<Unit>:
		Native.send(ref, ["mouseup", "3"])
		Native.focus(ref)
		Flight.keys([119, 115, 97, 100, 113, 101], output, ref, window, model, w => m => Flight.close(ref, completed, w, m))

def Flight.start(+output: String) -> IO(Unit):
	do IO<Unit>:
		UI.Check.mkdir(output)
		+completed : Chan(Bool) <- Chan.new(Bool, 1)
		window : Window <- IO.try(Window, Window.open("Bend Voxel Rewrite | native flight input check", 512, 512))
		UI.Check.frames(2n, window, App.Model.cube(5n, 5n), w => m => IO.bind(Window & WindowRef, Unit, UI.Reference.export(w), exported => Flight.ready(output, completed, m, exported)))
		Chan.close(Bool, completed)
		finished : Maybe<Bool> <- Chan.recv(Bool, completed)
		UI.Check.require(Maybe.default(&1, Bool, finished, False{}), "Native flight check did not complete")

def main() -> IO(Unit):
	do IO<Unit>:
		args : List<String> <- IO.args()
		Flight.start(Maybe.default(&2, String, App.Options.flag(App.Options.args(args), "--output", False{}), ".audit/screenshots/flight-ui"))
