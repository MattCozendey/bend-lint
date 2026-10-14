# A vanilla version-109 demo, shared by the sim, renderer and Chocolate
# Doom. Its first 1453 tics collect the blue key, armour and a dropped
# shotgun after four kills. Every tic's random index and player state
# were compared with Chocolate Doom 3.1.1.
import Base
import ../../src/bytes.bend as B
import ../../src/demo.bend as D
import ../../src/keys.bend as K

def Route.chunk(bytes: List<&2, U32>, kept: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, kept, bytes)

def Route.read(path: String) -> IO(List<&2, K.Cmd>):
  do IO<List<&2, K.Cmd>>:
    file : File <- IO.try(File, File.open(path, "r"))
    bytes : List<&2, U32> <- B.Bytes.fold(~List<&2, U32>, ~Route.chunk, file, [])
    return D.Demo.play(bytes)

def Route.fight() -> IO(List<&2, K.Cmd>):
  do IO<List<&2, K.Cmd>>:
    cmds : List<&2, K.Cmd> <- Route.read("tests/fixtures/freedoom.lmp")
    return List.take(&2, K.Cmd, cmds, 1453n)
