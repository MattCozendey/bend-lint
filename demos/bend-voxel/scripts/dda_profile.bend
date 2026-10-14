import Base
import ../dump.bend as D

# Native profiling adapter for Bend 2.0.34's emitted C. The engine stays pure Bend.
# Map numbers must be checked against emitted parameter names before each build.
type Symbols is Data:
	Symbols{count: String, advance: String, tree: String, crossing: String, grid: String, valid: String, trace: String, ray: String}

def Symbols.accepted() -> Symbols:
	Symbols{"45","61","63","99","102","103","141","181"}

def Hook.header() -> String:
	"#include <stdint.h>\n#include <stdio.h>\n#include <stdatomic.h>\n" ++
	"static _Atomic uint64_t dda_counts[18];\n" ++
	"#define DDA_COUNT(i,n) atomic_fetch_add_explicit(&dda_counts[i], (uint64_t)(n), memory_order_relaxed)\n" ++
	"static const char *dda_names[] = {\"region_lookups\",\"outside_lookups\",\"tree_lookups\",\"tree_branches\",\"tree_leaves\",\"region_crossings\",\"axis_advance_calls\",\"axis_count_calls\",\"axis_count_iterations\",\"axis_count_collapsed_iterations\",\"trace_region_iterations\",\"rays\",\"final_hits\",\"final_misses\",\"image_pixels\",\"image_quads\",\"frame_roots\",\"axis_count_zero_mid_iterations\"};\n" ++
	"static void __attribute__((destructor)) dda_report(void) { for (int i=0;i<18;i++) fprintf(stderr, \"%s\\t%llu\\n\", dda_names[i], (unsigned long long)atomic_load(&dda_counts[i])); }\n"

def Hook.entry(kind: String) -> String:
	match kind:
		case "count": "  DDA_COUNT(7,1);\n"
		case "advance": "  DDA_COUNT(6,1);\n"
		case "tree": "  DDA_COUNT(2,1);\n"
		case "crossing": "  DDA_COUNT(5,1);\n"
		case "grid": "  DDA_COUNT(0,1);\n"
		case "valid": "  DDA_COUNT(1,r0 == 0);\n"
		case "ray": "  DDA_COUNT(11,1);\n"
		case _: ""

def Hook.loop(kind: String) -> String:
	match kind:
		case "tree": "    DDA_COUNT(3,term_aux(_tree_0) != CID____DDA_SOLID);\n    DDA_COUNT(4,term_aux(_tree_0) == CID____DDA_SOLID);\n"
		case "trace": "    DDA_COUNT(10,1);\n"
		case "frame": "    DDA_COUNT(16,_size_0 == 512);\n"
		case _: ""

def Hook.return(kind: String) -> String:
	match kind:
		case "ray": "  DDA_COUNT(12,o[0] != 0);\n  DDA_COUNT(13,o[0] == 0);\n"
		case _: ""

def Hook.spin(+line: String, +number: String) -> Bool:
	String.starts_with(line,"INLINE Term spin_" ++ number ++ "(") || String.starts_with(line,"FAR Term spin_" ++ number ++ "(")

def Hook.kind(+line: String, symbols: Symbols, current: String) -> String:
	Symbols{count,advance,tree,crossing,grid,valid,trace,ray} = symbols
	Bool.pick(String,Hook.spin(line,count),"count",
	Bool.pick(String,Hook.spin(line,advance),"advance",
	Bool.pick(String,Hook.spin(line,tree),"tree",
	Bool.pick(String,Hook.spin(line,crossing),"crossing",
	Bool.pick(String,Hook.spin(line,grid),"grid",
	Bool.pick(String,Hook.spin(line,valid),"valid",
	Bool.pick(String,Hook.spin(line,trace),"trace",
	Bool.pick(String,Hook.spin(line,ray),"ray",
	Bool.pick(String,String.starts_with(line,"  WL_CASE(FID____DDA_FRAME_FORK)"),"frame",
	Bool.pick(String,String.starts_with(line,"INLINE Term spin_") || String.starts_with(line,"FAR Term spin_") || String.starts_with(line,"  WL_CASE("),"",current))))))))))

def Hook.anchor(kind: String, +line: String) -> U32:
	match kind:
		case "count": Bool.pick(U32,String.eq(line,"  u32 _high_1 = r7;") || String.eq(line,"  u32 _high_1 = r8;"),1,0)
		case "advance": Bool.pick(U32,String.eq(line,"  u32 _moving_1 = r0;"),2,0)
		case "tree": Bool.pick(U32,String.eq(line,"  u32 _low_0 = r9;"),4,0)
		case "crossing": Bool.pick(U32,String.eq(line,"  u32 _region_13 = r15;"),8,0)
		case "grid": Bool.pick(U32,String.eq(line,"  u32 _cell_8 = r4;"),16,0)
		case "valid": Bool.pick(U32,String.eq(line,"  u32 _inside_1 = r0;"),32,0)
		case "trace": Bool.pick(U32,String.eq(line,"  u32 _region_13 = r25;"),64,0)
		case "ray": Bool.pick(U32,String.eq(line,"  u32 _near_1 = r9;"),128,0)
		case _: 0

