import Base

def Dump.rgb(+color: U32) -> String:
	U32.show((color / 65536 % 256 : U32)) ++ " " ++ U32.show((color / 256 % 256 : U32)) ++ " " ++ U32.show((color % 256 : U32)) ++ " "

def Dump.zip(left: List<&2, String>, right: List<&2, String>) -> List<&2, String>:
	match left right:
		case Con{l, ls} Con{r, rs}:
			(l ++ r) <> Dump.zip(ls, rs)
		case _ _:
			Nil{}

def Dump.append(top: List<&2, String>, bottom: List<&2, String>) -> List<&2, String>:
	match top:
		case Nil{}:
			bottom
		case Con{row, rest}:
			row <> Dump.append(rest, bottom)

def Dump.repeat(fuel: Nat, +row: String) -> List<&2, String>:
	match fuel:
		case 0n:
			Nil{}
		case 1n+rest:
			row <> Dump.repeat(rest, row)

def Dump.rows(image: Image, +size: U32) -> List<&2, String>:
	match image:
		case Pix{color}:
			Dump.repeat(U32.to_nat(size), String.repeat(Dump.rgb(color), U32.to_nat(size)))
		case Qua{tl, tr, bl, br}:
			+h = (size / 2 : U32)
			Dump.append(Dump.zip(Dump.rows(tl, h), Dump.rows(tr, h)), Dump.zip(Dump.rows(bl, h), Dump.rows(br, h)))

def Dump.written(result: File & Result<&1, &1, U32 & String, Unit>) -> IO(File):
	(file, status) = result
	do IO<File>:
		Unit <- IO.try(Unit, IO.pure(Result<&1, &1, U32 & String, Unit>, status))
		return file

def Dump.write(rows: List<&2, String>, file: File) -> IO(Unit):
	match rows:
		case Nil{}:
			File.close(file)
		case Con{row, rest}:
			do IO<Unit>:
				result : File & Result<&1, &1, U32 & String, Unit> <- File.write(file, row ++ "\n")
				file : File <- Dump.written(result)
				Dump.write(rest, file)

def Dump.ppm(path: String, image: Image) -> IO(Unit):
	do IO<Unit>:
		file : File <- IO.try(File, File.open(path, "w"))
		result : File & Result<&1, &1, U32 & String, Unit> <- File.write(file, "P3\n512 512\n255\n")
		file : File <- Dump.written(result)
		Dump.write(Dump.rows(image, 512), file)
