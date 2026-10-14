import Base

type H8 is Data:
	H8{a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32}

type Words16 is Data:
	Words16{w0: U32, w1: U32, w2: U32, w3: U32,
		w4: U32, w5: U32, w6: U32, w7: U32,
		w8: U32, w9: U32, w10: U32, w11: U32,
		w12: U32, w13: U32, w14: U32, w15: U32}

type Context is Data:
	Ready{hash: H8, words: Words16, partial: U32, used: U32, low: U32, high: U32}
	Invalid{error: String}

def Words16.zero() -> Words16:
	Words16{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

def Words16.append(words: Words16, word: U32) -> Words16:
	Words16{w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15} = words
	Words16{w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15, word}

def SHA256.rotate(+word: U32, +right: Nat) -> U32:
	(word >> right .|. word << Nat.sub(32n, right) : U32)

def SHA256.big0(+word: U32) -> U32:
	(SHA256.rotate(word, 2n) .^. SHA256.rotate(word, 13n) .^. SHA256.rotate(word, 22n) : U32)

def SHA256.big1(+word: U32) -> U32:
	(SHA256.rotate(word, 6n) .^. SHA256.rotate(word, 11n) .^. SHA256.rotate(word, 25n) : U32)

def SHA256.small0(+word: U32) -> U32:
	(SHA256.rotate(word, 7n) .^. SHA256.rotate(word, 18n) .^. word >> 3n : U32)

def SHA256.small1(+word: U32) -> U32:
	(SHA256.rotate(word, 17n) .^. SHA256.rotate(word, 19n) .^. word >> 10n : U32)

def SHA256.choose(+x: U32, y: U32, z: U32) -> U32:
	(x .&. y .^. U32.not(x) .&. z : U32)

def SHA256.majority(+x: U32, +y: U32, +z: U32) -> U32:
	(x .&. y .^. x .&. z .^. y .&. z : U32)

def H8.add(left: H8, right: H8) -> H8:
	H8{a, b, c, d, e, f, g, h} = left
	H8{i, j, k, l, m, n, o, p} = right
	H8{(a + i : U32), (b + j : U32), (c + k : U32), (d + l : U32),
		(e + m : U32), (f + n : U32), (g + o : U32), (h + p : U32)}

def SHA256.round(state: H8, constant: U32, word: U32) -> H8:
	H8{+a, +b, +c, d, +e, +f, +g, h} = state
	+t1 = (h + SHA256.big1(e) + SHA256.choose(e, f, g) + constant + word : U32)
	t2 = (SHA256.big0(a) + SHA256.majority(a, b, c) : U32)
	H8{(t1 + t2 : U32), a, b, c, (d + t1 : U32), e, f, g}

def SHA256.constants() -> List<&2, U32>:
	[1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221,
	 3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580,
	 3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986,
	 2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895,
	 666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037,
	 2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344,
	 430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779,
	 1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298]

def SHA256.rounds(constants: List<&2, U32>, initial: H8, state: H8, words: Words16, +index: U32) -> H8:
	match constants words:
		case Nil{} _:
			H8.add(initial, state)
		case Con{constant, rest} Words16{+w0, +w1, w2, w3, w4, w5, w6, w7, w8, +w9, w10, w11, w12, w13, +w14, w15}:
			+word = Bool.pick(U32, U32.is_lt(index, 16), w0,
				(SHA256.small1(w14) + w9 + SHA256.small0(w1) + w0 : U32))
			SHA256.rounds(rest, initial, SHA256.round(state, constant, word),
				Words16{w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15, word},
				(index + 1 : U32))

def SHA256.compress(+hash: H8, words: Words16) -> H8:
	SHA256.rounds(SHA256.constants(), hash, hash, words, 0)

def SHA256.init() -> Context:
	Ready{H8{1779033703, 3144134277, 1013904242, 2773480762,
		1359893119, 2600822924, 528734635, 1541459225}, Words16.zero(), 0, 0, 0, 0}

def SHA256.block(full: Bool, hash: H8, words: Words16, used: U32, low: U32, high: U32) -> Context:
	match full:
		case True{}:
			Ready{SHA256.compress(hash, words), Words16.zero(), 0, 0, low, high}
		case False{}:
			Ready{hash, words, 0, used, low, high}

def SHA256.word(complete: Bool, hash: H8, words: Words16, partial: U32, +used: U32, low: U32, high: U32) -> Context:
	match complete:
		case True{}:
			SHA256.block(U32.is_eq(used, 64), hash, Words16.append(words, partial), used, low, high)
		case False{}:
			Ready{hash, words, partial, used, low, high}

def SHA256.absorb(context: Context, byte: U32) -> Context:
	match context:
		case Invalid{error}:
			Invalid{error}
		case Ready{hash, words, partial, used, low, high}:
			+next = (used + 1 : U32)
			SHA256.word(U32.is_zero((next .&. 3 : U32)), hash, words,
				(partial << 8n .|. byte : U32), next, low, high)

def SHA256.update.valid(valid: Bool, context: Context, byte: U32) -> Context:
	match valid context:
		case False{} _:
			Invalid{"SHA-256 requires bytes in 0..255 and fewer than 2^64 input bits"}
		case True{} Ready{hash, words, partial, used, low, high}:
			+next = (low + 1 : U32)
			SHA256.absorb(Ready{hash, words, partial, used, next,
				(high + Bool.to_u32(U32.is_zero(next)) : U32)}, byte)
		case True{} Invalid{error}:
			Invalid{error}

def SHA256.update(context: Context, +byte: U32) -> Context:
	match context:
		case Invalid{error}:
			Invalid{error}
		case Ready{hash, words, partial, used, +low, +high}:
			# Byte counts stop at 2^61-1 so their bit length fits the FIPS 64-bit field.
			valid = U32.is_le(byte, 255) && U32.is_lt(high, 536870912) &&
				Bool.not(U32.is_eq(high, 536870911) && U32.is_eq(low, 4294967295))
			SHA256.update.valid(valid, Ready{hash, words, partial, used, low, high}, byte)

def SHA256.pad(zeros: Nat, context: Context) -> Context:
	match zeros:
		case 0n:
			context
		case 1n+rest:
			SHA256.pad(rest, SHA256.absorb(context, 0))

def SHA256.hex.digit(+nibble: U32) -> Char:
	Chr{Bool.pick(U32, U32.is_lt(nibble, 10), (48 + nibble : U32), (87 + nibble : U32))}

def SHA256.hex.word(digits: Nat, +word: U32, acc: String) -> String:
	match digits:
		case 0n:
			acc
		case 1n+rest:
			SHA256.hex.word(rest, (word >> 4n : U32), SCon{SHA256.hex.digit((word .&. 15 : U32)), acc})

def H8.hex(hash: H8) -> String:
	H8{a, b, c, d, e, f, g, h} = hash
	SHA256.hex.word(8n, a, "") ++ SHA256.hex.word(8n, b, "") ++
		SHA256.hex.word(8n, c, "") ++ SHA256.hex.word(8n, d, "") ++
		SHA256.hex.word(8n, e, "") ++ SHA256.hex.word(8n, f, "") ++
		SHA256.hex.word(8n, g, "") ++ SHA256.hex.word(8n, h, "")

def SHA256.finish.block(context: Context) -> Result<&2, &2, String, String>:
	match context:
		case Invalid{error}:
			Fail{error}
		case Ready{hash, words, partial, used, +low, high}:
			upper = (high << 3n .|. low >> 29n : U32)
			lower = (low << 3n : U32)
			Done{H8.hex(SHA256.compress(hash, Words16.append(Words16.append(words, upper), lower)))}

def SHA256.finish(context: Context) -> Result<&2, &2, String, String>:
	match context:
		case Invalid{error}:
			Fail{error}
		case Ready{hash, words, partial, +used, low, high}:
			zeros = ((55 - used) .&. 63 : U32)
			SHA256.finish.block(SHA256.pad(U32.to_nat(zeros),
				SHA256.absorb(Ready{hash, words, partial, used, low, high}, 128)))

def SHA256.bytes(bytes: List<&2, U32>, context: Context) -> Context:
	match bytes:
		case Nil{}:
			context
		case Con{byte, rest}:
			SHA256.bytes(rest, SHA256.update(context, byte))

def SHA256.digest(bytes: List<&2, U32>) -> Result<&2, &2, String, String>:
	SHA256.finish(SHA256.bytes(bytes, SHA256.init()))
