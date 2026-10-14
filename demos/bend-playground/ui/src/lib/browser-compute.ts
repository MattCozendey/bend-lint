// Host code validates inputs and packages results. The numerical algorithms,
// random sampling, physics, and Life rules all execute in compiled Bend.
export type BendEngine = Record<string, (...args: any[]) => any>
type LoadEngine = (name: string) => Promise<BendEngine>
function integer(value: unknown, name: string, zero = false): number {
  const n = Number(value)
  if (!/^\d+$/.test(String(value)) || !Number.isSafeInteger(n) || n < (zero ? 0 : 1) || n > 0xffffffff)
    throw new Error(`${name} must be ${zero ? 'a nonnegative' : 'a positive'} U32 integer.`)
  return n
}
function leaves(root: any, tag: string): any[] {
  const result = [], stack = [root]
  while (stack.length) {
    const node = stack.pop()
    if (node.$ === 'Branch') stack.push(node.right, node.left)
    else if (node.$ === tag) result.push(node)
  }
  return result
}
export async function compute(body: Record<string, unknown>, load: LoadEngine): Promise<{ name: string; data: any; ppm?: string }> {
  const demo = String(body.demo)
  const names = demo === 'raytracer' ? [body.scene === 'mirrors' ? 'ray' : 'path'] : demo === 'cubes' ? ['collisions', 'replay'] : [demo]
  const engines = await Promise.all(names.map(load)), start = performance.now()
  let data: any, ppm: string | undefined, name = demo
  if (demo === 'raytracer') {
    const scene = String(body.scene), width = integer(body.width, 'Width'), height = integer(body.height, 'Height')
    if (!['mirrors', 'materials', 'weekend'].includes(scene)) throw new Error('Unknown scene.')
    const bounces = integer(body.bounces, 'Bounces', true), seed = integer(body.seed, 'Seed', true)
    const samples = scene === 'mirrors' ? 4 : integer(body.samples, 'Samples')
    const pixels = new Uint32Array(width * height), engine = engines[0]
    for (let y = 0; y < height; y++) for (let x = 0; x < width; x++)
      pixels[y * width + x] = scene === 'mirrors' ? engine.pixel(x, y, width, height, BigInt(bounces)) : engine.pixel(x, y, width, height, BigInt(bounces), scene === 'weekend', seed, samples, seed)
    data = { width, height, bounces, scene, samples, seed }
    data.kernelMs = performance.now() - start
    const lines = [`P3\n${width} ${height}\n255`]
    for (const p of pixels) lines.push(`${p >>> 16 & 255} ${p >>> 8 & 255} ${p & 255}`)
    ppm = lines.join('\n') + '\n'
  } else if (demo === 'life') {
    const size = integer(body.size, 'Size'), steps = integer(body.steps, 'Generations', true), seed = integer(body.seed, 'Seed', true)
    const kind = ['random', 'glider', 'blinker'].indexOf(String(body.pattern))
    if (size < 32 || (size & (size - 1)) !== 0 || kind < 0) throw new Error('Life needs a power-of-two grid of at least 32 and a valid pattern.')
    const depth = BigInt(Math.log2(size * size / 32)), engine = engines[0], frames: number[][] = []
    let grid = engine.initial(depth, kind, size, seed, 0)
    for (let i = 0; i <= steps; i++) {
      frames.push(leaves(grid, 'Leaf').flatMap(g => [g.index, g.word]))
      if (i < steps) grid = engine.step(depth, size, grid)
    }
    data = { size, steps, seed, pattern: body.pattern, encoding: 'sparse-words', frames }
  } else if (demo === 'cubes') {
    const digits = integer(body.digits, 'Digits'), places = BigInt(digits - 1)
    const total = engines[0].count(places), r = engines[1]
    if (!Number.isSafeInteger(Number(total))) throw new Error('The collision count exceeds the precision of the animation counters.')
    const flatten = (tree: any) => leaves(tree, 'Frame').map(({ state }) => ({ ...state, count: Number(state.count) }))
    const frames = flatten(r.make(places, total)), motion = flatten(r.motion(total > 2048n, places, total))
    if ([...frames, ...motion].some(f => ['x', 'y', 'v', 'w', 'time', 'u'].some(k => !Number.isFinite(f[k]))))
      throw new Error('This request exceeds the current numerical precision.')
    const count = String(total)
    data = { digits, total: count, pi: count.length === 1 ? count : `${count[0]}.${count.slice(1)}`, sampled: frames.length !== Number(total) + 1, frames, motion }
  } else if (demo === 'probability') {
    const method = String(body.method), samples = integer(body.samples, 'Samples'), seed = integer(body.seed, 'Seed', true)
    if (!['montecarlo', 'buffon'].includes(method)) throw new Error('Unknown probability method.')
    const needle = method === 'buffon', inner = BigInt(Math.max(0, Math.ceil(Math.log2(Math.ceil(samples / 256) / 128))))
    const engine = engines[0], result = engine.run(8n, 0, samples, inner, needle, seed)
    if (engine.failures(result)) throw new Error('Orientation sampling exhausted its retry budget; try another seed.')
    const frames = (engine.text(result, 0, 0, needle) as string).trim().split('\n').map(line => {
      const [n, hits, estimate, ...points] = line.trim().split(/\s+/).map(Number)
      return { n, hits, estimate: Number.isFinite(estimate) ? estimate : null, points }
    }).filter((f, i, all) => f.n > 0 && (i === 0 || f.n !== all[i - 1].n))
    name = method
    data = { method, samples, seed, previewLimit: needle ? 512 : 2048, frames }
  } else throw new Error('Unknown experiment.')
  data.kernelMs ??= performance.now() - start
  return { name, data: { ...data, backend: 'Browser CPU · compiled Bend', createdAt: new Date().toISOString() }, ppm }
}
