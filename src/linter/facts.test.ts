// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";

import { build, BUILDS, lint, run } from "./testing.ts";
import type { Found } from "./testing.ts";

// Constants
// =========

// Built once, before the tests; nothing to build when bend does not run.
const [TYPES, BUDGET, BINDERS, TERMS, USES] = BUILDS
  ? await Promise.all(
      ["types", "budget", "binders", "terms", "uses"].map((name) => build(`tests/${name}.bend`)),
    )
  : ["", "", "", "", ""];

const UTIL = "import Base\n\ntype T is Data:\n  A{}\n  B{}\n";

const LAW = "import Base\n\nlaw same_id:\n  for e: U32\n  {e == e : U32}\n";

const SHAPE = "import Base\n\ntype Shape is Data:\n  Circle{r: U32}\n  Rect{w: U32, h: String}\n\n";

// Functions
// =========

const found = async (
  program: string,
  main: string,
): Promise<Array<Pick<Found, "at" | "message">>> =>
  (await lint(program, { "main.bend": main, "util.bend": UTIL, "law.bend": LAW }, "main.bend")).map(
    ({ at, message }) => ({ at, message }),
  );

// Side effects
// ============

setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("facts", () => {
  test("a later run sees each file as it is now, the checker's types included", async () => {
    const add = (t: string): string =>
      `import Base\n\ndef add(a: ${t}, b: ${t}) -> ${t}:\n  (a + b : ${t})\n`;
    const first = await run(TYPES, { "main.bend": add("U32") }, "main.bend");
    const again = await run(TYPES, {}, "main.bend", [], first.dir);
    const changed = await run(TYPES, { "main.bend": add("F32") }, "main.bend", [], first.dir);
    expect([first.out.includes("type: U32"), again.out, changed.out.includes("type: F32")]).toEqual(
      [true, first.out, true],
    );
  });

  test("a variable use has the type it was checked as; same types are the same", async () => {
    expect(
      await found(TYPES, "import Base\n\ndef add(a: U32, b: U32) -> U32:\n  (a + b : U32)\n"),
    ).toEqual([
      { at: "4:4", message: "type: U32" },
      { at: "4:8", message: "type: U32" },
      { at: "4:4", message: "the first two are the same type" },
    ]);
  });

  test("different types are different", async () => {
    expect(
      await found(
        TYPES,
        "import Base\n\ndef size(s: String, n: U32) -> U32:\n  (U32.from_nat(String.length(s)) + n : U32)\n",
      ),
    ).toEqual([
      { at: "4:31", message: "type: String" },
      { at: "4:37", message: "type: U32" },
      { at: "4:31", message: "the first two are different types" },
    ]);
  });

  test("a type is shown as the file spells it", async () => {
    expect(
      await found(
        TYPES,
        "import Base\nimport ./util.bend as U\n\ndef push(t: U.T, xs: List<&2, U.T>) -> List<&2, U.T>:\n  t <> xs\n",
      ),
    ).toEqual([
      { at: "5:3", message: "type: U.T" },
      { at: "5:8", message: "type: List<&2, U.T>" },
      { at: "5:3", message: "the first two are different types" },
    ]);
  });

  test("a binder has the type it declares, with its quantity, also when nothing uses it", async () => {
    expect(
      await found(
        BINDERS,
        SHAPE +
          "def area(x: Shape, k: U32) -> U32:\n  match x:\n    case Circle{r}:\n      (r * k : U32)\n    case Rect{w, h}:\n      w\n",
      ),
    ).toEqual([
      { at: "4:10", message: "r (once): U32" },
      { at: "5:8", message: "w (once): U32" },
      { at: "5:16", message: "h (once): String" },
      { at: "7:10", message: "x (once): Shape" },
      { at: "7:20", message: "k (once): U32" },
      { at: "9:17", message: "r (once): U32" },
      { at: "11:15", message: "w (once): U32" },
      { at: "11:18", message: "h (once): String" },
    ]);
  });

  test("a binder is used as often as its body uses it, the most over its branches", async () => {
    expect(
      await found(
        USES,
        SHAPE +
          "def area(x: Shape, k: U32) -> U32:\n  match x:\n    case Circle{r}:\n      (r * k : U32)\n    case Rect{w, h}:\n      w\n\n" +
          "def inc(+n: U32) -> U32:\n  f : U32 -> U32 = z => (z + n : U32)\n  f(n)\n",
      ),
    ).toEqual([
      { at: "7:20", message: "k: used once" },
      { at: "9:17", message: "r: used once" },
      { at: "11:15", message: "w: used once" },
      { at: "11:18", message: "h: used erased" },
      { at: "14:10", message: "n: used many" },
      { at: "15:3", message: "f: used once" },
      { at: "15:20", message: "z: used once" },
    ]);
  });

  test("a let's and a lambda's binders have the types they bind", async () => {
    expect(
      await found(
        BINDERS,
        "import Base\n\ndef inc(+n: U32) -> U32:\n  f : U32 -> U32 = z => (z + n : U32)\n  f(n)\n",
      ),
    ).toEqual([
      { at: "3:10", message: "n (many): U32" },
      { at: "4:3", message: "f (once): @_:U32 -> U32" },
      { at: "4:20", message: "z (once): U32" },
    ]);
  });

  test("a law's fill takes the law's types for its parameters", async () => {
    expect(
      await found(BINDERS, "import Base\nimport ./law.bend as L\n\ndef L.same_id(e):\n  {==}\n"),
    ).toEqual([{ at: "4:15", message: "e (once): U32" }]);
  });

  test("a matched variable used again gets no other variable's type", async () => {
    const main =
      SHAPE +
      "def again(x: Shape) -> Shape:\n  match x:\n    case Circle{r}:\n      x\n    case Rect{w, h}:\n      x\n";
    expect(
      (await found(TYPES, main)).filter(
        ({ at, message }) => (at === "10:7" || at === "12:7") && message !== "type: Shape",
      ),
    ).toEqual([]);
    expect((await found(BINDERS, main)).filter(({ at }) => at === "7:11")).toEqual([
      { at: "7:11", message: "x (once): Shape" },
    ]);
  });

  test("a term has the type it has, not each type it is checked against", async () => {
    expect(await found(TYPES, "import Base\n\ndef up(A: Data) -> Type:\n  A\n")).toEqual([
      { at: "4:3", message: "type: Data" },
    ]);
  });

  test("in a do-block, each variable has its own type", async () => {
    expect(
      await found(
        TYPES,
        "import Base\n\ndef say(m: IO(Unit)) -> IO(U32):\n  do IO<U32>:\n    m\n    n : U32 <- IO.pure(U32, 3)\n    return n\n",
      ),
    ).toEqual([
      { at: "5:5", message: "type: IO(Unit)" },
      { at: "7:12", message: "type: U32" },
      { at: "5:5", message: "the first two are different types" },
    ]);
  });

  test("types that name different binders are different, though written alike", async () => {
    expect(
      await found(
        TYPES,
        "import Base\n\ndef f(-A: Type, x: A) -> A:\n  x\n\ndef g(-B: Type, y: B) -> B:\n  y\n",
      ),
    ).toEqual([
      { at: "4:3", message: "type: A" },
      { at: "7:3", message: "type: B" },
      { at: "4:3", message: "the first two are different types" },
    ]);
  });

  test("a template's parameter is shown as written, and a call to a template has its type", async () => {
    const main =
      "import Base\n\ndef tid(~A: Data, x: A) -> A:\n  x\n\ndef use(y: U32) -> U32:\n  tid(~U32, y)\n";
    expect(await found(TYPES, main)).toEqual([
      { at: "4:3", message: "type: A" },
      { at: "7:13", message: "type: U32" },
      { at: "4:3", message: "the first two are different types" },
    ]);
    expect(await found(TERMS, main)).toEqual([{ at: "7:3", message: "call: U32" }]);
  });

  test("a char literal is a Char, and no literal in it is", async () => {
    const terms = await found(TERMS, "import Base\n\ndef c() -> Char:\n  'a'\n");
    expect(terms).toContainEqual({ at: "4:3", message: "construction: Char" });
    expect(terms).not.toContainEqual({ at: "4:3", message: "literal: Char" });
  });

  test("a file with no variable uses asks nothing", async () => {
    expect(await found(TYPES, "import Base\n\ndef one() -> U32:\n  1\n")).toEqual([]);
  });

  test("a rule that asks past the round budget fails, and says so", async () => {
    expect(await found(BUDGET, "import Base\n\ndef id(x: U32) -> U32:\n  x\n")).toEqual([
      {
        at: "1:1",
        message: "The rule tests/budget asked the checker more rounds than its budget.",
      },
    ]);
  });
});
