// Functions
// =========

// `text` with each CRLF line end made LF.
export const getTextWithLfLineEnds = (text: string): string => text.replace(/\r\n/g, "\n");

// The offset where each line of `text` starts.
export const getLineStartOffsets = (text: string): number[] => [
  0,
  ...[...text.matchAll(/\n/g)].map((found) => found.index + 1),
];

// The index of the line that holds `offset`, given each line's start offset
// (from getLineStartOffsets).
export const getLineIndexAtOffset = (
  lineStarts: number[],
  offset: number,
  lo = 0,
  hi = lineStarts.length - 1,
): number => {
  if (lo >= hi) {
    return lo;
  }
  const mid = Math.ceil((lo + hi) / 2);
  return lineStarts[mid] <= offset
    ? getLineIndexAtOffset(lineStarts, offset, mid, hi)
    : getLineIndexAtOffset(lineStarts, offset, lo, mid - 1);
};

// `text` with each edit's first string replaced by its second, in order.
// Each first string must occur exactly once in the text the edits before it
// left; else `onMismatch` gets it, and how many times it occurs.
export const getTextWithEachEditAppliedOnce = (
  text: string,
  edits: ReadonlyArray<readonly [string, string]>,
  onMismatch: (at: string, count: number) => never,
): string =>
  edits.reduce((out, [at, to]) => {
    const count = out.split(at).length - 1;
    return count === 1 ? out.replace(at, () => to) : onMismatch(at, count);
  }, text);
