import Base
import ./image_data.bend as Data

type Options is Data:
	Options{cpu_only: Bool, root: String, binary: String, help: Bool}

type Variant is Data:
	Variant{gpu: String, tile: String, fork: String}

type Arguments is Data:
	Flags{options: Options}
	RootPath{options: Options}
	BinaryPath{options: Options}
	Help{options: Options}
	Bad{message: String}

def Check.require(ok: Bool, message: String) -> IO(Unit):
	match ok:
		case True{}:
			IO.pure(Unit, Unit{})
		case False{}:
			IO.die(Unit, 1, message)

def Check.result(-A: Data, result: Result<&2, &2, String, A>, +context: String) -> IO(A):
	match result:
		case Done{value}:
			IO.pure(A, value)
		case Fail{message}:
			IO.die(A, 1, context ++ ": " ++ message)

def Path.parent_reverse(path: String) -> String:
	match path:
		case SNil{}:
			"."
		case SCon{'/', SNil{}}:
			"/"
		case SCon{'/', rest}:
			String.reverse(rest)
		case SCon{_, rest}:
			Path.parent_reverse(rest)

def Path.parent(path: String) -> String:
	Path.parent_reverse(String.reverse(path))

def Path.root(+program: String) -> String:
	Bool.pick(String, String.contains(program, "/"), Path.parent(program) ++ "/..", "")

def Path.join(+root: String, +path: String) -> String:
	Bool.pick(String, String.starts_with(path, "/"), path, root ++ "/" ++ path)

def Options.tag(+flag: String) -> U32:
	(Bool.to_u32(String.eq(flag, "--cpu-only")) +
	 2 * Bool.to_u32(String.eq(flag, "--root")) +
	 3 * Bool.to_u32(String.eq(flag, "--binary")) +
	 4 * Bool.to_u32(String.eq(flag, "--help") || String.eq(flag, "-h")) : U32)

def Options.step(tag: U32, arg: String, state: Arguments) -> Arguments:
	match tag state:
		case _ Bad{message}:
			Bad{message}
		case _ Help{options}:
			Help{options}
		case _ RootPath{Options{cpu_only, root, binary, help}}:
			Flags{Options{cpu_only, arg, binary, help}}
		case _ BinaryPath{Options{cpu_only, root, binary, help}}:
			Flags{Options{cpu_only, root, arg, help}}
		case 1 Flags{Options{cpu_only, root, binary, help}}:
			Flags{Options{True{}, root, binary, help}}
		case 2 Flags{options}:
			RootPath{options}
		case 3 Flags{options}:
			BinaryPath{options}
		case 4 Flags{Options{cpu_only, root, binary, help}}:
			Help{Options{cpu_only, root, binary, True{}}}
		case _ Flags{_}:
			Bad{"Unknown image checker option"}

def Options.finish(state: Arguments) -> Result<&2, &2, String, Options>:
	match state:
		case Flags{options}:
			Done{options}
		case Help{options}:
			Done{options}
		case RootPath{_}:
			Fail{"--root requires a path"}
		case BinaryPath{_}:
			Fail{"--binary requires a path"}
		case Bad{message}:
			Fail{message}

def Options.parse(args: List<String>, state: Arguments) -> Result<&2, &2, String, Options>:
	match args:
		case Nil{}:
			Options.finish(state)
		case +arg <> rest:
			Options.parse(rest, Options.step(Options.tag(arg), arg, state))

def Run.stderr(empty: Bool, stderr: String) -> IO(Unit):
	match empty:
		case True{}:
			IO.pure(Unit, Unit{})
		case False{}:
			IO.print_err(stderr)

def Run.stderr_text(+stderr: String) -> IO(Unit):
	Run.stderr(String.is_empty(stderr), stderr)

def Run.process_done(label: String, value: U32 & (String & String)) -> IO(Unit):
	(+status, output) = value
	(stdout, stderr) = output
	do IO<Unit>:
		IO.write(stdout)
		Run.stderr_text(stderr)
		Check.require(U32.is_eq(status, 0), label ++ " failed with exit " ++ U32.show(status))

def Run.process(+label: String, result: Result<&1, &1, U32 & String, U32 & (String & String)>) -> IO(Unit):
	match result:
		case Fail{(code, message)}:
			IO.die(Unit, 1, label ++ ": " ++ message)
		case Done{value}:
			Run.process_done(label, value)

def Run.mkdir(path: String) -> IO(Unit):
	IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, Unit,
		Process.run("mkdir", ["-p", path], "", 16777216, 30000), Run.process("Image output directory setup"))

