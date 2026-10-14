*English | [Русский](ru/language-notes.md)*

# Bend 2 (2.0.5) — verified language notes

Everything below was verified by running on this machine: `bend 2.0.5`, clang-19 (19.1.1),
32 cores, an **RTX 4090 Laptop** (see §5 about CUDA). Always launch through the wrapper
`tools/bend` (`BEND_HOME` inside the working copy):

```sh
tools/bend file.bend            # check, then run on the JS backend
tools/bend file.bend -o out     # native binary via clang
tools/bend file.bend -o out.c   # C only
tools/bend file.bend -o out.js  # JS only
tools/bend PROOF.bend           # the laws gate
```

The experiment programs kept for this text live in `probes/`: `probes/raster/`
(the renderer experiments), `probes/bench/` (the parallel measurements), and
`probes/limits/` with `probes/neg/` (the laws and proofs). The command in the
header of each program is reproducible.

The main idea: Bend barely infers types, but its errors are precise — almost every
error prints `expected`/`observed` and a location. The language is affine by default,
termination is mandatory, and `match` is not an expression.

---

## 1. Syntax mini-cheatsheet

### Types, def, match

```python
import Base

type Shape is Data:
  Circle{r: U32}
  Square{s: U32}

def area(x: Shape) -> U32:
  match x:
    case Circle{+r}:
      (3 * r * r : U32)
    case Square{+s}:
      (s * s : U32)

def main() -> U32:
  area(Square{5})          # -> 25
```

`is Data` — values are copyable (`Kind(&2)`), `is Type` — they are not (`Kind(&1)`).
`def` is a function, its body after the `:`.
A `main` returning a non-`IO` type is not executed at runtime but **normalized by the
checker** and printed (see §8, this is a trap).

### Quantity annotations

```python
def replicate(-A: Data, n: Nat, +x: A) -> List<A>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      x <> replicate(A, p, x)
# replicate(U32, 3n, 7) -> [7, 7, 7]
```

| label | meaning |
|---|---|
| `-x` | erased: visible to the checker, removed by the compiler, types/proofs only |
| `x` | affine (default): at most one use |
| `+x` | reusable: requires `Data`; at runtime — a refcount |
| `+A: Data` | a quantity on the *type*: `Type` = `Kind(&1)`, `Data` = `Kind(&2)`, `Kind(a)` accepts either |

Matching `+`-values yields `+`-fields; on an affine value write `+r` in the pattern
so the field becomes reusable (`case Circle{+r}`).

### Kinds

```python
def length(a, -A: Kind(a), xs: List<a, A>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{h, t}:
      1n+length(a, A, t)

# length(&2, U32, [1, 2, 3]) -> 3n
```

### Templates (`~f`)

```python
def twice(~f: U32 -> U32, x: U32) -> U32:
  f(f(x))

# twice(~(x => (x + 1 : U32)), 40) -> 42
```

Substitution happens at compile time; a `~` argument must be closed (top-level names
only, no locals of the caller); template parameters come first; a template may call only
templates declared **above** it; each set of `~` arguments gets its own copy. At the
call site **all** template arguments need `~`, otherwise `expected : a term /
observed : '~'`:

```python
List.show(~&2, ~U32, ~U32.show, [1, 2, 3])   # ok -> "[1, 2, 3]"
List.show(&2, U32, ~U32.show, [1, 2, 3])     # error: observed '~'
```

### Closures

```python
def adder(k: U32) -> U32 -> U32:
  x => (x + k : U32)

def main() -> U32:
  add2 = adder(2)
  add5 = adder(5)
  add5(add2(1))            # -> 8
```

A closure is affine — it can be called at most once, even if everything it captures is
`Data`. `U32.add(2)` (partial application) is also a closure. A top-level `def` can be
called freely.

### `do` blocks

```python
do IO<Unit>:
  x : A <- m            # bind: x : A <- action
  x : A = v             # let inside do (this is the only place with `x : T = v`)
  m                     # a step of type Unit
  return v
```

`do M<xs.., R>:` works for any M with `M.bind`/`M.pure`: `IO`, `Maybe`,
`Result`. The example `do Maybe<&2, U32>:` from the guide was verified — `Some{42}`.

### Operators

Inside `(.. : T)` the operators `+ - * / %` call `T.add`…`T.mod`,
`.&. .|. .^.` are bitwise, `<< >>` are shifts (the shift is a `Nat`), `< <= > >=` are the
`T.is_lt` family. **Without `: T` they belong to `Nat`** — and that breaks
comparisons/arithmetic on `U32` (see §2). `&& ||` are `Bool` only, `++` is
`String`, `<>` is cons. Spaces around operators are mandatory per the spec,
but `(1+2 : U32)` does pass in practice (`-> 3`).

### Literals

| literal | type |
|---|---|
| `42` | `U32` (always, even when `Nat`/`F32` is expected) |
| `3n`, `1n+p` | `Nat` (a machine word, aborts past 2^48−1) |
| `1.5`, `0.0` | `F32` |
| `'c'` | `Char` |
| `"s"` | `String` |
| `[a, b]`, `h <> t` | `List` |
| `(a, b)` | `A & B` (this is a `Sigma`, kind `Type`, not `Data`) |

Literals are not converted implicitly: `(1n + 1 : U32)` →
`expected : U32 / observed : Nat`.

---

## 2. Rules and pitfalls (all verified)

![Four rules: declaration order is part of the program, mutual recursion is forbidden, match is a statement, only a parameter can be destructured](../assets/readme/language-rules.svg)

### 2.1 `match` is not a term: it does not exist in a `do` block

```python
do IO<Unit>:
  x : U32 = 3
  match x:            # error
    case 0:
      IO.print("zero")
```

```
Error:
- expected : a term (a match heads a def body, not a term)
- observed : ' '
```

The `observed` here is a space, and the message is misleading. The same happens if
`match` sits to the right of `=` in `do` (`y : U32 = match x:`).

Workaround: move it into a separate `def` and call that.

```python
def describe(x: U32) -> String:
  match x:
    case 0:
      "zero"
    case _:
      "other"

def main() -> IO(Unit):
  do IO<Unit>:
    x : U32 = 3
    s : String = describe(x)
    IO.print(s)          # -> other
```

`match` **is** an expression of a `def`/`case`/lambda body: `def describe(x) -> String:
match x: ...` works and returns a value (`match x:` as the last term).

### 2.2 `let` before `match` on a parameter is forbidden

