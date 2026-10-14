# Doom's s_sound.c channels: the eight voices a level's sounds are
# allotted. They live outside the sim's state because vanilla frees a
# channel when the device has finished it and not on a tic. A channel is
# the open file of the sound it plays, the sound and the source that
# made it, and the left and right volumes the device was given for it.
# The mixer reads the files; this module allots them.
import Base
import ./sound.bend as Sn

# A playing sound, its file open at the frame the mixer writes next.
type Channel is Type:
  Chan{file: File, sfx: U32, source: Sn.Sound.Source, left: U32, right: U32}

# snd_channels at Chocolate Doom's default, every one free.
def Channel.none() -> List<Maybe<Channel>>:
  [None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}]

# One side of I_SDL_UpdateSoundParams: a share of the separation times
# the volume over 127, clamped to a byte.
def Channel.side(+share: U32, +vol: U32) -> U32:
  U32.min(((share * vol : U32) / 127 : U32), 255)

# Its left, ((254 - sep) * vol) / 127. A separation of 255 leaves the
# share below zero, which C divides toward zero and clamps to none, so
# the share stops at 0 here.
def Channel.left(+vol: U32, +sep: U32) -> U32:
  Channel.side((254 - U32.min(sep, 254) : U32), vol)

# Its right, (sep * vol) / 127.
def Channel.right(+vol: U32, +sep: U32) -> U32:
  Channel.side(sep, vol)

# The file the sounds node left for a sound, beside the others.
def Channel.path(+dir: String, +sfx: U32) -> String:
  dir ++ "/" ++ Sn.Sound.lump(Sn.Sound.table(), sfx) ++ ".raw"

def Channel.hush.gone(+hit: Bool, file: File, +sfx: U32, source: Sn.Sound.Source, +left: U32, +right: U32) ->
  IO(Maybe<Channel>):
  match hit:
    case True{}:
      do IO<Maybe<Channel>>:
        File.close(file)
        return None{}
    case False{}:
      IO.pure(Maybe<Channel>, Some{Chan{file, sfx, source, left, right}})

def Channel.hush.slot(+source: Sn.Sound.Source, c: Maybe<Channel>) -> IO(Maybe<Channel>):
  match c:
    case None{}:
      IO.pure(Maybe<Channel>, None{})
    case Some{Chan{file, sfx, +was, left, right}}:
      Channel.hush.gone(Sn.Sound.Source.same(source, was), file, sfx, was, left, right)

# S_StopSound: the source's channel is freed and its file closed. A
# source holds one channel at a time, so there is at most one to free.
def Channel.hush(+source: Sn.Sound.Source, chans: List<Maybe<Channel>>) -> IO(List<Maybe<Channel>>):
  match chans:
    case []:
      IO.pure(List<Maybe<Channel>>, [])
    case c <> rest:
      do IO<List<Maybe<Channel>>>:
        kept : Maybe<Channel> <- Channel.hush.slot(source, c)
        cs : List<Maybe<Channel>> <- Channel.hush(source, rest)
        return kept <> cs

# A sound with no channel to play it is dropped, and the file opened for
# it closes again.
def Channel.put.gone(new: Channel) -> IO(List<Maybe<Channel>>):
  Chan{file, sfx, source, left, right} = new
  do IO<List<Maybe<Channel>>>:
    File.close(file)
    return []

def Channel.put.here(new: Channel, rest: List<Maybe<Channel>>, old: Maybe<Channel>) ->
  IO(List<Maybe<Channel>>):
  match old:
    case None{}:
      IO.pure(List<Maybe<Channel>>, Some{new} <> rest)
    case Some{Chan{file, sfx, source, left, right}}:
      do IO<List<Maybe<Channel>>>:
        File.close(file)
        return Some{new} <> rest

