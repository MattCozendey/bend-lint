import Base
import ../protocol-probe/protocol.bend as Protocol
import ./transport.bend as Transport

# Framed link helpers shared by the native host and its clients.
#
# The socket only ever carries the ASCII hex envelope from transport.bend,
# because TCP.poll is the only bounded read in the pinned API and it decodes
# received bytes as UTF-8.
#
# One read takes at most one poll with a deadline, so a stalled peer fails
# instead of hanging. A frame that arrives split across several TCP segments is
# reported as a failed read rather than reassembled: Bend has no loop shape that
# reassembles here (a `do` block admits only a bind and a final term, a match
# cannot scrutinize a computed value or a closure binder, and a recursion
# through helpers is rejected), so this probe requires one frame per poll.
# Transport.feed itself is unit tested for split and coalesced input.
type ReadResult is Data:
  FrameRead{frame: Protocol.Frame, buffer: String}
  ReadFailed{}

type Waited is Type:
  Closed{socket: Socket}
  Chunked{socket: Socket, chunk: String}

type Step is Data:
  Framed{ascii: String, rest: String}
  Partial{buffer: String}
  Broken{}

def Waited.of(pair: Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>) -> IO(Waited):
  (socket, result) = pair
  match result:
    case Fail{error}:
      IO.pure(Waited, Closed{socket})
    case Done{None{}}:
      IO.pure(Waited, Closed{socket})
    case Done{Some{chunk}}:
      IO.pure(Waited, Chunked{socket, chunk})

def poll.once(socket: Socket) -> IO(Waited):
  do IO<Waited>:
    polled : Socket & Result<&1, &1, U32 & String, Maybe<&1, String>> <-
      TCP.poll(socket, 112, 250)
    Waited.of(polled)

def classify(extraction: Transport.Extraction) -> Step:
  match extraction:
    case Transport.Complete{frame, rest}:
      Framed{frame, rest}
    case Transport.Incomplete{filled}:
      Partial{filled}
    case _:
      Broken{}

def step_of(waited: Waited, buffer: String) -> IO(Socket & Step):
  match waited:
    case Closed{socket}:
      IO.pure(Socket & Step, (socket, Broken{}))
    case Chunked{socket, chunk}:
      IO.pure(Socket & Step, (socket, classify(Transport.feed(buffer, chunk))))

def resolve.found(maybe: Maybe<&2, Protocol.Frame>, socket: Socket, rest: String) ->
  IO(Socket & ReadResult):
  match maybe:
    case Some{frame}:
      IO.pure(Socket & ReadResult, (socket, FrameRead{frame, rest}))
    case None{}:
      IO.pure(Socket & ReadResult, (socket, ReadFailed{}))

def resolve(pair: Socket & Step) -> IO(Socket & ReadResult):
  (socket, step) = pair
  match step:
    case Framed{ascii, rest}:
      resolve.found(Transport.decode_frame(ascii), socket, rest)
    case Partial{_}:
      IO.pure(Socket & ReadResult, (socket, ReadFailed{}))
    case Broken{}:
      IO.pure(Socket & ReadResult, (socket, ReadFailed{}))

# Reads one frame with a bounded poll. `buffer` is the leftover from a previous
# frame, so two frames delivered in one poll do not corrupt each other.
def read_frame(socket: Socket, buffer: String) -> IO(Socket & ReadResult):
  do IO<Socket & ReadResult>:
    waited : Waited <- poll.once(socket)
    stepped : Socket & Step <- step_of(waited, buffer)
    resolve(stepped)

def fail_socket(-A: Type, socket: Socket, message: String) -> IO(A):
  do IO<A>:
    closed : Unit <- Socket.close(socket)
    IO.die(A, 1, message)

# A generic type argument cannot be a product in this compiler, so the shape
# used by the read helpers gets its own failure path.
def fail_pair(socket: Socket, message: String) -> IO(Socket & String):
  do IO<Socket & String>:
    closed : Unit <- Socket.close(socket)
    IO.die(Socket & String, 1, message)

def send_frame.result(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Socket):
  (socket, result) = pair
  match result:
    case Done{unit}:
      IO.pure(Socket, socket)
    case Fail{error}:
      fail_socket(Socket, socket, "native-tcp: socket send failed")

def send_frame(socket: Socket, frame: Protocol.Frame) -> IO(Socket):
  do IO<Socket>:
    sent : Socket & Result<&1, &1, U32 & String, Unit> <-
      TCP.send(socket, Transport.encode_frame(frame))
    send_frame.result(sent)
