import Base
import ../dda.bend as X
import ../voxel.bend as V
import ../render.bend as R
import ../lighting.bend as L
import ../atelier.bend as A
import ../main.bend as M
import ../dump.bend as D

type Scene is Data:
	Dda{skip: Bool, grid: X.Grid, basis: R.Basis, palette: X.Palette, ground: R.GroundLighting}
	Faces{tiles: R.Tiles, basis: R.Basis, ground: R.GroundLighting}
	Existing{scene: R.RenderScene}

type Counts is Data:
	Counts{rays: U32, hits: U32, misses: U32, depth: U32, cells: U32, directions: U32, colors: U32, max_depth: F32}

def Require(valid: Bool, message: String) -> IO(Unit):
	match valid:
		case True{}: IO.pure(Unit,Unit{})
		case False{}: IO.die(Unit,1,message)

def Scene.grid(skip: Bool, camera: R.Camera, result: V.Body & X.Grid) -> Scene:
	(body,grid) = result
	Dda{skip,grid,R.Camera.basis(camera),X.Palette.build(),X.Ground()}

def Scene.surface(shadows: Bool, +camera: R.Camera, tile: Nat, result: V.Body & V.Surface) -> Scene:
	match shadows:
		case True{}:
			(body,surface) = result
			Existing{R.RenderScene.build(surface,camera,tile)}
		case False{}:
			(body,surface) = result
			V.Surface{faces} = surface
			+basis = R.Camera.basis(camera)
			Faces{R.Tiles.build(tile,R.Projected.list(faces,basis,L.Palette.build(),0),0,0,512),basis,X.Ground()}

def Scene.build(renderer: String, body: V.Body, camera: R.Camera, tile: Nat) -> Scene:
	match renderer:
		case "dda": Scene.grid(True{},camera,X.Grid.build(body))
		case "dda-step": Scene.grid(False{},camera,X.Grid.build(body))
		case "faces": Scene.surface(False{},camera,tile,V.Surface.build(body))
		case _: Scene.surface(True{},camera,tile,V.Surface.build(body))

def Scene.draw(+scene: Scene, fork: Nat) -> Scene & Image:
	match scene:
		case Dda{skip,grid,basis,palette,ground}:
			(scene,X.Frame.fork!(fork,skip,grid,basis,palette,ground,0,0,512))
		case Faces{tiles,basis,ground}:
			(scene,R.Tiles.image!(fork,ground,basis,None{},tiles))
		case Existing{R.RenderScene{basis,tiles,count,cache}}:
			(scene,R.Tiles.image!(fork,R.LightingCache.ground(cache),basis,None{},tiles))

def Frame.shown(scene: Scene, shown: Window & Image & List<Event>) -> IO(Window & Scene):
	(window,image,events) = shown
	do IO<Window & Scene>:
		Unit <- IO.pure(Unit,Image.drop!(image))
		return (window,scene)

def Frame.drawn(window: Window, drawn: Scene & Image) -> IO(Window & Scene):
	(scene,image) = drawn
	IO.bind(Window & Image & List<Event>,Window & Scene,Window.frame(window,image),Frame.shown(scene))

def Frames(fuel: Nat, +fork: Nat, state: Window & Scene) -> IO(Window & Scene):
	match fuel:
		case 0n: IO.pure(Window & Scene,state)
		case 1n+rest:
			(window,scene) = state
			IO.bind(Window & Scene,Window & Scene,Frame.drawn(window,Scene.draw(scene,fork)),next => Frames(rest,fork,next))

def Bench.finish(start: Nat, finish: Nat, frames: Nat, result: Window & Scene) -> IO(Unit):
	(window,scene) = result
	do IO<Unit>:
		Window.close(window)
		IO.print("frames=" ++ Nat.show(frames) ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finish,start)))

