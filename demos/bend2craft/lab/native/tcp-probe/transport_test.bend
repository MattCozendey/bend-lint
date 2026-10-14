import Base
import ../protocol-probe/protocol.bend as Protocol
import ./transport.bend as Transport

def require(condition: Bool, message: String) -> IO(Unit):
  match condition:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "native-tcp-probe: " ++ message)

def join_is(value: Maybe<&2, Protocol.Frame>, expected: U32) -> Bool:
  match value:
    case Some{Protocol.Join{client}}:
      U32.is_eq(client, expected)
    case _:
      False{}

def is_incomplete(value: Transport.Extraction, expected: String) -> Bool:
  match value:
    case Transport.Incomplete{buffer}:
      String.eq(buffer, expected)
    case _:
      False{}

def is_complete(value: Transport.Extraction, expected_frame: String,
  expected_rest: String) -> Bool:
  match value:
    case Transport.Complete{frame, rest}:
      String.eq(frame, expected_frame) && String.eq(rest, expected_rest)
    case _:
      False{}

def maybe_is_none(value: Maybe<&2, Protocol.Frame>) -> Bool:
  match value:
    case None{}:
      True{}
    case Some{frame}:
      False{}

def is_max_edit(value: Maybe<&2, Protocol.Frame>) -> Bool:
  match value:
    case Some{Protocol.Edit{client, expected, x, y, z, block}}:
      U32.is_eq(client, 4294967295) && U32.is_eq(expected, 4294967295)
        && U32.is_eq(x, 4294967295) && U32.is_eq(y, 4294967295)
        && U32.is_eq(z, 4294967295) && U32.is_eq(block, 4294967295)
    case _:
      False{}

def is_overflow(value: Transport.Extraction) -> Bool:
  match value:
    case Transport.Overflow{}:
      True{}
    case _:
      False{}

def is_invalid(value: Transport.Extraction) -> Bool:
  match value:
    case Transport.Invalid{}:
      True{}
    case _:
      False{}

def feed_next(value: Transport.Extraction, chunk: String) -> Transport.Extraction:
  match value:
    case Transport.Incomplete{buffer}:
      Transport.feed(buffer, chunk)
    case _:
      Transport.Invalid{}

def feed_rest(value: Transport.Extraction) -> Transport.Extraction:
  match value:
    case Transport.Complete{frame, rest}:
      Transport.feed(rest, "")
    case _:
      Transport.Invalid{}

def ascii_codec_checks() -> Bool:
  +join: Protocol.Frame = Protocol.Join{17}
  +edit: Protocol.Frame = Protocol.Edit{4294967295, 4294967295,
    4294967295, 4294967295, 4294967295, 4294967295}
  +join_ascii: String = "42320101000000110000000000000000000000000000000000000000"
  +edit_ascii: String = Transport.encode_frame(edit)
  String.eq(Transport.encode_frame(join), join_ascii)
    && join_is(Transport.decode_frame(join_ascii), 17)
    && is_max_edit(Transport.decode_frame(edit_ascii))
    && maybe_is_none(Transport.decode_frame(
      String.append("G", String.drop(join_ascii, 1n))))
    && maybe_is_none(Transport.decode_frame(
      String.append("42320201", String.drop(join_ascii, 8n))))
    && maybe_is_none(Transport.decode_frame(String.take(join_ascii, 55n)))
    && maybe_is_none(Transport.decode_frame(String.append(join_ascii, "0")))

def buffering_checks() -> Bool:
  +join_ascii: String = Transport.encode_frame(Protocol.Join{17})
  +edit_ascii: String = Transport.encode_frame(Protocol.Edit{17, 0, 4, 10, 5, 2})
  +coalesced: String = String.append(join_ascii, edit_ascii)
  +first: String = String.take(coalesced, 13n)
  +tail: String = String.drop(coalesced, 13n)
  +partial: Transport.Extraction = Transport.feed("", first)
  +both: Transport.Extraction = feed_next(partial, tail)
  +second: Transport.Extraction = feed_rest(both)
  is_incomplete(partial, first)
    && is_complete(both, join_ascii, edit_ascii)
    && is_complete(second, edit_ascii, "")
    && is_overflow(Transport.feed("", String.repeat("A", 113n)))
    && is_invalid(Transport.feed("", "G"))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- require(ascii_codec_checks(), "ASCII codec rejected a valid frame or accepted malformed input")
    Unit <- require(buffering_checks(), "bounded fragmented/coalesced frame extraction failed")
    IO.print("native-tcp-probe: ASCII codec and bounded buffering assertions passed")

#|native-tcp-probe: ASCII codec and bounded buffering assertions passed
