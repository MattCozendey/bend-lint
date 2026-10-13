// Functions
// =========

// `text` with each CRLF line end made LF.
export const getTextWithLfLineEnds = (text: string): string => text.replace(/\r\n/g, "\n");

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
