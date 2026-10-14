import Base
import ./sha256.bend as Sha

type Raster is Data:
	Raster{pixels: List<&2, U32>}

type Sink is Data:
	Save{pixels: List<&2, U32>}
	Compare{pixels: List<&2, U32>, equal: Bool}

type Scan is Data:
	HeaderGap{tokens: List<&2, String>, sink: Sink}
	HeaderToken{suffix: String, tokens: List<&2, String>, sink: Sink}
	Channels{active: Bool, value: U32, component: U32, packed: U32, count: U32, sink: Sink}
	Invalid{message: String}

type Parsed is Data:
	Retained{image: Raster}
	Compared{}

type Progress is Data:
	Progress{offset: U32, state: Scan}

def Parse.start(sink: Sink) -> Scan:
	HeaderGap{["P3", "512", "512", "255"], sink}

def Sink.pixel(sink: Sink, +pixel: U32) -> Sink:
	match sink:
		case Save{pixels}:
			Save{pixel <> pixels}
		case Compare{Nil{}, equal}:
			Compare{Nil{}, False{}}
		case Compare{head <> rest, equal}:
			Compare{rest, equal && U32.is_eq(head, pixel)}

def Parse.channel(active: Bool, value: U32, +component: U32, +packed: U32, +count: U32, sink: Sink) -> Scan:
	match active:
		case False{}:
			Channels{False{}, 0, component, packed, count, sink}
		case True{}:
			match component:
				case 2:
					Channels{False{}, 0, 0, 0, (count + 1 : U32), Sink.pixel(sink, ((packed << 8n) .|. value : U32))}
				case _:
					Channels{False{}, 0, (component + 1 : U32), ((packed << 8n) .|. value : U32), count, sink}

def Parse.digit(ok: Bool, digit: U32, active: Bool, +value: U32, component: U32, packed: U32, +count: U32, sink: Sink) -> Scan:
	match ok:
		case False{}:
			Invalid{"Expected an unsigned ASCII channel in 0..255"}
		case True{}:
			+next = (value * 10 + digit : U32)
			Bool.pick(Scan, U32.is_le(next, 255) && U32.is_lt(count, 262144),
				Channels{True{}, next, component, packed, count, sink},
				Invalid{"Channel is out of range or image has extra channels"})

def Parse.header_end(space: Bool, tokens: List<&2, String>, sink: Sink) -> Scan:
	match space tokens:
		case True{} Nil{}:
			Channels{False{}, 0, 0, 0, 0, sink}
		case True{} _:
			HeaderGap{tokens, sink}
		case False{} _:
			Invalid{"Expected literal P3 512 512 255 header tokens"}

def Parse.header(+byte: U32, suffix: String, tokens: List<&2, String>, sink: Sink) -> Scan:
	match suffix:
		case SNil{}:
			Parse.header_end(Char.is_space(Chr{byte}), tokens, sink)
		case SCon{Chr{expected}, rest}:
			Bool.pick(Scan, U32.is_eq(byte, expected), HeaderToken{rest, tokens, sink},
				Invalid{"Expected literal P3 512 512 255 header tokens"})

def Parse.header_gap(space: Bool, byte: U32, tokens: List<&2, String>, sink: Sink) -> Scan:
	match space tokens:
		case True{} _:
			HeaderGap{tokens, sink}
		case False{} token <> rest:
			Parse.header(byte, token, rest, sink)
		case False{} Nil{}:
			Invalid{"Missing image channels"}

def Parse.channel_byte(space: Bool, +byte: U32, active: Bool, value: U32, component: U32, packed: U32, count: U32, sink: Sink) -> Scan:
	match space:
		case True{}:
			Parse.channel(active, value, component, packed, count, sink)
		case False{}:
			Parse.digit((byte >= 48 : U32) && (byte <= 57 : U32), (byte - 48 : U32), active, value, component, packed, count, sink)

