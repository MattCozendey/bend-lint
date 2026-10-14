# What Chocolate Doom is handed to replay a command script: a copy of
# the IWAD whose E1M1 starts the player where the script does, and the
# script as a vanilla demo. A script is runs a space apart, each
# "count,forward,side,turn,buttons" in a demo's units, but for the
# buttons: use 1, attack 2, a change of weapon 4 and eight times the
# weapon's number from 0 (the key 1 is 4, the key 2 is 12, the key 3 is
# 20). That is the demo's byte with its two low bits trading places,
# since the scripts written when use was the one button say 1 for it.
# Sourced by tools/oracle.nu and tools/listen.nu.

source wad.nu

# An integer's low bytes, little-endian.
def le [width: int]: int -> binary {
  $in | into binary | bytes at 0..<$width
}

# The IWAD with record i of E1M1's THINGS replaced in place by a thing
# of a type at x, y facing angle on every skill, and every other byte
# kept. A whole IWAD and not a PWAD, since Doom refuses -file with the
# shareware one.
def rewrite [i: int, x: int, y: int, angle: int, type: int]: binary -> binary {
  let wad = $in
  let at = ($wad | map-lump THINGS | get pos) + $i * 10
  let record = [($x | le 2) ($y | le 2) ($angle | le 2) ($type | le 2) (7 | le 2)] | bytes collect
  [($wad | bytes at 0..<$at) $record ($wad | bytes at ($at + 10)..)] | bytes collect
}

# The IWAD with player 1 starting at x, y facing angle, and the records
# things names, each "record,type,x,y", rewritten facing 0.
def placed [x: int, y: int, angle: int, things: string]: binary -> binary {
  let wad = $in
  $things | split row ' ' | where $it != '' | reduce --fold ($wad
    | rewrite ($wad | things | where type == 1 | first | get i) $x $y $angle 1) {|t, wad|
    let f = $t | split row ',' | into int
    $wad | rewrite $f.0 $f.2 $f.3 0 $f.1
  }
}

# A script's runs: how many tics, and the four bytes a demo keeps of the
# tic's command (G_ReadDemoTiccmd: forward, side, the turn's high byte,
# the buttons: BT_ATTACK 1, BT_USE 2, BT_CHANGE 4, the weapon from 8).
def runs []: string -> table<tics: int, bytes: binary> {
  $in | split row ' ' | each {|run|
    let f = $run | split row ',' | into int
    let buttons = ($f.4 bit-and 0xfc) + ($f.4 bit-and 1) * 2 + ($f.4 bit-and 2) // 2
    {tics: $f.0, bytes: ([($f.1 | le 1) ($f.2 | le 1) ($f.3 | le 1) ($buttons | le 1)] | bytes collect)}
  }
}

# The runs as a version 109 demo: the 13-byte header (Hurt Me Plenty,
# E1M1, no deathmatch, respawn, fast or -nomonsters, console player 0,
# player 1 alone in the game), the tics, and the 0x80 that ends a demo.
# Under -playdemo Chocolate Doom quits when it reads the end.
def demo []: table<tics: int, bytes: binary> -> binary {
  let tics = $in | each {|run| 0..<$run.tics | each { $run.bytes } } | flatten
  [0x[6d 02 01 01 00 00 00 00 00 01 00 00 00]]
  | append $tics
  | append 0x[80]
  | bytes collect
}
