*[English](../language-notes.md) | Русский*

# Bend 2 (2.0.5) — проверенные заметки по языку

Всё ниже проверено запуском на этой машине: `bend 2.0.5`, clang-19 (19.1.1),
32 ядра, **RTX 4090 Laptop** (см. §5 про CUDA). Запуск только через обёртку
`tools/bend` (`BEND_HOME` внутри рабочей копии):

```sh
tools/bend file.bend            # check, затем run на JS-бэкенде
tools/bend file.bend -o out     # нативный бинарник через clang
tools/bend file.bend -o out.c   # только C
tools/bend file.bend -o out.js  # только JS
tools/bend PROOF.bend           # ворота законов
```

Программы-эксперименты, сохранённые для этого текста, лежат в `probes/`:
`probes/raster/` (опыты с рендерером), `probes/bench/` (параллельные замеры),
а также `probes/limits/` и `probes/neg/` (законы и доказательства). Команда
в шапке каждой программы воспроизводима.

Главная мысль: Bend почти не выводит типы, зато ошибки точные — почти каждая
ошибка печатает `expected`/`observed` и место. Язык affine по умолчанию,
завершаемость обязательна, а `match` — не выражение.

---

## 1. Мини-шпаргалка синтаксиса

### Типы, def, match

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

`is Data` — значения копируемы (`Kind(&2)`), `is Type` — нет (`Kind(&1)`).
`def` — функция, тело после `:`.
`main`, возвращающий не-`IO`, не выполняется на рантайме, а **нормализуется
чекером** и печатается (см. §8, это ловушка).

### Quantity-аннотации

```python
def replicate(-A: Data, n: Nat, +x: A) -> List<A>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      x <> replicate(A, p, x)
# replicate(U32, 3n, 7) -> [7, 7, 7]
```

| метка | смысл |
|---|---|
| `-x` | erased: виден чекеру, удаляется компилятором, только типы/доказательства |
| `x` | affine (по умолчанию): не более одного использования |
| `+x` | reusable: требует `Data`; в рантайме — refcount |
| `+A: Data` | quantity на *тип*: `Type` = `Kind(&1)`, `Data` = `Kind(&2)`, `Kind(a)` принимает любое |

Матчинг `+`-значения отдаёт `+`-поля; на affine-значении пиши `+r` в паттерне,
чтобы поле стало reusable (`case Circle{+r}`).

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

Подстановка на этапе компиляции; `~`-аргумент должен быть замкнут (только
top-level имена, без локалок вызывающего); шаблонные параметры идут первыми;
шаблон может вызывать только шаблоны, объявленные **выше**; каждый набор
`~`-аргументов даёт свою копию. На call-site **все** шаблонные аргументы нужны
с `~`, иначе `expected : a term / observed : '~'`:

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

Замыкание affine — вызывается не более одного раза, даже если всё захваченное
`Data`. `U32.add(2)` (частичное применение) — тоже замыкание. Top-level `def`
вызывается свободно.

### `do`-блоки

```python
do IO<Unit>:
  x : A <- m            # bind: x : A <- действие
  x : A = v             # let внутри do (только здесь есть `x : T = v`)
  m                     # шаг типа Unit
  return v
```

`do M<xs.., R>:` работает для любого M с `M.bind`/`M.pure`: `IO`, `Maybe`,
`Result`. Пример `do Maybe<&2, U32>:` из гайда проверен — `Some{42}`.

### Операторы

Внутри `(.. : T)` операторы `+ - * / %` вызывают `T.add`…`T.mod`,
`.&. .|. .^.` — битовые, `<< >>` — сдвиги (сдвиг — `Nat`), `< <= > >=` —
`T.is_lt`-семейство. **Без `: T` они принадлежат `Nat`** — и это ломает
сравнения/арифметику на `U32` (см. §2). `&& ||` — только `Bool`, `++` —
`String`, `<>` — cons. Пробелы вокруг операторов обязательны по спецификации,
но `(1+2 : U32)` на практике проходит (`-> 3`).

### Литералы

| литерал | тип |
|---|---|
| `42` | `U32` (всегда, даже если ожидается `Nat`/`F32`) |
| `3n`, `1n+p` | `Nat` (машинное слово, обрыв за 2^48−1) |
| `1.5`, `0.0` | `F32` |
| `'c'` | `Char` |
| `"s"` | `String` |
| `[a, b]`, `h <> t` | `List` |
| `(a, b)` | `A & B` (это `Sigma`, kind `Type`, не `Data`) |

Литералы не конвертируются неявно: `(1n + 1 : U32)` →
`expected : U32 / observed : Nat`.