def Parse.byte(+byte: U32, state: Scan) -> Scan:
	match state:
		case Invalid{message}:
			Invalid{message}
		case HeaderGap{tokens, sink}:
			Parse.header_gap(Char.is_space(Chr{byte}), byte, tokens, sink)
		case HeaderToken{suffix, tokens, sink}:
			Parse.header(byte, suffix, tokens, sink)
		case Channels{active, value, component, packed, count, sink}:
			Parse.channel_byte(Char.is_space(Chr{byte}), byte, active, value, component, packed, count, sink)

def Parse.feed(bytes: List<&2, U32>, state: Scan, +count: U32) -> Scan & U32:
	match bytes:
		case Nil{}:
			(state, count)
		case byte <> rest:
			Parse.feed(rest, Parse.byte(byte, state), (count + 1 : U32))

def Parse.sink(sink: Sink) -> Result<&2, &2, String, Parsed>:
	match sink:
		case Save{pixels}:
			Done{Retained{Raster{List.reverse(&2, U32, pixels)}}}
		case Compare{Nil{}, True{}}:
			Done{Compared{}}
		case Compare{_, _}:
			Fail{"Exact RGB pixels differ from the scene baseline"}

def Parse.complete(state: Scan) -> Result<&2, &2, String, Parsed>:
	match state:
		case Invalid{message}:
			Fail{message}
		case Channels{False{}, _, 0, _, 262144, sink}:
			Parse.sink(sink)
		case _:
			Fail{"Expected exactly 786432 RGB channels"}

def Parse.finish(state: Scan) -> Result<&2, &2, String, Parsed>:
	match state:
		case Channels{active, value, component, packed, count, sink}:
			Parse.complete(Parse.channel(active, value, component, packed, count, sink))
		case other:
			Parse.complete(other)

def Read.progress(+expected: U32, +offset: U32, +received: U32) -> Result<&2, &2, String, U32>:
	Bool.pick(Result<&2, &2, String, U32>,
		U32.is_le(offset, expected) && U32.is_le(received, (expected - offset : U32)),
		Bool.pick(Result<&2, &2, String, U32>, U32.is_eq(received, 0) && Bool.not(U32.is_eq(offset, expected)),
			Fail{"Image file ended before its reported size"}, Done{(offset + received : U32)}),
		Fail{"Image file size changed while reading"})

def Read.window_progress(progress: Result<&2, &2, String, U32>, file: File, state: Scan, next: File -> Scan -> U32 -> IO(File & Result<&2, &2, String, Progress>)) -> IO(File & Result<&2, &2, String, Progress>):
	match progress:
		case Fail{message}:
			IO.pure(File & Result<&2, &2, String, Progress>, (file, Fail{message}))
		case Done{position}:
			next(file, state, position)

def Read.window_scanned(scanned: Scan & U32, file: File, expected: U32, offset: U32, next: File -> Scan -> U32 -> IO(File & Result<&2, &2, String, Progress>)) -> IO(File & Result<&2, &2, String, Progress>):
	(state, received) = scanned
	Read.window_progress(Read.progress(expected, offset, received), file, state, next)

def Read.window_read(read: File & Result<&1, &1, U32 & String, List<&2, U32>>, expected: U32, offset: U32, state: Scan, next: File -> Scan -> U32 -> IO(File & Result<&2, &2, String, Progress>)) -> IO(File & Result<&2, &2, String, Progress>):
	match read:
		case (file, Fail{(code, message)}):
			IO.pure(File & Result<&2, &2, String, Progress>, (file, Fail{"Image read failed: " ++ message}))
		case (file, Done{bytes}):
			Read.window_scanned(Parse.feed(bytes, state, 0), file, expected, offset, next)

