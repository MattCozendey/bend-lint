# The mixer, the game's one writer to the sound device: the song of the
# render in the directory named by BENDOOM_MUSIC with every playing
# channel's sound over it, streamed to the device a frame of the loop at
# a time. first.raw plays once and second.raw for as long as the game
# runs, both raw 16-bit little-endian stereo at 44100 Hz, left then
# right; a sound is one file of raw 16-bit little-endian mono, as the
# sounds node writes it. The open files are the song's and each sound's
# place, and nothing but the frames about to be written is ever held.
import Base
import ./bytes.bend as B
import ./sound.bend as Sn
import ./channel.bend as C

# A pass being read: the open file and the path of second.raw, which
# opens again at every pass's end.
type Stream.Tape is Type:
  Tape{file: File, path: String}

# The mixer: the device, the pass feeding it, the channels playing over
# it, the directory their files come from, and the game frames whose
# top-up found the device's queue empty, which the window bench reports.
type Stream is Type:
  Stream{audio: Audio, tape: Maybe<Stream.Tape>, chans: List<Maybe<C.Channel>>, dir: String, dry: U32}

# A 16-bit sample as the device takes it: its sign bit flipped is its
# value over 32768, offset by a half.
def Stream.sample(+x: U32) -> F32:
  +half = U32.to_f32(32768)
  ((U32.to_f32((x .^. 32768 : U32)) - half : F32) / half : F32)

# A frame as the mix holds it: the left sample in the low half of a
# word, the right in the high half, each 16 bits as its file holds them.
def Stream.words(bytes: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case l <> m <> r <> s <> rest:
      (B.Bytes.le16(l, m) .|. (B.Bytes.le16(r, s) << 16n) : U32) <> Stream.words(rest)
    case _:
      []

# The frames of the mix as Audio.write takes them, left then right.
def Stream.samples(words: List<&2, U32>) -> List<&2, F32>:
  match words:
    case +w <> rest:
      Stream.sample((w .&. 65535 : U32)) <> Stream.sample((w >> 16n : U32)) <> Stream.samples(rest)
    case []:
      []

# SDL_mixer's _Eff_position_s16lsb on one side: (Sint16) ((float) sample
# * (side / 255.0f)), whose cast truncates toward zero, so a negative
# sample is scaled as its magnitude.
def Stream.side(+s: U32, +side: U32) -> U32:
  +neg = U32.is_ge(s, 32768)
  +q = F32.to_u32((U32.to_f32(Bool.pick(U32, neg, (65536 - s : U32), s)) * (U32.to_f32(side) / 255.0 : F32) : F32))
  (Bool.pick(U32, neg, (65536 - q : U32), q) .&. 65535 : U32)

# SDL3's SDL_MixAudio at full volume, which SDL_mixer calls once a
# channel: the two samples added and clipped to 16 bits. Each sign bit
# flipped puts the sum in 0 to 131070, so it cannot run below zero.
def Stream.add(+a: U32, +b: U32) -> U32:
  ((U32.clamp(((a .^. 32768 : U32) + (b .^. 32768 : U32) : U32), 32768, 98303) - 32768 : U32) .^. 32768 : U32)

# One frame of a channel over one frame of the mix: the sound's sample
# scaled to each side and added there. Both sides of the expansion hold
# the same sample, so the file is mono and the sides part here.
def Stream.mix(+left: U32, +right: U32, +s: U32, +w: U32) -> U32:
  (Stream.add(Stream.side(s, left), (w .&. 65535 : U32))
    .|. (Stream.add(Stream.side(s, right), (w >> 16n : U32)) << 16n) : U32)

# A channel's next frames added to what is mixed so far, as SDL_mixer
# adds a channel to the music. The mix ends where the shorter of the two
# does, and a channel whose file ran out is the shorter one.
def Stream.over(+left: U32, +right: U32, mono: List<&2, U32>, words: List<&2, U32>) -> List<&2, U32>:
  match mono words:
    case lo <> hi <> rest w <> ws:
      Stream.mix(left, right, B.Bytes.le16(lo, hi), w) <> Stream.over(left, right, rest, ws)
    case _ ws:
      ws

# The file to read next: a read cut short is the pass's end, where the
# open one closes and second.raw opens again, since Base cannot seek.
def Stream.turned(short: Bool, +path: String, file: File) -> IO(File):
  match short:
    case True{}:
      do IO<File>:
        File.close(file)
        next : File <- IO.try(File, File.open(path, "r"))
        return next
    case False{}:
      IO.pure(File, file)

def Stream.counted(+want: U32, +path: String, file: File, +bytes: List<&2, U32>) ->
  IO(Stream.Tape & List<&2, U32>):
  +short = U32.is_lt(U32.from_nat(List.length(&2, U32, bytes)), (want * 4 : U32))
  IO.bind(File, Stream.Tape & List<&2, U32>, Stream.turned(short, path, file),
    next => IO.pure(Stream.Tape & List<&2, U32>, (Tape{next, path}, bytes)))

# A failed read reads as a read of no bytes, which ends the pass.
def Stream.got(+want: U32, path: String, p: File & Result<&1, &1, U32 & String, List<&2, U32>>) ->
  IO(Stream.Tape & List<&2, U32>):
  (file, got) = p
  Stream.counted(want, path, file, Result.default(&1, &1, U32 & String, List<&2, U32>, got, []))

# The bytes of the song's next frames, at most the rest of the open pass,
# and the tape after them.
def Stream.pull(+want: U32, tape: Stream.Tape) -> IO(Stream.Tape & List<&2, U32>):
  Tape{file, path} = tape
  IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, Stream.Tape & List<&2, U32>,
    File.read_bytes(file, (want * 4 : U32)), p => Stream.got(want, path, p))

