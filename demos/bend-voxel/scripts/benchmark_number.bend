import Base

type Elapsed is Data:
	Elapsed{high: U32, low: U32}

type Binary64 is Data:
	Binary64{high: U32, low: U32}

type Wide is Data:
	Wide{high: U32, low: U32}

type Quotient is Data:
	Quotient{integer: Wide, remainder: U32}

type SmallPair is Data:
	SmallPair{first: U32, second: U32}

type Decimal is Data:
	Decimal{digits: List<&2, U32>, places: Nat}

def SmallPair.first(value: SmallPair) -> U32:
	SmallPair{first, second} = value
	first

def SmallPair.second(value: SmallPair) -> U32:
	SmallPair{first, second} = value
	second

def Wide.is_zero(value: Wide) -> Bool:
	Wide{high, low} = value
	U32.is_zero(high) && U32.is_zero(low)

def Wide.shl(value: Wide) -> Wide:
	Wide{high, +low} = value
	Wide{(high << 1n .|. low >> 31n : U32), (low << 1n : U32)}

def Wide.shr(value: Wide) -> Wide:
	Wide{+high, low} = value
	Wide{(high >> 1n : U32), (low >> 1n .|. high << 31n : U32)}

def Wide.shln(count: Nat, value: Wide) -> Wide:
	match count:
		case 0n:
			value
		case 1n+rest:
			Wide.shln(rest, Wide.shl(value))

def Wide.shr_jam(count: Nat, value: Wide) -> Wide:
	match count:
		case 0n:
			value
		case 1n+rest:
			Wide{+high, +low} = value
			Wide.shr_jam(rest, Wide{(high >> 1n : U32), (low >> 1n .|. high << 31n .|. low .&. 1 : U32)})

def Wide.add(left: Wide, right: Wide) -> Wide:
	Wide{left_high, +left_low} = left
	Wide{right_high, right_low} = right
	+low = (left_low + right_low : U32)
	Wide{(left_high + right_high + Bool.to_u32(U32.is_lt(low, left_low)) : U32), low}

def Wide.inc(value: Wide) -> Wide:
	Wide.add(value, Wide{0, 1})

def Division.step(+remainder: U32, bit: U32, +denominator: U32) -> SmallPair:
	+shifted = (remainder << 1n .|. bit : U32)
	+take = Bool.to_u32(U32.is_ge(remainder, 2147483648) || U32.is_ge(shifted, denominator))
	SmallPair{take, (shifted - take * denominator : U32)}

def Division.integer(count: Nat, source: Wide, +denominator: U32, quotient: Wide, remainder: U32) -> Quotient:
	match count:
		case 0n:
			Quotient{quotient, remainder}
		case 1n+rest:
			Wide{+high, low} = source
			+step = Division.step(remainder, (high >> 31n : U32), denominator)
			Division.integer(rest, Wide.shl(Wide{high, low}), denominator,
				Wide.add(Wide.shl(quotient), Wide{0, SmallPair.first(step)}), SmallPair.second(step))

def Number.pack(significand: Wide, exponent: U32) -> Binary64:
	Wide{high, low} = significand
	Binary64{(exponent << 20n .|. high .&. 1048575 : U32), low}

def Number.carry(significand: Wide, +exponent: U32) -> Binary64:
	Wide{+high, low} = significand
	+mantissa = {Wide{high, low} : Wide}
	Bool.pick(Binary64, U32.is_ge(high, 2097152),
		Number.pack(Wide.shr(mantissa), (exponent + 1 : U32)), Number.pack(mantissa, exponent))

def Number.round(significand: Wide, +exponent: U32, guard: U32, sticky: Bool) -> Binary64:
	Wide{high, +low} = significand
	+mantissa = {Wide{high, low} : Wide}
	Bool.pick(Binary64, U32.is_ne(guard, 0) && (sticky || U32.is_ne((low .&. 1 : U32), 0)),
		Number.carry(Wide.inc(mantissa), exponent), Number.pack(mantissa, exponent))

def Division.fraction(count: Nat, significand: Wide, exponent: U32, remainder: U32, +denominator: U32) -> Binary64:
	match count:
		case 0n:
			+step = Division.step(remainder, 0, denominator)
			Number.round(significand, exponent, SmallPair.first(step), U32.is_ne(SmallPair.second(step), 0))
		case 1n+rest:
			+step = Division.step(remainder, 0, denominator)
			Division.fraction(rest, Wide.add(Wide.shl(significand), Wide{0, SmallPair.first(step)}),
				exponent, SmallPair.second(step), denominator)