def Variant.list(cpu_only: Bool) -> List<&2, Variant>:
	+off = {[Variant{"off", "4", "0"}, Variant{"off", "4", "4"}, Variant{"off", "5", "5"}, Variant{"off", "6", "6"}] : List<&2, Variant>}
	Bool.pick(List<&2, Variant>, cpu_only, off, List.append(&2, Variant, off,
		[Variant{"on", "4", "0"}, Variant{"on", "4", "4"}, Variant{"on", "5", "5"}, Variant{"on", "6", "6"}]))

def Scene.name(cut: Bool) -> String:
	Bool.pick(String, cut, "cut", "full")

def Scene.boolean(cut: Bool) -> String:
	Bool.pick(String, cut, "True", "False")

def Scene.expected_hash(cut: Bool) -> String:
	Bool.pick(String, cut,
		"fad7c6dca2cad4341c84767ff7b9e6895e8d50241e78a09c7af928d7804f9a33",
		"02befa6e6575a5b6d3ea774e7df29e0a1f96d8c8d9fe2fb5149502b6694878db")

def Variant.label(cut: Bool, variant: Variant) -> String:
	Variant{gpu, tile, fork} = variant
	"cut=" ++ Scene.boolean(cut) ++ " GPU=" ++ gpu ++ " tile=" ++ tile ++ " fork=" ++ fork

def Variant.template(root: String, cut: Bool, variant: Variant) -> String:
	Variant{gpu, tile, fork} = variant
	Path.join(root, "build/image-check/" ++ Scene.name(cut) ++ "-" ++ gpu ++ "-" ++ tile ++ "-" ++ fork ++ ".XXXXXX")

def Run.directory_reverse(output: String) -> IO(String):
	match output:
		case SCon{'\n', rest}:
			+path = String.reverse(rest)
			do IO<String>:
				Check.require(Bool.not(String.is_empty(path)) && Bool.not(String.contains(path, "\n")), "Image output reservation returned an invalid path")
				return path
		case _:
			IO.die(String, 1, "Image output reservation did not return a newline-terminated path")

def Run.directory_done(value: U32 & (String & String)) -> IO(String):
	(+status, output) = value
	(stdout, stderr) = output
	do IO<String>:
		Run.stderr_text(stderr)
		Check.require(U32.is_eq(status, 0), "Image output reservation failed with exit " ++ U32.show(status))
		Run.directory_reverse(String.reverse(stdout))

def Run.directory_result(result: Result<&1, &1, U32 & String, U32 & (String & String)>) -> IO(String):
	match result:
		case Done{value}:
			Run.directory_done(value)
		case Fail{(code, message)}:
			IO.die(String, 1, "Image output reservation failed: " ++ message)

def Run.fresh_path(root: String, cut: Bool, variant: Variant) -> IO(String):
	do IO<String>:
		result : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("mktemp", ["-d", Variant.template(root, cut, variant)], "", 16777216, 30000)
		directory : String <- Run.directory_result(result)
		return directory ++ "/render.ppm"

def Variant.args_cut(cut: Bool, args: List<String>) -> List<String>:
	match cut:
		case True{}:
			List.append(&1, String, args, ["--cut"])
		case False{}:
			args

def Variant.args(cut: Bool, variant: Variant, path: String) -> List<String>:
	Variant{gpu, tile, fork} = variant
	Variant.args_cut(cut, ["--cube", "--gpu", gpu, "--threads", "1", "--tile-depth", tile, "--fork-depth", fork, "--dump", path])

def Check.golden(+cut: Bool, image: Data.Raster, +label: String) -> IO(Unit):
	do IO<Unit>:
		+hash : String <- Check.result(String, Data.Image.hash(image), label ++ " RGB SHA-256")
		Check.require(String.eq(hash, Scene.expected_hash(cut)), "Golden RGB SHA-256 mismatch for " ++ Scene.name(cut) ++ ". " ++ label ++ " expected " ++ Scene.expected_hash(cut) ++ ", found " ++ hash)
		IO.print(label ++ ": golden RGB sha256=" ++ hash)

def Run.agreement(baseline: Maybe<&2, Data.Raster>, path: String, +label: String, candidate: Data.Raster) -> IO(Data.Raster):
	match baseline:
		case None{}:
			IO.pure(Data.Raster, candidate)
		case Some{+image}:
			do IO<Data.Raster>:
				compared : Result<&2, &2, String, Unit> <- Data.Image.compare(path, image)
				Check.result(Unit, compared, label)
				IO.print(label ++ ": exact image equal to CPU reference")
				return image