```python
def f(x: U32) -> U32:
  y = x
  match x:            # error
    case 0: 1
    case _: y
```

```
- message : match scrutinees in binder order (this variable is unbound, consumed, or out of order: reorder the match)
```

The rule: scrutinee variables follow binder order; a `let` before `match`
"eats" the parameter. Workaround — `match` first, and the `let` inside the branches:
`case _: y = {x : U32}; y` (in a `def` body an annotated `let` is not written:
`y : U32 = x` there is a syntax error `expected : 'def', 'type' or 'law' /
observed : ':'`; `{x : U32}` is needed).

The same order is required with several scrutinees: `match ys xs:` with `def f(xs, ys)`
fails with the same message.

### 2.3 `match` only on a parameter/pattern field

```python
match U32.add(x, 1):   # error
```

```
- message : a parameter or field scrutinee (a match cannot scrutinize a computed value: give it its own def)
```

Workaround: pass the computed value into a helper `def` that matches on its parameter.

### 2.4 Affine: twice without `+` is not allowed; drop is free

```python
def f(x: U32) -> U32:
  (x + x : U32)
```

```
- expected : x
- observed : x (consumed more than once)
```

```python
def f(+x: U32) -> U32:
  (x + x : U32)          # -> 6 for f(3)
```

```python
def f(x: U32, y: String) -> U32:
  7                       # y is dropped — that's fine, affine = "at most once"
```

`+` cannot be put on a function/`Array`/IO handle: `def f(+g: U32 -> U32, ...)` →
`expected : Data / observed : Type`. A pair `A & B` is also `Type`:
`+p : U32 & U32 = (1, 2)` → `expected : Data / observed : Type`.

`main` with a parameter is not executed but printed as a value: `def main(x: U32)
-> U32: x` prints `x => x` (verified).

### 2.5 Termination is mandatory

```python
def loop(x: U32) -> U32:
  loop(x)
```

```
- expected : a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks)
- observed : loop
```

The rule: a recursive call's arguments are read left to right; each one up to the
"shrinking" one is passed unchanged. So put the shrinking parameter **first**:

```python
def f(acc: U32, xs: List<U32>) -> U32:   # error: xs is second
  match xs:
    case Nil{}: acc
    case h <> t: f((acc + h : U32), t)
```

```
- expected : a decreasing self-call (...)
- observed : f
```

It works when the first parameter shrinks:

```python
def sum(xs: List<U32>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case h <> t: sum(t, (acc + h : U32))
# sum([1,2,3,4], 0) -> 10
```

Mutual recursion is forbidden — `odd` declared below `even`, error:
`expected : a defined name / observed : odd`. The guide's workaround is a single `def`
with an extra selector argument.

`Nat` gives `case 1n+p`, `U32` does not:

```python
def f(x: U32) -> U32:
  match x:
    case 0: 0
    case 1n+p: 1        # error, and the text is strange
```

```
- expected : cases for True
- observed : \{}
```

That is why counters are `Nat`:

```python
def count(n: Nat, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p: count(p, (acc + 1 : U32))
# count(5n, 0) -> 5
```

`@unsafe def` lifts the termination check; a program with `@unsafe def loop(x:
U32) -> U32: loop(x)` compiles and **hangs** (here — `timeout 30`,
exit 124).

### 2.6 Numbers: there are no implicit conversions

| expression | result |
|---|---|
| `(7 / 2 : U32)` | `3` |
| `(7 % 2 : U32)` | `1` |
| `(7 / 0 : U32)` | `0` (not an error!) |
| `(7 % 0 : U32)` | `7` |
| `(7n / 2n : Nat)` | `3n` |
| `(7n / 0n : Nat)` | `0n` |
| `(7.0 / 2.0 : F32)` | `3.5` |
| `(7.0 % 2.0 : F32)` | `1.0` |
| `(1.0 / 0.0 : F32)` | `inf` |
| `(0.0 / 0.0 : F32)` | `nan` |
| `U32.add(4294967295, 1)` | `0` (wrap) |
| `U32.sub(0, 1)` | `4294967295` |
| `Nat.mul(2^24, 2^24)` | abort: `bend: a Nat past the largest immediate 2^48-1` (exit 1) |

Conversions are explicit only: `U32.to_nat`, `U32.from_nat`, `U32.to_f32` (law),
`F32.to_nat`, `F32.from_nat`. `U32.add(a, 1)` with `a: Nat` →
`expected : U32 / observed : Nat`.

Comparisons also default to `Nat` — this breaks `U32`:

```python
def f(x: U32) -> Bool:
  (x < 5)
```

```
- expected : Nat
- observed : U32
Context:
- x : U32
```

You need it explicit: `(x < 5 : U32)`. That is why the file `app_ray_tracer_3d/main.bend`
writes `(a < b : F32)`, `(fps < 100 : U32)` everywhere.

A trap with `: T` on a compound expression: `(e : T)` is **not a type cast**
but "treat the operators inside `e` as T". Therefore
`((x < 96) && (y < 40) : U32)` compiles and yields a **Bool** if the function's declared
type is `Bool`; but it fails if the function is declared `-> U32`
(`expected : U32 / observed : Bool`). `{e : T}` is not a conversion either:
`{3 : Nat}` gives `expected : Nat / observed : U32`.

### 2.7 `if` does not exist

```python
if x == 0:
```

```
- expected : a term
- observed : '='
```

Branching is `match` on `True{}`/`False{}` or `Bool.pick(-A, c, a, b)`.
`&&`/`||` work on `Bool` only: `a && b` with `a b : U32` →
`expected : Bool / observed : U32`. In the ray tracer `((x < 96) && (y < 40) : U32)`
works precisely because `<` yields a `Bool` and `&&` is `Bool.and`.

There is no unary minus: `-1.0` → `expected : a name / observed : '1'`; people write
`(0.0 - 1.0 : F32)`.

### 2.8 Annotations on `let`

* in a `def`/`case` body — only `x = {3 : U32}` (otherwise
  `expected : an annotated term (cannot infer) / observed : 3`);
* in a `do` block — `x : T = v` (the annotation is mandatory for non-literals);
* a function type in a `do`-let must be parenthesized: `f : (U32 -> U32) = (x => ...)`
  — without parentheses `expected : '<-' / observed : '-'`.

### 2.9 Other verified restrictions

* **No field projections.** `p.fst`, `p.snd`, `r.x` → `expected : a defined name /
  observed : p.fst`. Pairs/records are unpacked only by `(a, b) = p` in a
  `def` body, not in `do`.
