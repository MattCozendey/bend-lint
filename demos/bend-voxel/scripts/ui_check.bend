import Base
import ../main.bend as Slice
import ../dump.bend as D
import ../deps/bend-ui-test/uitest.bend as UITest
import ./ui_capture.bend as C

type Stage is Data:
	First{}
	Destroyed{}
	Repeated{}
	Reset{}
	Background{}
	Hovered{}
	Clicked{}
	ClickReset{}

type Session is Data:
	Session{output: String, ref: WindowRef, before: Image, cut: Image, close_window: Bool, completed: Chan(Bool)}

type Progress is Type:
	Progress{window: Window, model: Slice.Model, session: Session, stage: Stage, wait: Nat}

def Check.require(ok: Bool, message: String) -> IO(Unit):
	match ok:
		case True{}:
			IO.pure(Unit, Unit{})
		case False{}:
			IO.die(Unit, 1, message)

def Pixels.delta(+depth: Nat, a: Image, b: Image) -> U32:
	match depth a b:
		case 0n Pix{ac} Pix{bc}:
			Bool.to_u32(U32.is_ne((ac % 16777216 : U32), (bc % 16777216 : U32)))
		case 0n _ _:
			4294967295
		case 1n+rest Pix{+ac} Pix{+bc}:
			(4 * Pixels.delta(rest, Pix{ac}, Pix{bc}) : U32)
		case 1n+rest Pix{+ac} Qua{bl, br, bb, bc}:
			(Pixels.delta(rest, Pix{ac}, bl) + Pixels.delta(rest, Pix{ac}, br) + Pixels.delta(rest, Pix{ac}, bb) + Pixels.delta(rest, Pix{ac}, bc) : U32)
		case 1n+rest Qua{al, ar, ab, ac} Pix{+bc}:
			(Pixels.delta(rest, al, Pix{bc}) + Pixels.delta(rest, ar, Pix{bc}) + Pixels.delta(rest, ab, Pix{bc}) + Pixels.delta(rest, ac, Pix{bc}) : U32)
		case 1n+rest Qua{al, ar, ab, ac} Qua{bl, br, bb, bc}:
			(Pixels.delta(rest, al, bl) + Pixels.delta(rest, ar, br) + Pixels.delta(rest, ab, bb) + Pixels.delta(rest, ac, bc) : U32)

def Pixels.at(fuel: Nat, +x: U32, +y: U32, +size: U32, image: Image) -> U32:
	match fuel image:
		case 0n Pix{color}:
			(color % 16777216 : U32)
		case 0n _:
			4294967295
		case 1n+rest Pix{color}:
			(color % 16777216 : U32)
		case 1n+rest Qua{tl, tr, bl, br}:
			+half = (size / 2 : U32)
			Pixels.at(rest, (x % half : U32), (y % half : U32), half, Bool.pick(Image, (y < half : U32), Bool.pick(Image, (x < half : U32), tl, tr), Bool.pick(Image, (x < half : U32), bl, br)))

def Reference.same(a: WindowRef, b: WindowRef) -> Bool:
	X11WindowRef{ad, ai} = a
	X11WindowRef{bd, bi} = b
	String.eq(ad, bd) && U32.is_eq(ai, bi)

def Reference.unwrapped(exported: Window & Result<&1, &1, U32 & String, WindowRef>) -> IO(Window & WindowRef):
	(window, result) = exported
	do IO<Window & WindowRef>:
		ref : WindowRef <- IO.try(WindowRef, IO.pure(Result<&1, &1, U32 & String, WindowRef>, result))
		return (window, ref)

def Reference.export(window: Window) -> IO(Window & WindowRef):
	IO.bind(Window & Result<&1, &1, U32 & String, WindowRef>, Window & WindowRef, Window.export_ref(window), Reference.unwrapped)

def Reference.close(ref: WindowRef, button: Bool) -> IO(Unit):
	match button:
		case False{}:
			IO.try(Unit, UITest.key(ref, 27))
		case True{}:
			IO.try(Unit, UITest.request_close(ref))

def Reference.report(ref: WindowRef) -> IO(Unit):
	X11WindowRef{display, id} = ref
	IO.print("DISPLAY=" ++ display ++ " XID=" ++ U32.show(id))

def Check.frames(fuel: Nat, window: Window, model: Slice.Model, next: Window -> Slice.Model -> IO(Unit)) -> IO(Unit):
	match fuel:
		case 0n:
			next(window, model)
		case 1n+rest:
			Slice.Interactive.step(window, model, w => m => Check.frames(rest, w, m, next))

def Check.unclosed(window: Window, model: Slice.Model) -> IO(Unit):
	do IO<Unit>:
		Window.close(window)
		IO.die(Unit, 1, "Native close did not stop the real app reducer")

def Check.finish(+ref: WindowRef, close_window: Bool, completed: Chan(Bool), window: Window, model: Slice.Model) -> IO(Unit):
	do IO<Unit>:
		Reference.close(ref, close_window)
		Slice.Interactive.step(window, model, Check.unclosed)
		alive : Bool <- IO.try(Bool, UITest.alive(ref))
		Check.require(Bool.not(alive), "Exported window is still alive after app close")
		sent : Bool <- Chan.send(Bool, completed, True{})
		Check.require(sent, "Native check completion channel closed early")
		IO.print("PASS exported-window identity, native pixels, Space, repeated cut, primary click, background no-op, exact resets, and native close")