def Run.output(baseline: Maybe<&2, Data.Raster>, cut: Bool, +path: String, +label: String) -> IO(Data.Raster):
	do IO<Data.Raster>:
		parsed : Result<&2, &2, String, Data.Raster> <- Data.Image.read(path)
		+image : Data.Raster <- Check.result(Data.Raster, parsed, label)
		Check.golden(cut, image, label)
		Run.agreement(baseline, path, label, image)

def Run.variant(options: Options, +cut: Bool, +variant: Variant, baseline: Maybe<&2, Data.Raster>) -> IO(Data.Raster):
	Options{cpu_only, +root, binary, help} = options
	+label = Variant.label(cut, variant)
	do IO<Data.Raster>:
		+path : String <- Run.fresh_path(root, cut, variant)
		result : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(Path.join(root, binary), Variant.args(cut, variant, path), "", 16777216, 180000)
		Run.process(label, result)
		Run.output(baseline, cut, path, label)

def Run.variants(variants: List<&2, Variant>, +options: Options, +cut: Bool, baseline: Maybe<&2, Data.Raster>) -> IO(Data.Raster):
	match variants baseline:
		case Nil{} Some{image}:
			IO.pure(Data.Raster, image)
		case Nil{} None{}:
			IO.die(Data.Raster, 1, "No renderer variants were checked")
		case variant <> rest _:
			IO.bind(Data.Raster, Data.Raster, Run.variant(options, cut, variant, baseline), image => Run.variants(rest, options, cut, Some{image}))

def Check.pixel(found: Maybe<&2, U32>, expected: U32, label: String) -> IO(Unit):
	match found:
		case None{}:
			IO.die(Unit, 1, "Missing full-scene pixel " ++ label)
		case Some{actual}:
			Check.require(U32.is_eq(actual, expected), "Full-scene sample differs at " ++ label)

def Run.images(+options: Options) -> IO(Unit):
	Options{cpu_only, root, binary, help} = options
	+variants = Variant.list(cpu_only)
	do IO<Unit>:
		Run.mkdir(Path.join(root, "build/image-check"))
		+full : Data.Raster <- Run.variants(variants, options, False{}, None{})
		+cut : Data.Raster <- Run.variants(variants, options, True{}, None{})
		Check.pixel(Data.Image.pixel(full, 0, 0), (16 * 65536 + 24 * 256 + 32 : U32), "(0,0)")
		Check.pixel(Data.Image.pixel(full, 256, 256), (57 * 65536 + 151 * 256 + 128 : U32), "(256,256)")
		Check.pixel(Data.Image.pixel(full, 256, 300), (57 * 65536 + 151 * 256 + 128 : U32), "(256,300)")
		+changed : U32 <- Check.result(U32, Data.Image.changed(full, cut), "Destruction comparison")
		Check.require(U32.is_eq(changed, 9826), "Destruction changed " ++ U32.show(changed) ++ " pixels; expected 9826")
		full_hash : String <- Check.result(String, Data.Image.hash(full), "Full RGB SHA-256")
		IO.print("full RGB sha256=" ++ full_hash)
		cut_hash : String <- Check.result(String, Data.Image.hash(cut), "Cut RGB SHA-256")
		IO.print("cut RGB sha256=" ++ cut_hash)
		IO.print("Image checks passed. Destruction changed " ++ U32.show(changed) ++ " pixels.")

def Run.options_checked(help: Bool, options: Options, +root: String, +binary: String) -> IO(Unit):
	match help:
		case True{}:
			IO.print("Usage: image-checker [--cpu-only] [--root repository] [--binary renderer]\nCheck fresh complete 512x512 P3 exports against scene goldens and exact CPU/GPU agreement.")
		case False{}:
			do IO<Unit>:
				Check.require(Bool.not(String.is_empty(root)), "Use an executable path containing '/' or provide --root repository")
				Check.require(Bool.not(String.is_empty(binary)), "--binary requires a nonempty renderer path")
				Run.images(options)

def Run.options(+options: Options) -> IO(Unit):
	Options{cpu_only, root, binary, help} = options
	Run.options_checked(help, options, root, binary)

def Run.start(args: List<String>) -> IO(Unit):
	match args:
		case program <> rest:
			do IO<Unit>:
				options : Options <- Check.result(Options, Options.parse(rest, Flags{Options{False{}, Path.root(program), "build/bend-voxel-rewrite", False{}}}), "Arguments")
				Run.options(options)
		case Nil{}:
			IO.die(Unit, 1, "Missing executable path")

def main() -> IO(Unit):
	IO.bind(List<String>, Unit, IO.args(), Run.start)