* **Destructuring inside `do` is forbidden**: `(a, b) = p` in a block →
  `expected : a pattern (a binder or a constructor) observed : ...`.
  You have to introduce a helper `def` that takes the pair and unpacks it.
* **Comments are `#` only.** `//` → `expected : 'def', 'type' or 'law' /
  observed : '/'`.
* **`String.show` does not exist** (verified: `expected : a defined name /
  observed : String.show`). Strings print as they are; for `List.show` over
  strings you need your own `def sh(s: String) -> String: s`.
* **`List.map` returns `List<&1, B>`** (`~A: Type`), while `List.show` is parametric
  in quantity: on the result of `map` you must write `List.show(~&1, ...)`, otherwise
  `expected : List<&2, U32> / observed : List<&1, U32>`.
* **`Map.get`/`Map.has` are pure**, not `IO`: `<-` gives
  `expected : @-R:Type -> ... observed : Sigma<...>`. Use `=`.
* **A template argument must be a closed name.** The law `for -f: U32 -> U32`
  with `List.map(~U32, ~U32, ~f, xs)` cannot be expressed at all:
  `expected : a defined name / observed : List.map`.
* **Matching `+`-fields must be explicit**: `case Node{l, r}` with repeated use of
  `l`/`r` → `expected : r / observed : r (consumed more than once)`;
  write `case Node{+l, +r}`. In a `Nat` pattern — `case 1n++p`, so that `p` is
  reusable.

---

## 3. The Base API by section

Signatures are copied from `bend base <Name>`. `law` entries (for F32 — all
arithmetic ones) have no body: they are unprovable built-in operations (see §6).

### F32

`type F32 is Data: F32{data: Word(32n)}`.

All arithmetic and comparison operations are **`law`** (opaque, they do not reduce in
proofs):

```
F32.to_u32(a: F32) -> U32
F32.add(a, b) -> F32      F32.sub(a, b) -> F32      F32.mul(a, b) -> F32
F32.div(a, b) -> F32      F32.mod(a, b) -> F32      F32.pow(a, b) -> F32
F32.atan2(a, b) -> F32
F32.neg(a) -> F32   F32.abs(a) -> F32   F32.sqrt(a) -> F32  F32.exp(a) -> F32
F32.log(a)  F32.log2(a)  F32.log10(a)
F32.sin(a)  F32.cos(a)  F32.tan(a)  F32.asin(a)  F32.acos(a)  F32.atan(a)
F32.sinh(a) F32.cosh(a) F32.tanh(a)
F32.floor(a) F32.ceil(a) F32.trunc(a)
F32.is_eq(a,b) F32.is_ne(a,b) F32.is_lt(a,b) F32.is_le(a,b) F32.is_gt(a,b) F32.is_ge(a,b) -> Bool
F32.show(+a) -> String    F32.bits(a) -> U32    F32.read(s) -> Maybe<&2, F32>
```

Ordinary `def`s (built on top of the `law`s):

```
F32.min(+a, +b) -> F32          F32.max(+a, +b) -> F32
F32.clamp(x, lo, hi) -> F32     F32.lerp(+a, b, t) -> F32
F32.square(+a) -> F32           F32.hypot(+x, +y) -> F32
F32.round(a) -> F32             F32.pi() -> F32
F32.from_nat(n: Nat) -> F32     F32.to_nat(a: F32) -> Nat
```

### U32

```
U32.inc(a) -> U32
U32.add(a, b) -> U32    U32.sub(a, b) -> U32    U32.mul(a, b) -> U32
U32.not(a) U32.and(a,b) U32.or(a,b) U32.xor(a,b) -> U32
U32.shl(a) U32.shr(a) -> U32        U32.shln(a, n: Nat) U32.shrn(a, n: Nat) -> U32
U32.cmp(a, b) -> Cmp
U32.is_eq/is_ne/is_lt/is_le/is_gt/is_ge(a, b) -> Bool
U32.is_zero(a) -> Bool   U32.is_even(a) -> Bool
U32.to_nat(a) -> Nat     U32.from_nat(n) -> U32
U32.div(a, +b) -> U32    U32.mod(a, +b) -> U32
U32.min(+a,+b) U32.max(+a,+b) -> U32   U32.clamp(x, lo, hi) -> U32
U32.pow(+a, n: Nat) -> U32
U32.show(a) -> String    U32.read(s) -> Maybe<&2, U32>
law U32.to_f32: for a: U32 -> F32
law U32.add_comm: {U32.add(a,b) == U32.add(b,a) : U32}   # proved in Base
```

### Nat

```
Nat.double(n) -> Nat
Nat.add(a, b) -> Nat   Nat.sub(a, b) -> Nat   Nat.mul(a, +b) -> Nat
Nat.divmod(a, b) -> Nat & Nat
Nat.div(a, b) -> Nat   Nat.mod(a, b) -> Nat   Nat.pow(+a, b) -> Nat
Nat.cmp(a, b) -> Cmp
Nat.is_lt/is_eq/is_ne/is_le/is_gt/is_ge(a, b) -> Bool
Nat.min(+a,+b) Nat.max(+a,+b) -> Nat
Nat.show(n) -> String  Nat.read(s) -> Maybe<&2, Nat>
```

### Bool

```
Bool.not(b) -> Bool       Bool.and(a, b) -> Bool     Bool.or(a, b) -> Bool
Bool.xor(a, b) -> Bool    Bool.cmp(a, b) -> Cmp
Bool.full_add(a, b, c) -> Bool & Bool
Bool.pick(-A: Type, c: Bool, a: A, b: A) -> A
Bool.to_u32(b) -> U32     Bool.show(b) -> String
```

### Cmp

```
Cmp.is_lt(c)  Cmp.is_eq(c)  Cmp.is_gt(c)  Cmp.is_le(c)  Cmp.is_ge(c) -> Bool
```

### Maybe

```
Maybe.pure(a, -A: Kind(a), x: A) -> Maybe<a, A>
Maybe.bind(a, -A, -B: Kind(a), m: Maybe<a,A>, f: A -> Maybe<a,B>) -> Maybe<a,B>
Maybe.default(a, -A, m, d: A) -> A
Maybe.is_some(a, -A, m) -> Bool     Maybe.is_none(a, -A, m) -> Bool
Maybe.map(a, -A, -B, f: A -> B, m) -> Maybe<a, B>
Maybe.or(a, -A, m, n) -> Maybe<a, A>
Maybe.show(~a: Quant, ~A: Kind(a), ~f: A -> String, m) -> String
```