---

## 2. Правила и подводные камни (все проверены)

![Четыре правила: порядок объявлений — часть программы, взаимная рекурсия запрещена, match — утверждение, деструктурировать можно только параметр](../../assets/readme/language-rules.svg)

### 2.1 `match` — не терм: в `do`-блоке его нет

```python
do IO<Unit>:
  x : U32 = 3
  match x:            # ошибка
    case 0:
      IO.print("zero")
```

```
Error:
- expected : a term (a match heads a def body, not a term)
- observed : ' '
```

`observed` тут — пробел, сообщение вводит в заблуждение. То же самое, если
`match` стоит справа от `=` в `do` (`y : U32 = match x:`).

Обход: вынести в отдельный `def` и вызвать его.

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

`match` — это **выражение** тела `def`/`case`/лямбды: `def describe(x) -> String:
match x: ...` работает и возвращает значение (`match x:` как последний терм).

### 2.2 `let` перед `match` на параметре запрещён

```python
def f(x: U32) -> U32:
  y = x
  match x:            # ошибка
    case 0: 1
    case _: y
```

```
- message : match scrutinees in binder order (this variable is unbound, consumed, or out of order: reorder the match)
```

Правило: scrutinee-переменные идут в порядке биндеров; `let` перед `match`
«съедает» параметр. Обход — `match` первым, а `let` внутри ветвей:
`case _: y = {x : U32}; y` (в теле `def` аннотированный `let` не пишется:
`y : U32 = x` там — синтаксическая ошибка `expected : 'def', 'type' or 'law' /
observed : ':'`; нужен `{x : U32}`).

Тот же порядок нужен у нескольких scrutinee: `match ys xs:` при `def f(xs, ys)`
падает с тем же сообщением.

### 2.3 `match` только по параметру/полю паттерна

```python
match U32.add(x, 1):   # ошибка
```

```
- message : a parameter or field scrutinee (a match cannot scrutinize a computed value: give it its own def)
```

Обход: передать вычисленное значение в helper-`def`, который матчит свой параметр.

### 2.4 Affine: дважды без `+` нельзя; drop бесплатен

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
  (x + x : U32)          # -> 6 при f(3)
```

```python
def f(x: U32, y: String) -> U32:
  7                       # y выброшен — это нормально, affine = "не более одного раза"
```

`+` нельзя ставить на функцию/`Array`/IO-хэндл: `def f(+g: U32 -> U32, ...)` →
`expected : Data / observed : Type`. Пара `A & B` — тоже `Type`:
`+p : U32 & U32 = (1, 2)` → `expected : Data / observed : Type`.

`main` с параметром не выполняется, а печатается как значение: `def main(x: U32)
-> U32: x` печатает `x => x` (проверено).

### 2.5 Завершаемость обязательна

```python
def loop(x: U32) -> U32:
  loop(x)
```

```
- expected : a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks)
- observed : loop
```

Правило: аргументы рекурсивного вызова читаются слева направо; каждый до
«усыхающего» — без изменений. Поэтому усыхающий параметр ставь **первым**:

```python
def f(acc: U32, xs: List<U32>) -> U32:   # ошибка: xs второй
  match xs:
    case Nil{}: acc
    case h <> t: f((acc + h : U32), t)