def Division.leading(fuel: Nat, remainder: U32, +denominator: U32, exponent: U32, leading: U32) -> Binary64:
	match fuel leading:
		case _ 1:
			Division.fraction(52n, Wide{0, 1}, exponent, remainder, denominator)
		case 0n _:
			Binary64{0, 0}
		case 1n+rest _:
			+step = Division.step(remainder, 0, denominator)
			Division.leading(rest, SmallPair.second(step), denominator, (exponent - 1 : U32), SmallPair.first(step))

def Division.finish.zero(zero: Bool, remainder_zero: Bool, integer: Wide, remainder: U32, +denominator: U32) -> Binary64:
	match zero remainder_zero:
		case True{} True{}:
			Binary64{0, 0}
		case True{} False{}:
			Division.leading(32n, remainder, denominator, 1023, 0)
		case False{} _:
			Wide{+high, +low} = integer
			+top = Bool.pick(Nat, U32.is_zero(high), U32.log2(low), Nat.add(32n, U32.log2(high)))
			Division.fraction(Nat.sub(52n, top), Wide{high, low},
				(1023 + U32.from_nat(top) : U32), remainder, denominator)

def Division.finish(result: Quotient, +denominator: U32) -> Binary64:
	Quotient{+integer, +remainder} = result
	Division.finish.zero(Wide.is_zero(integer), U32.is_zero(remainder), integer, remainder, denominator)

def Number.sample.valid(zero_frames: Bool, invalid_elapsed: Bool, elapsed: Elapsed, +frames: U32) -> Result<&2, &2, String, Binary64>:
	match zero_frames invalid_elapsed:
		case True{} _:
			Fail{"frame denominator must be positive"}
		case False{} True{}:
			Fail{"elapsed_ms exceeds 281474976710655"}
		case False{} False{}:
			Elapsed{high, low} = elapsed
			Done{Division.finish(Division.integer(64n, Wide{high, low}, frames, Wide{0, 0}, 0), frames)}

def Number.sample(+elapsed: Elapsed, +frames: U32) -> Result<&2, &2, String, Binary64>:
	Elapsed{high, low} = elapsed
	Number.sample.valid(U32.is_zero(frames), U32.is_gt(high, 65535), elapsed, frames)

def Elapsed.read.go(text: String, high: U32, +low: U32, valid: Bool, ascii: Bool) -> Result<&2, &2, String, Elapsed>:
	match text valid ascii:
		case _ _ False{}:
			Fail{"elapsed_ms must be nonempty unsigned ASCII decimal"}
		case _ False{} True{}:
			Fail{"elapsed_ms exceeds 281474976710655"}
		case SNil{} True{} True{}:
			Done{Elapsed{high, low}}
		case SCon{Chr{+code}, rest} True{} True{}:
			+digit = (code - 48 : U32)
			+lower = ((low .&. 65535) * 10 + digit : U32)
			+upper = ((low >> 16n) * 10 + (lower >> 16n) : U32)
			+next_high = (high * 10 + (upper >> 16n) : U32)
			Elapsed.read.go(rest, next_high, (upper << 16n .|. lower .&. 65535 : U32),
				U32.is_le(next_high, 65535), U32.is_le(digit, 9))

def Elapsed.read(text: String) -> Result<&2, &2, String, Elapsed>:
	match text:
		case SNil{}:
			Fail{"elapsed_ms must be nonempty unsigned ASCII decimal"}
		case SCon{head, rest}:
			Elapsed.read.go(SCon{head, rest}, 0, 0, True{}, True{})

def Number.compare.words(order: Cmp, left_low: U32, right_low: U32) -> Cmp:
	match order:
		case EQ{}:
			U32.cmp(left_low, right_low)
		case LT{}:
			LT{}
		case GT{}:
			GT{}

def Number.compare(left: Binary64, right: Binary64) -> Cmp:
	Binary64{left_high, left_low} = left
	Binary64{right_high, right_low} = right
	Number.compare.words(U32.cmp(left_high, right_high), left_low, right_low)

def Number.half(value: Binary64) -> Binary64:
	Binary64{+high, +low} = value
	Bool.pick(Binary64, U32.is_zero(high) && U32.is_zero(low), Binary64{0, 0}, Binary64{(high - 1048576 : U32), low})

