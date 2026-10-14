// Samples into the silent device; the frames queued after the write.
function snd_write(snd, samples) {
  let n = 0;
  for (let xs = samples; xs.$ === "Con"; xs = xs.tail) {
    n += 1;
  }
  const now = Date.now();
  snd.queued = Math.max(0, snd.queued - (now - snd.at) * snd.rate / 1000);
  snd.at = now;
  if (snd.queued + n / 2 <= 4096) {
    snd.queued += n / 2;
  }
  return io_tup(snd, Math.floor(snd.queued));
}