def Read.window(fuel: Nat, done: Bool, file: File, +expected: U32, +chunk: U32, +target: U32, +offset: U32, state: Scan) -> IO(File & Result<&2, &2, String, Progress>):
	match fuel done:
		case _ True{}:
			IO.pure(File & Result<&2, &2, String, Progress>, (file, Done{Progress{offset, state}}))
		case 0n False{}:
			IO.pure(File & Result<&2, &2, String, Progress>, (file, Fail{"Image read made no progress"}))
		case 1n+rest False{}:
			IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, File & Result<&2, &2, String, Progress>,
				File.read_bytes(file, U32.min(chunk, (target - offset : U32))),
				read => Read.window_read(read, expected, offset, state,
					f => s => +p => Read.window(rest, U32.is_eq(p, target), f, expected, chunk, target, p, s)))

def Read.eof_result(result: Result<&1, &1, U32 & String, List<&2, U32>>, state: Scan) -> Result<&2, &2, String, Parsed>:
	match result:
		case Fail{(code, message)}:
			Fail{"Image EOF read failed: " ++ message}
		case Done{Nil{}}:
			Parse.finish(state)
		case Done{_}:
			Fail{"Image file has an unread suffix or changed size"}

def Read.eof_read(read: File & Result<&1, &1, U32 & String, List<&2, U32>>, state: Scan) -> IO(Result<&2, &2, String, Parsed>):
	(file, result) = read
	do IO<Result<&2, &2, String, Parsed>>:
		File.close(file)
		return Read.eof_result(result, state)

def Read.eof(file: File, state: Scan) -> IO(Result<&2, &2, String, Parsed>):
	IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, Result<&2, &2, String, Parsed>, File.read_bytes(file, 1), read => Read.eof_read(read, state))

def Read.windows_read(window: File & Result<&2, &2, String, Progress>, next: File -> Scan -> U32 -> IO(Result<&2, &2, String, Parsed>)) -> IO(Result<&2, &2, String, Parsed>):
	match window:
		case (file, Fail{message}):
			do IO<Result<&2, &2, String, Parsed>>:
				File.close(file)
				return Fail{message}
		case (file, Done{Progress{position, state}}):
			next(file, state, position)

def Read.windows(fuel: Nat, done: Bool, file: File, +expected: U32, +chunk: U32, +offset: U32, state: Scan) -> IO(Result<&2, &2, String, Parsed>):
	match fuel done:
		case _ True{}:
			Read.eof(file, state)
		case 0n False{}:
			do IO<Result<&2, &2, String, Parsed>>:
				File.close(file)
				return Fail{"Image reader exhausted its progress bound"}
		case 1n+rest False{}:
			+target = (offset + U32.min(65536, (expected - offset : U32)) : U32)
			IO.bind(File & Result<&2, &2, String, Progress>, Result<&2, &2, String, Parsed>,
				Read.window(65537n, False{}, file, expected, chunk, target, offset, state),
				window => Read.windows_read(window, f => s => +p => Read.windows(rest, U32.is_eq(p, expected), f, expected, chunk, p, s)))

def Read.file_size(sized: File & Result<&1, &1, U32 & String, U32>, +chunk: U32, sink: Sink) -> IO(Result<&2, &2, String, Parsed>):
	match sized:
		case (file, Fail{(code, message)}):
			do IO<Result<&2, &2, String, Parsed>>:
				File.close(file)
				return Fail{"Image size failed: " ++ message}
		case (file, Done{+size}):
			Read.windows(U32.to_nat((size / 65536 + 2 : U32)), U32.is_eq(size, 0), file, size, chunk, 0, Parse.start(sink))

def Read.file_open(opened: Result<&1, &1, U32 & String, File>, +chunk: U32, sink: Sink) -> IO(Result<&2, &2, String, Parsed>):
	match opened:
		case Fail{(code, message)}:
			IO.pure(Result<&2, &2, String, Parsed>, Fail{"Image open failed: " ++ message})
		case Done{file}:
			IO.bind(File & Result<&1, &1, U32 & String, U32>, Result<&2, &2, String, Parsed>, File.size(file), sized => Read.file_size(sized, chunk, sink))

