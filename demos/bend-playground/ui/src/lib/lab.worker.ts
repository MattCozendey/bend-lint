import { asset } from './runtime'
// Algorithm implementations are imported from Bend-generated modules. This
// worker handles input/output, presentation ordering, and bounded scheduling.
type Bend = Record<string, (...args: any[]) => any>
const engines = new Map<string, Promise<Bend>>()
const engine = (name: string) => { if (!engines.has(name)) engines.set(name, import(/* @vite-ignore */ asset(`${name}-engine.js`)).then(m => m.default)); return engines.get(name)! }
const list = (a: any[]) => a.reduceRight((tail, head) => ({ $: 'Con', head, tail }), { $: 'Nil' })
const array = (xs: any) => { const a = []; for (let x = xs; x.$ === 'Con'; x = x.tail) a.push(x.head); return a }
let coefficients: any[] = [], selected: any = list([])
let population: any, target: any, alphabet: string[] = [], generation = 0, seed = 42, targetLength = 0, populationSize = 100, mode = 'evolution', mutation = 100, bestEver: any
function genome(g: any) { return { text: array(g.genes).map((i: number) => alphabet[i]).join(''), fitness: g.fitness } }
async function handle(d: any) {
  if (d.action.startsWith('fourier')) {
    const f = await engine('fourier')
    if (d.action === 'fourier-init') {
      if (d.mode === 'wave') coefficients = Array.from({ length: 64 }, (_, i) => f.harmonic(i))
      else {
        const points = list(d.points.map(([x, y]: number[]) => ({ $: 'Point', x, y })))
        coefficients = d.points.map((_: unknown, k: number) => f.dft(points, k, d.points.length)).sort((a: any, b: any) => b.amplitude - a.amplitude)
      }
    }
    if (d.action !== 'fourier-frame') {
      selected = list(coefficients.slice(0, d.terms))
      const path = new Float32Array(513 * 2)
      for (let i = 0; i <= 512; i++) { const p = f.endpoint(selected, i / 512 * 2 * Math.PI, 0, 0); path[i * 2] = p.x; path[i * 2 + 1] = p.y }
      return { path, available: coefficients.length }
    }
    return { chain: array(f.chain(selected, d.phase * Math.PI * 2, 0, 0)) }
  }
  if (d.action === 'polar') {
    const p = await engine('polar'), path = new Float32Array(2049 * 2)
    for (let i = 0; i <= 2048; i++) { const v = p.point(BigInt(d.kind), i / 2048, d.petals, d.turns); path[i * 2] = v.x; path[i * 2 + 1] = v.y }
    return { path }
  }
  if (d.action === 'sort') {
    const s = await engine('sorting'), depth = BigInt(Math.ceil(Math.log2(d.size)))
    const input = s.build(depth, 0, d.size, BigInt(d.pattern), d.seed)
    const result = s.sort(BigInt(d.algorithm), input, d.size, depth)
    const values = Array.from({ length: d.size }, (_, i) => s.value(BigInt(d.pattern), i, d.size, d.seed))
    const stack = [result.events], ops: number[] = []
    while (stack.length) { const e = stack.pop()!; if (e.$ === 'Both') stack.push(e.right, e.left); else if (e.$ === 'Op') ops.push(e.kind, e.a, e.b) }
    return { values, operations: new Uint32Array(ops) }
  }
  if (d.action.startsWith('shakespeare')) {
    const e = await engine('shakespeare')
    if (d.action === 'shakespeare-init') {
      const chars = Array.from(d.target as string)
      if (!chars.length) throw new Error('Enter a target phrase.')
      alphabet = [...new Set(Array.from('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz 0123456789!;.,?\'"-:' + d.target))]
      target = list(chars.map(c => alphabet.indexOf(c))); targetLength = chars.length
      populationSize = d.population; mutation = d.mutation; mode = d.mode; seed = d.seed >>> 0; generation = 0
      population = e.initial(BigInt(populationSize), BigInt(targetLength), alphabet.length, seed, target); bestEver = e.best(population)
    } else if (bestEver.fitness < targetLength) {
      seed = e.next_seed(seed)
      population = mode === 'random' ? e.initial(BigInt(populationSize), BigInt(targetLength), alphabet.length, seed, target) : e.generation(BigInt(populationSize), population, target, alphabet.length, mutation, seed)
      bestEver = e.better(e.best(population), bestEver); generation++
    }
    return { generation, best: genome(bestEver), average: e.total(population) / populationSize, candidates: array(population).slice(0, 12).map(genome), finished: bestEver.fitness === targetLength, targetLength, attempts: (generation + 1) * populationSize }
  }
  throw new Error('Unknown Bend request.')
}
let queue = Promise.resolve()
self.onmessage = event => {
  queue = queue.then(async () => {
    const { id, ...d } = event.data
    try {
      // Lazy load before timing so compute doesn't include network/module startup.
      const name = d.action.startsWith('fourier') ? 'fourier' : d.action.startsWith('shakespeare') ? 'shakespeare' : d.action === 'sort' ? 'sorting' : 'polar'
      await engine(name)
      const start = performance.now(), result = await handle(d)
      const transfers = Object.values(result).filter(v => ArrayBuffer.isView(v)).map(v => (v as Float32Array).buffer)
      self.postMessage({ id, result: { ...result, computeMs: performance.now() - start } }, { transfer: transfers })
    } catch (e) { self.postMessage({ id, error: (e as Error).message }) }
  })
}
