// A silent device for the JavaScript target: the ring drains by the clock.
function snd_open(rate) {
  return { rate: rate, queued: 0, at: Date.now() };
}
