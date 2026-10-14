import Base
import ./sha256.bend as SHA

def Host.require(ok: Bool, message: String) -> IO(Unit):
	match ok:
		case True{}:
			IO.pure(Unit, Unit{})
		case False{}:
			IO.die(Unit, 1, message)

def Host.result(-A: Data, result: Result<&2, &2, String, A>, context: String) -> IO(A):
	match result:
		case Done{value}:
			IO.pure(A, value)
		case Fail{message}:
			IO.die(A, 1, context ++ ": " ++ message)

def Host.process_result(+label: String, result: Result<&1, &1, U32 & String, U32 & (String & String)>) -> IO(String):
	match result:
		case Fail{(code, message)}:
			IO.die(String, 1, label ++ ": " ++ message)
		case Done{(0, (stdout, stderr))}:
			IO.pure(String, stdout)
		case Done{(status, (stdout, stderr))}:
			IO.die(String, 1, label ++ " failed with exit " ++ U32.show(status) ++ "\n" ++ stderr ++ stdout)

def Host.process(label: String, program: String, args: List<String>) -> IO(String):
	IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, String,
		Process.run(program, args, "", 4294967295, 4294967295), Host.process_result(label))

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

def Path.join(root: String, +path: String) -> String:
	Bool.pick(String, String.starts_with(path, "/"), path, root ++ "/" ++ path)

def Host.line_reverse(text: String) -> String:
	match text:
		case SCon{'\n', rest}:
			String.reverse(rest)
		case rest:
			String.reverse(rest)

def Host.line(text: String) -> String:
	Host.line_reverse(String.reverse(text))

def Host.root_choice(empty: Bool, program: String, explicit: String) -> IO(String):
	match empty:
		case False{}:
			IO.bind(String, String,
				Host.process("Repository root", "sh", ["-c", "cd -P -- \"$1\" && pwd -P", "benchmark-root", explicit]),
				text => IO.pure(String, Host.line(text)))
		case True{}:
			IO.bind(String, String,
				Host.process("Repository root", "sh", ["-c", "case \"$1\" in */*) p=$1 ;; *) p=$(command -v -- \"$1\") || exit ;; esac; p=$(realpath -e -- \"$p\") || exit; dirname -- \"$(dirname -- \"$p\")\"", "benchmark-root", program]),
				text => IO.pure(String, Host.line(text)))

def Host.root(program: String, +explicit: String) -> IO(String):
	Host.root_choice(String.is_empty(explicit), program, explicit)

def Host.resolve(path: String) -> IO(String):
	IO.bind(String, String, Host.process("Renderer path", "realpath", ["-e", "--", path]), text => IO.pure(String, Host.line(text)))

def Host.renderer(root: String, binary: String, args: List<String>) -> IO(String):
	Host.process("Renderer", "sh", List.append(&1, String,
		["-c", "cd -P -- \"$1\" || exit; shift; exec \"$@\"", "benchmark-renderer", root, binary], args))

def Host.ascii_digits(text: String) -> Bool:
	match text:
		case SNil{}:
			True{}
		case SCon{Chr{+byte}, rest}:
			(byte >= 48 : U32) && (byte <= 57 : U32) && Host.ascii_digits(rest)

def Host.cores_value(ascii: Bool, value: Maybe<&2, U32>) -> U32:
	match ascii value:
		case True{} Some{+cores}:
			U32.max(1, cores)
		case _ _:
			1

def Host.cores_result(result: Result<&1, &1, U32 & String, U32 & (String & String)>) -> U32:
	match result:
		case Done{(0, (stdout, stderr))}:
			+text = Host.line(stdout)
			Host.cores_value(Host.ascii_digits(text), U32.read(text))
		case other:
			1

def Host.cores() -> IO(U32):
	IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, U32,
		Process.run("getconf", ["_NPROCESSORS_ONLN"], "", 4294967295, 4294967295),
		result => IO.pure(U32, Host.cores_result(result)))

def Host.date_matches(text: String, mask: String) -> Bool:
	match text mask:
		case SNil{} SNil{}:
			True{}
		case SCon{Chr{+byte}, rest} SCon{'#', tail}:
			(byte >= 48 : U32) && (byte <= 57 : U32) && Host.date_matches(rest, tail)
		case SCon{+char, rest} SCon{expected, tail}:
			Char.is_eq(char, expected) && Host.date_matches(rest, tail)
		case _ _:
			False{}

def Host.timestamp() -> IO(String):
	do IO<String>:
		text : String <- Host.process("UTC timestamp", "date", ["-u", "+%Y-%m-%dT%H:%M:%S.%6N+00:00"])
		+timestamp : String = Host.line(text)
		Host.require(Host.date_matches(timestamp, "####-##-##T##:##:##.######+00:00"), "date did not return UTC with six microsecond digits")
		return timestamp

def Host.mkdir(output: String) -> IO(Unit):
	do IO<Unit>:
		text : String <- Host.process("Report directory", "mkdir", ["-p", "--", Path.parent(output)])
		return Unit{}

