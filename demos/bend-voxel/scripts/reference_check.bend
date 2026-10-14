import Base

# Independent oracle: this module deliberately does not import the engine.
type Cell is Data:
	Cell{x: U32, y: U32, z: U32, material: U32}

# Offsets encode 1 - direction, keeping translated fixture coordinates nonnegative.
type Direction is Data:
	Direction{name: String, x: U32, y: U32, z: U32}

type Case is Data:
	Case{cells: Map<&2, U32>, faces: Set(), count: Maybe<&2, U32>, face_lines: U32}

type Parser is Data:
	Parser{cases: Map<&2, Case>, current: Maybe<&2, String>, value: Case}

type Fixture is Data:
	Fixture{name: String, cells: List<&2, Cell>}

type Lines is Data:
	Lines{word: String, parts: List<&2, String>}

def Check.require(ok: Bool, message: String) -> IO(Unit):
	match ok:
		case True{}:
			IO.pure(Unit, Unit{})
		case False{}:
			IO.die(Unit, 1, message)

def Lookup.has.result(-V: Data, result: Map<&2, V> & Bool) -> Bool:
	(map, found) = result
	found

def Lookup.has(-V: Data, map: Map<&2, V>, key: String) -> Bool:
	Lookup.has.result(V, Map.has(&2, V, map, key))

def Lookup.get.result(-V: Data, result: Map<&2, V> & V) -> V:
	(map, value) = result
	value

def Lookup.get(-V: Data, fallback: V, map: Map<&2, V>, key: String) -> V:
	Lookup.get.result(V, Map.get(V, fallback, map, key))

def Cell.key(cell: Cell) -> String:
	Cell{x, y, z, material} = cell
	U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z)

def Cell.material(cell: Cell) -> U32:
	Cell{x, y, z, material} = cell
	material

def Cell.shift(cell: Cell, direction: Direction) -> String:
	Cell{x, y, z, material} = cell
	Direction{name, dx, dy, dz} = direction
	Cell.key(Cell{(x + dx : U32), (y + dy : U32), (z + dz : U32), 0})

def Cell.face(cell: Cell, direction: String) -> String:
	Cell{+x, +y, +z, material} = cell
	Cell.key(Cell{x, y, z, 0}) ++ " " ++ direction ++ " " ++ U32.show(material)

def Reference.directions() -> List<&2, Direction>:
	[Direction{"-x", 2, 1, 1}, Direction{"+x", 0, 1, 1},
	 Direction{"-y", 1, 2, 1}, Direction{"+y", 1, 0, 1},
	 Direction{"-z", 1, 1, 2}, Direction{"+z", 1, 1, 0}]

def Reference.cube(fuel: Nat, +side: U32, +index: U32) -> List<&2, Cell>:
	match fuel:
		case 0n:
			Nil{}
		case 1n+rest:
			Cell{(index / (side * side) : U32), ((index / side) % side : U32), (index % side : U32), 1} <>
				Reference.cube(rest, side, (index + 1 : U32))

def Reference.outside_interior(cell: Cell) -> Bool:
	Cell{x, y, z, material} = cell
	Bool.not(U32.is_eq(x, 1) && U32.is_eq(y, 1) && U32.is_eq(z, 1))

def Reference.outside_cut(cell: Cell) -> Bool:
	Cell{x, y, z, material} = cell
	+dx = (U32.to_f32(x) - 6.0 : F32)
	+dy = (U32.to_f32(y) - 6.0 : F32)
	+dz = (U32.to_f32(z) - 6.0 : F32)
	(dx * dx + dy * dy + dz * dz > 9.0 : F32)