### Result

```
Result.pure(a, b, -E: Kind(a), -A: Kind(b), x: A) -> Result<a,b,E,A>
Result.bind(a, b, -E, -A, -B, r, f: A -> Result<a,b,E,B>) -> Result<a,b,E,B>
Result.default(a, b, -E, -A, r, d: A) -> A
Result.is_done / Result.is_fail(a, b, -E, -A, r) -> Bool
Result.map(a, b, -E, -A, -B, f: A -> B, r) -> Result<a,b,E,B>
```

### Equal

```
law Equal.cong:  for -A -B: Type, -f: A -> B, -a -b: A, e: {a == b : A}  {f(a) == f(b) : B}
law Equal.sym:   for -A: Type, -a -b: A, e: {a == b : A}                 {b == a : A}
law Equal.trans: for -A: Type, -a -b -c: A, ab: {a==b:A}, bc: {b==c:A}   {a == c : A}
```

### List

```
List.map(~A: Type, ~B: Type, ~f: A -> B, xs: List<A>) -> List<B>
List.length(a, -A: Kind(a), xs) -> Nat
List.append(a, -A, xs, ys) -> List<a, A>
List.concat(a, -A, xss: List<a, List<a, A>>) -> List<a, A>
List.reverse(a, -A, xs) -> List<a, A>
List.is_empty(a, -A, xs) -> Bool
List.head(a, -A, xs) -> Maybe<a, A>     List.tail(a, -A, xs) -> List<a, A>
List.last(a, -A, xs) -> Maybe<a, A>
List.get(a, -A, xs, n: Nat) -> Maybe<a, A>
List.set(a, -A, xs, n: Nat, x: A) -> List<a, A>
List.take(a, -A, xs, n: Nat) -> List<a, A>    List.drop(a, -A, xs, n: Nat) -> List<a, A>
List.zip(a, -A, b, -B, xs, ys) -> List<&1, A & B>
List.range(n: Nat) -> List<&2, Nat>
List.replicate(-A: Data, n: Nat, +x: A) -> List<&2, A>
List.filter(~A: Data, ~f: A -> Bool, xs: List<&2, A>) -> List<&2, A>
List.foldl(~a: Quant, ~A: Kind(a), ~B: Type, ~f: B -> A -> B, xs, acc: B) -> B
List.foldr(~a, ~A, ~B, ~f: A -> B -> B, xs, z: B) -> B
List.any(~a, ~A, ~f: A -> Bool, xs) -> Bool   List.all(...) -> Bool
List.find(~A: Data, ~f: A -> Bool, xs: List<&2, A>) -> Maybe<&2, A>
List.contains(~A: Data, ~eq: A -> A -> Bool, xs: List<&2, A>, +x: A) -> Bool
List.sort(~A: Data, ~le: A -> A -> Bool, +xs: List<&2, A>) -> List<&2, A>
List.for_each(~a, ~A, ~f: A -> IO(Unit), xs) -> IO(Unit)
List.show(~a: Quant, ~A: Kind(a), ~f: A -> String, xs) -> String
```

### Array

`type Array<-T: Type> is Type` — an array always has exactly one owner.

```
Array.new(-T: Data, +d: Nat, +v: T) -> Array<T>          # 2^d slots
Array.get(-T: Data, a, +i: U32) -> Array<T> & T
Array.set(-T: Type, a, i: U32, v: T) -> Array<T>
Array.swap(-T: Type, a, +i: U32, v: T) -> Array<T> & T
Array.clone(-T: Data, a) -> Array<T> & Array<T>
Array.size(-T: Type, a) -> Array<T> & U32
Array.to_list(~T: Type, a) -> List<T>
Array.map(~T: Type, ~U: Type, ~f: T -> U, a: Array<T>) -> Array<U>
```

The `a[i]`/`a[i] <- v` sugar works only for `Array<U32>`; `[v : T*n]` is n slots,
`[v : T^d]` is 2^d. Verified:

```python
def main() -> Array<U32> & U32:
  a = [0 : U32*8n]
  a[5] <- 42
  a[5]
# -> ([0, 0, 0, 0, 0, 42, 0, 0], 42)
```

### Map (and Set on top of it)

```
Map.new(a, -V: Kind(a)) -> Map<a, V>
Map.set(a, -V, m, key: String, x: V) -> Map<a, V>
Map.del(a, -V, m, key: String) -> Map<a, V>
law Map.get: for -V: Data, d: V, m: Map<&2,V>, key: String   Map<&2,V> & V
law Map.has: for -a: Quant, -V: Kind(a), m: Map<a,V>, key: String   Map<a,V> & Bool
law Map.pop: for -a: Quant, -V: Kind(a), m: Map<a,V>, key: String   Map<a,V> & Maybe<a,V>
Map.keys(a, -V, m) -> List<&2, String>
Map.values(a, -V, m) -> List<a, V>
Map.to_list(a, -V, m) -> List<a, Sigma<&2, a, String, _ => V>>
Map.from_list(a, -V, kvs) -> Map<a, V>
Map.union(a, -V, m, n) -> Map<a, V>
Map.size(a, -V, m) -> Nat

Set() -> Data                       # = Map<&2, Unit>
Set.new() -> Set()                  Set.add(s, key) -> Set()
Set.has(s, key) -> Set() & Bool     Set.del(s, key) -> Set()
Set.size(s) -> Nat                  Set.to_list(s) -> List<&2, String>
Set.from_list(keys: List<&2, String>) -> Set()
```

`get` takes a default and returns a pair; `has` is **pure** too and returns a pair
(`Map.has(&2, U32, m2, "a")` is not `IO`). Verified: `Map.get(U32, 0, m2, "zz")`
→ `0` for a missing key.

### String / Char

