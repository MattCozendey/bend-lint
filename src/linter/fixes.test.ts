// Imports
// =======

import { describe, expect, setDefaultTimeout, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

import { tryGetBend2SourceUrl } from "../shared/bend2.ts";
import { unwrap } from "../shared/result.ts";
import { getCommandOutcome, writeFileAtomically } from "../shared/utils.ts";
import { BUILD, getBuiltProgram } from "./seam.ts";
import { BUILDS, getFreshFolder } from "./testing.ts";

// Constants
// =========

const BLOCK = "#".padEnd(255, "a");
const REPEATS = 257;
const ORIGINAL = BLOCK.repeat(REPEATS) + "é\n";
const DRIVER = path.join(BUILD, "fixes-test.bend");
const SOURCE = `import Base
import ../fixes.bend as Fixes
import ../lint.bend as Lint

def main() -> IO(Unit):
  +span = {Lint.Span{"main.bend", 0, 0} : Lint.Span}
  fix = {Lint.Fix{"Insert a comment", [Lint.Replace{span, "# fixed\\n"}]} : Lint.Fix}
  found = {Lint.Found{"tests/fix", Lint.Finding{Lint.Hint{}, span, "Insert a comment", [fix]}} : Lint.Found}
  do IO<Unit>:
    n : U32 <- Fixes.apply(
      True{},
      [found],
      [],
      [Lint.Source{"main.bend", "", String.repeat(${JSON.stringify(BLOCK)}, ${REPEATS}n) ++ "é\\n", []}]
    )
    IO.print(U32.show(n))
`;

// Functions
// =========

const getFixOutcome = async (saved: string) => {
  const dir = getFreshFolder();
  const file = path.join(dir, "main.bend");
  fs.writeFileSync(file, ORIGINAL);
  fs.writeFileSync(file, saved);
  const program = await getBuiltProgram(DRIVER, unwrap(await tryGetBend2SourceUrl()));
  const ran = await getCommandOutcome(
    /\.m?js$/.test(program) ? [process.execPath, program] : [program],
    dir,
  );
  return { ...ran, text: fs.readFileSync(file, "utf8") };
};

// Side effects
// ============

writeFileAtomically(DRIVER, SOURCE);
setDefaultTimeout(120_000);

(BUILDS ? describe : describe.skip)("fixes", () => {
  test("preserves text saved after the source was read", async () => {
    const saved = ORIGINAL.replace("é", "ø");
    const ran = await getFixOutcome(saved);
    expect(ran.code).toBe(2);
    expect(ran.text).toBe(saved);
    expect(ran.err).toContain("main.bend: file changed during lint; run the command again");
  });

  test("applies a fix after a save with identical text", async () => {
    const ran = await getFixOutcome(ORIGINAL);
    expect([ran.code, ran.out.trim(), ran.err]).toEqual([0, "1", ""]);
    expect(ran.text).toBe("# fixed\n" + ORIGINAL);
  });
});
