import Base
import ./benchmark_host.bend as Host
import ./benchmark_number.bend as Num

type Options is Data:
	Options{frames: U32, repeats: U32, threads: List<&2, U32>, root: String, binary: String, output: String, help: Bool}

type Arguments is Data:
	Flags{options: Options}
	Value{tag: U32, options: Options}
	Threads{options: Options, reversed: List<&2, U32>}
	Help{options: Options}
	Bad{message: String}

type Config is Data:
	Config{gpu: String, threads: U32, tile: U32, fork: U32}

type Row is Data:
	Row{config: Config, reversed: List<&2, Num.Binary64>}

type Identity is Data:
	Identity{timestamp: String, binary: String, main: String, voxel: String, render: String, material: String, lighting: String, dump: String}

type Metric is Data:
	Seeking{}
	Prefix{suffix: String}
	FrameDigits{reversed: String}
	Separator{frames: String, suffix: String}
	ElapsedDigits{frames: String, reversed: String}
	Complete{frames: String, elapsed: String}

type MetricText is Data:
	MetricText{frames: String, elapsed: String}

def Decimal.digit(+byte: U32) -> Bool:
	(byte >= 48 : U32) && (byte <= 57 : U32)

def Decimal.char(char: Char) -> Bool:
	Chr{byte} = char
	Decimal.digit(byte)

def Decimal.fold(text: String, +value: U32, valid: Bool) -> Result<&2, &2, String, U32>:
	match text valid:
		case _ False{}:
			Fail{"Expected an ASCII decimal integer in 0..4294967295"}
		case SNil{} True{}:
			Done{value}
		case SCon{Chr{+byte}, rest} True{}:
			+digit = (byte - 48 : U32)
			Decimal.fold(rest, (value * 10 + digit : U32), Decimal.digit(byte) &&
				((value < 429496729 : U32) || (U32.is_eq(value, 429496729) && (digit <= 5 : U32))))

def Decimal.read(text: String) -> Result<&2, &2, String, U32>:
	match text:
		case SNil{}:
			Fail{"Expected a nonempty ASCII decimal integer"}
		case SCon{_, _}:
			Decimal.fold(text, 0, True{})

def Options.default_threads(+half: U32, +cores: U32) -> List<&2, U32>:
	Bool.pick(List<&2, U32>, U32.is_eq(cores, 1), [1],
		Bool.pick(List<&2, U32>, U32.is_eq(half, 1) || U32.is_eq(half, cores), [1, cores], [1, half, cores]))

def Options.defaults(+cores: U32) -> Options:
	+half = U32.max(1, (cores / 2 : U32))
	+last = U32.max(1, cores)
	Options{24, 3, Options.default_threads(half, last), "", "build/bend-voxel-rewrite", "", False{}}

def Option.split(text: String, reversed: String) -> String & Maybe<&2, String>:
	match text:
		case SNil{}:
			(String.reverse(reversed), None{})
		case SCon{'=', rest}:
			(String.reverse(reversed), Some{rest})
		case SCon{char, rest}:
			Option.split(rest, SCon{char, reversed})

def Option.tag(+flag: String) -> U32:
	(Bool.to_u32(String.eq(flag, "--frames")) +
	 2 * Bool.to_u32(String.eq(flag, "--repeats")) +
	 3 * Bool.to_u32(String.eq(flag, "--output")) +
	 4 * Bool.to_u32(String.eq(flag, "--cpu-threads")) +
	 5 * Bool.to_u32(String.eq(flag, "--root")) +
	 6 * Bool.to_u32(String.eq(flag, "--binary")) +
	 7 * Bool.to_u32(String.eq(flag, "--help") || String.eq(flag, "-h")) : U32)

def Options.with_threads(options: Options, threads: List<&2, U32>) -> Options:
	Options{frames, repeats, old, root, binary, output, help} = options
	Options{frames, repeats, threads, root, binary, output, help}

def Options.number(tag: U32, result: Result<&2, &2, String, U32>, options: Options) -> Arguments:
	match result:
		case Fail{message}:
			Bad{message}
		case Done{+value}:
			Options{frames, repeats, +threads, +root, +binary, +output, +help} = options
			Bool.pick(Arguments, U32.is_eq(tag, 1),
				Flags{Options{value, repeats, threads, root, binary, output, help}},
				Flags{Options{frames, value, threads, root, binary, output, help}})