```
String.append(a, b) -> String           # operator ++
String.cmp(a, b) -> (String & String) & Cmp     String.order(a, b) -> Cmp
String.eq(a, b) -> Bool
String.is_lt/is_le/is_gt/is_ge(a, b) -> Bool
String.length(s) -> Nat                 String.is_empty(s) -> Bool
String.reverse(s) -> String
String.starts_with(s, p) -> Bool        String.ends_with(s, p) -> Bool
String.contains(s, p) -> Bool
String.take(s, n: Nat) / String.drop(s, n: Nat) -> String
String.get(s, n: Nat) -> Maybe<&2, Char>
String.to_list(s) -> List<&2, Char>     String.from_list(cs) -> String
String.concat(xs: List<&2, String>) -> String
String.join(xs: List<&2, String>, +sep: String) -> String
String.split(s, +sep: Char) -> List<&2, String>   String.lines(s) -> List<&2, String>
String.repeat(+s, n: Nat) -> String
String.to_upper(s) / String.to_lower(s) -> String
String.trim_start(s) / String.trim_end(s) / String.trim(s) -> String
# no show: strings print directly

Char.cmp(a,b) -> (Char & Char) & Cmp     Char.to_u32(c) -> U32
Char.from_u32(x) -> Char                Char.is_eq(a,b) -> Bool
Char.is_digit/is_upper/is_lower/is_alpha/is_space(c) -> Bool
Char.to_upper(+c) / Char.to_lower(+c) -> Char
Char.show(c) -> String
```

### File / IO / other effects

```
File.open(path, mode: String) -> IO(Result<&1,&1,U32 & String, File>)   # "r" | "w" | "a"
File.read(file, max: U32) -> IO(File & Result<..., String>)
File.read_bytes(file, max: U32) -> IO(File & Result<..., List<&2, U32>>)
File.write(file, data: String) -> IO(File & Result<..., Unit>)
File.close(file) -> IO(Unit)

IO.pure(-A, x) -> IO(A)      IO.bind(-A, -B, m, f) -> IO(B)
IO.print(text)  IO.write(text)  IO.print_err(text) -> IO(Unit)   # print adds \n, write does not
IO.get_env(name) -> IO(Result<&1,&1,U32 & String, String>)
IO.die(-A, code: U32, msg: String) -> IO(A)
IO.pass(-A, r: Result<...>) -> IO(A)     IO.try(-A, act: IO(Result<...>)) -> IO(A)
IO.spawn(-A, act: IO(A)) -> IO(Unit)     IO.sleep(ms: U32) -> IO(Unit)
IO.now() -> IO(Nat)                      IO.fork(-A, act) -> IO(Chan(A))
IO.join(-A, +chan: Chan(A)) -> IO(A)

Chan.new(-A: Type, room: U32) -> IO(Chan(A))
Chan.send(-A, chan, value: A) -> IO(Bool)
Chan.recv(-A, chan) -> IO(Maybe<&1, A>)
Chan.close(-A, chan) -> IO(Unit)

Window.open(title, w, h) -> IO(Result<..., Window>)
Window.frame(window, image) -> IO(Window & Image & List<Event>)
Window.set_title(window, title) -> IO(Window)   Window.close(window) -> IO(Unit)
Audio.open(rate: U32) -> IO(Result<..., Audio>)
Audio.write(audio, samples: List<&2, F32>) -> IO(Audio & U32)   Audio.close(audio)

type Image is Data: Pix{color: U32} | Qua{tl,tr,bl,br: Image}
Image.drop(img) -> Unit
App.run(~S: Type, ~app: App<S>, title, width, height, state: S) -> IO(Unit)
type App<-S: Type> is Type:
  App{view: S -> Pair(S, Image), tick: List<Event> -> S -> IO(Maybe<S>)}
type Event is Data: Key{code: U32, down: Bool} | Mouse{x,y,button,down} | Move{x,y} | Close{}
```

---

## 4. IO, File, measurements

### Writing and reading a file

A `do` block cannot destructure, so the `File & Result` pair is unpacked by
helper `def`s:

```python
def snd_of(-A: Type, -B: Type, p: A & B) -> B:
  (a, b) = p
  b

def keep_file(-A: Type, p: File & Result<&1, &1, U32 & String, A>) -> IO(File):
  (f, res) = p
  do IO<File>:
    x : A <- IO.try(A, IO.pure(Result<&1, &1, U32 & String, A>, res))
    return f

def main() -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open("io_probe.txt", "w"))
    wr : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, "hello, bend\nsecond line\n")
    f2 : File <- keep_file(Unit, wr)
    g : File <- IO.try(File, File.open("io_probe.txt", "r"))
    gr : File & Result<&1, &1, U32 & String, String> <- File.read(g, 100)
    text : String <- IO.try(String, IO.pure(Result<&1, &1, U32 & String, String>, snd_of(File, Result<&1, &1, U32 & String, String>, gr)))
    IO.print(text)
```

Output (and the file contents — exactly two lines):

```
hello, bend
second line

```

`File.read(file, max)` reads at most `max` bytes (in `.c` — `read()`); the modes
`"r"`, `"w"` (O_TRUNC), `"a"`.

### `IO.try`, `Result`, termination

* `IO.try(A, act)` unwraps a `Result` or **terminates the program**: the error is
  printed to stderr, the exit code = errno. Verified:
  `File.open("no_such_file_xyz.txt", "r")` → stderr `No such file or directory`,
  exit `2`; `IO.get_env("NO_SUCH_ENV_VAR_XYZ")` — the same; `IO.get_env("USER")` →
  `env=user`.
* `IO.die(Unit, 7, "custom failure")` → stderr `custom failure`, exit `7`.
* `IO.print` writes to stdout and **adds `\n`**.
* `IO.now()` returns a `Nat` — milliseconds of a monotonic timer (sources:
  `now.js` — `performance.now()`, `now.c` — `io_tick()/1000000`). The value
  is platform-dependent (on JS here ~78, natively ~3.17e6); what matters is the
  difference within one run; `IO.sleep(50)` gave `b-a = 60`. Resolution 1 ms; two
  consecutive `IO.now()` calls give 0.

### `IO.fork` / `Chan`

```python
def greet(name: String) -> IO(String):
  do IO<String>:
    return "Hello, " ++ name

def main() -> IO(Unit):
  do IO<Unit>:
    chan : Chan(String) <- IO.fork(String, greet("world"))
    IO.print("Waiting...")
    text : String <- IO.join(String, chan)
    IO.print(text)
# -> Waiting...\nHello, world
```

`Chan` by hand (`Chan.new` → `send` → `recv` → `close` → `recv`): `True`,
`Some(42)`, `None` — a `recv` on a closed channel gives `None`.

Deadlock: two tasks `IO.spawn(waiter(ch))` on an empty channel →
`bend: deadlock: every computation waits on a channel`, exit 1.
All that `+ch` needs is that `Chan` is `Data`, but the binder is affine: for two
uses write `+ch : Chan(U32) <- ...`.

---

## 5. Parallelism

### Forms

* Parallel let: `a b = f(x) g(y)` — exactly N calls and N names (verified
  `a b c = f(1) f(2) f(3)` → `9`). This is the only primitive.