def Stream.song.got(p: Stream.Tape & List<&2, U32>) -> IO(Maybe<Stream.Tape> & List<&2, U32>):
  (tape, bytes) = p
  IO.pure(Maybe<Stream.Tape> & List<&2, U32>, (Some{tape}, Stream.words(bytes)))

# The song's next frames, which are silence when the game has no render
# to play and the sounds play alone.
def Stream.song(+want: U32, tape: Maybe<Stream.Tape>) -> IO(Maybe<Stream.Tape> & List<&2, U32>):
  match tape:
    case None{}:
      IO.pure(Maybe<Stream.Tape> & List<&2, U32>, (None{}, List.replicate(U32, U32.to_nat(want), 0)))
    case Some{t}:
      IO.bind(Stream.Tape & List<&2, U32>, Maybe<Stream.Tape> & List<&2, U32>, Stream.pull(want, t),
        Stream.song.got)

# A channel whose read came up short has played its sound out: its file
# closes and the channel frees itself.
def Stream.voice.kept(+short: Bool, file: File, +sfx: U32, source: Sn.Sound.Source, +left: U32, +right: U32,
  words: List<&2, U32>) -> IO(Maybe<C.Channel> & List<&2, U32>):
  match short:
    case True{}:
      do IO<Maybe<C.Channel> & List<&2, U32>>:
        File.close(file)
        return (None{}, words)
    case False{}:
      IO.pure(Maybe<C.Channel> & List<&2, U32>, (Some{C.Chan{file, sfx, source, left, right}}, words))

def Stream.voice.got(+want: U32, +sfx: U32, source: Sn.Sound.Source, +left: U32, +right: U32,
  words: List<&2, U32>, p: File & Result<&1, &1, U32 & String, List<&2, U32>>) ->
  IO(Maybe<C.Channel> & List<&2, U32>):
  (file, got) = p
  +bytes = Result.default(&1, &1, U32 & String, List<&2, U32>, got, [])
  Stream.voice.kept(U32.is_lt(U32.from_nat(List.length(&2, U32, bytes)), (want * 2 : U32)), file, sfx, source,
    left, right, Stream.over(left, right, bytes, words))

# One channel mixed into the frames about to be written: its own next
# frames, read from where its file stands.
def Stream.voice(+want: U32, c: Maybe<C.Channel>, words: List<&2, U32>) ->
  IO(Maybe<C.Channel> & List<&2, U32>):
  match c:
    case None{}:
      IO.pure(Maybe<C.Channel> & List<&2, U32>, (None{}, words))
    case Some{C.Chan{file, sfx, source, left, right}}:
      IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, Maybe<C.Channel> & List<&2, U32>,
        File.read_bytes(file, (want * 2 : U32)), p => Stream.voice.got(want, sfx, source, left, right, words, p))