def Number.sum.round(value: Wide, exponent: U32) -> Binary64:
	Wide{high, +low} = value
	+tail = (low .&. 7 : U32)
	Number.round(Wide.shr(Wide.shr(Wide.shr(Wide{high, low}))), exponent,
		Bool.to_u32(U32.is_ge(tail, 4)), U32.is_ne((tail .&. 3 : U32), 0))

def Number.sum.normalize(value: Wide, +exponent: U32) -> Binary64:
	Wide{+high, low} = value
	+mantissa = {Wide{high, low} : Wide}
	Bool.pick(Binary64, U32.is_ge(high, 16777216),
		Number.sum.round(Wide.shr_jam(1n, mantissa), (exponent + 1 : U32)),
		Number.sum.round(mantissa, exponent))

def Number.sum.ordered(left: Binary64, right: Binary64) -> Binary64:
	Binary64{+left_high, left_low} = left
	Binary64{+right_high, right_low} = right
	+exponent = (left_high >> 20n : U32)
	shift = U32.to_nat((exponent - (right_high >> 20n) : U32))
	left_mantissa = Wide.shln(3n, Wide{(left_high .&. 1048575 .|. 1048576 : U32), left_low})
	right_mantissa = Wide.shr_jam(shift, Wide.shln(3n, Wide{(right_high .&. 1048575 .|. 1048576 : U32), right_low}))
	Number.sum.normalize(Wide.add(left_mantissa, right_mantissa), exponent)

def Number.midpoint.valid(left_zero: Bool, right_zero: Bool, order: Cmp, left: Binary64, right: Binary64) -> Binary64:
	match left_zero right_zero order:
		case True{} _ _:
			Number.half(right)
		case False{} True{} _:
			Number.half(left)
		case False{} False{} LT{}:
			Number.half(Number.sum.ordered(right, left))
		case False{} False{} EQ{}:
			Number.half(Number.sum.ordered(left, right))
		case False{} False{} GT{}:
			Number.half(Number.sum.ordered(left, right))

def Number.midpoint(+left: Binary64, +right: Binary64) -> Binary64:
	Binary64{left_high, left_low} = left
	Binary64{right_high, right_low} = right
	Number.midpoint.valid(U32.is_zero(left_high) && U32.is_zero(left_low),
		U32.is_zero(right_high) && U32.is_zero(right_low), Number.compare(left, right), left, right)

def Decimal.limb(+limb: U32, remainder: U32) -> SmallPair:
	+value = (remainder * 65536 + limb : U32)
	SmallPair{(value / 10 : U32), (value % 10 : U32)}

def Decimal.div10(value: Wide) -> Quotient:
	Wide{+high, +low} = value
	+a = Decimal.limb((high >> 16n : U32), 0)
	+b = Decimal.limb((high .&. 65535 : U32), SmallPair.second(a))
	+c = Decimal.limb((low >> 16n : U32), SmallPair.second(b))
	+d = Decimal.limb((low .&. 65535 : U32), SmallPair.second(c))
	Quotient{Wide{(SmallPair.first(a) << 16n .|. SmallPair.first(b) : U32),
		(SmallPair.first(c) << 16n .|. SmallPair.first(d) : U32)}, SmallPair.second(d)}

def Quotient.integer(value: Quotient) -> Wide:
	Quotient{integer, remainder} = value
	integer

def Quotient.remainder(value: Quotient) -> U32:
	Quotient{integer, remainder} = value
	remainder

def Decimal.integer(fuel: Nat, value: Wide, zero: Bool) -> List<&2, U32>:
	match fuel zero:
		case 0n _:
			Nil{}
		case 1n+rest True{}:
			Nil{}
		case 1n+rest False{}:
			+divided = Decimal.div10(value)
			+quotient = Quotient.integer(divided)
			Quotient.remainder(divided) <> Decimal.integer(rest, quotient, Wide.is_zero(quotient))

def Decimal.mul(digits: List<&2, U32>, +factor: U32, carry: U32) -> List<&2, U32>:
	match digits:
		case Nil{}:
			+last = carry
			Bool.pick(List<&2, U32>, U32.is_zero(last), Nil{}, [last])
		case Con{digit, rest}:
			+value = (digit * factor + carry : U32)
			(value % 10 : U32) <> Decimal.mul(rest, factor, (value / 10 : U32))