def Reference.fixtures() -> List<&2, Fixture>:
	+single = {[Cell{1, 1, 1, 7}] : List<&2, Cell>}
	+full4 = Reference.cube(64n, 4, 0)
	+interior = List.filter(~Cell, ~Reference.outside_interior, full4)
	+full8 = Reference.cube(512n, 8, 0)
	+cut = List.filter(~Cell, ~Reference.outside_cut, full8)
	[Fixture{"empty", []}, Fixture{"single", single},
	 Fixture{"adjacent", Cell{2, 1, 1, 7} <> single}, Fixture{"full4", full4},
	 Fixture{"interior", interior}, Fixture{"repeat", interior},
	 Fixture{"bounds", single}, Fixture{"far-brush", full4},
	 Fixture{"edges", [Cell{0, 1, 1, 1}, Cell{3, 1, 1, 1}]},
	 Fixture{"full8", full8}, Fixture{"cut", cut}, Fixture{"cut-repeat", cut}]

def Reference.cells(cells: List<&2, Cell>, acc: Map<&2, U32>) -> Map<&2, U32>:
	match cells:
		case Nil{}:
			acc
		case Cell{+x, +y, +z, material} <> rest:
			Reference.cells(rest, Map.set(&2, U32, acc, Cell.key(Cell{x, y, z, 0}), material))

def Reference.shifted(cells: List<&2, Cell>, +direction: Direction, acc: Set()) -> Set():
	match cells:
		case Nil{}:
			acc
		case cell <> rest:
			Reference.shifted(rest, direction, Set.add(acc, Cell.shift(cell, direction)))

def Reference.add(hidden: Bool, cell: Cell, direction: String, acc: Set()) -> Set():
	match hidden:
		case True{}:
			acc
		case False{}:
			Set.add(acc, Cell.face(cell, direction))

def Reference.exposed(cells: List<&2, Cell>, +direction: String, +shifted: Set(), acc: Set()) -> Set():
	match cells:
		case Nil{}:
			acc
		case +cell <> rest:
			hidden = Lookup.has(Unit, shifted, Cell.shift(cell, Direction{"", 1, 1, 1}))
			Reference.exposed(rest, direction, shifted,
				Reference.add(hidden, cell, direction, acc))

def Reference.faces(directions: List<&2, Direction>, +cells: List<&2, Cell>, acc: Set()) -> Set():
	match directions:
		case Nil{}:
			acc
		case +direction <> rest:
			Direction{name, x, y, z} = direction
			Reference.faces(rest, cells, Reference.exposed(cells, name,
				Reference.shifted(cells, direction, Set.new()), acc))

def Case.empty() -> Case:
	Case{Map.new(&2, U32), Set.new(), None{}, 0}

def Parse.digits(text: String) -> Bool:
	match text:
		case SNil{}:
			True{}
		case SCon{head, rest}:
			Char.is_digit(head) && Parse.digits(rest)

def Parse.number.result(result: Maybe<&2, U32>) -> IO(U32):
	match result:
		case None{}:
			IO.die(U32, 1, "Invalid or overflowing unsigned integer")
		case Some{value}:
			IO.pure(U32, value)

def Parse.number(+text: String) -> IO(U32):
	do IO<U32>:
		Check.require(Bool.not(String.eq(text, "")) && Parse.digits(text), "Invalid unsigned integer: " ++ text)
		Parse.number.result(U32.read(text))

def Parse.cell.parts(parts: List<&2, String>, material: U32) -> IO(Cell):
	match parts:
		case Con{x, Con{y, Con{z, Nil{}}}}:
			do IO<Cell>:
				x : U32 <- Parse.number(x)
				y : U32 <- Parse.number(y)
				z : U32 <- Parse.number(z)
				return Cell{x, y, z, material}
		case _:
			IO.die(Cell, 1, "Expected three comma-separated coordinates")

def Parse.cell(position: String, material: String) -> IO(Cell):
	do IO<Cell>:
		material : U32 <- Parse.number(material)
		Parse.cell.parts(String.split(position, ','), material)

def Parse.active(current: Maybe<&2, String>) -> IO(String):
	match current:
		case None{}:
			IO.die(String, 1, "Record outside BEGIN/END")
		case Some{name}:
			IO.pure(String, name)

def Parse.direction(+direction: String) -> Bool:
	String.eq(direction, "-x") || String.eq(direction, "+x") ||
		String.eq(direction, "-y") || String.eq(direction, "+y") ||
		String.eq(direction, "-z") || String.eq(direction, "+z")