def Hook.validate(lines: List<&2,String>, +symbols: Symbols, kind: String, found: U32) -> U32:
	match lines:
		case Nil{}: found
		case Con{+line,rest}:
			+next = Hook.kind(line,symbols,kind)
			Hook.validate(rest,symbols,next,(found .|. Hook.anchor(next,line) : U32))

def Hook.output(counters: Bool, header: Bool, loop: Bool, returns: Bool, pix: Bool, qua: Bool, mid: Bool, +line: String, +kind: String) -> String:
	match counters header loop returns pix qua mid:
		case False{} _ _ _ _ _ _:
			Bool.pick(String,String.eq(kind,"count") && String.starts_with(line,"INLINE Term spin_"),"FAR" ++ String.drop(line,6n),line) ++ "\n"
		case True{} True{} _ _ _ _ _: line ++ "\n" ++ Hook.entry(kind)
		case True{} False{} True{} _ _ _ _: line ++ "\n" ++ Hook.loop(kind)
		case True{} False{} False{} True{} _ _ _: Hook.return(kind) ++ line ++ "\n"
		case True{} False{} False{} False{} True{} _ _: "    DDA_COUNT(14,1);\n" ++ line ++ "\n"
		case True{} False{} False{} False{} False{} True{} _: "    DDA_COUNT(15,1);\n" ++ line ++ "\n"
		case True{} False{} False{} False{} False{} False{} True{}: "      DDA_COUNT(8,1);\n      DDA_COUNT(9,_low_1 == _high_1);\n      DDA_COUNT(17,_mid_0 == 0);\n" ++ line ++ "\n"
		case _ _ _ _ _ _ _: line ++ "\n"

def Hook.line(+line: String, +kind: String, counters: Bool) -> String:
	Hook.output(counters,String.starts_with(line,"INLINE Term spin_") || String.starts_with(line,"FAR Term spin_"),
		String.eq(line,"  WL_SPIN") || String.eq(line,"    WL_SPIN"),String.eq(line,"  return 1;"),
		String.contains(line,"term_pak(CID_PIX,"),String.contains(line,"term_ctr(CID_QUA,"),
		String.eq(kind,"count") && String.contains(line,"u32 _before_0 ="),line,kind)

def Hook.lines(lines: List<&2,String>, +symbols: Symbols, +counters: Bool, kind: String) -> List<&2,String>:
	match lines:
		case Nil{}: Nil{}
		case Con{+line,rest}:
			+next = Hook.kind(line,symbols,kind)
			Hook.line(line,next,counters) <> Hook.lines(rest,symbols,counters,next)

def Read.result(result: File & Result<&1,&1,U32 & String,String>) -> IO(String):
	(file,status) = result
	do IO<String>:
		File.close(file)
		IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))

def Write(valid: Bool, +source: String, output: String, +mode: String) -> IO(Unit):
	match valid:
		case False{}: IO.die(Unit,1,"Emitted function map differs; inspect C and update Symbols and anchors first")
		case True{}:
			+counters = String.eq(mode,"counters")
			prefix = Bool.pick(String,counters,Hook.header(),"")
			do IO<Unit>:
				file : File <- IO.try(File,File.open(output,"w"))
				written : File & Result<&1,&1,U32 & String,Unit> <- File.write(file,prefix ++ String.join(Hook.lines(String.split(source,'\n'),Symbols.accepted(),counters,""),""))
				file : File <- D.Dump.written(written)
				File.close(file)

def Run(input: String, output: String, mode: String) -> IO(Unit):
	do IO<Unit>:
		file : File <- IO.try(File,File.open(input,"r"))
		read : File & Result<&1,&1,U32 & String,String> <- File.read(file,8388608)
		+source : String <- Read.result(read)
		Write(U32.is_eq(Hook.validate(String.split(source,'\n'),Symbols.accepted(),"",0),255),source,output,mode)

def Args.valid(valid: Bool, input: String, output: String, mode: String) -> IO(Unit):
	match valid:
		case True{}: Run(input,output,mode)
		case False{}: IO.die(Unit,1,"Mode must be counters or profile")

def Args(args: List<String>) -> IO(Unit):
	match args:
		case Con{program,Con{input,Con{output,Con{+mode,Nil{}}}}}:
			Args.valid(String.eq(mode,"counters") || String.eq(mode,"profile"),input,output,mode)
		case _: IO.die(Unit,1,"Usage: dda-profile input.c output.c counters|profile")

def main() -> IO(Unit):
	IO.bind(List<String>,Unit,IO.args(),Args)