* `!` after a name: `f!(x)` — "this call and all parallel calls inside it go on the GPU".
  `IO.spawn`/`IO.fork` are effect concurrency, not computation parallelism.

### On this machine (GPU present, distro CUDA 12, clang 19)

Verified on this machine (2026-09-18):

* Hardware: an **RTX 4090 Laptop**, driver 580.178.04, CUDA 13.0. `nvidia-smi`
  answers and `/dev/nvidia*` exists.
* The toolkit is the distro CUDA 12 package: `nvcc` 12.0 at `/usr/bin/nvcc`,
  `cuda.h`/`nvrtc.h` in `/usr/include`, `libcuda`/`libnvrtc` in
  `/usr/lib/x86_64-linux-gnu`. **`/usr/local/cuda` is absent** — and that is
  exactly where Bend looks for CUDA by default.
* `tools/bend` sets `CUDA_HOME=/usr` (when `/usr/local/cuda/include/nvrtc.h`
  is missing while `/usr/include/nvrtc.h` exists), so a program with `!` now builds
  its device program next to the binary as `<binary>.gpu`, and `--gpu` runs it
  on the device.
* `--gpu` on a CPU-only binary (one built without a `.gpu` alongside it) fails with
  `bend: --gpu on, but this binary found no GPU device`. This is about how the
  binary was built, not about the machine lacking a GPU.
* The GPU lane needs **clang 19+**; Bend picks `clang-19` itself when it is
  installed. On clang 18 the build silently produces a CPU-only binary.
* `!` on the JS backend is still ignored: the time is the same as without `!`.
* The difference in the C file between `!` and no `!`: `#define BANGS 0` versus `1`
  and one flag in `FID_FLAG_T`.

Historical — measured when the GPU lane did not exist yet, not remeasured since:

* With and without `!`, programs behaved identically and parallelized identically on
  the CPU: CUDA was not found and no device program was built.
* `-o` with `!` built even on clang 18.1.3, exit 0 — but that was a silent
  CPU-only build, contrary to the guide's "clang 19+ with `!`" requirement.
* The `.gpu` file was **not created** (neither for `bench_sum_gpu`, nor for the ray
  tracer, nor for `pure_par_sort`).

### Measurements: `bench_sum.bend` (summing 2^22 numbers, fork/join, `d=22`)

The same code, `main -> IO(Unit)`, with `IO.now()` around `sum(22n, 0n)`.
Native binary (`-o`), 5 runs each, ms (median):

| `--threads` | without `!` (`sum`) | with `!` (`sum!`) |
|---|---|---|
| 1 | 26 | 29 |
| 2 | 15 | 19 |
| 4 | 11 | 11 |
| 8 | 6 | 6 |
| 16 | 4 | 4 |
| 32 | 4 | 4 |

The sum matches everywhere: `8796090925056` (= 2^21·(2^22−1)).

JS backend (`tools/bend bench_sum.bend`), the same code: **419–432 ms** both without
`!` and with `!` — JS is always sequential. So the speedup from 1→16 threads is ≈ 6–7×,
after which it hits memory/overhead.

The official `demos/pure_par_sort` (2^16 leaves, `sort!`), binary time:

| threads | 1 | 2 | 4 | 8 | 16 | 32 |
|---|---|---|---|---|---|---|
| sec | 0.16 | 0.11 | 0.08 | 0.06 | 0.06 | 0.06 |

### Runtime flags

* `./bin --threads N` — N ≥ 1; `--threads 0` and `--threads abc` →
  `bend: expected a thread count of 1 or more after --threads`, exit 1.
* `./bin --gpu 4GB`:
  * on a CPU-only binary (no `<binary>.gpu`) — `bend: --gpu on, but this
    binary found no GPU device`, exit 1. This covers both a build without `!` and
    a build on clang 18;
  * on a binary with a device program — it runs on the device
    (the historical note "on a binary without `!` the flag is silently ignored"
    referred to the no-CUDA state).
* Building `bench_sum_gpu.bend -o ...` took 0.48 s (back then, without CUDA), `bench_sum` — 1.05 s.
  These times have not been remeasured with the GPU lane active (see `docs/benchmarks.md`).

---

## 6. Laws and proofs

### Workflow

`LAWS.bend` (human) + `PROOF.bend` (AI) + `bend PROOF.bend` — the gate.
Verified on the official ray tracer:

```sh
cd rt/ && tools/bend PROOF.bend     # -> All terms check.
tools/bend LAWS.bend                # -> Error: 2 TODOs found. ... (if a law is opened)
```

`All terms check.` is also printed for a file without `main` where all laws are closed
(including `bend mymath.bend` with no laws at all). An open law without a `def` is
a TODO: `Error: 2 TODOs found. The code is incomplete, and not a valid proof yet.`

### What makes `{==}` succeed

`{==}` closes the goal `{a == b : T}` only if both sides **evaluate to a single term**.
This works:

```python
law add_zero:
  for x: Nat
  {Nat.add(x, 0n) == x : Nat}

def add_zero(x):
  match x:
    case 0n:
      {==}
    case 1n+p:
      %add_zero(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}
# -> All terms check.
```

A false law prints expected/observed and a location:

```
- expected : 1n
- observed : 0n
```

### `%e : P` — rewriting

The semantics (verified): if `e : {a == b : T}`, then `P` is a goal in which
**`b` has been replaced by `_`**, and after the rewrite `a` takes the place of `_`.
That is, a rewrite always goes "b → a"; to get the opposite direction you need
`Equal.sym`.

Example — a proved `List.length(List.map(f, xs)) == List.length(xs)` for a concrete
`f` (file `proofs/65_map_length.bend`):

```python
def inc(x: U32) -> U32:
  (x + 1 : U32)

law map_length:
  for xs: List<&1, U32>
  {List.length(&1, U32, List.map(~U32, ~U32, ~inc, xs)) == List.length(&1, U32, xs) : Nat}

def map_length(xs):
  match xs:
    case Nil{}:
      {==}
    case h <> t:
      %map_length(t) : {1n+List.length(&1, U32, List.map(~U32, ~U32, ~inc, t)) == 1n+_ : Nat}
      {==}
# -> All terms check.
```

**What is NOT provable:** the same law with `for -f: U32 -> U32` cannot be expressed at
all (it fails during the law check, before the proof):

```
- expected : a defined name
- observed : List.map
Context:
- f  : @_:U32 -> U32
```

