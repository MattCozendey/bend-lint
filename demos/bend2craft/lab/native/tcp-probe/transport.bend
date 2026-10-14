import Base
import ../protocol-probe/protocol.bend as Protocol

# TCP.poll returns UTF-8 text, so the socket envelope is fixed-width ASCII hex.
type Extraction is Data:
  Overflow{}
  Invalid{}
  Incomplete{buffer: String}
  Complete{frame: String, rest: String}

type HexState is Data:
  High{bytes: List<&2, U32>}
  Low{high: U32, high_valid: Bool, bytes: List<&2, U32>}

type Split is Data:
  Split{frame: String, rest: String}

def hex_digit.choose(+value: U32, decimal: Bool) -> Char:
  match decimal:
    case True{}:
      Chr{U32.add(value, 48)}
    case False{}:
      Chr{U32.add(value, 55)}

def hex_digit(+value: U32) -> Char:
  hex_digit.choose(value, U32.is_lt(value, 10))

def hex_byte(+value: U32) -> String:
  +high = U32.div(value, 16)
  +low = U32.mod(value, 16)
  String.append(String.from_list([hex_digit(high)]),
    String.from_list([hex_digit(low)]))

def encode_bytes(bytes: List<&2, U32>, +remaining: Nat) -> String:
  match bytes remaining:
    case Nil{} _:
      ""
    case Con{+head, tail} 0n:
      ""
    case Con{head, tail} 1n+p:
      String.append(hex_byte(head), encode_bytes(tail, p))

def encode_frame(frame: Protocol.Frame) -> String:
  encode_bytes(Protocol.encode(frame), 28n)

def hex_value.finish(+value: U32, decimal: Bool, upper: Bool,
  lower: Bool) -> Maybe<&2, U32>:
  match decimal:
    case True{}:
      Some{U32.sub(value, 48)}
    case False{}:
      match upper:
        case True{}:
          Some{U32.add(U32.sub(value, 65), 10)}
        case False{}:
          match lower:
            case True{}:
              Some{U32.add(U32.sub(value, 97), 10)}
            case False{}:
              None{}

def hex_value(char: Char) -> Maybe<&2, U32>:
  +value = Char.to_u32(char)
  hex_value.finish(value,
    U32.is_le(48, value) && U32.is_le(value, 57),
    U32.is_le(65, value) && U32.is_le(value, 70),
    U32.is_le(97, value) && U32.is_le(value, 102))

def hex_value.or(value: Maybe<&2, U32>, fallback: U32) -> U32:
  match value:
    case Some{digit}:
      digit
    case None{}:
      fallback

def hex_value.valid(char: Char) -> Bool:
  U32.is_lt(hex_value.or(hex_value(char), 16), 16)

def decode_hex(ascii: String, +remaining: Nat, state: HexState) ->
  Maybe<&2, List<&2, U32>>:
  match ascii remaining:
    case SNil{} 0n:
      match state:
        case High{+bytes}:
          Some{List.reverse(&2, U32, bytes)}
        case Low{high, high_valid, bytes}:
          None{}
    case _ 0n:
      None{}
    case SNil{} 1n+p:
      None{}
    case SCon{+head, tail} 1n+p:
      match state:
        case High{+bytes}:
          +digit = hex_value.or(hex_value(head), 0)
          decode_hex(tail, p, Low{digit, hex_value.valid(head), bytes})
        case Low{high, high_valid, +bytes}:
          +digit = hex_value.or(hex_value(head), 0)
          +raw_byte = U32.add(U32.mul(high, 16), digit)
          +invalid = Bool.to_u32(Bool.not(high_valid && hex_value.valid(head)))
          +byte = U32.add(raw_byte, U32.mul(invalid, 256))
          decode_hex(tail, p, High{byte <> bytes})

def decode_parsed(value: Maybe<&2, List<&2, U32>>) -> Maybe<&2, Protocol.Frame>:
  match value:
    case Some{bytes}:
      Protocol.decode(bytes)
    case None{}:
      None{}

def decode_frame(ascii: String) -> Maybe<&2, Protocol.Frame>:
  decode_parsed(decode_hex(ascii, 56n, High{Nil{}}))

def split_chars(chars: List<&2, Char>, +remaining: Nat,
  +acc: List<&2, Char>) -> Maybe<&2, Split>:
  match chars remaining:
    case rest 0n:
      Some{Split{String.from_list(List.reverse(&2, Char, acc)),
        String.from_list(rest)}}
    case Nil{} 1n+p:
      None{}
    case Con{head, tail} 1n+p:
      split_chars(tail, p, head <> acc)

def feed.finish.parts(buffer: String, +count: Nat,
  parts: Maybe<&2, Split>) -> Extraction:
  match parts:
    case Some{Split{frame, rest}}:
      Complete{frame, rest}
    case None{}:
      Incomplete{buffer}

def feed.finish.length(+buffer: String, +count: Nat, enough: Bool) -> Extraction:
  match enough:
    case False{}:
      Incomplete{buffer}
    case True{}:
      feed.finish.parts(buffer, count,
        split_chars(String.to_list(buffer), 56n, Nil{}))

def feed.finish(buffer: String, +count: Nat) -> Extraction:
  feed.finish.length(buffer, count, Nat.is_ge(count, 56n))

def feed.finish.checked(acc: String, +count: Nat, valid: Bool) -> Extraction:
  match valid:
    case False{}:
      Invalid{}
    case True{}:
      feed.finish(acc, count)

def feed.collect.chunk(chunk: String, +remaining: Nat,
  +count: Nat, acc: String, valid: Bool) -> Extraction:
  match chunk remaining:
    case SNil{} _:
      feed.finish.checked(acc, count, valid)
    case SCon{+head, tail} 0n:
      Overflow{}
    case SCon{+head, tail} 1n+p:
      +next_acc = String.append(acc, String.from_list([head]))
      feed.collect.chunk(tail, p, Nat.add(count, 1n), next_acc,
        Bool.and(valid, hex_value.valid(head)))

def feed.collect.buffer(buffer: String, chunk: String, +remaining: Nat,
  +count: Nat, acc: String, valid: Bool) -> Extraction:
  match buffer remaining:
    case SNil{} _:
      feed.collect.chunk(chunk, remaining, count, acc, valid)
    case SCon{+head, tail} 0n:
      Overflow{}
    case SCon{+head, tail} 1n+p:
      +next_acc = String.append(acc, String.from_list([head]))
      feed.collect.buffer(tail, chunk, p, Nat.add(count, 1n), next_acc,
        Bool.and(valid, hex_value.valid(head)))

def feed(buffer: String, chunk: String) -> Extraction:
  feed.collect.buffer(buffer, chunk, 112n, 0n, "", True{})
