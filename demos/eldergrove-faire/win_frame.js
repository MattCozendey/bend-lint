// Adapted from Bend's window_frame.js (HigherOrderCO, Apache License 2.0).
// Window
// ======

function win_frame(window, image) {
  return { $: "Tuple", fst: window,
    snd: { $: "Tuple", fst: image, snd: { $: "Nil" } } };
}
