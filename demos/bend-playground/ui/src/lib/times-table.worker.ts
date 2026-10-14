import { asset } from './runtime'
// The tiny Bend module is fetched once. Only packed coordinates cross to the UI.
interface Engine { chord: (i: number, n: number, multiplier: number) => { x: number; y: number; u: number; v: number } }
let engine: Promise<Engine> | undefined
self.onmessage = async (event: MessageEvent<{ id: number; n: number; multiplier: number }>) => {
  const { id, n, multiplier } = event.data
  try {
    engine ??= import(/* @vite-ignore */ asset('times-table-engine.js')).then(m => m.default as Engine)
    const bend = await engine, coordinates = new Float32Array(n * 4), start = performance.now()
    for (let i = 0; i < n; i++) {
      const c = bend.chord(i, n, multiplier)
      coordinates.set([c.x, c.y, c.u, c.v], i * 4)
    }
    self.postMessage({ id, coordinates, computeMs: performance.now() - start }, { transfer: [coordinates.buffer] })
  } catch (e) { self.postMessage({ id, error: (e as Error).message }) }
}