def Check.image(stage: Stage, session: Session, window: Window, model: Slice.Model, +image: Image) -> IO(Maybe<Progress>):
	match stage session:
		case First{} Session{+output, +ref, +before, +cut, +close_window, completed}:
			do IO<Maybe<Progress>>:
				D.Dump.ppm(output ++ "/before.ppm", image)
				Check.require(U32.is_eq(Pixels.at(9n, 0, 0, 512, image), 1054752) && U32.is_eq(Pixels.at(9n, 256, 256, 512, image), 3774336) && U32.is_eq(Pixels.at(9n, 256, 300, 512, image), 3774336), "Initial native pixels differ: " ++ U32.show(Pixels.at(9n, 0, 0, 512, image)) ++ "," ++ U32.show(Pixels.at(9n, 256, 256, 512, image)) ++ "," ++ U32.show(Pixels.at(9n, 256, 300, 512, image)))
				IO.try(Unit, UITest.key(ref, 32))
				return Some{Progress{window, model, Session{output, ref, image, cut, close_window, completed}, Destroyed{}, 1n}}
		case Destroyed{} Session{+output, +ref, +before, +cut, +close_window, completed}:
			do IO<Maybe<Progress>>:
				Check.require(U32.is_eq(Pixels.delta(9n, before, image), 9826), "Space must change exactly 9826 native pixels")
				D.Dump.ppm(output ++ "/destroyed.ppm", image)
				IO.try(Unit, UITest.key(ref, 32))
				return Some{Progress{window, model, Session{output, ref, before, image, close_window, completed}, Repeated{}, 1n}}
		case Repeated{} Session{+output, +ref, +before, +cut, +close_window, completed}:
			do IO<Maybe<Progress>>:
				Check.require(U32.is_eq(Pixels.delta(9n, cut, image), 0), "Repeated native cut changed pixels")
				D.Dump.ppm(output ++ "/repeated.ppm", image)
				IO.try(Unit, UITest.key(ref, 114))
				return Some{Progress{window, model, Session{output, ref, before, cut, close_window, completed}, Reset{}, 1n}}
		case Reset{} Session{+output, +ref, +before, +cut, +close_window, completed}:
			do IO<Maybe<Progress>>:
				Check.require(U32.is_eq(Pixels.delta(9n, before, image), 0), "Reset did not restore exact native pixels")
				D.Dump.ppm(output ++ "/reset.ppm", image)
				IO.try(Unit, UITest.click(ref, 20, 20))
				return Some{Progress{window, model, Session{output, ref, before, cut, close_window, completed}, Background{}, 1n}}
		case Background{} Session{+output, +ref, +before, +cut, +close_window, completed}:
			do IO<Maybe<Progress>>:
				Check.require(U32.is_eq(Pixels.delta(9n, before, image), 0), "Background click changed native pixels")
				D.Dump.ppm(output ++ "/background-click.ppm", image)
				return Some{Progress{window, Slice.Model.point(model, 256, 200), Session{output, ref, before, cut, close_window, completed}, Hovered{}, 1n}}
		case Hovered{} Session{+output, +ref, +before, +cut, +close_window, completed}:
			do IO<Maybe<Progress>>:
				Check.require(U32.is_eq(Pixels.at(9n, 256, 200, 512, image), 16776960), "Hovered selected cell is not yellow")
				D.Dump.ppm(output ++ "/hovered.ppm", image)
				IO.try(Unit, UITest.click(ref, 256, 200))
				return Some{Progress{window, model, Session{output, ref, image, cut, close_window, completed}, Clicked{}, 1n}}
		case Clicked{} Session{+output, +ref, +before, +cut, +close_window, completed}:
			do IO<Maybe<Progress>>:
				Check.require((Pixels.delta(9n, before, image) > 100 : U32) && (Pixels.delta(9n, cut, image) > 0 : U32), "Primary click did not carve the picked voxel")
				D.Dump.ppm(output ++ "/clicked.ppm", image)
				IO.try(Unit, UITest.key(ref, 114))
				return Some{Progress{window, model, Session{output, ref, before, cut, close_window, completed}, ClickReset{}, 1n}}
		case ClickReset{} Session{+output, +ref, +before, +cut, +close_window, completed}:
			do IO<Maybe<Progress>>:
				Check.require(U32.is_eq(Pixels.delta(9n, before, image), 0), "Second reset did not restore exact native pixels")
				D.Dump.ppm(output ++ "/click-reset.ppm", image)
				Check.finish(ref, close_window, completed, window, model)
				return None{}

def Check.converted(stage: Stage, session: Session, window: Window, model: Slice.Model, converted: Result<&2, &2, String, Image>) -> IO(Maybe<Progress>):
	match converted:
		case Fail{message}:
			do IO<Maybe<Progress>>:
				Window.close(window)
				IO.die(Maybe<Progress>, 1, message)
		case Done{image}:
			Check.image(stage, session, window, model, image)