# The sound put in the channel of that number, whose own sound stops,
# S_GetChannel's S_StopChannel. A number past the last channel is the
# sound dropped.
def Channel.put(chans: List<Maybe<Channel>>, n: Nat, new: Channel) -> IO(List<Maybe<Channel>>):
  match chans n:
    case [] _:
      Channel.put.gone(new)
    case c <> rest 0n:
      Channel.put.here(new, rest, c)
    case c <> rest 1n+m:
      do IO<List<Maybe<Channel>>>:
        cs : List<Maybe<Channel>> <- Channel.put(rest, m, new)
        return c <> cs

type Channel.Pick is Data:
  Pick{free: Nat, victim: Nat, size: Nat}

type Channel.Voice is Data:
  Voice{mine: Bool, priority: Nat}

def Channel.model.none() -> List<&2, Maybe<&2, Channel.Voice>>:
  [None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}]

def Channel.pick.busy(+take: Bool, p: Channel.Pick) -> Channel.Pick:
  Pick{free, victim, size} = p
  Pick{1n+free, Bool.pick(Nat, take, 0n, 1n+victim), 1n+size}

def Channel.pick.slot(+pri: Nat, c: Maybe<&2, Nat>, p: Channel.Pick) -> Channel.Pick:
  match c:
    case None{}:
      Pick{free, victim, size} = p
      Pick{0n, 1n+victim, 1n+size}
    case Some{old}:
      Channel.pick.busy(Nat.is_le(pri, old), p)

# S_GetChannel's two searches, independent of the files they allot: the
# first free slot and the first sound no more important than the new one.
def Channel.pick(+pri: Nat, slots: List<&2, Maybe<&2, Nat>>) -> Channel.Pick:
  match slots:
    case []:
      Pick{0n, 0n, 0n}
    case c <> rest:
      Channel.pick.slot(pri, c, Channel.pick(pri, rest))

def Channel.choice.free(p: Channel.Pick) -> Nat:
  Pick{+free, victim, size} = p
  Bool.pick(Nat, Nat.is_lt(free, size), free, victim)

def Channel.choice(+pri: Nat, slots: List<&2, Maybe<&2, Nat>>) -> Nat:
  Channel.choice.free(Channel.pick(pri, slots))

def Channel.model.keys.none(
  p: List<&2, Maybe<&2, Channel.Voice>> & List<&2, Maybe<&2, Nat>>) ->
  List<&2, Maybe<&2, Channel.Voice>> & List<&2, Maybe<&2, Nat>>:
  (slots, keys) = p
  (None{} <> slots, None{} <> keys)

def Channel.model.keys.some(+mine: Bool, +priority: Nat,
  p: List<&2, Maybe<&2, Channel.Voice>> & List<&2, Maybe<&2, Nat>>) ->
  List<&2, Maybe<&2, Channel.Voice>> & List<&2, Maybe<&2, Nat>>:
  (slots, keys) = p
  (Some{Voice{mine, priority}} <> slots,
    Bool.pick(Maybe<&2, Nat>, mine, None{}, Some{priority}) <> keys)

def Channel.model.keys.cons(c: Maybe<&2, Channel.Voice>,
  p: List<&2, Maybe<&2, Channel.Voice>> & List<&2, Maybe<&2, Nat>>) ->
  List<&2, Maybe<&2, Channel.Voice>> & List<&2, Maybe<&2, Nat>>:
  match c:
    case None{}:
      Channel.model.keys.none(p)
    case Some{Voice{mine, +priority}}:
      Channel.model.keys.some(mine, priority, p)

def Channel.model.keys(slots: List<&2, Maybe<&2, Channel.Voice>>) ->
  List<&2, Maybe<&2, Channel.Voice>> & List<&2, Maybe<&2, Nat>>:
  match slots:
    case []:
      ([], [])
    case c <> rest:
      Channel.model.keys.cons(c, Channel.model.keys(rest))

def Channel.model.table(p: List<&2, Maybe<&2, Channel.Voice>> & List<&2, Maybe<&2, Nat>>) ->
  List<&2, Maybe<&2, Channel.Voice>>:
  (slots, keys) = p
  slots

def Channel.model.clear(c: Maybe<&2, Channel.Voice>) -> Maybe<&2, Channel.Voice>:
  match c:
    case None{}:
      None{}
    case Some{Voice{mine, priority}}:
      Some{Voice{False{}, priority}}

