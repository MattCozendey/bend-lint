// get_spliced_text
// ================
// The text with its code points from beg to end replaced by put. Bend can
// splice a String itself, but on the JS lane each step copies the rest.

function bendlint_get_spliced_text(text, beg, end, put) {
  if (!/[\uD800-\uDFFF]/.test(text)) {
    return text.slice(0, beg) + put + text.slice(end);
  }
  const points = Array.from(text);
  return points.slice(0, beg).join("") + put + points.slice(end).join("");
}

io_eff(CID(get_spliced_text), bendlint_get_spliced_text);
