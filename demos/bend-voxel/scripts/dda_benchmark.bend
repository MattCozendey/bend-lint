import Base
import ../main.bend as M
import ../render.bend as R
import ./dda_compare.bend as C
import ./benchmark.bend as B
import ./benchmark_number.bend as N
import ./benchmark_host.bend as H

type Work is Data:
	Work{renderer: String, scene: C.Scene, samples: List<&2,N.Binary64>}

def Sample.finish(+renderer: String, samples: List<&2,N.Binary64>, +frames: U32, repeat: U32, start: Nat, finish: Nat, result: Window & C.Scene) -> IO(Window & Work):
	(window,scene) = result
	do IO<Window & Work>:
		elapsed : N.Elapsed <- H.Host.result(N.Elapsed,N.Elapsed.read(Nat.show(Nat.sub(finish,start))),"Elapsed time")
		+value : N.Binary64 <- H.Host.result(N.Binary64,N.Number.sample(elapsed,frames),"Frame sample")
		IO.print("renderer=" ++ renderer ++ " repeat=" ++ U32.show(repeat) ++ " frames=" ++ U32.show(frames) ++ " ms/frame=" ++ N.Number.fixed3(value))
		return (window,Work{renderer,scene,value <> samples})

def Sample(+frames: U32, +fork: Nat, repeat: U32, window: Window, work: Work) -> IO(Window & Work):
	Work{renderer,scene,samples} = work
	do IO<Window & Work>:
		warm : Window & C.Scene <- C.Frames(4n,fork,(window,scene))
		start : Nat <- IO.now()
		result : Window & C.Scene <- C.Frames(U32.to_nat(frames),fork,warm)
		finish : Nat <- IO.now()
		Sample.finish(renderer,samples,frames,repeat,start,finish,result)

def Sample.prepend(work: Work, result: Window & List<&2,Work>) -> Window & List<&2,Work>:
	(window,rest) = result
	(window,work <> rest)

def Sample.rest(result: Window & Work, next: Window -> IO(Window & List<&2,Work>)) -> IO(Window & List<&2,Work>):
	(window,work) = result
	IO.bind(Window & List<&2,Work>,Window & List<&2,Work>,next(window),result => IO.pure(Window & List<&2,Work>,Sample.prepend(work,result)))

def Samples(works: List<&2,Work>, window: Window, +frames: U32, +fork: Nat, +repeat: U32) -> IO(Window & List<&2,Work>):
	match works:
		case Nil{}: IO.pure(Window & List<&2,Work>,(window,Nil{}))
		case work <> rest:
			IO.bind(Window & Work,Window & List<&2,Work>,Sample(frames,fork,repeat,window,work),result => Sample.rest(result,w => Samples(rest,w,frames,fork,repeat)))

def Repeats.next(result: Window & List<&2,Work>, next: Window -> List<&2,Work> -> IO(Window & List<&2,Work>)) -> IO(Window & List<&2,Work>):
	(window,works) = result
	next(window,List.reverse(&2,Work,works))

def Repeats(fuel: Nat, +repeat: U32, +frames: U32, +fork: Nat, state: Window & List<&2,Work>) -> IO(Window & List<&2,Work>):
	match fuel:
		case 0n: IO.pure(Window & List<&2,Work>,state)
		case 1n+rest:
			(window,works) = state
			IO.bind(Window & List<&2,Work>,Window & List<&2,Work>,Samples(works,window,frames,fork,repeat),
				result => Repeats.next(result,w => ws => Repeats(rest,(repeat + 1 : U32),frames,fork,(w,ws))))

def Values(values: List<&2,N.Binary64>) -> String:
	match values:
		case Nil{}: ""
		case head <> rest: N.Number.json(head) ++ " " ++ Values(rest)