def Channel.model.clear.all(slots: List<&2, Maybe<&2, Channel.Voice>>) ->
  List<&2, Maybe<&2, Channel.Voice>>:
  match slots:
    case []:
      []
    case c <> rest:
      Channel.model.clear(c) <> Channel.model.clear.all(rest)

def Channel.model.replace(slots: List<&2, Maybe<&2, Channel.Voice>>, +n: Nat, +priority: Nat) ->
  List<&2, Maybe<&2, Channel.Voice>>:
  match slots n:
    case [] _:
      []
    case c <> rest 0n:
      Some{Voice{True{}, priority}} <> Channel.model.clear.all(rest)
    case c <> rest 1n+m:
      Channel.model.clear(c) <> Channel.model.replace(rest, m, priority)

def Channel.model.start.hushed(+priority: Nat,
  p: List<&2, Maybe<&2, Channel.Voice>> & List<&2, Maybe<&2, Nat>>) ->
  List<&2, Maybe<&2, Channel.Voice>>:
  (slots, keys) = p
  Channel.model.replace(slots, Channel.choice(priority, keys), priority)

def Channel.model.start(+priority: Nat, slots: List<&2, Maybe<&2, Channel.Voice>>) ->
  List<&2, Maybe<&2, Channel.Voice>>:
  Channel.model.start.hushed(priority, Channel.model.keys(slots))

def Channel.model.size(slots: List<&2, Maybe<&2, Channel.Voice>>) -> Nat:
  match slots:
    case []:
      0n
    case c <> rest:
      1n+Channel.model.size(rest)

def Channel.model.size.keys(slots: List<&2, Maybe<&2, Nat>>) -> Nat:
  match slots:
    case []:
      0n
    case c <> rest:
      1n+Channel.model.size.keys(rest)

def Channel.model.one(slots: List<&2, Maybe<&2, Channel.Voice>>, +seen: Bool) -> Bool:
  match slots:
    case []:
      True{}
    case None{} <> rest:
      Channel.model.one(rest, seen)
    case Some{Voice{+mine, priority}} <> rest:
      Bool.and(Bool.not(Bool.and(seen, mine)),
        Channel.model.one(rest, Bool.or(seen, mine)))

def Channel.model.protected(+priority: Nat, slots: List<&2, Maybe<&2, Nat>>) -> Bool:
  match slots:
    case []:
      True{}
    case None{} <> rest:
      False{}
    case Some{old} <> rest:
      Bool.and(Bool.not(Nat.is_le(priority, old)), Channel.model.protected(priority, rest))

def Channel.keys.slot(c: Maybe<Channel>) -> Maybe<Channel> & Maybe<&2, Nat>:
  match c:
    case None{}:
      (None{}, None{})
    case Some{Chan{file, +sfx, source, left, right}}:
      (Some{Chan{file, sfx, source, left, right}},
        Some{U32.to_nat(Sn.Sound.priority(Sn.Sound.table(), sfx))})

def Channel.keys.cons(p: Maybe<Channel> & Maybe<&2, Nat>,
  q: List<Maybe<Channel>> & List<&2, Maybe<&2, Nat>>) -> List<Maybe<Channel>> & List<&2, Maybe<&2, Nat>>:
  (kept, key) = p
  (cs, keys) = q
  (kept <> cs, key <> keys)

def Channel.keys(chans: List<Maybe<Channel>>) -> List<Maybe<Channel>> & List<&2, Maybe<&2, Nat>>:
  match chans:
    case []:
      ([], [])
    case c <> rest:
      Channel.keys.cons(Channel.keys.slot(c), Channel.keys(rest))

def Channel.opened(+sfx: U32, source: Sn.Sound.Source, +left: U32, +right: U32, chans: List<Maybe<Channel>>,
  n: Nat, r: Result<&1, &1, U32 & String, File>) -> IO(List<Maybe<Channel>>):
  match r:
    case Fail{e}:
      IO.pure(List<Maybe<Channel>>, chans)
    case Done{f}:
      Channel.put(chans, n, Chan{f, sfx, source, left, right})