def Parse.tag(+tag: String) -> U32:
	(Bool.to_u32(String.eq(tag, "BEGIN")) + 2 * Bool.to_u32(String.eq(tag, "COUNT")) +
	 3 * Bool.to_u32(String.eq(tag, "C")) + 4 * Bool.to_u32(String.eq(tag, "F")) +
	 5 * Bool.to_u32(String.eq(tag, "END")) : U32)

def Parse.record(tag: U32, fields: List<&2, String>, state: Parser) -> IO(Parser):
	match tag fields state:
		case 1 Con{+name, Nil{}} Parser{+cases, current, value}:
			duplicate = Lookup.has(Case, cases, name)
			do IO<Parser>:
				Check.require(Maybe.is_none(&2, String, current) && Bool.not(duplicate), "Nested or duplicate BEGIN: " ++ name)
				return Parser{cases, Some{name}, Case.empty()}
		case 2 Con{text, Nil{}} Parser{cases, +current, Case{cells, faces, count, face_lines}}:
			do IO<Parser>:
				name : String <- Parse.active(current)
				Check.require(Maybe.is_none(&2, U32, count), name ++ ": duplicate COUNT")
				value : U32 <- Parse.number(text)
				return Parser{cases, current, Case{cells, faces, Some{value}, face_lines}}
		case 3 Con{position, Con{material, Nil{}}} Parser{cases, +current, Case{+cells, faces, count, face_lines}}:
			do IO<Parser>:
				name : String <- Parse.active(current)
				+cell : Cell <- Parse.cell(position, material)
				duplicate : Bool = Lookup.has(U32, cells, Cell.key(cell))
				Check.require(Bool.not(duplicate), name ++ ": duplicate cell")
				return Parser{cases, current, Case{Map.set(&2, U32, cells, Cell.key(cell), Cell.material(cell)), faces, count, face_lines}}
		case 4 Con{position, Con{+direction, Con{material, Nil{}}}} Parser{cases, +current, Case{cells, faces, count, face_lines}}:
			do IO<Parser>:
				name : String <- Parse.active(current)
				Check.require(Parse.direction(direction), name ++ ": invalid face direction")
				cell : Cell <- Parse.cell(position, material)
				return Parser{cases, current, Case{cells, Set.add(faces, Cell.face(cell, direction)), count, (face_lines + 1 : U32)}}
		case 5 Nil{} Parser{cases, +current, +value}:
			Case{cells, faces, count, face_lines} = value
			do IO<Parser>:
				+name : String <- Parse.active(current)
				Check.require(Maybe.is_some(&2, U32, count), name ++ ": missing COUNT")
				return Parser{Map.set(&2, Case, cases, name, value), None{}, Case.empty()}
		case _ _ _:
			IO.die(Parser, 1, "Unknown or malformed geometry record")

def Parse.line(words: List<&2, String>, state: Parser) -> IO(Parser):
	match words:
		case Nil{}:
			IO.pure(Parser, state)
		case tag <> fields:
			Parse.record(Parse.tag(tag), fields, state)

def Parse.nonempty(text: String) -> Bool:
	Bool.not(String.eq(text, ""))

def Parse.spaces(text: String) -> String:
	match text:
		case SNil{}:
			SNil{}
		case SCon{+head, rest}:
			SCon{Bool.pick(Char, Char.is_space(head), ' ', head), Parse.spaces(rest)}

def Parse.finish(state: Parser) -> IO(Map<&2, Case>):
	Parser{cases, current, value} = state
	do IO<Map<&2, Case>>:
		Check.require(Maybe.is_none(&2, String, current), "Unterminated geometry case")
		return cases

# Base's String.lines recursively visits each character before returning.
# Accumulate reversed words and lines to keep long candidate dumps tail-recursive.
def Parse.newline(cut: Bool, head: Char, word: String, parts: List<&2, String>) -> Lines:
	match cut:
		case True{}:
			Lines{"", String.reverse(word) <> parts}
		case False{}:
			Lines{SCon{head, word}, parts}