def Options.thread_number(result: Result<&2, &2, String, U32>, options: Options, reversed: List<&2, U32>) -> Arguments:
	match result:
		case Fail{message}:
			Bad{message}
		case Done{value}:
			Threads{options, value <> reversed}

def Options.assign(tag: U32, +value: String, options: Options) -> Arguments:
	match tag:
		case 1:
			Options.number(1, Decimal.read(value), options)
		case 2:
			Options.number(2, Decimal.read(value), options)
		case 4:
			Options.thread_number(Decimal.read(value), options, Nil{})
		case +other:
			Options{+frames, +repeats, +threads, +root, +binary, +output, +help} = options
			Bool.pick(Arguments, String.is_empty(value), Bad{"Benchmark paths must be nonempty"},
				Bool.pick(Arguments, U32.is_eq(other, 3), Flags{Options{frames, repeats, threads, root, binary, value, help}},
					Bool.pick(Arguments, U32.is_eq(other, 5), Flags{Options{frames, repeats, threads, value, binary, output, help}},
						Flags{Options{frames, repeats, threads, root, value, output, help}})))

def Options.flag(tag: U32, value: Maybe<&2, String>, options: Options) -> Arguments:
	match tag value:
		case 0 _:
			Bad{"Unknown benchmark option"}
		case 7 None{}:
			Help{options}
		case 7 Some{_}:
			Bad{"--help does not accept a value"}
		case 4 None{}:
			Threads{options, Nil{}}
		case _ None{}:
			Value{tag, options}
		case _ Some{text}:
			Options.assign(tag, text, options)

def Options.flag_split(split: String & Maybe<&2, String>, options: Options) -> Arguments:
	(+flag, value) = split
	Options.flag(Option.tag(flag), value, options)

def Options.flags(arg: String, options: Options) -> Arguments:
	Options.flag_split(Option.split(arg, ""), options)

def Options.thread_step(option: Bool, arg: String, options: Options, reversed: List<&2, U32>) -> Arguments:
	match option reversed:
		case True{} Nil{}:
			Bad{"--cpu-threads requires at least one integer"}
		case True{} values:
			Options.flags(arg, Options.with_threads(options, List.reverse(&2, U32, values)))
		case False{} values:
			Options.thread_number(Decimal.read(arg), options, values)

def Options.value_step(option: Bool, tag: U32, arg: String, options: Options) -> Arguments:
	match option:
		case True{}:
			Bad{"Benchmark option requires a value"}
		case False{}:
			Options.assign(tag, arg, options)

def Options.step(+arg: String, state: Arguments) -> Arguments:
	match state:
		case Bad{message}:
			Bad{message}
		case Help{options}:
			Help{options}
		case Flags{options}:
			Options.flags(arg, options)
		case Value{tag, options}:
			Options.value_step(String.starts_with(arg, "--"), tag, arg, options)
		case Threads{options, reversed}:
			Options.thread_step(String.starts_with(arg, "-"), arg, options, reversed)

def Options.valid_tail(threads: List<&2, U32>, valid: Bool) -> Bool:
	match threads:
		case Nil{}:
			valid
		case head <> tail:
			Options.valid_tail(tail, valid && U32.is_gt(head, 0))

def Options.valid(threads: List<&2, U32>) -> Bool:
	Options.valid_tail(threads, True{})

def Options.checked(+options: Options) -> Result<&2, &2, String, Options>:
	Options{frames, repeats, +threads, root, binary, output, help} = options
	Bool.pick(Result<&2, &2, String, Options>,
		(frames >= 24 : U32) && (repeats >= 2 : U32) && Options.valid(threads) &&
		Bool.not(List.is_empty(&2, U32, threads)) && Bool.not(String.is_empty(binary)),
		Done{options}, Fail{"Require frames >= 24, repeats >= 2, positive CPU threads, and a nonempty binary path"})

def Options.finish(state: Arguments) -> Result<&2, &2, String, Options>:
	match state:
		case Flags{options}:
			Options.checked(options)
		case Threads{options, Nil{}}:
			Fail{"--cpu-threads requires at least one integer"}
		case Threads{options, values}:
			Options.checked(Options.with_threads(options, List.reverse(&2, U32, values)))
		case Value{tag, options}:
			Fail{"Benchmark option requires a value"}
		case Bad{message}:
			Fail{message}
		case Help{Options{frames, repeats, threads, root, binary, output, help}}:
			Done{Options{frames, repeats, threads, root, binary, output, True{}}}