def Check.captured(stage: Stage, session: Session, model: Slice.Model, captured: Window & Result<&1, &1, U32 & String, Capture>) -> IO(Maybe<Progress>):
	match captured:
		case (window, Fail{(code, message)}):
			do IO<Maybe<Progress>>:
				Window.close(window)
				IO.die(Maybe<Progress>, code, message)
		case (window, Done{capture}):
			Check.converted(stage, session, window, model, C.Capture.image(capture))

def Check.verified(stage: Stage, +session: Session, model: Slice.Model, exported: Window & WindowRef) -> IO(Maybe<Progress>):
	Session{output, expected, before, cut, close_window, completed} = session
	(window, +ref) = exported
	do IO<Maybe<Progress>>:
		Check.require(Reference.same(ref, expected), "Owned window reference changed")
		captured : Window & Result<&1, &1, U32 & String, Capture> <- Window.capture(window)
		Check.captured(stage, session, model, captured)

def Check.run(stage: Stage, session: Session, window: Window, model: Slice.Model) -> IO(Maybe<Progress>):
	IO.bind(Window & WindowRef, Maybe<Progress>, Reference.export(window), exported => Check.verified(stage, session, model, exported))

def Check.wait(wait: Nat, stage: Stage, session: Session, window: Window, model: Slice.Model) -> IO(Maybe<Progress>):
	match wait:
		case 0n:
			Check.run(stage, session, window, model)
		case 1n+rest:
			IO.pure(Maybe<Progress>, Some{Progress{window, model, session, stage, rest}})

def Check.advance(next: Progress -> IO(Unit), result: Maybe<Progress>) -> IO(Unit):
	match result:
		case None{}:
			IO.pure(Unit, Unit{})
		case Some{progress}:
			next(progress)

def Check.loop(fuel: Nat, progress: Progress) -> IO(Unit):
	match fuel:
		case 0n:
			Progress{window, model, session, stage, wait} = progress
			do IO<Unit>:
				Window.close(window)
				IO.die(Unit, 1, "Native UI check exhausted its frame budget")
		case 1n+rest:
			Progress{window, model, session, stage, wait} = progress
			Slice.Interactive.step(window, model,
				w => m => IO.bind(Maybe<Progress>, Unit, Check.wait(wait, stage, session, w, m), result => Check.advance(p => Check.loop(rest, p), result)))

def Check.ready(output: String, close_window: Bool, completed: Chan(Bool), model: Slice.Model, exported: Window & WindowRef) -> IO(Unit):
	(window, +ref) = exported
	do IO<Unit>:
		Reference.report(ref)
		renamed : Window <- Window.set_title(window, "Bend Voxel Rewrite | testing exported window")
		IO.try(Unit, UITest.click(ref, 20, 20))
		Check.loop(32n, Progress{renamed, model, Session{output, ref, Pix{0}, Pix{0}, close_window, completed}, First{}, 1n})

def Check.begin(output: String, close_window: Bool, completed: Chan(Bool), window: Window, model: Slice.Model) -> IO(Unit):
	IO.bind(Window & WindowRef, Unit, Reference.export(window), exported => Check.ready(output, close_window, completed, model, exported))

def Check.mkdir_result(result: U32 & (String & String)) -> IO(Unit):
	(status, streams) = result
	Check.require(U32.is_eq(status, 0), "Cannot create native screenshot directory")

def Check.mkdir(output: String) -> IO(Unit):
	IO.bind(U32 & (String & String), Unit, IO.try(U32 & (String & String), Process.run("mkdir", ["-p", output], "", 4096, 3000)), Check.mkdir_result)

def Check.options(+args: List<&2, String>, options: Slice.Options) -> IO(Unit):
	Slice.Options{mode, cut, tile_depth, fork_depth} = options
	+output = Maybe.default(&2, String, Slice.Options.flag(args, "--output", False{}), ".audit/screenshots/ui")
	+method = Maybe.default(&2, String, Slice.Options.flag(args, "--close-method", False{}), "escape")
	do IO<Unit>:
		Check.require(String.eq(method, "escape") || String.eq(method, "window"), "--close-method must be escape or window")
		Check.mkdir(output)
		+completed : Chan(Bool) <- Chan.new(Bool, 1)
		window : Window <- IO.try(Window, Window.open("Bend Voxel Rewrite | Space destroy | click carve | R reset | Esc exit", 512, 512))
		Check.frames(2n, window, Slice.Model.cube(tile_depth, fork_depth), w => m => Check.begin(output, String.eq(method, "window"), completed, w, m))
		Chan.close(Bool, completed)
		finished : Maybe<Bool> <- Chan.recv(Bool, completed)
		Check.require(Maybe.default(&1, Bool, finished, False{}), "Native check did not complete")

def Check.start(+args: List<&2, String>) -> IO(Unit):
	Check.options(args, Slice.Options.parse(args))

def main() -> IO(Unit):
	do IO<Unit>:
		args : List<String> <- IO.args()
		Check.start(Slice.Options.args(args))
