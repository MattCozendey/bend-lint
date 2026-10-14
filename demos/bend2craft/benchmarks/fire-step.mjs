// FIRE_DIR points at another copy of world/ to compare two versions.
const { default: Fire } = await import(`${process.env.FIRE_DIR ?? "../world"}/fire.bend`);

function sampleList(values) {
  let list = { $: "Nil" };
  for (let index = values.length - 1; index >= 0; index -= 1) {
    list = { $: "Con", head: values[index], tail: list };
  }
  return list;
}

function measure(fn, repeats = 10) {
  fn();
  const start = performance.now();
  for (let repeat = 0; repeat < repeats; repeat += 1) fn();
  return (performance.now() - start) / repeats;
}

const samples = sampleList([
  Fire.sample(2n, 3n, 2n, 0),
  Fire.sample(4n, 3n, 2n, 5),
]);
const state = Fire.ignite(Fire.empty(), 2n, 3n, 2n);
console.log(JSON.stringify({
  tickAndChangesMs: measure(() => {
    const next = Fire.tick(state, samples);
    Fire.changes(state, next);
  }),
}));

// A pool of water: the simulation samples every fluid cell's neighbourhood
// (hundreds of samples, one lava cell), and fire checks them every tick.
const pool = [];
for (let x = 0; x < 12; x += 1) {
  for (let z = 0; z < 12; z += 1) {
    pool.push(Fire.sample(BigInt(100 + x), 8n, BigInt(100 + z), 7));
    pool.push(Fire.sample(BigInt(100 + x), 7n, BigInt(100 + z), 3));
    pool.push(Fire.sample(BigInt(100 + x), 9n, BigInt(100 + z), 0));
  }
}
pool.push(Fire.sample(99n, 8n, 99n, 21));
const poolSamples = sampleList(pool);
console.log(JSON.stringify({
  samples: pool.length,
  poolIgniteMs: measure(() => Fire.ignite_lava(Fire.empty(), poolSamples), 3),
}));