def Options.parse_state(args: List<String>, state: Arguments) -> Result<&2, &2, String, Options>:
	match args:
		case Nil{}:
			Options.finish(state)
		case arg <> rest:
			Options.parse_state(rest, Options.step(arg, state))

def Options.parse(args: List<String>, defaults: Options) -> Result<&2, &2, String, Options>:
	Options.parse_state(args, Flags{defaults})

def Config.equal(left: Config, right: Config) -> Bool:
	Config{lg, lt, ld, lf} = left
	Config{rg, rt, rd, rf} = right
	String.eq(lg, rg) && U32.is_eq(lt, rt) && U32.is_eq(ld, rd) && U32.is_eq(lf, rf)

def Config.cpu_reversed(threads: List<&2, U32>, reversed: List<&2, Config>) -> List<&2, Config>:
	match threads:
		case Nil{}:
			reversed
		case head <> tail:
			Config.cpu_reversed(tail, Config{"off", head, 6, 6} <> reversed)

def Config.cpu(threads: List<&2, U32>) -> List<&2, Config>:
	List.reverse(&2, Config, Config.cpu_reversed(threads, Nil{}))

def Config.list(threads: List<&2, U32>) -> List<&2, Config>:
	Config{"off", 1, 6, 0} <> List.reverse.go(&2, Config, Config.cpu_reversed(threads, Nil{}),
		[Config{"on", 1, 4, 0}, Config{"on", 1, 4, 4}, Config{"on", 1, 5, 5}, Config{"on", 1, 6, 6}])

def Config.order(reverse: Bool, +configs: List<&2, Config>) -> List<&2, Config>:
	Bool.pick(List<&2, Config>, reverse, List.reverse(&2, Config, configs), configs)

def Config.args(config: Config, frames: U32) -> List<String>:
	Config{gpu, threads, tile, fork} = config
	["--gpu", gpu, "--threads", U32.show(threads), "--tile-depth", U32.show(tile), "--fork-depth", U32.show(fork), "--bench", U32.show(frames)]

def Rows.contains_tail(rows: List<&2, Row>, +config: Config, found: Bool) -> Bool:
	match rows found:
		case _ True{}:
			True{}
		case Nil{} False{}:
			False{}
		case Row{other, values} <> rest False{}:
			Rows.contains_tail(rest, config, Config.equal(other, config))

def Rows.contains(rows: List<&2, Row>, config: Config) -> Bool:
	Rows.contains_tail(rows, config, False{})

def Rows.ensure_present(found: Bool, rows: List<&2, Row>, config: Config) -> List<&2, Row>:
	match found:
		case True{}:
			rows
		case False{}:
			List.reverse.go(&2, Row, List.reverse(&2, Row, rows), [Row{config, Nil{}}])

def Rows.ensure(+rows: List<&2, Row>, +config: Config) -> List<&2, Row>:
	Rows.ensure_present(Rows.contains(rows, config), rows, config)

def Rows.from_configs(configs: List<&2, Config>, rows: List<&2, Row>) -> List<&2, Row>:
	match configs:
		case Nil{}:
			rows
		case config <> rest:
			Rows.from_configs(rest, Rows.ensure(rows, config))

def Rows.add_tail(rows: List<&2, Row>, +wanted: Config, +value: Num.Binary64, reversed: List<&2, Row>, found: Bool) -> List<&2, Row>:
	match rows found:
		case remaining True{}:
			List.reverse.go(&2, Row, reversed, remaining)
		case Nil{} False{}:
			List.reverse(&2, Row, reversed)
		case Row{+config, +values} <> rest False{}:
			+same = Config.equal(config, wanted)
			Rows.add_tail(rest, wanted, value,
				Row{config, Bool.pick(List<&2, Num.Binary64>, same, value <> values, values)} <> reversed, same)

def Rows.add(rows: List<&2, Row>, wanted: Config, value: Num.Binary64) -> List<&2, Row>:
	Rows.add_tail(rows, wanted, value, Nil{}, False{})

def Scan.seek(char: Char) -> Metric:
	match char:
		case 'f':
			Prefix{"rames="}
		case _:
			Seeking{}