def Stream.voices.cons(c: Maybe<C.Channel>, q: List<Maybe<C.Channel>> & List<&2, U32>) ->
  IO(List<Maybe<C.Channel>> & List<&2, U32>):
  (cs, words) = q
  IO.pure(List<Maybe<C.Channel>> & List<&2, U32>, (c <> cs, words))

def Stream.voices.on(p: Maybe<C.Channel> & List<&2, U32>,
  rest: List<&2, U32> -> IO(List<Maybe<C.Channel>> & List<&2, U32>)) ->
  IO(List<Maybe<C.Channel>> & List<&2, U32>):
  (c, words) = p
  IO.bind(List<Maybe<C.Channel>> & List<&2, U32>, List<Maybe<C.Channel>> & List<&2, U32>, rest(words),
    q => Stream.voices.cons(c, q))

# Every channel mixed in, in the order SDL_mixer takes them, since the
# clipping of one addition is what the next adds to.
def Stream.voices(+want: U32, chans: List<Maybe<C.Channel>>, words: List<&2, U32>) ->
  IO(List<Maybe<C.Channel>> & List<&2, U32>):
  match chans:
    case []:
      IO.pure(List<Maybe<C.Channel>> & List<&2, U32>, ([], words))
    case c <> rest:
      IO.bind(Maybe<C.Channel> & List<&2, U32>, List<Maybe<C.Channel>> & List<&2, U32>,
        Stream.voice(want, c, words), p => Stream.voices.on(p, ws => Stream.voices(want, rest, ws)))

def Stream.post(song: List<&2, U32>, words: List<&2, U32>) -> List<&2, U32>:
  match song words:
    case +s <> ss +w <> ws:
      (Stream.add((w .&. 65535 : U32), (s .&. 65535 : U32))
        .|. (Stream.add((w >> 16n : U32), (s >> 16n : U32)) << 16n) : U32) <> Stream.post(ss, ws)
    case _ ws:
      ws

def Stream.window.done(tape: Maybe<Stream.Tape>, song: List<&2, U32>, q: List<Maybe<C.Channel>> & List<&2, U32>) ->
  IO(Maybe<Stream.Tape> & List<Maybe<C.Channel>> & List<&2, U32>):
  (chans, words) = q
  IO.pure(Maybe<Stream.Tape> & List<Maybe<C.Channel>> & List<&2, U32>, (tape, chans, Stream.post(song, words)))

def Stream.window.mixed(chans: List<Maybe<C.Channel>>, p: Maybe<Stream.Tape> & List<&2, U32>) ->
  IO(Maybe<Stream.Tape> & List<Maybe<C.Channel>> & List<&2, U32>):
  (tape, +words) = p
  +count = List.length(&2, U32, words)
  IO.bind(List<Maybe<C.Channel>> & List<&2, U32>, Maybe<Stream.Tape> & List<Maybe<C.Channel>> & List<&2, U32>,
    Stream.voices(U32.from_nat(count), chans, List.replicate(U32, count, 0)), q => Stream.window.done(tape, words, q))

# Chocolate Doom registers OPL_Mix_Callback as MIX_CHANNEL_POST, so the
# song is added after the sound channels have clipped. Each channel reads
# as many frames as the song gave, so its last short read costs no sound.
def Stream.window(+want: U32, tape: Maybe<Stream.Tape>, chans: List<Maybe<C.Channel>>) ->
  IO(Maybe<Stream.Tape> & List<Maybe<C.Channel>> & List<&2, U32>):
  IO.bind(Maybe<Stream.Tape> & List<&2, U32>, Maybe<Stream.Tape> & List<Maybe<C.Channel>> & List<&2, U32>,
    Stream.song(want, tape), p => Stream.window.mixed(chans, p))

# The frames the device holds between top-ups, of the ring's 4096: 52.2
# ms at 44100 Hz, against Chocolate Doom's 1024 frames and 23.2 ms.
# The fight bench found 2048 dry on its cold run, 1536 intermittently
# dry and 1024 routinely dry.
def Stream.top() -> U32:
  2304