def Bench(+frames: Nat, +fork: Nat, scene: Scene) -> IO(Unit):
	do IO<Unit>:
		window : Window <- IO.try(Window,Window.open("Bend DDA comparison",512,512))
		warm : Window & Scene <- Frames(4n,fork,(window,scene))
		start : Nat <- IO.now()
		result : Window & Scene <- Frames(frames,fork,warm)
		finish : Nat <- IO.now()
		Bench.finish(start,finish,frames,result)

def Profile.shown(start: Nat, +rendered: Nat, scene: Scene, shown: Window & Image & List<Event>) -> IO(Unit):
	(window,image,events) = shown
	do IO<Unit>:
		+presented : Nat <- IO.now()
		Unit <- IO.pure(Unit,Image.drop!(image))
		finish : Nat <- IO.now()
		Window.close(window)
		IO.print("render_ms=" ++ Nat.show(Nat.sub(rendered,start)) ++ " present_ms=" ++ Nat.show(Nat.sub(presented,rendered)) ++ " dispose_ms=" ++ Nat.show(Nat.sub(finish,presented)))

def Profile.drawn(start: Nat, window: Window, drawn: Scene & Image) -> IO(Unit):
	(scene,image) = drawn
	do IO<Unit>:
		rendered : Nat <- IO.now()
		shown : Window & Image & List<Event> <- Window.frame(window,image)
		Profile.shown(start,rendered,scene,shown)

def Profile.ready(fork: Nat, state: Window & Scene) -> IO(Unit):
	(window,scene) = state
	do IO<Unit>:
		start : Nat <- IO.now()
		drawn : Scene & Image <- IO.pure(Scene & Image,Scene.draw(scene,fork))
		Profile.drawn(start,window,drawn)

def Profile(+fork: Nat, scene: Scene) -> IO(Unit):
	do IO<Unit>:
		window : Window <- IO.try(Window,Window.open("Bend DDA phase profile",512,512))
		warm : Window & Scene <- Frames(4n,fork,(window,scene))
		Profile.ready(fork,warm)

def Measure(profile: Bool, frames: Nat, fork: Nat, scene: Scene) -> IO(Unit):
	match profile:
		case True{}: Profile(fork,scene)
		case False{}: Bench(frames,fork,scene)

def Dump(path: String, drawn: Scene & Image) -> IO(Unit):
	(scene,image) = drawn
	D.Dump.ppm(path,image)

def Cells.equal(a: Maybe<&2,V.Cell>, b: Maybe<&2,V.Cell>) -> Bool:
	match a b:
		case None{} None{}: True{}
		case Some{V.Cell{x,y,z}} Some{V.Cell{rx,ry,rz}}:
			U32.is_eq(x,rx) && U32.is_eq(y,ry) && U32.is_eq(z,rz)
		case _ _: False{}

def Directions.equal(a: V.Direction, b: V.Direction) -> Bool:
	match a b:
		case V.NegX{} V.NegX{}: True{}
		case V.PosX{} V.PosX{}: True{}
		case V.NegY{} V.NegY{}: True{}
		case V.PosY{} V.PosY{}: True{}
		case V.NegZ{} V.NegZ{}: True{}
		case V.PosZ{} V.PosZ{}: True{}
		case _ _: False{}

def Counts.pixel(dda: R.Hit, reference: R.Hit, counts: Counts) -> Counts:
	R.Hit{dt,dc,id,+cell,direction} = dda
	R.Hit{rt,rc,rid,+reference_cell,reference_direction} = reference
	Counts{rays,hits,misses,depth,cells,directions,colors,max_depth} = counts
	+both = Maybe.is_some(&2,V.Cell,cell) && Maybe.is_some(&2,V.Cell,reference_cell)
	+distance = Bool.pick(F32,both,F32.abs((dt - rt : F32)),0.0)
	Counts{(rays + 1 : U32),(hits + Bool.to_u32(Maybe.is_some(&2,V.Cell,cell)) : U32),
		(misses + Bool.to_u32(U32.is_ne(Bool.to_u32(Maybe.is_some(&2,V.Cell,cell)),Bool.to_u32(Maybe.is_some(&2,V.Cell,reference_cell)))) : U32),
		(depth + Bool.to_u32((distance > 0.001 : F32)) : U32),
		(cells + Bool.to_u32(Bool.not(Cells.equal(cell,reference_cell))) : U32),
		(directions + Bool.to_u32(both && Bool.not(Directions.equal(direction,reference_direction))) : U32),
		(colors + Bool.to_u32(U32.is_ne(dc,rc)) : U32),F32.max(max_depth,distance)}