def Scan.prefix_same(same: Bool, char: Char, suffix: String) -> Metric:
	match same suffix:
		case True{} SNil{}:
			FrameDigits{""}
		case True{} tail:
			Prefix{tail}
		case False{} _:
			Scan.seek(char)

def Scan.prefix(+char: Char, suffix: String) -> Metric:
	match suffix:
		case SCon{expected, rest}:
			Scan.prefix_same(Char.is_eq(char, expected), char, rest)
		case SNil{}:
			Scan.seek(char)

def Scan.frame_digit(digit: Bool, +char: Char, +reversed: String) -> Metric:
	match digit:
		case True{}:
			FrameDigits{SCon{char, reversed}}
		case False{}:
			Bool.pick(Metric, Char.is_eq(char, ' ') && Bool.not(String.is_empty(reversed)),
				Separator{String.reverse(reversed), "elapsed_ms="}, Scan.seek(char))

def Scan.separator_same(same: Bool, char: Char, frames: String, suffix: String) -> Metric:
	match same suffix:
		case True{} SNil{}:
			ElapsedDigits{frames, ""}
		case True{} tail:
			Separator{frames, tail}
		case False{} _:
			Scan.seek(char)

def Scan.separator(+char: Char, frames: String, suffix: String) -> Metric:
	match suffix:
		case SCon{expected, rest}:
			Scan.separator_same(Char.is_eq(char, expected), char, frames, rest)
		case SNil{}:
			Scan.seek(char)

def Scan.elapsed_digit(digit: Bool, char: Char, frames: String, +reversed: String) -> Metric:
	match digit:
		case True{}:
			ElapsedDigits{frames, SCon{char, reversed}}
		case False{}:
			Bool.pick(Metric, String.is_empty(reversed), Scan.seek(char), Complete{frames, String.reverse(reversed)})

def Scan.step(+char: Char, state: Metric) -> Metric:
	match state:
		case Seeking{}:
			Scan.seek(char)
		case Prefix{suffix}:
			Scan.prefix(char, suffix)
		case FrameDigits{reversed}:
			Scan.frame_digit(Decimal.char(char), char, reversed)
		case Separator{frames, suffix}:
			Scan.separator(char, frames, suffix)
		case ElapsedDigits{frames, reversed}:
			Scan.elapsed_digit(Decimal.char(char), char, frames, reversed)
		case Complete{frames, elapsed}:
			Complete{frames, elapsed}

def Scan.finish(state: Metric) -> Maybe<&2, MetricText>:
	match state:
		case Complete{frames, elapsed}:
			Some{MetricText{frames, elapsed}}
		case ElapsedDigits{frames, +reversed}:
			Bool.pick(Maybe<&2, MetricText>, String.is_empty(reversed), None{}, Some{MetricText{frames, String.reverse(reversed)}})
		case _:
			None{}

def Scan.feed(text: String, state: Metric) -> Maybe<&2, MetricText>:
	match text:
		case SNil{}:
			Scan.finish(state)
		case SCon{char, rest}:
			Scan.feed(rest, Scan.step(char, state))

def Scan.checked_frames(equal: Bool, elapsed: String) -> Result<&2, &2, String, Num.Elapsed>:
	match equal:
		case False{}:
			Fail{"Renderer reported a different measured frame count"}
		case True{}:
			Num.Elapsed.read(elapsed)

def Scan.measured(complete: Maybe<&2, MetricText>, expected: U32) -> Result<&2, &2, String, Num.Elapsed>:
	match complete:
		case None{}:
			Fail{"Missing frames=digits elapsed_ms=digits in renderer stdout"}
		case Some{MetricText{frames, elapsed}}:
			do Result<&2, &2, String, Num.Elapsed>:
				actual : U32 <- Decimal.read(frames)
				Scan.checked_frames(U32.is_eq(actual, expected), elapsed)

def Scan.measurement(stdout: String, expected: U32) -> Result<&2, &2, String, Num.Elapsed>:
	Scan.measured(Scan.feed(stdout, Seeking{}), expected)

def Rows.le(left: Num.Binary64, right: Num.Binary64) -> Bool:
	Cmp.is_le(Num.Number.compare(left, right))

def Rows.length(values: List<&2, Num.Binary64>, count: Nat) -> Nat:
	match values:
		case Nil{}:
			count
		case head <> rest:
			Rows.length(rest, 1n+count)