The reason: `List.map` is a template, `~f` must be a closed top-level name, and
the law's `f` is a local (dead) variable. A universal law about `List.map`
for an arbitrary function cannot be written in Bend 2.0.5; only instances for
concrete `def`s.

### `?name` and `?TODO`

* `?name` — **fails on purpose**, printing the goal (this is how you "look at the goal"):

```python
def add_zero(x):
  ?add_zero
```
```
- expected : {Nat.add(x, 0n) == x : Nat}
- observed : ?add_zero
```

  Inside `match` it shows the branch's refined goal: `expected : {0n == 0n : Nat}`.
* `?TODO` — leaves the goal open and marks the file incomplete:
  `Error: 1 TODO found. The code is incomplete, and not a valid proof yet.`

### Inductives and helper lemmas

A helper lemma is an ordinary `def` returning a proof type; it needs no law.
A complete verified example (file `proofs2/tree4.bend`, prints
`All terms check.`): `add_zero`, `add_succ`, `add_comm` for `Nat`, then a law
about a custom inductive type:

```python
type Tree is Data:
  Leaf{}
  Node{l: Tree, r: Tree}

def size(t: Tree) -> Nat:
  match t:
    case Leaf{}: 0n
    case Node{l, r}: 1n+Nat.add(size(l), size(r))

def mirror(t: Tree) -> Tree:
  match t:
    case Leaf{}: Leaf{}
    case Node{l, r}: Node{mirror(r), mirror(l)}

law mirror_size:
  for t: Tree
  {size(mirror(t)) == size(t) : Nat}

def mirror_size(t):
  match t:
    case Leaf{}:
      {==}
    case Node{+l, +r}:
      %Equal.sym(Nat, size(mirror(l)), size(l), mirror_size(l)) : {1n+Nat.add(size(mirror(r)), _) == 1n+Nat.add(size(l), size(r)) : Nat}
      %Equal.sym(Nat, size(mirror(r)), size(r), mirror_size(r)) : {1n+Nat.add(_, size(l)) == 1n+Nat.add(size(l), size(r)) : Nat}
      %add_comm(size(r), size(l)) : {1n+Nat.add(size(r), size(l)) == 1n+_ : Nat}
      {==}
```

Here you can see that the recursive call is the inductive hypothesis, `match`
refines the goal per branch, `Equal.sym` reverses the rewrite direction, and
`case Node{+l, +r}` is needed so the fields can be used repeatedly.

Additionally verified: `Equal.sym/trans/cong` directly; `exs y: Nat`
(`def two_plus_two(): (2n, {==})` — a pair serves as the witness); refuting
`{1n != 0n : Nat}` via the motive `disc(_)`:

```python
def disc(n: Nat) -> Type:
  match n:
    case 0n: Empty
    case 1n+p: Unit

law one_ne_zero:
  {1n != 0n : Nat}

def one_ne_zero(e):
  %e : {disc(_) : Type}
  Unit{}
# -> All terms check.
```

`for y: B where P(y)` binds `y` as a dependent pair (`Sigma`). To mention `y` itself
in the law's statement you need a helper with a dependent type (there are no field
projections):

```python
def fst_dep(-A: Type, -B: @-x: A -> Type, p: &x: A -> B(x)) -> A:
  (a, b) = p
  a

law pick_ge:
  for n: Nat
  for m: Nat where {Nat.is_le(n, m) == True{} : Bool}
  {Nat.is_le(n, fst_dep(Nat, x => {Nat.is_le(n, x) == True{} : Bool}, m)) == True{} : Bool}

def pick_ge(n, m):
  (m2, p) = m
  p
# -> All terms check.
```

### F32: what is and is not possible

`F32` is **not opaque**: it is `type F32 is Data: F32{data: Word(32n)}`, and its
constructor is visible (`match x: case F32{w}: 0` compiles). But everything
arithmetic and comparative in Base is declared as `law F32.add`, `law
F32.is_le`, … **without a `def`** — these are unprovable built-in operations, and they
do not reduce in proofs. There are no F32 lemmas in Base at all (only
`law` declarations; `F32.min/max/clamp/lerp/...` are built on them).

Verified:

| law | result |
|---|---|
| `{0.5 == 0.5 : F32}` + `{==}` | `All terms check.` (identical literals are one term) |
| `{F32.add(0.5, 0.5) == 1.0 : F32}` | fails: `expected : F32.add(0.5, 0.5) / observed : 1.0` |
| `{F32.is_le(0.25, 1.0) == True{} : Bool}` | fails: `expected : F32.is_le(0.25, 1.0) / observed : True{}` |
| `{F32.bits(1.0) == 1065353216 : U32}` | fails: `expected : F32.bits(1.0) / observed : 1065353216` |
| `for x: F32 {F32.is_le(clamp01(x), 1.0) == True{} : Bool}` | fails, the goal is printed unreduced: `expected : F32.is_le(Bool.pick(F32, F32.is_lt(1.0, ...), ...), 1.0) / observed : True{}` |

Conclusion: about F32 you cannot prove anything except the equality of syntactically
identical literals. `F32.min/max/clamp` are ordinary `def`s, but they unfold into
opaque `law`s, so they do not compute on F32 values. That is exactly why
`demos/app_ray_tracer_3d/LAWS.bend` states plainly: "The F32 scene is not claimed" —
its laws are only about the list of pressed keys.

### `@unsafe`

`@unsafe def` disables the termination check (and declares binders `+` at any
kind). Verified: `@unsafe def loop(x: U32) -> U32: loop(x)` compiles and
hangs. Such `def`s are outside the guarantees of proofs.

---

## 7. Compilation

Measurements on this machine (`tiny.bend` — `IO.print("compile me")`):

| command | time | result |
|---|---|---|
| `tools/bend tiny.bend` | ~0.09 s (JS) | prints `compile me` |
| `tools/bend tiny.bend -o tiny.c` | ~0.09 s | `tiny.c`, 76 KB |
| `tools/bend tiny.bend -o tiny.js` | ~0.09 s | `tiny.js`, 11 KB |
| `tools/bend tiny.bend -o tiny.bin` | ~0.34 s | a 1.08 MB binary, runs |
| `tools/bend tiny.bend --checkup` | — | nothing, exit 0 |
| `tools/bend tiny.bend --publish` | — | the wrapper now refuses, exit 2 (see below) |

Larger files (historical measurements, without the GPU lane; not remeasured with
`CUDA_HOME=/usr` — for current numbers see `docs/benchmarks.md`):