def Stream.wrote(tape: Maybe<Stream.Tape>, chans: List<Maybe<C.Channel>>, dir: String, dry: U32,
  p: Audio & U32) -> IO(Stream):
  (audio, queued) = p
  IO.pure(Stream, Stream{audio, tape, chans, dir, dry})

def Stream.filled(audio: Audio, dir: String, dry: U32,
  r: Maybe<Stream.Tape> & List<Maybe<C.Channel>> & List<&2, U32>) -> IO(Stream):
  (tape, chans, words) = r
  IO.bind(Audio & U32, Stream, Audio.write(audio, Stream.samples(words)),
    q => Stream.wrote(tape, chans, dir, dry, q))

def Stream.topped(tape: Maybe<Stream.Tape>, chans: List<Maybe<C.Channel>>, dir: String, +dry: U32,
  p: Audio & U32) -> IO(Stream):
  (audio, +queued) = p
  IO.bind(Maybe<Stream.Tape> & List<Maybe<C.Channel>> & List<&2, U32>, Stream,
    Stream.window((Stream.top() - queued : U32), tape, chans),
    r => Stream.filled(audio, dir, (dry + Bool.to_u32(U32.is_zero(queued)) : U32), r))

# A frame of the mix: a write of no samples reads the queue, and the
# frames that bring it back to the top follow it. The song's place and
# each sound's therefore follow the device's clock, not the tic clock.
def Stream.frame(m: Stream) -> IO(Stream):
  Stream{audio, tape, chans, dir, dry} = m
  IO.bind(Audio & U32, Stream, Audio.write(audio, []), p => Stream.topped(tape, chans, dir, dry, p))

def Stream.play(m: Maybe<Stream>) -> IO(Maybe<Stream>):
  match m:
    case None{}:
      IO.pure(Maybe<Stream>, None{})
    case Some{s}:
      IO.bind(Stream, Maybe<Stream>, Stream.frame(s), kept => IO.pure(Maybe<Stream>, Some{kept}))

def Stream.heard(audio: Audio, tape: Maybe<Stream.Tape>, dir: String, dry: U32,
  chans: List<Maybe<C.Channel>>) -> IO(Maybe<Stream>):
  IO.pure(Maybe<Stream>, Some{Stream{audio, tape, chans, dir, dry}})

# The sounds a frame's tics reported, given to the channels before the
# frame's write, so that a sound is in the write that follows its tic.
def Stream.hear(events: List<&2, Sn.Sound.Event>, m: Maybe<Stream>) -> IO(Maybe<Stream>):
  match m:
    case None{}:
      IO.pure(Maybe<Stream>, None{})
    case Some{Stream{audio, tape, chans, +dir, dry}}:
      IO.bind(List<Maybe<C.Channel>>, Maybe<Stream>, C.Channel.hear(dir, events, chans),
        cs => Stream.heard(audio, tape, dir, dry, cs))

def Stream.update(~Ctx: Data, ~params: Ctx -> Sn.Sound.Source -> U32 & U32, +ctx: Ctx,
  m: Maybe<Stream>) -> IO(Maybe<Stream>):
  match m:
    case None{}:
      IO.pure(Maybe<Stream>, None{})
    case Some{Stream{audio, tape, chans, dir, dry}}:
      IO.bind(List<Maybe<C.Channel>>, Maybe<Stream>, C.Channel.update(~Ctx, ~params, ctx, chans),
        cs => Stream.heard(audio, tape, dir, dry, cs))

# The sounds directory the launcher names, or none, which is one line
# and a game with the music alone.
def Stream.sounds(dir: Result<&1, &1, U32 & String, String>) -> IO(String):
  match dir:
    case Fail{e}:
      do IO<String>:
        IO.print_err("bendoom: BENDOOM_SOUNDS names no sounds; playing the music alone")
        return ""
    case Done{d}:
      IO.pure(String, d)

