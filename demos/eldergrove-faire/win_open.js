// Adapted from Bend's window_open.js (HigherOrderCO, Apache License 2.0).
// The JavaScript target has no native window.
function win_open(title, width, height) {
  const text = "Window.open: no display (build a native binary with bend <file> -o <out> and run it from a desktop session)";
  return { $: "Fail", error: { $: "Tuple", fst: 95, snd: text } };
}