# S_GetChannel: a free channel takes the sound, or else the first
# channel of no greater importance is kicked out, and if every one is
# more important the sound is dropped. A sound whose file will not open
# is dropped too, which is the game with no sounds directory.
def Channel.start(+dir: String, +sfx: U32, source: Sn.Sound.Source, +left: U32, +right: U32,
  p: List<Maybe<Channel>> & List<&2, Maybe<&2, Nat>>) -> IO(List<Maybe<Channel>>):
  (chans, keys) = p
  IO.bind(Result<&1, &1, U32 & String, File>, List<Maybe<Channel>>, File.open(Channel.path(dir, sfx), "r"),
    r => Channel.opened(sfx, source, left, right, chans,
      Channel.choice(U32.to_nat(Sn.Sound.priority(Sn.Sound.table(), sfx)), keys), r))

# What the sim reported, played: S_StartSound's tail after the
# audibility test, where the source's old sound is stopped and the new
# one takes a channel at the sides the volume and separation give.
def Channel.event(+dir: String, e: Sn.Sound.Event, chans: List<Maybe<Channel>>) ->
  IO(List<Maybe<Channel>>):
  match e:
    case Sn.Start{+sfx, +source, +vol, +sep}:
      do IO<List<Maybe<Channel>>>:
        hushed : List<Maybe<Channel>> <- Channel.hush(source, chans)
        Channel.start(dir, sfx, source, Channel.left(vol, sep), Channel.right(vol, sep),
          Channel.keys(hushed))
    case Sn.Stop{source}:
      Channel.hush(source, chans)

# The channels after the sounds of a frame's tics, in the order the tics
# made them.
def Channel.hear(+dir: String, events: List<&2, Sn.Sound.Event>, chans: List<Maybe<Channel>>) ->
  IO(List<Maybe<Channel>>):
  match events:
    case []:
      IO.pure(List<Maybe<Channel>>, chans)
    case e <> rest:
      do IO<List<Maybe<Channel>>>:
        cs : List<Maybe<Channel>> <- Channel.event(dir, e, chans)
        Channel.hear(dir, rest, cs)

def Channel.moved(c: Channel, p: U32 & U32) -> IO(Maybe<Channel>):
  Chan{file, sfx, source, left, right} = c
  (+vol, +sep) = p
  Channel.hush.gone(U32.is_zero(vol), file, sfx, source, Channel.left(vol, sep), Channel.right(vol, sep))

def Channel.update.slot(~Ctx: Data, ~params: Ctx -> Sn.Sound.Source -> U32 & U32, +ctx: Ctx,
  c: Maybe<Channel>) -> IO(Maybe<Channel>):
  match c:
    case None{}:
      IO.pure(Maybe<Channel>, None{})
    case Some{Chan{file, sfx, +source, left, right}}:
      Channel.moved(Chan{file, sfx, source, left, right}, params(ctx, source))

# S_UpdateSounds follows the current listener and source positions.
def Channel.update(~Ctx: Data, ~params: Ctx -> Sn.Sound.Source -> U32 & U32, +ctx: Ctx,
  chans: List<Maybe<Channel>>) -> IO(List<Maybe<Channel>>):
  match chans:
    case []:
      IO.pure(List<Maybe<Channel>>, [])
    case c <> rest:
      do IO<List<Maybe<Channel>>>:
        moved : Maybe<Channel> <- Channel.update.slot(~Ctx, ~params, ctx, c)
        cs : List<Maybe<Channel>> <- Channel.update(~Ctx, ~params, ctx, rest)
        return moved <> cs

# Every channel's file closed, when the game lets the device go.
def Channel.stop(chans: List<Maybe<Channel>>) -> IO(Unit):
  match chans:
    case []:
      IO.pure(Unit, Unit{})
    case None{} <> rest:
      Channel.stop(rest)
    case Some{Chan{file, sfx, source, left, right}} <> rest:
      do IO<Unit>:
        File.close(file)
        Channel.stop(rest)
