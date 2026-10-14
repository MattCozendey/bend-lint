#!/usr/bin/env python3
"""Reorder the top-level items of a Bend file into dependency order.

Bend has no forward references: a def may only use names declared above it,
and mutual recursion is rejected outright.  That makes declaration order part
of the program, which is easy to get wrong while editing.  This script reads
a .bend file, builds the reference graph between its top-level items, and
rewrites the file with the items topologically sorted.

  python3 tools/order.py src/scene.bend          # rewrite in place
  python3 tools/order.py src/scene.bend --check  # report, change nothing

It exits non-zero on a cycle, naming the items involved: a cycle is a real
error in Bend (mutual recursion) and has to be broken by hand, usually by
folding the two defs into one and matching on a Bool parameter instead of
calling a helper.
"""

from __future__ import annotations

import re
import sys

ITEM = re.compile(
    r"^(def|type|law)\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)"
)


def parse(text: str):
    lines = text.split("\n")
    starts = []
    for i, line in enumerate(lines):
        m = ITEM.match(line)
        if m:
            starts.append((i, m.group(1), m.group(2)))
    if not starts:
        return lines, []
    header = lines[: starts[0][0]]
    chunks = []
    for k, (i, kind, name) in enumerate(starts):
        end = starts[k + 1][0] if k + 1 < len(starts) else len(lines)
        chunks.append(list(lines[i:end]))
    # A comment block sitting directly above a def belongs to that def, so
    # move it from the previous chunk into the next one.
    for k in range(len(chunks) - 2, -1, -1):
        body = chunks[k]
        j = len(body)
        while j > 0 and (body[j - 1].strip() == "" or body[j - 1].lstrip().startswith("#")):
            j -= 1
        chunks[k] = body[:j]
        chunks[k + 1] = body[j:] + chunks[k + 1]
    return header, [(name, kind, chunks[k]) for k, (_, kind, name) in enumerate(starts)]


def strip_comments(lines):
    return "\n".join(l for l in lines if not l.lstrip().startswith("#"))


def deps_of(body: str, names: set[str]) -> set[str]:
    found = set()
    for other in names:
        # a def reference is `name(`; a type reference is `name{`, `name<` or
        # a bare `name` in a signature
        if re.search(r"(?<![A-Za-z0-9_.])" + re.escape(other) + r"\s*[({<]", body):
            found.add(other)
    return found


def order(header, items, check_only):
    names = {n for n, _, _ in items}
    body = {n: strip_comments(b) for n, _, b in items}
    graph = {n: deps_of(body[n], names) - {n} for n in names}

    ordered: list[str] = []
    state: dict[str, int] = {}
    cycle: list[str] = []

    def visit(n: str, stack: list[str]):
        if state.get(n) == 2:
            return
        if state.get(n) == 1:
            cycle.extend(stack[stack.index(n):] + [n])
            return
        state[n] = 1
        for d in sorted(graph[n]):
            visit(d, stack + [n])
        state[n] = 2
        ordered.append(n)

    for n in sorted(names):
        visit(n, [])

    if cycle:
        print("cycle (mutual recursion, not allowed in Bend): " + " -> ".join(cycle), file=sys.stderr)
        return None

    by_name = {n: (kind, b) for n, kind, b in items}
    out = list(header)
    for n in ordered:
        kind, b = by_name[n]
        out.extend(b)
        if out and out[-1].strip() != "":
            out.append("")
    return out


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    check_only = "--check" in sys.argv[2:]
    text = open(path, encoding="utf-8").read()
    header, items = parse(text)
    was = [n for n, _, _ in items]
    out = order(header, items, check_only)
    if out is None:
        return 1
    new = "\n".join(out).rstrip("\n") + "\n"
    now = [m.group(2) for m in (ITEM.match(l) for l in out) if m]
    if now == was:
        print(f"{path}: already in dependency order ({len(now)} items)")
        return 0
    if check_only:
        print(f"{path}: NOT in dependency order")
        print("  was: " + ", ".join(was))
        print("  want: " + ", ".join(now))
        return 1
    open(path, "w", encoding="utf-8").write(new)
    print(f"{path}: reordered {len(now)} items")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