def Hash.progress(+expected: U32, +offset: U32, +received: U32) -> Result<&2, &2, String, U32>:
	Bool.pick(Result<&2, &2, String, U32>,
		(offset <= expected : U32) && (received <= expected - offset : U32),
		Bool.pick(Result<&2, &2, String, U32>, U32.is_eq(received, 0) && U32.is_ne(offset, expected),
			Fail{"File ended before its reported size"}, Done{(offset + received : U32)}),
		Fail{"File size changed while hashing"})

def Hash.eof_result(result: Result<&1, &1, U32 & String, List<&2, U32>>, context: SHA.Context) -> Result<&2, &2, String, String>:
	match result:
		case Done{Nil{}}:
			SHA.SHA256.finish(context)
		case Done{_}:
			Fail{"File has an unread suffix or changed size"}
		case Fail{(code, message)}:
			Fail{"File EOF read failed: " ++ message}

def Hash.eof_read(read: File & Result<&1, &1, U32 & String, List<&2, U32>>, context: SHA.Context) -> IO(Result<&2, &2, String, String>):
	(file, result) = read
	do IO<Result<&2, &2, String, String>>:
		File.close(file)
		return Hash.eof_result(result, context)

def Hash.eof(file: File, context: SHA.Context) -> IO(Result<&2, &2, String, String>):
	IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, Result<&2, &2, String, String>, File.read_bytes(file, 1), read => Hash.eof_read(read, context))

def Hash.advance(progress: Result<&2, &2, String, U32>, file: File, context: SHA.Context, next: File -> SHA.Context -> U32 -> IO(Result<&2, &2, String, String>)) -> IO(Result<&2, &2, String, String>):
	match progress:
		case Fail{message}:
			do IO<Result<&2, &2, String, String>>:
				File.close(file)
				return Fail{message}
		case Done{offset}:
			next(file, context, offset)

def Hash.count(bytes: List<&2, U32>, count: U32) -> U32:
	match bytes:
		case Nil{}:
			count
		case byte <> rest:
			Hash.count(rest, (count + 1 : U32))

def Hash.read_result(read: File & Result<&1, &1, U32 & String, List<&2, U32>>, expected: U32, offset: U32, context: SHA.Context, next: File -> SHA.Context -> U32 -> IO(Result<&2, &2, String, String>)) -> IO(Result<&2, &2, String, String>):
	match read:
		case (file, Fail{(code, message)}):
			do IO<Result<&2, &2, String, String>>:
				File.close(file)
				return Fail{"File read failed: " ++ message}
		case (file, Done{+bytes}):
			Hash.advance(Hash.progress(expected, offset, Hash.count(bytes, 0)), file, SHA.SHA256.bytes(bytes, context), next)

def Hash.chunks(fuel: Nat, done: Bool, file: File, +expected: U32, +offset: U32, context: SHA.Context) -> IO(Result<&2, &2, String, String>):
	match fuel done:
		case _ True{}:
			Hash.eof(file, context)
		case 0n False{}:
			do IO<Result<&2, &2, String, String>>:
				File.close(file)
				return Fail{"File reader exhausted its progress bound"}
		case 1n+rest False{}:
			IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, Result<&2, &2, String, String>,
				File.read_bytes(file, U32.min(65536, (expected - offset : U32))),
				read => Hash.read_result(read, expected, offset, context,
					f => h => +position => Hash.chunks(rest, U32.is_eq(position, expected), f, expected, position, h)))

def Hash.sized(sized: File & Result<&1, &1, U32 & String, U32>) -> IO(Result<&2, &2, String, String>):
	match sized:
		case (file, Fail{(code, message)}):
			do IO<Result<&2, &2, String, String>>:
				File.close(file)
				return Fail{"File size failed: " ++ message}
		case (file, Done{+size}):
			Hash.chunks(1n+U32.to_nat(size), U32.is_eq(size, 0), file, size, 0, SHA.SHA256.init())

def Hash.opened(opened: Result<&1, &1, U32 & String, File>) -> IO(Result<&2, &2, String, String>):
	match opened:
		case Fail{(code, message)}:
			IO.pure(Result<&2, &2, String, String>, Fail{"File open failed: " ++ message})
		case Done{file}:
			IO.bind(File & Result<&1, &1, U32 & String, U32>, Result<&2, &2, String, String>, File.size(file), Hash.sized)

def Host.hash(+path: String) -> IO(String):
	do IO<String>:
		result : Result<&2, &2, String, String> <- IO.bind(Result<&1, &1, U32 & String, File>, Result<&2, &2, String, String>, File.open(path, "r"), Hash.opened)
		Host.result(String, result, "SHA-256 " ++ path)

def Host.write_checked(result: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
	match result:
		case Done{value}:
			IO.pure(Unit, Unit{})
		case Fail{(code, message)}:
			IO.die(Unit, 1, "Report write failed: " ++ message)

def Host.write_result(written: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
	(file, result) = written
	do IO<Unit>:
		File.close(file)
		Host.write_checked(result)

def Host.write(path: String, text: String) -> IO(Unit):
	do IO<Unit>:
		file : File <- IO.try(File, File.open(path, "w"))
		IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write(file, text), Host.write_result)
