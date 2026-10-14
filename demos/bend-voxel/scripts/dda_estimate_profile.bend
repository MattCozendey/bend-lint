import Base
import ./dda_profile.bend as P
import ../dump.bend as D

# CPU diagnostics for the corrected-estimate candidate emitted by Bend 2.0.34.
def Symbols() -> P.Symbols:
	P.Symbols{"","62","64","101","104","105","143","183"}

def Hook.header() -> String:
	"#include <stdint.h>\n#include <stdio.h>\n#include <stdatomic.h>\n" ++
	"static _Atomic uint64_t dda_counts[24];\n" ++
	"#define DDA_COUNT(i,n) atomic_fetch_add_explicit(&dda_counts[i], (uint64_t)(n), memory_order_relaxed)\n" ++
	"static const char *dda_names[] = {\"region_lookups\",\"outside_lookups\",\"tree_lookups\",\"tree_branches\",\"tree_leaves\",\"region_crossings\",\"axis_advance_calls\",\"axis_count_calls\",\"axis_count_iterations\",\"axis_count_collapsed_iterations\",\"trace_region_iterations\",\"rays\",\"final_hits\",\"final_misses\",\"image_pixels\",\"image_quads\",\"frame_roots\",\"axis_count_zero_mid_iterations\",\"plane_predicate_evaluations\",\"zero_event_predicate_evaluations\",\"estimate_up_steps\",\"estimate_down_steps\",\"correction_iterations\",\"correction_fuel_exhaustions\"};\n" ++
	"static void __attribute__((destructor)) dda_report(void) { for (int i=0;i<24;i++) fprintf(stderr, \"%s\\t%llu\\n\", dda_names[i], (unsigned long long)atomic_load(&dda_counts[i])); }\n"

def Hook.kind(+line: String, current: String) -> String:
	Bool.pick(String,P.Hook.spin(line,"46"),"estimate",
	Bool.pick(String,P.Hook.spin(line,"19"),"predicate",
	Bool.pick(String,P.Hook.spin(line,"26"),"correct",P.Hook.kind(line,Symbols(),current))))

def Hook.predicate(line: String) -> Bool:
	String.starts_with(line,"    _v_2 = ((U32_BIN(_count_1, ==, 0)) |")

def Hook.up(line: String) -> Bool:
	String.eq(line,"            u32 _next_1 = U32_BIN(_count_0, +, 1ull);")

def Hook.down(line: String) -> Bool:
	String.eq(line,"          u32 _next_0 = U32_BIN(_count_0, -, 1ull);")

def Hook.anchor(+kind: String, +line: String) -> U32:
	match kind:
		case "estimate": Bool.pick(U32,String.eq(line,"  u32 _limit_0 = r5;"),1,0)
		case "predicate": (Bool.pick(U32,String.eq(line,"  u32 _count_1 = r5;"),256,0) .|. Bool.pick(U32,Hook.predicate(line),1024,0) : U32)
		case "correct": (Bool.pick(U32,String.eq(line,"  u32 _limit_1 = r10;"),512,0) .|. Bool.pick(U32,Hook.up(line),2048,0) .|. Bool.pick(U32,Hook.down(line),4096,0) : U32)
		case _: P.Hook.anchor(kind,line)

def Hook.validate(lines: List<&2,String>, kind: String, found: U32) -> U32:
	match lines:
		case Nil{}: found
		case Con{+line,rest}:
			+next = Hook.kind(line,kind)
			Hook.validate(rest,next,(found .|. Hook.anchor(next,line) : U32))

def Hook.line(predicate: Bool, up: Bool, down: Bool, loop: Bool, exhausted: Bool, header: Bool, +line: String, +kind: String) -> String:
	match predicate up down loop exhausted header:
		case True{} _ _ _ _ _: "    DDA_COUNT(18,1);\n    DDA_COUNT(19,_count_1 == 0);\n" ++ line ++ "\n"
		case False{} True{} _ _ _ _: "            DDA_COUNT(20,1);\n" ++ line ++ "\n"
		case False{} False{} True{} _ _ _: "          DDA_COUNT(21,1);\n" ++ line ++ "\n"
		case False{} False{} False{} True{} _ _: line ++ "\n    DDA_COUNT(22,1);\n"
		case False{} False{} False{} False{} True{} _: line ++ "\n      DDA_COUNT(23,1);\n"
		case False{} False{} False{} False{} False{} True{}: line ++ "\n  DDA_COUNT(7,1);\n"
		case _ _ _ _ _ _: P.Hook.line(line,kind,True{})

def Hook.lines(lines: List<&2,String>, kind: String) -> List<&2,String>:
	match lines:
		case Nil{}: Nil{}
		case Con{+line,rest}:
			+next = Hook.kind(line,kind)
			Hook.line(String.eq(next,"predicate") && Hook.predicate(line),String.eq(next,"correct") && Hook.up(line),
				String.eq(next,"correct") && Hook.down(line),String.eq(next,"correct") && String.eq(line,"  WL_SPIN"),
				String.eq(next,"correct") && String.eq(line,"    if (_fuel_0 == 0) {"),String.eq(next,"estimate") && P.Hook.spin(line,"46"),line,next) <> Hook.lines(rest,next)

def Write(valid: Bool, source: String, output: String) -> IO(Unit):
	match valid:
		case False{}: IO.die(Unit,1,"Candidate function map or predicate sites differ; inspect emitted C first")
		case True{}:
			do IO<Unit>:
				file : File <- IO.try(File,File.open(output,"w"))
				written : File & Result<&1,&1,U32 & String,Unit> <- File.write(file,Hook.header() ++ String.join(Hook.lines(String.split(source,'\n'),""),""))
				file : File <- D.Dump.written(written)
				File.close(file)

def Run(input: String, output: String) -> IO(Unit):
	do IO<Unit>:
		file : File <- IO.try(File,File.open(input,"r"))
		read : File & Result<&1,&1,U32 & String,String> <- File.read(file,8388608)
		+source : String <- P.Read.result(read)
		Write(U32.is_eq(Hook.validate(String.split(source,'\n'),"",0),8191),source,output)

def Args(args: List<String>) -> IO(Unit):
	match args:
		case Con{program,Con{input,Con{output,Nil{}}}}: Run(input,output)
		case _: IO.die(Unit,1,"Usage: dda-estimate-profile input.c output.c")

def main() -> IO(Unit):
	IO.bind(List<String>,Unit,IO.args(),Args)