def Decimal.power(count: Nat, digits: List<&2, U32>, +factor: U32) -> List<&2, U32>:
	match count:
		case 0n:
			digits
		case 1n+rest:
			Decimal.power(rest, Decimal.mul(digits, factor, 0), factor)

def Decimal.trim(digits: List<&2, U32>, places: Nat) -> Decimal:
	match digits places:
		case Con{0, rest} 1n+remaining:
			Decimal.trim(rest, remaining)
		case _ _:
			Decimal{digits, places}

def Number.decimal.parts(zero: Bool, significand: Wide, exponent: U32) -> Decimal:
	match zero:
		case True{}:
			Decimal{[0], 0n}
		case False{}:
			+places = U32.to_nat((1075 - exponent : U32))
			Decimal.trim(Decimal.power(places, Decimal.integer(16n, significand, False{}), 5), places)

def Number.decimal(value: Binary64) -> Decimal:
	Binary64{+high, +low} = value
	Number.decimal.parts(U32.is_zero(high) && U32.is_zero(low),
		Wide{(high .&. 1048575 .|. 1048576 : U32), low}, (high >> 20n : U32))

def Decimal.string(digits: List<&2, U32>, acc: String) -> String:
	match digits:
		case Nil{}:
			match acc:
				case SNil{}:
					"0"
				case _:
					acc
		case Con{digit, rest}:
			Decimal.string(rest, SCon{Chr{(48 + digit : U32)}, acc})

def Decimal.render.parts(wide: Bool, +text: String, +length: Nat, +places: Nat) -> String:
	match wide:
		case True{}:
			+whole = Nat.sub(length, places)
			String.take(text, whole) ++ "." ++ String.drop(text, whole)
		case False{}:
			"0." ++ String.repeat("0", Nat.sub(places, length)) ++ text

def Decimal.render(digits: List<&2, U32>, +places: Nat) -> String:
	+text = Decimal.string(digits, "")
	+length = String.length(text)
	Decimal.render.parts(Nat.is_gt(length, places), text, length, places)

def Number.json.decimal(value: Decimal) -> String:
	Decimal{digits, places} = value
	match places:
		case 0n:
			Decimal.string(digits, "") ++ ".0"
		case 1n+rest:
			Decimal.render(digits, 1n+rest)

def Number.json(value: Binary64) -> String:
	Number.json.decimal(Number.decimal(value))

def Decimal.inc(digits: List<&2, U32>) -> List<&2, U32>:
	match digits:
		case Nil{}:
			[1]
		case Con{9, rest}:
			0 <> Decimal.inc(rest)
		case Con{digit, rest}:
			(digit + 1 : U32) <> rest

def Decimal.is_odd(digits: List<&2, U32>) -> Bool:
	match digits:
		case Nil{}:
			False{}
		case Con{digit, rest}:
			U32.is_ne((digit .&. 1 : U32), 0)

def Decimal.round(count: Nat, digits: List<&2, U32>, sticky: Bool) -> List<&2, U32>:
	match count digits:
		case 0n _:
			digits
		case 1n+rest Nil{}:
			Nil{}
		case 1n+0n Con{+digit, +remaining}:
			Bool.pick(List<&2, U32>, U32.is_gt(digit, 5) || (U32.is_eq(digit, 5) && (sticky || Decimal.is_odd(remaining))),
				Decimal.inc(remaining), remaining)
		case 1n+1n+rest Con{digit, remaining}:
			Decimal.round(1n+rest, remaining, sticky || U32.is_ne(digit, 0))

def Decimal.zeros(count: Nat, digits: List<&2, U32>) -> List<&2, U32>:
	match count:
		case 0n:
			digits
		case 1n+rest:
			0 <> Decimal.zeros(rest, digits)

def Number.fixed3.parts(fractional: Bool, digits: List<&2, U32>, places: Nat) -> String:
	match fractional:
		case True{}:
			Decimal.render(Decimal.round(Nat.sub(places, 3n), digits, False{}), 3n)
		case False{}:
			Decimal.render(Decimal.zeros(Nat.sub(3n, places), digits), 3n)

def Number.fixed3.decimal(value: Decimal) -> String:
	Decimal{digits, +places} = value
	Number.fixed3.parts(Nat.is_gt(places, 3n), digits, places)

def Number.fixed3(value: Binary64) -> String:
	Number.fixed3.decimal(Number.decimal(value))