def Parse.split(text: String, state: Lines) -> List<&2, String>:
	match text state:
		case SNil{} Lines{word, parts}:
			List.reverse(&2, String, String.reverse(word) <> parts)
		case SCon{+head, rest} Lines{word, parts}:
			Parse.split(rest, Parse.newline(Char.is_eq(head, '\n'), head, word, parts))

def Parse.lines(lines: List<&2, String>, state: Parser) -> IO(Map<&2, Case>):
	match lines:
		case Nil{}:
			Parse.finish(state)
		case line <> rest:
			IO.bind(Parser, Map<&2, Case>,
				Parse.line(List.filter(~String, ~Parse.nonempty, String.split(Parse.spaces(line), ' ')), state),
				next => Parse.lines(rest, next))

def Check.materials(entries: List<&2, Sigma<&2, &2, String, _ => U32>>, +actual: Map<&2, U32>) -> Bool:
	match entries:
		case Nil{}:
			True{}
		case (key, material) <> rest:
			found = Lookup.get(U32, 0, actual, key)
			U32.is_eq(material, found) && Check.materials(rest, actual)

def Check.cells(+expected: Map<&2, U32>, +actual: Map<&2, U32>) -> Bool:
	Nat.is_eq(Map.size(&2, U32, expected), Map.size(&2, U32, actual)) &&
		Check.materials(Map.to_list(&2, U32, expected), actual)

def Check.members(keys: List<&2, String>, +actual: Set()) -> Bool:
	match keys:
		case Nil{}:
			True{}
		case key <> rest:
			found = Lookup.has(Unit, actual, key)
			found && Check.members(rest, actual)

def Check.faces(+expected: Set(), +actual: Set()) -> Bool:
	Nat.is_eq(Set.size(expected), Set.size(actual)) && Check.members(Set.to_list(expected), actual)

def Check.fixture(fixture: Fixture, actual: Case) -> IO(Unit):
	Fixture{+name, +occupied} = fixture
	Case{cells, faces, count, face_lines} = actual
	+expected_faces = Reference.faces(Reference.directions(), occupied, Set.new())
	+n = U32.from_nat(Set.size(expected_faces))
	do IO<Unit>:
		Check.require(Check.cells(Reference.cells(occupied, Map.new(&2, U32)), cells), name ++ ": occupancy or material differs")
		Check.require(Check.faces(expected_faces, faces), name ++ ": exact exposed face set differs")
		Check.require(U32.is_eq(Maybe.default(&2, U32, count, 4294967295), n) && U32.is_eq(face_lines, n), name ++ ": duplicate, missing, or miscounted faces")
		IO.print(name ++ ": " ++ Nat.show(List.length(&2, Cell, occupied)) ++ " cells, " ++ U32.show(n) ++ " exact faces")

def Check.fixtures(fixtures: List<&2, Fixture>, +cases: Map<&2, Case>) -> IO(Unit):
	match fixtures:
		case Nil{}:
			IO.pure(Unit, Unit{})
		case +fixture <> rest:
			Fixture{+name, cells} = fixture
			found = Lookup.has(Case, cases, name)
			value = Lookup.get(Case, Case.empty(), cases, name)
			do IO<Unit>:
				Check.require(found, "Missing geometry case: " ++ name)
				Check.fixture(fixture, value)
				Check.fixtures(rest, cases)

