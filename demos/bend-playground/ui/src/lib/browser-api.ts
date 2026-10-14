const outputs = new Map<string, unknown>()
let active: { worker: Worker; reject: (error: Error) => void } | null = null
let ppmUrl: string | undefined
export const readBrowserOutput = <T>(name: string): T | null => (outputs.get(name) as T) ?? null
export const browserPpmUrl = () => ppmUrl
export function runBrowserDemo(body: Record<string, unknown>): Promise<string> {
  if (active) return Promise.reject(new Error('Another experiment is running.'))
  const start = performance.now()
  return new Promise((resolve, reject) => {
    const worker = new Worker(new URL('./compute.worker.ts', import.meta.url), { type: 'module' })
    active = { worker, reject }
    const finish = () => { worker.terminate(); active = null }
    worker.onerror = event => { finish(); reject(new Error(event.message || 'Browser worker failed.')) }
    worker.onmessage = ({ data }) => {
      finish()
      if (data.error) { reject(new Error(data.error)); return }
      const { name, data: output, ppm } = data.result
      output.wallMs = performance.now() - start
      if (ppm !== undefined) {
        if (ppmUrl) URL.revokeObjectURL(ppmUrl)
        ppmUrl = URL.createObjectURL(new Blob([ppm], { type: 'image/x-portable-pixmap' }))
      }
      outputs.set(name, output)
      resolve('Complete')
    }
    worker.postMessage(body)
  })
}
export function cancelBrowserDemo() {
  if (!active) return
  active.worker.terminate()
  active.reject(new Error('Computation cancelled.'))
  active = null
}