def Compare.scan(fuel: Nat, +grid: X.Grid, +tiles: R.Tiles, +basis: R.Basis, +palette: X.Palette, +index: U32, counts: Counts) -> Counts:
	match fuel:
		case 0n: counts
		case 1n+rest:
			R.Basis{eye,right,up,forward,focal,near} = basis
			+x = (index % 512 : U32)
			+y = (index / 512 : U32)
			+ray = R.Pixel.ray(basis,x,y)
			Compare.scan(rest,grid,tiles,basis,palette,(index + 1 : U32),Counts.pixel(
				X.Pixel.hit(X.Trace.ray(grid,eye,ray,near),palette,R.Hit.background(x,y)),
				R.Tiles.hit(tiles,ray,near,x,y,512,(x >= 256 : U32),(y >= 256 : U32)),counts))

def Compare.report(counts: Counts) -> IO(Unit):
	Counts{rays,hits,+misses,+depth,cells,directions,colors,max_depth} = counts
	do IO<Unit>:
		IO.print("rays=" ++ U32.show(rays) ++ " dda_hits=" ++ U32.show(hits) ++ " occupancy_mismatches=" ++ U32.show(misses) ++ " depth_mismatches=" ++ U32.show(depth) ++ " cell_mismatches=" ++ U32.show(cells) ++ " direction_mismatches=" ++ U32.show(directions) ++ " color_mismatches=" ++ U32.show(colors) ++ " max_depth_error=" ++ F32.show(max_depth))
		Require(U32.is_zero(misses) && U32.is_zero(depth),"DDA and existing surface geometry disagree")

def Compare.scenes(grid: Scene, reference: Scene) -> IO(Unit):
	match grid reference:
		case Dda{skip,grid,basis,palette,ground} Faces{tiles,reference_basis,reference_ground}:
			IO.bind(Counts,Unit,IO.pure(Counts,Compare.scan(262144n,grid,tiles,basis,palette,0,Counts{0,0,0,0,0,0,0,0.0})),Compare.report)
		case _ _: IO.die(Unit,1,"Invalid comparison scenes")

def Compare.body(+camera: R.Camera, tile: Nat, result: V.Body & X.Grid) -> IO(Unit):
	(body,grid) = result
	Compare.scenes(Dda{True{},grid,R.Camera.basis(camera),X.Palette.build(),X.Ground()},Scene.build("faces",body,camera,tile))

def Surface.equal(a: Maybe<&2,X.SurfaceHit>, b: Maybe<&2,X.SurfaceHit>) -> Bool:
	match a b:
		case None{} None{}: True{}
		case Some{X.SurfaceHit{depth,cell,direction,material}} Some{X.SurfaceHit{rd,rc,rdir,rm}}:
			F32.is_eq(depth,rd) && Cells.equal(Some{cell},Some{rc}) && Directions.equal(direction,rdir) && U32.is_eq(material,rm)
		case _ _: False{}

def Compare.steps.scan(fuel: Nat, +grid: X.Grid, +basis: R.Basis, +index: U32, mismatches: U32) -> U32:
	match fuel:
		case 0n: mismatches
		case 1n+rest:
			R.Basis{+eye,right,up,forward,focal,+near} = basis
			+ray = R.Pixel.ray(basis,(index % 512 : U32),(index / 512 : U32))
			Compare.steps.scan(rest,grid,basis,(index + 1 : U32),(mismatches + Bool.to_u32(Bool.not(Surface.equal(
				X.Trace.mode(True{},grid,eye,ray,near),X.Trace.mode(False{},grid,eye,ray,near)))) : U32))