def Check.regression_values(full4: Case, interior: Case, full8: Case, cut: Case, repeated: Case) -> IO(Unit):
	Case{cells4, faces4, count4, lines4} = full4
	Case{cells_i, faces_i, count_i, lines_i} = interior
	Case{+cells8, faces8, count8, lines8} = full8
	Case{+cells_cut, +faces_cut, count_cut, lines_cut} = cut
	Case{cells_repeat, faces_repeat, count_repeat, lines_repeat} = repeated
	do IO<Unit>:
		Check.require(U32.is_eq(Maybe.default(&2, U32, count4, 0), 96) && U32.is_eq(Maybe.default(&2, U32, count_i, 0), 102) && U32.is_eq(Maybe.default(&2, U32, count8, 0), 384), "Known surface counts differ")
		Check.require(Nat.is_lt(Map.size(&2, U32, cells_cut), Map.size(&2, U32, cells8)) && Check.members(Map.keys(&2, U32, cells_cut), Set.from_list(Map.keys(&2, U32, cells8))), "Cut must be a proper subset of the full body")
		Check.require(Check.cells(cells_cut, cells_repeat) && Check.faces(faces_cut, faces_repeat) && U32.is_eq(lines_cut, lines_repeat) && U32.is_eq(Maybe.default(&2, U32, count_cut, 0), Maybe.default(&2, U32, count_repeat, 0)), "Repeated cut changed geometry")

def Check.regressions(+cases: Map<&2, Case>) -> IO(Unit):
	Check.regression_values(Lookup.get(Case, Case.empty(), cases, "full4"),
		Lookup.get(Case, Case.empty(), cases, "interior"),
		Lookup.get(Case, Case.empty(), cases, "full8"),
		Lookup.get(Case, Case.empty(), cases, "cut"),
		Lookup.get(Case, Case.empty(), cases, "cut-repeat"))

def Check.output(text: String) -> IO(Unit):
	do IO<Unit>:
		+cases : Map<&2, Case> <- Parse.lines(Parse.split(text, Lines{"", []}), Parser{Map.new(&2, Case), None{}, Case.empty()})
		Check.require(Nat.is_eq(Map.size(&2, Case, cases), 12n), "Expected exactly 12 geometry cases")
		Check.fixtures(Reference.fixtures(), cases)
		Check.regressions(cases)
		IO.print("Geometry reference checks passed.")

def Check.process(result: U32 & (String & String)) -> IO(Unit):
	(+status, (stdout, stderr)) = result
	do IO<Unit>:
		Check.require(U32.is_eq(status, 0), "Geometry candidate failed with exit " ++ U32.show(status) ++ ": " ++ stderr)
		Check.output(stdout)

def Check.binary(path: String) -> IO(Unit):
	IO.bind(U32 & (String & String), Unit, IO.try(U32 & (String & String),
		Process.run(path, ["--gpu", "off"], "", 1048576, 30000)), Check.process)

def Check.file.read(read: File & Result<&1, &1, U32 & String, String>) -> IO(Unit):
	(file, result) = read
	do IO<Unit>:
		File.close(file)
		+text : String <- IO.try(String, IO.pure(Result<&1, &1, U32 & String, String>, result))
		Check.require(Nat.is_lt(String.length(text), 1048576n), "Geometry dump exceeds the input limit")
		Check.output(text)

def Check.file(path: String) -> IO(Unit):
	do IO<Unit>:
		file : File <- IO.try(File, File.open(path, "r"))
		IO.bind(File & Result<&1, &1, U32 & String, String>, Unit, File.read(file, 1048576), Check.file.read)

def Check.option(input: Bool, binary: Bool, path: String) -> IO(Unit):
	match input binary:
		case True{} False{}:
			Check.file(path)
		case False{} True{}:
			Check.binary(path)
		case _ _:
			IO.die(Unit, 1, "Usage: reference-check [--input dump | --binary geometry-dump]")

def Check.args(args: List<String>) -> IO(Unit):
	match args:
		case Nil{}:
			Check.binary("./build/geometry-dump")
		case Con{+flag, Con{path, Nil{}}}:
			Check.option(String.eq(flag, "--input"), String.eq(flag, "--binary"), path)
		case _:
			IO.die(Unit, 1, "Usage: reference-check [--input dump | --binary geometry-dump]")

def Check.start(args: List<String>) -> IO(Unit):
	match args:
		case program <> rest:
			Check.args(rest)
		case Nil{}:
			Check.args([])

def main() -> IO(Unit):
	IO.bind(List<String>, Unit, IO.args(), Check.start)