def Bounds(values: List<&2,N.Binary64>, +low: N.Binary64, +high: N.Binary64) -> String:
	match values:
		case Nil{}: N.Number.json(low) ++ "\t" ++ N.Number.json(high)
		case +head <> rest:
			Bounds(rest,Bool.pick(N.Binary64,B.Rows.le(head,low),head,low),Bool.pick(N.Binary64,B.Rows.le(high,head),head,high))

def Range(values: List<&2,N.Binary64>) -> String:
	match values:
		case Nil{}: "0\t0"
		case +head <> rest: Bounds(rest,head,head)

def Report.rows(works: List<&2,Work>, +label: String, text: String) -> IO(String):
	match works:
		case Nil{}: IO.pure(String,text)
		case Work{renderer,scene,+samples} <> rest:
			do IO<String>:
				median : N.Binary64 <- H.Host.result(N.Binary64,B.Rows.median(samples),"Median")
				Report.rows(rest,label,text ++ label ++ "\t" ++ renderer ++ "\t" ++ N.Number.json(median) ++ "\t" ++ Range(samples) ++ "\t" ++ Values(List.reverse(&2,N.Binary64,samples)) ++ "\n")

def Report(+output: String, label: String, result: Window & List<&2,Work>) -> IO(Unit):
	(window,works) = result
	do IO<Unit>:
		Window.close(window)
		text : String <- Report.rows(works,label,"configuration\trenderer\tmedian_ms\tmin_ms\tmax_ms\tsamples_ms\n")
		H.Host.mkdir(output)
		H.Host.write(output,text)
		IO.print("Saved " ++ output)

def Work.steps(steps: Bool, cube: Bool, cut: Bool, camera: R.Camera, tile: Nat, works: List<&2,Work>) -> List<&2,Work>:
	match steps:
		case False{}: works
		case True{}: Work{"dda-step",C.Scene.build("dda-step",C.Body(cube,cut),camera,tile),Nil{}} <> works

def Run(+args: List<&2,String>) -> IO(Unit):
	+frames = M.Options.number(M.Options.flag(args,"--frames",False{}),12)
	+repeats = M.Options.number(M.Options.flag(args,"--repeats",False{}),5)
	+tile = M.Options.depth(M.Options.flag(args,"--tile-depth",False{}),6)
	+fork = M.Options.depth(M.Options.flag(args,"--fork-depth",False{}),6)
	+cube = M.Options.has(args,"--cube")
	+cut = M.Options.has(args,"--cut")
	+camera = C.Camera("opening",cube)
	output = Maybe.default(&2,String,M.Options.flag(args,"--output",False{}),"build/dda-benchmark.tsv")
	label = Maybe.default(&2,String,M.Options.flag(args,"--label",False{}),"runtime")
	do IO<Unit>:
		H.Host.require((frames >= 1 : U32) && (repeats >= 5 : U32),"Use at least one frame and five repetitions")
		dda : List<&2,Work> <- IO.pure(List<&2,Work>,[Work{"dda",C.Scene.build("dda",C.Body(cube,cut),camera,tile),Nil{}}])
		faces : List<&2,Work> <- IO.pure(List<&2,Work>,List.append(&2,Work,dda,[Work{"faces",C.Scene.build("faces",C.Body(cube,cut),camera,tile),Nil{}}]))
		existing : List<&2,Work> <- IO.pure(List<&2,Work>,List.append(&2,Work,faces,[Work{"existing",C.Scene.build("existing",C.Body(cube,cut),camera,tile),Nil{}}]))
		window : Window <- IO.try(Window,Window.open("Bend DDA comparison",512,512))
		works : List<&2,Work> <- IO.pure(List<&2,Work>,Work.steps(M.Options.has(args,"--steps"),cube,cut,camera,tile,existing))
		result : Window & List<&2,Work> <- Repeats(U32.to_nat(repeats),1,frames,fork,(window,works))
		Report(output,label,result)

def main() -> IO(Unit):
	IO.bind(List<String>,Unit,IO.args(),args => Run(M.Options.args(args)))