def Compare.steps.report(+mismatches: U32) -> IO(Unit):
	do IO<Unit>:
		IO.print("rays=262144 exact_surface_mismatches=" ++ U32.show(mismatches))
		Require(U32.is_zero(mismatches),"Region traversal and unit DDA disagree")

def Compare.steps(camera: R.Camera, result: V.Body & X.Grid) -> IO(Unit):
	(body,grid) = result
	IO.bind(U32,Unit,IO.pure(U32,Compare.steps.scan(262144n,grid,R.Camera.basis(camera),0,0)),mismatches => Compare.steps.report(mismatches))

def Body(cube: Bool, cut: Bool) -> V.Body:
	match cube cut:
		case True{} False{}: V.Body.solid(3n)
		case True{} True{}: V.Body.cut(V.Body.solid(3n),V.MetricSphere.demo())
		case False{} False{}: A.body()
		case False{} True{}: V.Body.cut(A.body(),V.MetricSphere.brush(V.PointCm{2500.0,750.0,450.0}))

def Camera(view: String, cube: Bool) -> R.Camera:
	match view cube:
		case "inside" True{}: R.Camera{R.Vec3{4.5,4.5,4.5},0.0,0.0}
		case "axis" True{}: R.Camera{R.Vec3{18.0,4.5,4.5},3.14159265,0.0}
		case "opposite" True{}: R.Camera{R.Vec3{(0.0 - 10.0 : F32),(0.0 - 10.0 : F32),15.0},0.78539816,(0.0 - 0.5070985 : F32)}
		case _ True{}: R.Camera.initial()
		case _ False{}: R.Camera.atelier()

def Run.mode(verify: Bool, steps: Bool, dump: Maybe<&2,String>, +args: List<&2,String>, +renderer: String, +camera: R.Camera, tile: Nat, +fork: Nat, body: V.Body) -> IO(Unit):
	match verify steps dump:
		case _ True{} _: Compare.steps(camera,X.Grid.build(body))
		case True{} False{} _: Compare.body(camera,tile,X.Grid.build(body))
		case False{} False{} Some{path}:
			do IO<Unit>:
				scene : Scene <- IO.pure(Scene,Scene.build(renderer,body,camera,tile))
				barrier : Nat <- IO.now()
				Dump(path,Scene.draw(scene,fork))
		case False{} False{} None{}:
			do IO<Unit>:
				start : Nat <- IO.now()
				scene : Scene <- IO.pure(Scene,Scene.build(renderer,body,camera,tile))
				finish : Nat <- IO.now()
				IO.print("renderer=" ++ renderer ++ " init_ms=" ++ Nat.show(Nat.sub(finish,start)))
				Measure(M.Options.has(args,"--profile"),U32.to_nat(M.Options.number(M.Options.flag(args,"--bench",False{}),24)),fork,scene)

def Run(+args: List<&2,String>) -> IO(Unit):
	+cube = M.Options.has(args,"--cube")
	+renderer = Maybe.default(&2,String,M.Options.flag(args,"--renderer",False{}),"dda")
	+view = Maybe.default(&2,String,M.Options.flag(args,"--view",False{}),"opening")
	do IO<Unit>:
		Require(String.eq(renderer,"dda") || String.eq(renderer,"dda-step") || String.eq(renderer,"faces") || String.eq(renderer,"existing"),"Renderer must be dda, dda-step, faces, or existing")
		Require((M.Options.number(M.Options.flag(args,"--bench",False{}),24) >= 1 : U32),"Benchmark frames must be positive")
		Run.mode(M.Options.has(args,"--verify"),M.Options.has(args,"--verify-steps"),M.Options.flag(args,"--dump",False{}),args,renderer,Camera(view,cube),
			M.Options.depth(M.Options.flag(args,"--tile-depth",False{}),6),M.Options.depth(M.Options.flag(args,"--fork-depth",False{}),6),Body(cube,M.Options.has(args,"--cut")))

def main() -> IO(Unit):
	IO.bind(List<String>,Unit,IO.args(),args => Run(M.Options.args(args)))