def Rows.runs(values: List<&2, Num.Binary64>, reversed: List<&2, List<&2, Num.Binary64>>) -> List<&2, List<&2, Num.Binary64>>:
	match values:
		case Nil{}:
			reversed
		case head <> rest:
			Rows.runs(rest, [head] <> reversed)

def Rows.pair_pass(+length: Nat, runs: List<&2, List<&2, Num.Binary64>>, reversed: List<&2, List<&2, Num.Binary64>>) -> List<&2, List<&2, Num.Binary64>>:
	match runs:
		case Nil{}:
			reversed
		case run <> Nil{}:
			run <> reversed
		case left <> right <> rest:
			Rows.pair_pass(length, rest, List.merge.go(~Num.Binary64, ~Rows.le, length, (Nil{}, left, right)) <> reversed)

def Rows.sort_passes(fuel: Nat, +length: Nat, runs: List<&2, List<&2, Num.Binary64>>) -> Result<&2, &2, String, List<&2, Num.Binary64>>:
	match fuel runs:
		case _ Nil{}:
			Done{Nil{}}
		case _ run <> Nil{}:
			Done{run}
		case 0n _:
			Fail{"Median sort exhausted its progress bound"}
		case 1n+rest remaining:
			Rows.sort_passes(rest, length, Rows.pair_pass(length, remaining, Nil{}))

def Rows.middle(odd: Bool, upper: Maybe<&2, Num.Binary64>, lower: Maybe<&2, Num.Binary64>) -> Result<&2, &2, String, Num.Binary64>:
	match odd upper lower:
		case True{} Some{value} _:
			Done{value}
		case False{} Some{right} Some{left}:
			Done{Num.Number.midpoint(left, right)}
		case _ _ _:
			Fail{"Cannot report a configuration with no samples"}

def Rows.median_length(+sorted: List<&2, Num.Binary64>, +length: Nat) -> Result<&2, &2, String, Num.Binary64>:
	+middle = (length / 2n : Nat)
	Rows.middle(Nat.is_eq((length % 2n : Nat), 1n), List.get(&2, Num.Binary64, sorted, middle),
		List.get(&2, Num.Binary64, sorted, (middle - 1n : Nat)))

def Rows.sorted_median(+sorted: List<&2, Num.Binary64>) -> Result<&2, &2, String, Num.Binary64>:
	Rows.median_length(sorted, Rows.length(sorted, 0n))

def Rows.median(+values: List<&2, Num.Binary64>) -> Result<&2, &2, String, Num.Binary64>:
	+length = Rows.length(values, 0n)
	do Result<&2, &2, String, Num.Binary64>:
		sorted : List<&2, Num.Binary64> <- Rows.sort_passes(length, length, Rows.runs(values, Nil{}))
		Rows.median_length(sorted, length)

def Progress.line(repeat: U32, config: Config, value: Num.Binary64) -> String:
	Config{gpu, threads, tile, fork} = config
	"repeat=" ++ U32.show(repeat) ++ " gpu=" ++ gpu ++ " threads=" ++ U32.show(threads) ++
		" tile=" ++ U32.show(tile) ++ " fork=" ++ U32.show(fork) ++ " ms/frame=" ++ Num.Number.fixed3(value)

def JSON.hex(+digit: U32) -> Char:
	Chr{Bool.pick(U32, (digit < 10 : U32), (48 + digit : U32), (87 + digit : U32))}

def JSON.char(+byte: U32) -> String:
	match byte:
		case 34:
			"\\\""
		case 92:
			"\\\\"
		case 8:
			"\\b"
		case 9:
			"\\t"
		case 10:
			"\\n"
		case 12:
			"\\f"
		case 13:
			"\\r"
		case _:
			Bool.pick(String, (byte < 32 : U32), "\\u00" ++ SCon{JSON.hex((byte / 16 : U32)), SCon{JSON.hex((byte % 16 : U32)), SNil{}}}, SCon{Chr{byte}, SNil{}})

def JSON.escape(text: String) -> String:
	match text:
		case SNil{}:
			""
		case SCon{Chr{byte}, rest}:
			JSON.char(byte) ++ JSON.escape(rest)

def JSON.quote(text: String) -> String:
	"\"" ++ JSON.escape(text) ++ "\""