def Stream.rolled(+dir: String, file: Result<&1, &1, U32 & String, File>) -> Maybe<Stream.Tape>:
  match file:
    case Fail{e}:
      None{}
    case Done{f}:
      Some{Tape{f, dir ++ "/second.raw"}}

def Stream.probed(+dir: String, second: Result<&1, &1, U32 & String, File>) -> IO(Maybe<Stream.Tape>):
  match second:
    case Fail{e}:
      IO.pure(Maybe<Stream.Tape>, None{})
    case Done{f}:
      do IO<Maybe<Stream.Tape>>:
        File.close(f)
        first : Result<&1, &1, U32 & String, File> <- File.open(dir ++ "/first.raw", "r")
        return Stream.rolled(dir, first)

# The first pass of the render in the given directory, open at its
# first frame, if the second opens too.
def Stream.tape(+dir: String) -> IO(Maybe<Stream.Tape>):
  IO.bind(Result<&1, &1, U32 & String, File>, Maybe<Stream.Tape>, File.open(dir ++ "/second.raw", "r"),
    s => Stream.probed(dir, s))

def Stream.render(render: Result<&1, &1, U32 & String, String>) -> IO(Maybe<Stream.Tape>):
  match render:
    case Fail{e}:
      IO.pure(Maybe<Stream.Tape>, None{})
    case Done{d}:
      Stream.tape(d)

# No render: the line is said, and the device is let go unless there are
# sounds to play over the silence.
def Stream.songless(+mute: Bool, audio: Audio, +dir: String) -> IO(Maybe<Stream>):
  match mute:
    case True{}:
      do IO<Maybe<Stream>>:
        Audio.close(audio)
        IO.print_err("bendoom: BENDOOM_MUSIC names no render; playing silent")
        return None{}
    case False{}:
      do IO<Maybe<Stream>>:
        IO.print_err("bendoom: BENDOOM_MUSIC names no render; playing the sounds alone")
        return Some{Stream{audio, None{}, C.Channel.none(), dir, 0}}

def Stream.first(audio: Audio, +dir: String, tape: Maybe<Stream.Tape>) -> IO(Maybe<Stream>):
  match tape:
    case None{}:
      Stream.songless(String.is_empty(dir), audio, dir)
    case Some{t}:
      IO.pure(Maybe<Stream>, Some{Stream{audio, Some{t}, C.Channel.none(), dir, 0}})

# A game with no sound device says so once and plays on in silence.
def Stream.silent() -> IO(Maybe<Stream>):
  do IO<Maybe<Stream>>:
    IO.print_err("bendoom: no sound device; playing silent")
    return None{}

def Stream.device(dir: String, render: Result<&1, &1, U32 & String, String>,
  audio: Result<&1, &1, U32 & String, Audio>) -> IO(Maybe<Stream>):
  match audio:
    case Fail{e}:
      Stream.silent()
    case Done{a}:
      IO.bind(Maybe<Stream.Tape>, Maybe<Stream>, Stream.render(render), t => Stream.first(a, dir, t))

# The device at 44100 Hz, the song's first pass open if there is a
# render, and the directory the sounds are read from, or silence.
def Stream.open() -> IO(Maybe<Stream>):
  do IO<Maybe<Stream>>:
    sounds : Result<&1, &1, U32 & String, String> <- IO.get_env("BENDOOM_SOUNDS")
    dir : String <- Stream.sounds(sounds)
    render : Result<&1, &1, U32 & String, String> <- IO.get_env("BENDOOM_MUSIC")
    audio : Result<&1, &1, U32 & String, Audio> <- Audio.open(44100)
    Stream.device(dir, render, audio)

def Stream.shut(tape: Maybe<Stream.Tape>) -> IO(Unit):
  match tape:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{Tape{file, path}}:
      File.close(file)

# The device, the song and every playing sound let go; the frames that
# found the queue empty, if the mixer ran.
def Stream.stop(m: Maybe<Stream>) -> IO(Maybe<U32>):
  match m:
    case None{}:
      IO.pure(Maybe<U32>, None{})
    case Some{Stream{audio, tape, chans, dir, dry}}:
      do IO<Maybe<U32>>:
        Audio.close(audio)
        Stream.shut(tape)
        C.Channel.stop(chans)
        return Some{dry}