| file | `-o` binary | size |
|---|---|---|
| `bench/bench_sum.bend` (d=22) | 1.05 s | 1.09 MB |
| `bench/bench_sum_gpu.bend` (`!`) | 0.48 s | 1.10 MB, no `.gpu` produced |
| `demos/app_ray_tracer_3d/main.bend` | 1.45 s | 1.16 MB, no `.gpu` produced |
| `demos/pure_par_sort/main.bend` | 3.19 s | `sort`, no `.gpu` produced |

* `-o out.c` and `-o out.js` just dump the source (C ~76 KB even for
  hello world, JS ~11 KB); `-o` without an extension — clang compilation + run.
* `-o` with `!` on clang 18 **works** (the guide requires 19+) but silently produces
  a CPU-only binary: no `.gpu` appears. With `tools/bend` (that is, with
  `CUDA_HOME=/usr`) and clang-19 installed, `<binary>.gpu` appears next to the
  binary. `--gpu` on a CPU-only binary fails with
  `bend: --gpu on, but this binary found no GPU device`.
* `--checkup` checks the file and each import separately:

```
--- ./mymath.bend ---
All terms check.
```

* `--publish` does go over the network: it prints
  `publishing 1 files, 79 bytes, as 0x<sha> (mining its proof of work)`,
  then the hash and a ready-made line `import 0x<sha>/tiny.bend as Tiny`.
  (That was before `tools/bend` gained its guard: the wrapper now refuses with
  exit 2 and lets `--publish` through only under `BEND_ALLOW_PUBLISH=1`, which
  **only a human** may set. Publishing is irreversible.)
* `main -> IO(...)` is executed; a `main` without `IO` is normalized by the checker and
  printed (`25`, `[1, 2, 3]`, `{==}`); a file without `main` is only checked and
  prints `All terms check.`

---

## 8. Traps, bugs, oddities

1. **A `main` without `IO` is normalized by the checker and easily blows the stack.** The same
   fork/join `sum` that works in §5 at depth 22 from an `IO` `main` fails from
   `main -> Nat` already at depth 8:
   `Error: the machine stack overflowed (a deep recursion, or a literal too
   large to expand)`. `d=4` still prints `120n`. For real programs `main`
   must return `IO`.
2. **The `match` error text in `do`:** `expected : a term (a match heads a def body,
   not a term) / observed : ' '` — the observed is a space, not a token.
3. **`case 1n+p` on `U32`:** `expected : cases for True / observed : \{}` —
   the message does not say that `U32` does not support a successor pattern.
4. **Scrutinee/`let` order:** the message `match scrutinees in binder order (...)`
   does not say which `let` is in the way.
5. **No field projections** (`.fst`/`.snd`/`.x`) and no destructuring in `do` —
   the most common reason for workaround helper `def`s. The guide does not say this explicitly.
6. **No `String.show`** in Base — surprising if you expect symmetry with `U32.show`.
7. **`List.map` returns `List<&1, _>`**, while `List.show` by default expects
   `&2`; the direct composition does not pass on kind.
8. **`: T` is not a type cast.** `(e : T)` sets the type of the operators inside `e`,
   and `{e : T}` is an annotation, but there is no conversion: `{3 : Nat}` does not compile.
   It is easy to mistake `((a < b) && (c < d) : U32)` for a U32 expression — in fact
   it is a Bool.
9. **There is no unary minus**, no `//` comments, no `if` — all of these are
   syntax errors with non-obvious `observed`.
10. **An annotated `let` (`x : T = v`) exists only in `do`;** in a `def` body it is
    `expected : 'def', 'type' or 'law' / observed : ':'`.
11. **A function type in a `do`-let needs parentheses**: `f : U32 -> U32 = ...` →
    `expected : '<-' / observed : '-'`.
12. **Template arguments at the call site are all marked with `~`**; you cannot mix
    (`expected : a term / observed : '~'`).
13. **Universal laws about `List.map` are inexpressible** — a template argument
    must be a closed name; the error `expected : a defined name / observed :
    List.map` appears for a law that looks perfectly normal.
14. **F32 is impervious to proofs**, even though it is not opaque: all operations are
    `law`s without `def`s. There is no F32 lemma in Base at all.
15. **Division by zero for `U32`/`Nat` returns 0**, rather than failing or
    `Maybe`/`Result` — easy to miss.
16. **`Nat` silently aborts the program** past `2^48−1`:
    `bend: a Nat past the largest immediate 2^48-1`, exit 1 (the same on JS and
    natively).
17. **`@unsafe` + infinite recursion = a hang** with no warnings.
18. **`--gpu` on a CPU-only binary** (no `<binary>.gpu`: a build without `!` or on
    clang 18) — an error `bend: --gpu on, but this binary found no GPU
    device`. The message is about the build, not about the machine lacking a GPU.
19. `Map.get`/`Map.has` are not IO, although they return a pair; `<-` for them gives
    a long error about `@-R:Type -> ...`, not "this is not IO".
20. `tools/bend` refuses `--publish` (exit 2) until a human explicitly sets
    `BEND_ALLOW_PUBLISH=1`; publishing is irreversible, and scripts
    must take this into account.

---

## Appendix: where the checks live

| topic | files |
|---|---|
| syntax, types, quantities, kinds, templates, closures | `probes/01…06*` |
| `match`/`let`/affine/termination | `probes/10…23*, 40…49*` |
| numbers, division, overflow | `probes/30…39*` |
| files, `IO.now`, `IO.try`, `Chan`, deadlock | `probes/50…53*` |
| arrays, `do Maybe`, modules | `probes/70…73*` |
| laws, `%`, `?name`, `?TODO`, F32, `where`, `exs`, Empty | `proofs/60…68*, proofs2/*` |
| the full `Tree` law + `Nat` lemmas | `proofs2/tree4.bend` |
| parallel measurements | `bench/`, `results/10-parallel-*` |
| official demos (ray tracer, par_sort, par_sum) | `rt/`, `pps/`, `demos/` |

Raw logs: `results/01-syntax.txt`, `results/02-gotchas.txt`,
`results/03-gotchas2.txt`, `results/04-numbers.txt`, `results/05-numbers2.txt`,
`results/06-cmp.txt`, `results/07-termination.txt`, `results/07b-termination.txt`,
`results/08-patterns.txt`, `results/09-io.txt`, `results/10-parallel-noBang.txt`,
`results/11-laws.txt`, `results/12-laws2.txt`, `results/13-arrays.txt`,
`results/14-proofs3.txt`.