def Report.samples_tail(values: List<&2, Num.Binary64>, reversed: String) -> String:
	match values:
		case Nil{}:
			String.reverse(reversed)
		case value <> +rest:
			prefix = "        " ++ Num.Number.json(value) ++ Bool.pick(String, List.is_empty(&2, Num.Binary64, rest), "\n", ",\n")
			Report.samples_tail(rest, String.reverse.go(prefix, reversed))

def Report.samples(values: List<&2, Num.Binary64>) -> String:
	Report.samples_tail(values, "")

def Report.parts(parts: List<String>, reversed: String) -> String:
	match parts:
		case Nil{}:
			String.reverse(reversed)
		case part <> rest:
			Report.parts(rest, String.reverse.go(part, reversed))

def Report.row(row: Row) -> Result<&2, &2, String, String>:
	Row{Config{gpu, threads, tile, fork}, +reversed} = row
	do Result<&2, &2, String, String>:
		median : Num.Binary64 <- Rows.median(reversed)
		return Report.parts(["    {\n      \"gpu\": ", JSON.quote(gpu), ",\n      \"threads\": ", U32.show(threads),
			",\n      \"tile_depth\": ", U32.show(tile), ",\n      \"fork_depth\": ", U32.show(fork),
			",\n      \"samples_ms_per_frame\": [\n", Report.samples(List.reverse(&2, Num.Binary64, reversed)),
			"      ],\n      \"median_ms_per_frame\": ", Num.Number.json(median), "\n    }"], "")

def Report.row_prefix(result: Result<&2, &2, String, String>, reversed: String, last: Bool) -> Result<&2, &2, String, String>:
	match result:
		case Fail{message}:
			Fail{message}
		case Done{row}:
			Done{String.reverse.go(Bool.pick(String, last, "", ",\n"), String.reverse.go(row, reversed))}