```

```
- expected : a decreasing self-call (...)
- observed : f
```

Работает, когда первый параметр усыхает:

```python
def sum(xs: List<U32>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case h <> t: sum(t, (acc + h : U32))
# sum([1,2,3,4], 0) -> 10
```

Взаимная рекурсия запрещена — `odd` объявлен ниже `even`, ошибка:
`expected : a defined name / observed : odd`. Обход по гайду — один `def` с
доп. аргументом-селектором.

`Nat` даёт `case 1n+p`, `U32` — нет:

```python
def f(x: U32) -> U32:
  match x:
    case 0: 0
    case 1n+p: 1        # ошибка, и текст странный
```

```
- expected : cases for True
- observed : \{}
```

Поэтому счётчики — `Nat`:

```python
def count(n: Nat, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p: count(p, (acc + 1 : U32))
# count(5n, 0) -> 5
```

`@unsafe def` снимает проверку завершаемости; программа с `@unsafe def loop(x:
U32) -> U32: loop(x)` компилируется и **зависает** (у нас — `timeout 30`,
exit 124).

### 2.6 Числа: неявных конверсий нет

| выражение | результат |
|---|---|
| `(7 / 2 : U32)` | `3` |
| `(7 % 2 : U32)` | `1` |
| `(7 / 0 : U32)` | `0` (не ошибка!) |
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

Конверсии только явные: `U32.to_nat`, `U32.from_nat`, `U32.to_f32` (law),
`F32.to_nat`, `F32.from_nat`. `U32.add(a, 1)` при `a: Nat` →
`expected : U32 / observed : Nat`.

Сравнения по умолчанию тоже `Nat` — это ломает `U32`:

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

Нужно явно: `(x < 5 : U32)`. Файл `app_ray_tracer_3d/main.bend` поэтому везде
пишет `(a < b : F32)`, `(fps < 100 : U32)`.

Ловушка с `: T` у составного выражения: `(e : T)` — это **не приведение типа**,
а «операторы внутри `e` считать по T». Поэтому
`((x < 96) && (y < 40) : U32)` компилируется и даёт **Bool**, если объявленный
тип функции `Bool`; но падает, если функция объявлена `-> U32`
(`expected : U32 / observed : Bool`). `{e : T}` — тоже не конверсия:
`{3 : Nat}` даёт `expected : Nat / observed : U32`.

### 2.7 `if` не существует

```python
if x == 0:
```

```
- expected : a term
- observed : '='
```

Ветвление — `match` по `True{}`/`False{}` или `Bool.pick(-A, c, a, b)`.
`&&`/`||` работают только на `Bool`: `a && b` при `a b : U32` →
`expected : Bool / observed : U32`. В ray tracer `((x < 96) && (y < 40) : U32)`
работает именно потому, что `<` даёт `Bool`, а `&&` — `Bool.and`.

Унарного минуса нет: `-1.0` → `expected : a name / observed : '1'`; пишут
`(0.0 - 1.0 : F32)`.

### 2.8 Аннотации на `let`

* в теле `def`/`case` — только `x = {3 : U32}` (иначе
  `expected : an annotated term (cannot infer) / observed : 3`);
* в `do`-блоке — `x : T = v` (аннотация обязательна для не-литералов);
* тип-функция в `do`-let нужно брать в скобки: `f : (U32 -> U32) = (x => ...)`
  — без скобок `expected : '<-' / observed : '-'`.

### 2.9 Прочие проверенные ограничения

* **Нет проекций полей.** `p.fst`, `p.snd`, `r.x` → `expected : a defined name /
  observed : p.fst`. Пары/записи распаковываются только `(a, b) = p` в теле
  `def`, не в `do`.
* **Деструктуризация внутри `do` запрещена**: `(a, b) = p` в блоке →
  `expected : a pattern (a binder or a constructor) observed : ...`.
  Приходится заводить helper-`def`, который принимает пару и распаковывает её.
* **Комментарии только `#`.** `//` → `expected : 'def', 'type' or 'law' /
  observed : '/'`.
* **`String.show` не существует** (проверено: `expected : a defined name /
  observed : String.show`). Строки печатаются как есть; для `List.show` над
  строками нужен свой `def sh(s: String) -> String: s`.
* **`List.map` возвращает `List<&1, B>`** (`~A: Type`), а `List.show` параметричен
  по quantity: на результате `map` нужно писать `List.show(~&1, ...)`, иначе
  `expected : List<&2, U32> / observed : List<&1, U32>`.
* **`Map.get`/`Map.has` — чистые**, не `IO`: `<-` даёт
  `expected : @-R:Type -> ... observed : Sigma<...>`. Используй `=`.
* **Шаблонный аргумент — только закрытое имя.** Закон `for -f: U32 -> U32`
  с `List.map(~U32, ~U32, ~f, xs)` не выражается вовсе:
  `expected : a defined name / observed : List.map`.
* **Матчинг `+`-полей нужен явно**: `case Node{l, r}` при многократном
  использовании `l`/`r` → `expected : r / observed : r (consumed more than once)`;
  пиши `case Node{+l, +r}`. В `Nat`-паттерне — `case 1n++p`, чтобы `p` был
  reusable.

---

## 3. Base API по разделам

Сигнатуры скопированы из `bend base <Name>`. У `law`-записей (у F32 — все
арифметические) тела нет: это недоказуемые встроенные операции (см. §6).

### F32

`type F32 is Data: F32{data: Word(32n)}`.

Все арифметические и сравнительные — **`law`** (opaque, не редуцируются в
доказательствах):

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

Обычные `def` (построены поверх `law`):

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
law U32.add_comm: {U32.add(a,b) == U32.add(b,a) : U32}   # доказан в Base
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

`type Array<-T: Type> is Type` — у массива всегда один владелец.

```
Array.new(-T: Data, +d: Nat, +v: T) -> Array<T>          # 2^d слотов
Array.get(-T: Data, a, +i: U32) -> Array<T> & T
Array.set(-T: Type, a, i: U32, v: T) -> Array<T>
Array.swap(-T: Type, a, +i: U32, v: T) -> Array<T> & T
Array.clone(-T: Data, a) -> Array<T> & Array<T>
Array.size(-T: Type, a) -> Array<T> & U32
Array.to_list(~T: Type, a) -> List<T>
Array.map(~T: Type, ~U: Type, ~f: T -> U, a: Array<T>) -> Array<U>
```

Сахар `a[i]`/`a[i] <- v` — только для `Array<U32>`; `[v : T*n]` — n слотов,
`[v : T^d]` — 2^d. Проверено:

```python
def main() -> Array<U32> & U32:
  a = [0 : U32*8n]
  a[5] <- 42
  a[5]
# -> ([0, 0, 0, 0, 0, 42, 0, 0], 42)
```

### Map (и Set поверх него)

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

`get` берёт default и возвращает пару; `has` тоже **чистая** и возвращает пару
(`Map.has(&2, U32, m2, "a")` — не `IO`). Проверено: `Map.get(U32, 0, m2, "zz")`
→ `0` для отсутствующего ключа.

### String / Char

```
String.append(a, b) -> String           # оператор ++
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
# show НЕТ: строки печатаются напрямую

Char.cmp(a,b) -> (Char & Char) & Cmp     Char.to_u32(c) -> U32
Char.from_u32(x) -> Char                Char.is_eq(a,b) -> Bool
Char.is_digit/is_upper/is_lower/is_alpha/is_space(c) -> Bool
Char.to_upper(+c) / Char.to_lower(+c) -> Char
Char.show(c) -> String
```

### File / IO / прочие эффекты

```
File.open(path, mode: String) -> IO(Result<&1,&1,U32 & String, File>)   # "r" | "w" | "a"
File.read(file, max: U32) -> IO(File & Result<..., String>)
File.read_bytes(file, max: U32) -> IO(File & Result<..., List<&2, U32>>)
File.write(file, data: String) -> IO(File & Result<..., Unit>)
File.close(file) -> IO(Unit)

IO.pure(-A, x) -> IO(A)      IO.bind(-A, -B, m, f) -> IO(B)
IO.print(text)  IO.write(text)  IO.print_err(text) -> IO(Unit)   # print добавляет \n, write — нет
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

## 4. IO, File, замеры

### Запись и чтение файла

`do`-блок не умеет деструктуризацию, поэтому пару `File & Result` распаковывают
helper-`def`-ы:

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

Вывод (и содержимое файла — ровно две строки):

```
hello, bend
second line

```

`File.read(file, max)` читает не больше `max` байт (в `.c` — `read()`), режимы
`"r"`, `"w"` (O_TRUNC), `"a"`.

### `IO.try`, `Result`, завершение

* `IO.try(A, act)` разворачивает `Result` или **завершает программу**: ошибка
  печатается в stderr, код выхода = errno. Проверено:
  `File.open("no_such_file_xyz.txt", "r")` → stderr `No such file or directory`,
  exit `2`; `IO.get_env("NO_SUCH_ENV_VAR_XYZ")` — то же; `IO.get_env("USER")` →
  `env=user`.
* `IO.die(Unit, 7, "custom failure")` → stderr `custom failure`, exit `7`.
* `IO.print` пишет в stdout и **добавляет `\n`**.
* `IO.now()` возвращает `Nat` — миллисекунды монотонного таймера (исходники:
  `now.js` — `performance.now()`, `now.c` — `io_tick()/1000000`). Значение
  платформозависимо (на JS у нас ~78, нативно ~3.17e6), важна разница в
  пределах одного запуска; `IO.sleep(50)` дал `b-a = 60`. Разрешение 1 мс, два
  подряд `IO.now()` дают 0.

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

`Chan` вручную (`Chan.new` → `send` → `recv` → `close` → `recv`): `True`,
`Some(42)`, `None` — `recv` по закрытому каналу даёт `None`.

Дедлок: две задачи `IO.spawn(waiter(ch))` на пустом канале →
`bend: deadlock: every computation waits on a channel`, exit 1.
Всё, что нужно для `+ch`, — `Chan` это `Data`, но биндер affine: для двух
использований пиши `+ch : Chan(U32) <- ...`.

---

## 5. Параллелизм

### Формы

* Параллельный let: `a b = f(x) g(y)` — ровно N вызовов и N имён (проверено
  `a b c = f(1) f(2) f(3)` → `9`). Это единственный примитив.
* `!` после имени: `f!(x)` — «этот вызов и все параллельные внутри — на GPU».
  `IO.spawn`/`IO.fork` — конкурентность эффектов, не параллелизм вычислений.

### На этой машине (GPU есть, CUDA 12 из дистрибутива, clang 19)

Проверено на этой машине (2026-09-18):

* Железо: **RTX 4090 Laptop**, драйвер 580.178.04, CUDA 13.0. `nvidia-smi`
  отвечает, `/dev/nvidia*` существует.
* Тулчейн — пакет CUDA 12 из дистрибутива: `nvcc` 12.0 в `/usr/bin/nvcc`,
  `cuda.h`/`nvrtc.h` в `/usr/include`, `libcuda`/`libnvrtc` в
  `/usr/lib/x86_64-linux-gnu`. **`/usr/local/cuda` отсутствует** — а именно там
  Bend ищет CUDA по умолчанию.
* `tools/bend` выставляет `CUDA_HOME=/usr` (когда `/usr/local/cuda/include/nvrtc.h`
  нет, а `/usr/include/nvrtc.h` есть), поэтому программа с `!` теперь собирает
  device-программу рядом с бинарником как `<binary>.gpu`, а `--gpu` исполняет её
  на устройстве.
* `--gpu` на CPU-only бинарнике (той сборки, где `.gpu` не появился) падает с
  `bend: --gpu on, but this binary found no GPU device`. Это про сборку
  бинарника, а не про отсутствие GPU на машине.
* GPU-линия требует **clang 19+**; Bend сам выбирает `clang-19`, когда он
  установлен. На clang 18 сборка молча даёт CPU-only бинарник.
* `!` на JS-бэкенде по-прежнему игнорируется: время то же, что без `!`.
* Разница в C-файле между `!` и без `!`: `#define BANGS 0` против `1` и один
  флаг в `FID_FLAG_T`.

Историческое — измерено, когда GPU-линии ещё не было, сейчас не перемерялось:

* Без `!` и с `!` программы вели себя одинаково и одинаково параллелились на
  CPU: CUDA не находилась, device-программа не собиралась.
* `-o` с `!` собирался и на clang 18.1.3, exit 0, — но это была молча
  CPU-only сборка вопреки требованию «clang 19+ с `!`» из гайда.
* Файл `.gpu` **не создавался** (ни для `bench_sum_gpu`, ни для ray tracer,
  ни для `pure_par_sort`).

### Замеры: `bench_sum.bend` (сумма 2^22 чисел, fork/join, `d=22`)

Один и тот же код, `main -> IO(Unit)`, внутри `IO.now()` вокруг `sum(22n, 0n)`.
Нативный бинарник (`-o`), по 5 прогонов, мс (медиана):

| `--threads` | без `!` (`sum`) | с `!` (`sum!`) |
|---|---|---|
| 1 | 26 | 29 |
| 2 | 15 | 19 |
| 4 | 11 | 11 |
| 8 | 6 | 6 |
| 16 | 4 | 4 |
| 32 | 4 | 4 |

Сумма совпадает везде: `8796090925056` (= 2^21·(2^22−1)).

JS-бэкенд (`tools/bend bench_sum.bend`), тот же код: **419–432 мс** и без `!`,
и с `!` — JS всегда последовательный. То есть ускорение 1→16 потоков ≈ 6–7×,
дальше упирается в память/накладные расходы.

Официальный `demos/pure_par_sort` (2^16 листьев, `sort!`), время бинарника:

| threads | 1 | 2 | 4 | 8 | 16 | 32 |
|---|---|---|---|---|---|---|
| сек | 0.16 | 0.11 | 0.08 | 0.06 | 0.06 | 0.06 |

### Флаги рантайма

* `./bin --threads N` — N ≥ 1; `--threads 0` и `--threads abc` →
  `bend: expected a thread count of 1 or more after --threads`, exit 1.
* `./bin --gpu 4GB`:
  * на CPU-only бинарнике (без `<binary>.gpu`) — `bend: --gpu on, but this
    binary found no GPU device`, exit 1. Сюда попадает и сборка без `!`, и
    сборка на clang 18;
  * на бинарнике с device-программой — исполняется на устройстве
    (историческая заметка «на бинарнике без `!` флаг тихо игнорируется»
    относилась к состоянию без CUDA).
* Сборка `bench_sum_gpu.bend -o ...` заняла 0.48 с (тогда — без CUDA), `bench_sum` — 1.05 с.
  С включённой GPU-линией эти времена не перемерялись (см. `docs/benchmarks.md`).

---

## 6. Законы и доказательства

### Рабочий процесс

`LAWS.bend` (человек) + `PROOF.bend` (ИИ) + `bend PROOF.bend` — ворота.
Проверено на официальном ray tracer:

```sh
cd rt/ && tools/bend PROOF.bend     # -> All terms check.
tools/bend LAWS.bend                # -> Error: 2 TODOs found. ... (если открыть закон)
```

`All terms check.` печатается и для файла без `main`, где все законы закрыты
(в т.ч. `bend mymath.bend` без единого закона). Открытый закон без `def` —
это TODO: `Error: 2 TODOs found. The code is incomplete, and not a valid proof yet.`

### Что делает `{==}` успешным

`{==}` закрывает цель `{a == b : T}`, только если обе стороны **вычисляются до
одного терма**. Работает:

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

Ложный закон печатает expected/observed и место:

```
- expected : 1n
- observed : 0n
```

### `%e : P` — перезапись

Семантика (проверена): если `e : {a == b : T}`, то `P` — это цель, в которой
**`b` заменён на `_`**, а после перезаписи на место `_` встаёт `a`. То есть
перезапись всегда идёт «b → a»; чтобы получить обратное направление, нужен
`Equal.sym`.

Пример — доказанный `List.length(List.map(f, xs)) == List.length(xs)` для
конкретного `f` (файл `proofs/65_map_length.bend`):

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

**Что НЕ доказуемо:** тот же закон с `for -f: U32 -> U32` не выражается вообще
(падение на этапе проверки закона, до доказательства):

```
- expected : a defined name
- observed : List.map
Context:
- f  : @_:U32 -> U32
```

Причина: `List.map` — шаблон, `~f` обязан быть замкнутым именем top-level, а
`f` из закона — локальная (dead) переменная. Универсальный закон о `List.map`
для произвольной функции в Bend 2.0.5 записать нельзя; только инстансы под
конкретные `def`.

### `?name` и `?TODO`

* `?name` — **намеренно падает**, печатая цель (это и есть «посмотреть goal»):

```python
def add_zero(x):
  ?add_zero
```
```
- expected : {Nat.add(x, 0n) == x : Nat}
- observed : ?add_zero
```

  Внутри `match` показывает уточнённую цель ветки: `expected : {0n == 0n : Nat}`.
* `?TODO` — оставляет цель открытой и помечает файл незавершённым:
  `Error: 1 TODO found. The code is incomplete, and not a valid proof yet.`

### Индуктивы и helper-леммы

Helper-лемма — обычный `def`, возвращающий тип-доказательство, закон для него
не нужен. Полный проверенный пример (файл `proofs2/tree4.bend`, печатает
`All terms check.`): `add_zero`, `add_succ`, `add_comm` для `Nat`, затем закон
о собственном индуктивном типе:

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

Здесь видно, что рекурсивный вызов — это индуктивная гипотеза, `match`
уточняет цель по ветвям, `Equal.sym` разворачивает направление перезаписи, а
`case Node{+l, +r}` нужен, чтобы поля можно было использовать многократно.

Дополнительно проверены: `Equal.sym/trans/cong` напрямую; `exs y: Nat`
(`def two_plus_two(): (2n, {==})` — свидетелем идёт пара); опровержение
`{1n != 0n : Nat}` через мотив `disc(_)`:

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

`for y: B where P(y)` связывает `y` как зависимую пару (`Sigma`). Чтобы
упомянуть сам `y` в утверждении закона, нужен helper с зависимым типом
(проекций полей нет):

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

### F32: что можно и что нельзя

`F32` **не opaque**: это `type F32 is Data: F32{data: Word(32n)}`, и его
конструктор виден (`match x: case F32{w}: 0` компилируется). Но всё
арифметическое и сравнительное в Base объявлено как `law F32.add`, `law
F32.is_le`, … **без `def`** — это недоказуемые встроенные операции, и в
доказательствах они не редуцируются. Никаких F32-лемм в Base нет (есть только
`law`-объявления; `F32.min/max/clamp/lerp/...` построены на них).

Проверено:

| закон | результат |
|---|---|
| `{0.5 == 0.5 : F32}` + `{==}` | `All terms check.` (одинаковые литералы — один терм) |
| `{F32.add(0.5, 0.5) == 1.0 : F32}` | падает: `expected : F32.add(0.5, 0.5) / observed : 1.0` |
| `{F32.is_le(0.25, 1.0) == True{} : Bool}` | падает: `expected : F32.is_le(0.25, 1.0) / observed : True{}` |
| `{F32.bits(1.0) == 1065353216 : U32}` | падает: `expected : F32.bits(1.0) / observed : 1065353216` |
| `for x: F32 {F32.is_le(clamp01(x), 1.0) == True{} : Bool}` | падает, цель печатается нередуцированной: `expected : F32.is_le(Bool.pick(F32, F32.is_lt(1.0, ...), ...), 1.0) / observed : True{}` |

Вывод: про F32 нельзя доказать ничего, кроме равенства синтаксически одинаковых
литералов. `F32.min/max/clamp` — обычные `def`, но они разворачиваются в
opaque-`law`, поэтому на F32-значениях не вычисляются. Именно поэтому
`demos/app_ray_tracer_3d/LAWS.bend` прямо пишет: «The F32 scene is not claimed» —
законы там только про список нажатых клавиш.

### `@unsafe`

`@unsafe def` отключает проверку завершаемости (и объявляет биндеры `+` при любом
kind). Проверено: `@unsafe def loop(x: U32) -> U32: loop(x)` компилируется и
зависает. Такие `def` вне гарантий доказательств.

---

## 7. Компиляция

Замеры на этой машине (`tiny.bend` — `IO.print("compile me")`):

| команда | время | результат |
|---|---|---|
| `tools/bend tiny.bend` | ~0.09 с (JS) | печатает `compile me` |
| `tools/bend tiny.bend -o tiny.c` | ~0.09 с | `tiny.c`, 76 КБ |
| `tools/bend tiny.bend -o tiny.js` | ~0.09 с | `tiny.js`, 11 КБ |
| `tools/bend tiny.bend -o tiny.bin` | ~0.34 с | бинарник 1.08 МБ, запускается |
| `tools/bend tiny.bend --checkup` | — | ничего, exit 0 |
| `tools/bend tiny.bend --publish` | — | сейчас обёртка отказывает, exit 2 (см. ниже) |

Более крупное (исторические замеры, без GPU-линии; с `CUDA_HOME=/usr` не
перемерялись — актуальные числа см. в `docs/benchmarks.md`):

| файл | `-o` бинарник | размер |
|---|---|---|
| `bench/bench_sum.bend` (d=22) | 1.05 с | 1.09 МБ |
| `bench/bench_sum_gpu.bend` (`!`) | 0.48 с | 1.10 МБ, `.gpu` не создавался |
| `demos/app_ray_tracer_3d/main.bend` | 1.45 с | 1.16 МБ, `.gpu` не создавался |
| `demos/pure_par_sort/main.bend` | 3.19 с | `sort`, `.gpu` не создавался |

* `-o out.c` и `-o out.js` — просто выгрузка исходника (C ~76 КБ даже для
  hello world, JS ~11 КБ); `-o` без расширения — компиляция clang + запуск.
* `-o` с `!` на clang 18 **работает** (гайд требует 19+), но молча даёт
  CPU-only бинарник: `.gpu` не появляется. С `tools/bend` (то есть с
  `CUDA_HOME=/usr`) и установленным clang-19 рядом с бинарником появляется
  `<binary>.gpu`. `--gpu` на CPU-only бинарнике падает с
  `bend: --gpu on, but this binary found no GPU device`.
* `--checkup` проверяет файл и каждый импорт по отдельности:

```
--- ./mymath.bend ---
All terms check.
```

* `--publish` ходит в сеть: печатает
  `publishing 1 files, 79 bytes, as 0x<sha> (mining its proof of work)`,
  затем хэш и готовую строку `import 0x<sha>/tiny.bend as Tiny`.
  (Так было до того, как `tools/bend` получил защиту: теперь обёртка отказывает
  с exit 2 и пропускает `--publish` только при `BEND_ALLOW_PUBLISH=1`, а
  выставлять его разрешено **только человеку**. Публикация необратима.)
* `main -> IO(...)` выполняется; `main` без `IO` нормализуется чекером и
  печатается (`25`, `[1, 2, 3]`, `{==}`); файл без `main` — только проверка,
  печатает `All terms check.`

---

## 8. Ловушки, баги, странности

1. **`main` без `IO` нормализуется чекером и легко роняет стек.** Тот же
   fork/join `sum`, что в §5 работает на глубине 22 из `IO`-`main`, из
   `main -> Nat` падает уже на глубине 8:
   `Error: the machine stack overflowed (a deep recursion, or a literal too
   large to expand)`. `d=4` ещё печатает `120n`. Для реальных программ `main`
   должен возвращать `IO`.
2. **Текст ошибки `match` в `do`:** `expected : a term (a match heads a def body,
   not a term) / observed : ' '` — observed это пробел, а не токен.
3. **`case 1n+p` по `U32`:** `expected : cases for True / observed : \{}` —
   сообщение не говорит, что `U32` не поддерживает successor-паттерн.
4. **Порядок scrutinee/`let`:** сообщение `match scrutinees in binder order (...)`
   не указывает, какой именно `let` мешает.
5. **Нет проекций полей** (`.fst`/`.snd`/`.x`) и нет деструктуризации в `do` —
   самая частая причина обходных helper-`def`. В гайде про это не сказано явно.
6. **Нет `String.show`** в Base — неожиданно, если ждёшь симметрии с `U32.show`.
7. **`List.map` возвращает `List<&1, _>`**, а `List.show` по умолчанию ждёт
   `&2`; прямая композиция не проходит по kind.
8. **`: T` — не приведение типа.** `(e : T)` задаёт тип операторов внутри `e`,
   а `{e : T}` — аннотация, но конверсии нет: `{3 : Nat}` не компилируется.
   Легко принять `((a < b) && (c < d) : U32)` за U32-выражение — на самом деле
   это Bool.
9. **Унарного минуса нет**, `//`-комментариев нет, `if` нет — всё это
   синтаксические ошибки с неочевидными `observed`.
10. **Аннотированный `let` (`x : T = v`) существует только в `do`;** в теле
    `def` это `expected : 'def', 'type' or 'law' / observed : ':'`.
11. **Тип-функция в `do`-let требует скобок**: `f : U32 -> U32 = ...` →
    `expected : '<-' / observed : '-'`.
12. **Шаблонные аргументы на call-site — все с `~`**; смешивать нельзя
    (`expected : a term / observed : '~'`).
13. **Универсальные законы про `List.map` невыразимы** — шаблонный аргумент
    обязан быть закрытым именем; ошибка `expected : a defined name / observed :
    List.map` на законе, который выглядит совершенно нормально.
14. **F32 непроницаем для доказательств**, хотя и не opaque: все операции —
    `law` без `def`. Никакой F32-леммы в Base нет.
15. **Деление на ноль у `U32`/`Nat` возвращает 0**, а не падает и не
    `Maybe`/`Result` — легко пропустить.
16. **`Nat` молча обрывает программу** за `2^48−1`:
    `bend: a Nat past the largest immediate 2^48-1`, exit 1 (одинаково на JS и
    нативно).
17. **`@unsafe` + бесконечная рекурсия = зависание** без предупреждений.
18. **`--gpu` на CPU-only бинарнике** (нет `<binary>.gpu`: сборка без `!`
    или на clang 18) — ошибка `bend: --gpu on, but this binary found no GPU
    device`. Сообщение говорит про сборку, а не про отсутствие GPU.
19. `Map.get`/`Map.has` — не IO, хотя возвращают пару; `<-` для них даёт
    длинную ошибку про `@-R:Type -> ...`, а не «это не IO».
20. `tools/bend` отказывает на `--publish` (exit 2), пока человек явно не
    выставит `BEND_ALLOW_PUBLISH=1`; публикация необратима, и в скриптах это
    надо учитывать.

---

## Приложение: где лежат проверки

| тема | файлы |
|---|---|
| синтаксис, типы, quantities, kinds, шаблоны, замыкания | `probes/01…06*` |
| `match`/`let`/affine/termination | `probes/10…23*, 40…49*` |
| числа, деление, overflow | `probes/30…39*` |
| файлы, `IO.now`, `IO.try`, `Chan`, дедлок | `probes/50…53*` |
| массивы, `do Maybe`, модули | `probes/70…73*` |
| законы, `%`, `?name`, `?TODO`, F32, `where`, `exs`, Empty | `proofs/60…68*, proofs2/*` |
| полный закон о `Tree` + леммы о `Nat` | `proofs2/tree4.bend` |
| параллельные замеры | `bench/`, `results/10-parallel-*` |
| официальные демо (ray tracer, par_sort, par_sum) | `rt/`, `pps/`, `demos/` |

Сырые логи: `results/01-syntax.txt`, `results/02-gotchas.txt`,
`results/03-gotchas2.txt`, `results/04-numbers.txt`, `results/05-numbers2.txt`,
`results/06-cmp.txt`, `results/07-termination.txt`, `results/07b-termination.txt`,
`results/08-patterns.txt`, `results/09-io.txt`, `results/10-parallel-noBang.txt`,
`results/11-laws.txt`, `results/12-laws2.txt`, `results/13-arrays.txt`,
`results/14-proofs3.txt`.
