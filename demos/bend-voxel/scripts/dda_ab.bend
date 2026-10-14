import Base
import ./benchmark.bend as B
import ./benchmark_number.bend as N
import ./benchmark_host.bend as H

type Samples is Data:
	Samples{accepted: List<&2,N.Binary64>, candidate: List<&2,N.Binary64>}

def Args.linear(args: List<&2,String>) -> List<String>:
	match args:
		case Nil{}: Nil{}
		case Con{head,rest}: head <> Args.linear(rest)

def Args.shared(args: List<String>) -> List<&2,String>:
	match args:
		case Nil{}: Nil{}
		case Con{head,rest}: head <> Args.shared(rest)

def Sample.line(valid: Bool, frames: String, elapsed: String) -> IO(N.Elapsed):
	match valid:
		case False{}: IO.die(N.Elapsed,1,"Invalid renderer measurement")
		case True{}: H.Host.result(N.Elapsed,N.Elapsed.read(String.drop(elapsed,11n)),"Elapsed time")

def Sample.tokens(tokens: List<&2,String>, +frames: String) -> IO(N.Elapsed):
	match tokens:
		case Con{+count,Con{+elapsed,Nil{}}}:
			Sample.line(String.eq(count,"frames=" ++ frames) && String.starts_with(elapsed,"elapsed_ms="),count,elapsed)
		case _: IO.die(N.Elapsed,1,"Missing renderer measurement")

def Sample.find.go(found: Bool, line: String, frames: String, next: Unit -> IO(N.Elapsed)) -> IO(N.Elapsed):
	match found:
		case True{}: Sample.tokens(String.split(line,' '),frames)
		case False{}: next(Unit{})

def Sample.find(lines: List<&2,String>, +frames: String) -> IO(N.Elapsed):
	match lines:
		case Nil{}: IO.die(N.Elapsed,1,"Renderer did not finish its measured frames")
		case Con{+line,rest}:
			Sample.find.go(String.starts_with(line,"frames="),line,frames,unit => Sample.find(rest,frames))

def Sample(program: String, +args: List<&2,String>, +frames: String, denominator: U32) -> IO(N.Binary64):
	do IO<N.Binary64>:
		+stdout : String <- H.Host.process("Native DDA renderer",program,Args.linear(args))
		IO.print(stdout)
		elapsed : N.Elapsed <- Sample.find(String.split(stdout,'\n'),frames)
		H.Host.result(N.Binary64,N.Number.sample(elapsed,denominator),"Frame time")

def Sample.pair(reverse: Bool, +accepted: String, +candidate: String, +args: List<&2,String>, +frames: String, +denominator: U32) -> IO(N.Binary64 & N.Binary64):
	match reverse:
		case False{}:
			do IO<N.Binary64 & N.Binary64>:
				a : N.Binary64 <- Sample(accepted,args,frames,denominator)
				b : N.Binary64 <- Sample(candidate,args,frames,denominator)
				return (a,b)
		case True{}:
			do IO<N.Binary64 & N.Binary64>:
				b : N.Binary64 <- Sample(candidate,args,frames,denominator)
				a : N.Binary64 <- Sample(accepted,args,frames,denominator)
				return (a,b)

def Repeats.next(old: List<&2,N.Binary64>, new: List<&2,N.Binary64>, pair: N.Binary64 & N.Binary64, next: Samples -> IO(Samples)) -> IO(Samples):
	(a,b) = pair
	next(Samples{a <> old,b <> new})

def Repeats(fuel: Nat, +reverse: Bool, +accepted: String, +candidate: String, +args: List<&2,String>, +frames: String, +denominator: U32, samples: Samples) -> IO(Samples):
	match fuel:
		case 0n: IO.pure(Samples,samples)
		case 1n+rest:
			Samples{old,new} = samples
			do IO<Samples>:
				pair : N.Binary64 & N.Binary64 <- Sample.pair(reverse,accepted,candidate,args,frames,denominator)
				Repeats.next(old,new,pair,samples => Repeats(rest,Bool.not(reverse),accepted,candidate,args,frames,denominator,samples))

def Values(values: List<&2,N.Binary64>) -> String:
	match values:
		case Nil{}: ""
		case Con{head,rest}: N.Number.json(head) ++ " " ++ Values(rest)

def Bounds(values: List<&2,N.Binary64>, +low: N.Binary64, +high: N.Binary64) -> String:
	match values:
		case Nil{}: N.Number.json(low) ++ "\t" ++ N.Number.json(high)
		case Con{+head,rest}:
			Bounds(rest,Bool.pick(N.Binary64,B.Rows.le(head,low),head,low),Bool.pick(N.Binary64,B.Rows.le(high,head),head,high))

def Range(values: List<&2,N.Binary64>) -> String:
	match values:
		case Nil{}: "0\t0"
		case Con{+head,rest}: Bounds(rest,head,head)

def Row(label: String, +values: List<&2,N.Binary64>) -> IO(String):
	do IO<String>:
		median : N.Binary64 <- H.Host.result(N.Binary64,B.Rows.median(values),"Median")
		return label ++ "\t" ++ N.Number.json(median) ++ "\t" ++ Range(values) ++ "\t" ++ Values(List.reverse(&2,N.Binary64,values)) ++ "\n"

def Report(+output: String, samples: Samples) -> IO(Unit):
	Samples{a,b} = samples
	do IO<Unit>:
		old : String <- Row("accepted",a)
		new : String <- Row("candidate",b)
		H.Host.mkdir(output)
		H.Host.write(output,"renderer\tmedian_ms\tmin_ms\tmax_ms\tsamples_ms\n" ++ old ++ new)
		IO.print("Saved " ++ output)

def Run(accepted: String, candidate: String, +threads: String, +gpu: String, +fork: String, +frames: String, output: String, extra: List<String>) -> IO(Unit):
	do IO<Unit>:
		+denominator : U32 <- IO.pure(U32,Maybe.default(&2,U32,U32.read(frames),0))
		H.Host.require((denominator >= 1 : U32),"Measured frames must be positive")
		samples : Samples <- Repeats(5n,False{},accepted,candidate,List.append(&2,String,
			["--gpu",gpu,"--threads",threads,"--","--renderer","dda","--fork-depth",fork,"--bench",frames],Args.shared(extra)),frames,denominator,Samples{Nil{},Nil{}})
		Report(output,samples)

def Args(args: List<String>) -> IO(Unit):
	match args:
		case Con{program,Con{accepted,Con{candidate,Con{threads,Con{gpu,Con{fork,Con{frames,Con{output,extra}}}}}}}}:
			Run(accepted,candidate,threads,gpu,fork,frames,output,extra)
		case _: IO.die(Unit,1,"Usage: dda-ab accepted candidate threads off|on fork-depth frames output.tsv [scene options]")

def main() -> IO(Unit):
	IO.bind(List<String>,Unit,IO.args(),Args)
