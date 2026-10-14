import Base
import ../main.bend as App
import ../voxel.bend as V
import ../dump.bend as D
import ../render.bend as R

def Cuboid.volume(box: V.Cuboid) -> U32:
  V.Cuboid{V.Cell{x,y,z},V.Cell{hx,hy,hz},material} = box
  ((hx - x) * (hy - y) * (hz - z) : U32)

def Cuboid.disjoint(a: V.Cuboid,b: V.Cuboid) -> Bool:
  V.Cuboid{V.Cell{+x,+y,+z},V.Cell{+hx,+hy,+hz},material} = a
  V.Cuboid{V.Cell{+bx,+by,+bz},V.Cell{+bhx,+bhy,+bhz},other} = b
  ((hx <= bx) || (bhx <= x) || (hy <= by) || (bhy <= y) || (hz <= bz) || (bhz <= z) : U32)

def Cuboid.valid(box: V.Cuboid) -> Bool:
  V.Cuboid{V.Cell{+x,+y,+z},V.Cell{+hx,+hy,+hz},material} = box
  ((x < hx) && (y < hy) && (z < hz) && (hx <= 440) && (hy <= 340) && (hz <= 93) : U32) && U32.is_ne(material,0)

def Boxes.disjoint(boxes: List<&2,V.Cuboid>,+box: V.Cuboid) -> Bool:
  match boxes:
    case Nil{}: True{}
    case item <> rest: Cuboid.disjoint(item,box) && Boxes.disjoint(rest,box)

def Boxes.valid(boxes: List<&2,V.Cuboid>) -> Bool:
  match boxes:
    case Nil{}: True{}
    case +box <> +rest: Cuboid.valid(box) && Boxes.disjoint(rest,box) && Boxes.valid(rest)

def Boxes.volume(boxes: List<&2,V.Cuboid>,total: U32) -> U32:
  match boxes:
    case Nil{}: total
    case box <> rest: Boxes.volume(rest,(total + Cuboid.volume(box) : U32))

def Body.measure(body: V.Body) -> V.Body & U32 & Bool:
  match body:
    case V.Body{side,cells}: (V.Body{side,cells},0,False{})
    case V.Cuboids{+boxes}: (V.Cuboids{boxes},Boxes.volume(boxes,0),Boxes.valid(boxes))

def Model.measured(result: V.Body & U32 & Bool,surface: V.Surface,scene: R.RenderScene,camera: R.Camera,controls: App.Controls,pointer: App.Pointer,previous: Maybe<&2,Nat>,dirty: Bool,tile_depth: Nat,fork_depth: Nat) -> App.Model & U32 & Bool:
  (body,count,valid) = result
  (App.Model{body,surface,scene,camera,controls,pointer,previous,dirty,tile_depth,fork_depth},count,valid)

def Model.measure(model: App.Model) -> App.Model & U32 & Bool:
  App.Model{body,surface,scene,camera,controls,pointer,previous,dirty,tile_depth,fork_depth} = model
  Model.measured(Body.measure(body),surface,scene,camera,controls,pointer,previous,dirty,tile_depth,fork_depth)

def Require.ok(ok: Bool,message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,message)

def Image.child(image: Image,index: U32) -> Image:
  match image index:
    case Pix{color} _: Pix{color}
    case Qua{a,b,c,d} 0: a
    case Qua{a,b,c,d} 1: b
    case Qua{a,b,c,d} 2: c
    case Qua{a,b,c,d} _: d

def Image.changed(+depth: Nat,a: Image,b: Image) -> U32:
  match depth a b:
    case 0n Pix{x} Pix{y}: Bool.to_u32(U32.is_ne(x,y))
    case 0n _ _: 0
    case 1n+rest +a +b:
      (Image.changed(rest,Image.child(a,0),Image.child(b,0)) +
       Image.changed(rest,Image.child(a,1),Image.child(b,1)) +
       Image.changed(rest,Image.child(a,2),Image.child(b,2)) +
       Image.changed(rest,Image.child(a,3),Image.child(b,3)) : U32)

def Export.opening(result: App.Model & Image) -> IO(App.Model & Image):
  (model,+image) = result
  do IO<App.Model & Image>:
    D.Dump.ppm("build/atelier-evidence/opening.ppm",image)
    return (model,image)

def Run.reset_drawn(result: App.Model & Image,before: Image) -> IO(Unit):
  (model,+image) = result
  do IO<Unit>:
    Require.ok(U32.is_eq(Image.changed(9n,before,image),0),"Reset changed the opening pixels")
    D.Dump.ppm("build/atelier-evidence/reset.ppm",image)

def Run.reset(result: App.Model & U32 & Bool,+original: U32,before: Image) -> IO(Unit):
  (model,+count,valid) = result
  do IO<Unit>:
    Require.ok(valid && U32.is_eq(count,original),"Reset differs from the original scene")
    Run.reset_drawn(App.Model.view(model),before)
    IO.print("reset occupied=" ++ U32.show(count) ++ " changed_pixels=0")

def Run.cut_drawn(result: App.Model & Image,+original: U32,+before: Image) -> IO(Unit):
  (model,+image) = result
  do IO<Unit>:
    Require.ok((Image.changed(9n,before,image) > 0 : U32),"The carved silhouette did not change the opening pixels")
    D.Dump.ppm("build/atelier-evidence/cut.ppm",image)
    IO.print("cut changed_pixels=" ++ U32.show(Image.changed(9n,before,image)))
    Run.reset(Model.measure(App.Model.reset(model)),original,before)

def Run.cut(result: App.Model & U32 & Bool,+original: U32,before: Image) -> IO(Unit):
  (model,+count,valid) = result
  do IO<Unit>:
    Require.ok(valid && (count < original : U32),"Click did not carve the scene")
    IO.print("cut occupied=" ++ U32.show(count) ++ " removed=" ++ U32.show((original - count : U32)))
    Run.cut_drawn(App.Model.view(model),original,before)

def Run.opened(result: App.Model & Image,+count: U32) -> IO(Unit):
  (model,image) = result
  Run.cut(Model.measure(App.Model.click(model,226,224)),count,image)

def Run.opening(result: App.Model & U32 & Bool) -> IO(Unit):
  (model,+count,valid) = result
  do IO<Unit>:
    Require.ok(valid && U32.is_eq(count,803970),"Light Atelier occupancy or disjointness differs from source")
    opened : App.Model & Image <- Export.opening(App.Model.view(model))
    IO.print("opening occupied=" ++ U32.show(count))
    Run.opened(opened,count)

def Output.created(result: U32 & (String & String)) -> IO(Unit):
  (status,streams) = result
  Require.ok(U32.is_eq(status,0),"Cannot create the scene evidence directory")

def main() -> IO(Unit):
  do IO<Unit>:
    result : U32 & (String & String) <- IO.try(U32 & (String & String),Process.run("mkdir",["-p","build/atelier-evidence"],"",4096,3000))
    Output.created(result)
    Run.opening(Model.measure(App.Model.init(6n,6n)))