def Read.file_valid(positive: Bool, path: String, +chunk: U32, sink: Sink) -> IO(Result<&2, &2, String, Parsed>):
	match positive:
		case False{}:
			IO.pure(Result<&2, &2, String, Parsed>, Fail{"Image read chunk must be positive"})
		case True{}:
			IO.bind(Result<&1, &1, U32 & String, File>, Result<&2, &2, String, Parsed>, File.open(path, "r"), opened => Read.file_open(opened, chunk, sink))

def Read.file(path: String, +chunk: U32, sink: Sink) -> IO(Result<&2, &2, String, Parsed>):
	Read.file_valid(U32.is_gt(chunk, 0), path, chunk, sink)

def Image.retained(result: Result<&2, &2, String, Parsed>) -> Result<&2, &2, String, Raster>:
	match result:
		case Done{Retained{image}}:
			Done{image}
		case Done{Compared{}}:
			Fail{"Expected a retained image"}
		case Fail{message}:
			Fail{message}

def Image.read(path: String) -> IO(Result<&2, &2, String, Raster>):
	IO.bind(Result<&2, &2, String, Parsed>, Result<&2, &2, String, Raster>, Read.file(path, 8192, Save{Nil{}}), result => IO.pure(Result<&2, &2, String, Raster>, Image.retained(result)))

def Image.compared(result: Result<&2, &2, String, Parsed>) -> Result<&2, &2, String, Unit>:
	match result:
		case Done{Compared{}}:
			Done{Unit{}}
		case Done{Retained{_}}:
			Fail{"Expected an image comparison"}
		case Fail{message}:
			Fail{message}

def Image.compare(path: String, image: Raster) -> IO(Result<&2, &2, String, Unit>):
	Raster{pixels} = image
	IO.bind(Result<&2, &2, String, Parsed>, Result<&2, &2, String, Unit>, Read.file(path, 8192, Compare{pixels, True{}}), result => IO.pure(Result<&2, &2, String, Unit>, Image.compared(result)))

def Image.pixel_checked(in_bounds: Bool, image: Raster, x: U32, y: U32) -> Maybe<&2, U32>:
	match in_bounds:
		case False{}:
			None{}
		case True{}:
			Raster{pixels} = image
			List.get(&2, U32, pixels, U32.to_nat((512 * y + x : U32)))

def Image.pixel(image: Raster, +x: U32, +y: U32) -> Maybe<&2, U32>:
	Image.pixel_checked((x < 512 : U32) && (y < 512 : U32), image, x, y)

def Image.count(left: List<&2, U32>, right: List<&2, U32>, +count: U32) -> Result<&2, &2, String, U32>:
	match left right:
		case Nil{} Nil{}:
			Done{count}
		case head <> rest other <> tail:
			Image.count(rest, tail, (count + Bool.to_u32(U32.is_ne(head, other)) : U32))
		case _ _:
			Fail{"Image sizes differ"}

def Image.changed(left: Raster, right: Raster) -> Result<&2, &2, String, U32>:
	Raster{a} = left
	Raster{b} = right
	Image.count(a, b, 0)

def Image.hash_pixels(pixels: List<&2, U32>, context: Sha.Context) -> Result<&2, &2, String, String>:
	match pixels:
		case Nil{}:
			Sha.SHA256.finish(context)
		case +pixel <> rest:
			red = ((pixel >> 16n) .&. 255 : U32)
			green = ((pixel >> 8n) .&. 255 : U32)
			blue = (pixel .&. 255 : U32)
			Image.hash_pixels(rest, Sha.SHA256.update(Sha.SHA256.update(Sha.SHA256.update(context, red), green), blue))

def Image.hash(image: Raster) -> Result<&2, &2, String, String>:
	Raster{pixels} = image
	Image.hash_pixels(pixels, Sha.SHA256.init())
