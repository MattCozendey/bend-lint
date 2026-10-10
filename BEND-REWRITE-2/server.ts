// The checker server: see the header of lint.bend. It runs a rules program
// (a build of a file that imports lint.bend), and answers its questions
// about Bend files over local TCP, until the program exits. It is the one TS
// file of this folder, and it goes when Bend's checker is Bend.
//
// Usage: bun server.ts <program> <args...> (or node, 24 or later)

// Imports
// =======

import { spawn } from "node:child_process";
import { once } from "node:events";
import * as nodeFs from "node:fs";
import * as net from "node:net";
import * as nodePath from "node:path";
import * as readline from "node:readline";
import * as url from "node:url";

import type * as BendModule from "bend2/bend.ts";

// Types
// =====

type Bend = typeof BendModule;

// Bend, and Base as checked once.
type Checker = { Bend: Bend; base: BendModule.Book };

// Constants
// =========

const GIVE = "set BEND_DIR to a bend checkout";

const ESCAPES: Record<string, string> = { "\\": "\\\\", "\t": "\\t", "\n": "\\n" };

// Functions
// =========

const message = (e: unknown): string => (e instanceof Error ? e.message : String(e));

const field = (text: string): string => text.replace(/[\\\t\n]/g, (c) => ESCAPES[c]);

const unfield = (text: string): string =>
  text.replace(/\\(.)/g, (_, c: string) => (c === "t" ? "\t" : c === "n" ? "\n" : c));

const record = (fields: string[]): string => fields.map(field).join("\t") + "\n";

const isErr = (e: unknown): e is BendModule.Err =>
  typeof e === "object" && e !== null && (e as { $?: unknown }).$ === "Err";

// The bend2 folder: BEND_DIR, a checkout or its bend2 folder.
const bendDir = (): string => {
  const chosen = process.env.BEND_DIR;
  if (chosen === undefined) {
    throw new Error("no BEND_DIR; " + GIVE);
  }
  const dir = nodePath.resolve(chosen);
  const found = [nodePath.join(dir, "bend2"), dir].find((d) =>
    nodeFs.existsSync(nodePath.join(d, "bend.ts")),
  );
  if (found === undefined) {
    throw new Error(`no bend2 at ${dir} (it needs bend.ts); ${GIVE}`);
  }
  return found;
};

// A fresh book that holds Base, as main.ts's book_seed makes it.
const seeded = (Bend: Bend, base: BendModule.Book): BendModule.Book => ({
  ...Bend.book_nil(),
  tlds: Object.fromEntries(Object.entries(base.tlds).map(([k, tld]) => [k, { ...tld }])),
  ctrs: { ...base.ctrs },
  order: [...base.order],
  tmps: Object.fromEntries(Object.entries(base.tmps).map(([k, m]) => [k, new Map(m)])),
});

const load = async (): Promise<Checker> => {
  const Bend = (await import(url.pathToFileURL(nodePath.join(bendDir(), "bend.ts")).href)) as Bend;
  const base = Bend.book_nil();
  await Bend.book_load(base, Bend.BASE_BEND, "", new Map());
  Bend.book_valid(base, 0);
  return { Bend, base };
};

// The answer to `check <path>`: the files the check read, then its
// definitions, or why it failed.
const check = async ({ Bend, base }: Checker, path: string): Promise<string> => {
  const book = seeded(Bend, base);
  const seen = new Map<string, string | null>([[Bend.BASE_BEND, ""]]);
  try {
    await Bend.book_load(book, nodePath.resolve(path).replaceAll("\\", "/"), "", seen);
    Bend.book_valid(book, base.order.length);
  } catch (e) {
    return record(["fail", isErr(e) ? Bend.err_show(e) : message(e)]);
  }
  const sources = [...seen.keys()].filter((p) => p !== Bend.BASE_BEND);
  return [
    ...sources.map((p) => record(["source", p])),
    ...book.order.slice(base.order.length).map((k) => record(["def", k])),
  ].join("");
};

const answer = (checker: Checker, line: string): Promise<string> => {
  const [op, ...args] = line.split("\t").map(unfield);
  return op === "check" && args.length === 1
    ? check(checker, args[0])
    : Promise.resolve(record(["fail", "unknown request: " + line]));
};

// One request: read its line, write the whole answer, close.
const serve = async (checker: Checker, socket: net.Socket): Promise<void> => {
  const lines = readline.createInterface({ input: socket });
  const [line] = (await once(lines, "line")) as [string];
  lines.close();
  socket.end(await answer(checker, line));
};

// Side effects
// ============

const [program, ...args] = process.argv.slice(2);
if (program === undefined) {
  console.error("usage: bun server.ts <program> <args...>");
  process.exit(2);
}

const checker = await load().catch((e: unknown) => {
  console.error("bend-lint: " + message(e));
  process.exit(2);
});

const server = net.createServer((socket) => void serve(checker, socket));
server.listen(0, "127.0.0.1");
await once(server, "listening");

const child = spawn(program, args, {
  env: { ...process.env, BEND_LINT_PORT: String((server.address() as net.AddressInfo).port) },
  stdio: "inherit",
});
const [code] = (await once(child, "exit")) as [number | null];
server.close();
process.exit(code ?? 1);
