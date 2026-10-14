import Base
import ./voxel.bend as V
import ./scene_data.bend as R
import ./scene_data.bend as S
import ./material.bend as M
import ./atelier_assets.bend as A

def box(+x: F32, +y: F32, +z: F32, dx: F32, dy: F32, dz: F32, material: U32) -> S.Box:
  S.Box{R.Vec{x,y,z},R.Vec{(x + dx : F32),(y + dy : F32),(z + dz : F32)},material}

def ground() -> List<&2,S.Box>:
  S.build([
    box((0.0 - 220.0 : F32),0.0,(0.0 - 140.0 : F32),440.0,1.0,340.0,M.foundation()),
    box((0.0 - 220.0 : F32),1.0,(0.0 - 140.0 : F32),440.0,2.0,340.0,M.plaster()),
    box((0.0 - 220.0 : F32),3.0,(0.0 - 140.0 : F32),3.0,1.0,340.0,M.frame()),
    box(217.0,3.0,(0.0 - 140.0 : F32),3.0,1.0,340.0,M.frame()),
    box((0.0 - 217.0 : F32),3.0,(0.0 - 140.0 : F32),434.0,1.0,3.0,M.frame()),
    box((0.0 - 217.0 : F32),3.0,197.0,434.0,1.0,3.0,M.frame())])

def wall.ribs(n: Nat, +i: U32, bs: List<&2,S.Box>) -> List<&2,S.Box>:
  match n:
    case 0n: bs
    case 1n+k:
      wall.ribs(k,(i + 1 : U32),
        box((0.0 - 188.0 + U32.to_f32(i) * 90.0 : F32),5.0,(0.0 - 104.0 : F32),3.0,85.0,3.0,M.frame()) <> bs)
def backdrop() -> List<&2,S.Box>:
  S.build(wall.ribs(5n,0,[
    box((0.0 - 190.0 : F32),3.0,(0.0 - 110.0 : F32),380.0,2.0,6.0,M.foundation()),
    box((0.0 - 190.0 : F32),5.0,(0.0 - 110.0 : F32),380.0,85.0,6.0,M.plaster()),
    box((0.0 - 194.0 : F32),90.0,(0.0 - 112.0 : F32),388.0,3.0,10.0,M.frame())]))

def canopy.slats(n: Nat, +i: U32, bs: List<&2,S.Box>) -> List<&2,S.Box>:
  match n:
    case 0n: bs
    case 1n+k:
      canopy.slats(k,(i + 1 : U32),
        box((0.0 - 180.0 : F32),62.0,(35.0 + U32.to_f32(i) * 14.0 : F32),65.0,3.0,3.0,M.frame()) <> bs)
def canopy() -> List<&2,S.Box>:
  S.build(canopy.slats(9n,0,[
    box((0.0 - 180.0 : F32),3.0,35.0,4.0,2.0,4.0,M.foundation()),
    box((0.0 - 119.0 : F32),3.0,35.0,4.0,2.0,4.0,M.foundation()),
    box((0.0 - 180.0 : F32),3.0,146.0,4.0,2.0,4.0,M.foundation()),
    box((0.0 - 119.0 : F32),3.0,146.0,4.0,2.0,4.0,M.foundation()),
    box((0.0 - 180.0 : F32),5.0,35.0,4.0,53.0,4.0,M.frame()),
    box((0.0 - 119.0 : F32),5.0,35.0,4.0,53.0,4.0,M.frame()),
    box((0.0 - 180.0 : F32),5.0,146.0,4.0,53.0,4.0,M.frame()),
    box((0.0 - 119.0 : F32),5.0,146.0,4.0,53.0,4.0,M.frame()),
    box((0.0 - 180.0 : F32),58.0,35.0,4.0,4.0,115.0,M.frame()),
    box((0.0 - 119.0 : F32),58.0,35.0,4.0,4.0,115.0,M.frame())]))

type Assembly is Data:
  Assembly{tree: List<&2,S.Box>}
def translate.box(b: S.Box, +delta: R.Vec) -> S.Box:
  S.Box{l,h,m} = b
  S.Box{R.Vec.add(l,delta),R.Vec.add(h,delta),m}
def translate(t: List<&2,S.Box>, +delta: R.Vec) -> List<&2,S.Box>:
  match t:
    case Nil{}: Nil{}
    case b <> rest: translate.box(b,delta) <> translate(rest,delta)
def generate() -> List<&2,Assembly>:
  [Assembly{ground()},
   Assembly{backdrop()},
   Assembly{canopy()},
   Assembly{translate(A.suzanne(),R.Vec{(0.0 - 75.0 : F32),3.0,15.0})},
   Assembly{translate(A.oculus(),R.Vec{5.0,3.0,(0.0 - 15.0 : F32)})},
   Assembly{translate(A.twist(),R.Vec{125.0,3.0,(0.0 - 25.0 : F32)})}]


def cuboid(box: S.Box) -> V.Cuboid:
  S.Box{R.Vec{x,y,z},R.Vec{hx,hy,hz},material} = box
  V.Cuboid{V.Cell{F32.to_u32((x + 220.0 : F32)), F32.to_u32((200.0 - hz : F32)), F32.to_u32(y)},
    V.Cell{F32.to_u32((hx + 220.0 : F32)), F32.to_u32((200.0 - z : F32)), F32.to_u32(hy)},material}

def cuboids(boxes: List<&2,S.Box>, tail: List<&2,V.Cuboid>) -> List<&2,V.Cuboid>:
  match boxes:
    case Nil{}: tail
    case box <> rest: cuboid(box) <> cuboids(rest,tail)

def assemblies(items: List<&2,Assembly>) -> List<&2,V.Cuboid>:
  match items:
    case Nil{}: Nil{}
    case Assembly{boxes} <> rest: cuboids(boxes,assemblies(rest))

def body() -> V.Body:
  V.Cuboids{assemblies(generate())}
