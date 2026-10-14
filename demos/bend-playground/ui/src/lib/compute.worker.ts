import { compute } from './browser-compute'
import { asset } from './runtime'
self.onmessage = async event => {
  try {
    const result = await compute(event.data, async name => (await import(/* @vite-ignore */ asset(`${name}-engine.js`))).default)
    self.postMessage({ result })
  } catch (error) { self.postMessage({ error: (error as Error).message }) }
}