def Report.rows_tail(rows: List<&2, Row>, result: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
	match rows result:
		case _ Fail{message}:
			Fail{message}
		case Nil{} Done{reversed}:
			Done{String.reverse(reversed)}
		case row <> +rest Done{reversed}:
			Report.rows_tail(rest, Report.row_prefix(Report.row(row), reversed, List.is_empty(&2, Row, rest)))

def Report.rows(rows: List<&2, Row>) -> Result<&2, &2, String, String>:
	Report.rows_tail(rows, Done{""})

def Report.json(options: Options, identity: Identity, rows: List<&2, Row>) -> Result<&2, &2, String, String>:
	Options{frames, repeats, threads, root, binary_path, output, help} = options
	Identity{timestamp, binary, main, voxel, render, material, lighting, dump} = identity
	do Result<&2, &2, String, String>:
		results : String <- Report.rows(rows)
		return Report.parts(["{\n  \"generated_at\": ", JSON.quote(timestamp), ",\n  \"binary_sha256\": ", JSON.quote(binary),
			",\n  \"source_sha256\": {\n    \"main.bend\": ", JSON.quote(main), ",\n    \"voxel.bend\": ", JSON.quote(voxel),
			",\n    \"render.bend\": ", JSON.quote(render), ",\n    \"material.bend\": ", JSON.quote(material), ",\n    \"lighting.bend\": ", JSON.quote(lighting), ",\n    \"dump.bend\": ", JSON.quote(dump),
			"\n  },\n  \"frames\": ", U32.show(frames), ",\n  \"warmup_frames\": 8,\n  \"repeats\": ", U32.show(repeats),
			",\n  \"workload\": \"native Window.frame with cached scene and scripted destruction/reset\",\n  \"results\": [\n", results, "\n  ]\n}\n"], "")

def Run.config(+root: String, +binary: String, +frames: U32, +repeat: U32, +config: Config, rows: List<&2, Row>) -> IO(List<&2, Row>):
	do IO<List<&2, Row>>:
		stdout : String <- Host.Host.renderer(root, binary, Config.args(config, frames))
		elapsed : Num.Elapsed <- Host.Host.result(Num.Elapsed, Scan.measurement(stdout, frames), "Renderer metrics")
		+value : Num.Binary64 <- Host.Host.result(Num.Binary64, Num.Number.sample(elapsed, frames), "Milliseconds per frame")
		IO.print(Progress.line(repeat, config, value))
		return Rows.add(rows, config, value)

def Run.configs(configs: List<&2, Config>, +root: String, +binary: String, +frames: U32, +repeat: U32, rows: List<&2, Row>) -> IO(List<&2, Row>):
	match configs:
		case Nil{}:
			IO.pure(List<&2, Row>, rows)
		case config <> rest:
			IO.bind(List<&2, Row>, List<&2, Row>, Run.config(root, binary, frames, repeat, config, rows),
				next => Run.configs(rest, root, binary, frames, repeat, next))

def Run.repeats(fuel: Nat, +reverse: Bool, +repeat: U32, +configs: List<&2, Config>, +root: String, +binary: String, +frames: U32, rows: List<&2, Row>) -> IO(List<&2, Row>):
	match fuel:
		case 0n:
			IO.pure(List<&2, Row>, rows)
		case 1n+rest:
			IO.bind(List<&2, Row>, List<&2, Row>, Run.configs(Config.order(reverse, configs), root, binary, frames, repeat, rows),
				next => Run.repeats(rest, Bool.not(reverse), (repeat + 1 : U32), configs, root, binary, frames, next))

def Run.identity(+root: String, binary: String) -> IO(Identity):
	do IO<Identity>:
		timestamp : String <- Host.Host.timestamp()
		binary_hash : String <- Host.Host.hash(binary)
		main_hash : String <- Host.Host.hash(Host.Path.join(root, "main.bend"))
		voxel_hash : String <- Host.Host.hash(Host.Path.join(root, "voxel.bend"))
		render_hash : String <- Host.Host.hash(Host.Path.join(root, "render.bend"))
		material_hash : String <- Host.Host.hash(Host.Path.join(root, "material.bend"))
		lighting_hash : String <- Host.Host.hash(Host.Path.join(root, "lighting.bend"))
		dump_hash : String <- Host.Host.hash(Host.Path.join(root, "dump.bend"))
		return Identity{timestamp, binary_hash, main_hash, voxel_hash, render_hash, material_hash, lighting_hash, dump_hash}

def Run.output(+root: String, +output: String) -> String:
	Bool.pick(String, String.is_empty(output), Host.Path.join(root, "build/benchmark.json"), output)

def Run.benchmark(+options: Options, program: String) -> IO(Unit):
	Options{+frames, repeats, threads, explicit_root, binary_path, explicit_output, help} = options
	+configs = Config.list(threads)
	do IO<Unit>:
		+root : String <- Host.Host.root(program, explicit_root)
		+binary : String <- Host.Host.resolve(Host.Path.join(root, binary_path))
		+output : String = Run.output(root, explicit_output)
		rows : List<&2, Row> <- Run.repeats(U32.to_nat(repeats), False{}, 1, configs, root, binary, frames, Rows.from_configs(configs, Nil{}))
		Host.Host.mkdir(output)
		identity : Identity <- Run.identity(root, binary)
		json : String <- Host.Host.result(String, Report.json(options, identity, rows), "Benchmark report")
		Host.Host.write(output, json)
		IO.print("Wrote " ++ output)

def Run.options(help: Bool, options: Options, program: String) -> IO(Unit):
	match help:
		case True{}:
			IO.print("Usage: benchmark [--frames N] [--repeats N] [--cpu-threads N ...] [--output PATH] [--root REPOSITORY] [--binary RENDERER]\nMeasure native displayed frames after eight warmup frames. Defaults: 24 frames, 3 repeats, CPU threads 1/half/all logical processors. Numeric options use unsigned ASCII decimal integers in U32 range; frames >= 24, repeats >= 2, threads > 0. Progress has three fractional digits; JSON retains 53-bit binary precision.")
		case False{}:
			Run.benchmark(options, program)

def Run.parsed(+options: Options, program: String) -> IO(Unit):
	Options{frames, repeats, threads, root, binary, output, help} = options
	Run.options(help, options, program)

def Run.start(args: List<String>) -> IO(Unit):
	match args:
		case Nil{}:
			IO.die(Unit, 1, "Missing benchmark executable path")
		case program <> rest:
			do IO<Unit>:
				cores : U32 <- Host.Host.cores()
				+options : Options <- Host.Host.result(Options, Options.parse(rest, Options.defaults(cores)), "Arguments")
				Run.parsed(options, program)

def main() -> IO(Unit):
	IO.bind(List<String>, Unit, IO.args(), Run.start)
