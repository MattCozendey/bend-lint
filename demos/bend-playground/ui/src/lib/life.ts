import type { LifeOutput } from './types'

let pixels: ImageData | null = null
let words: Uint32Array | null = null
const DEAD: [number, number, number] = [24, 24, 27] // zinc-900
const ALIVE: [number, number, number] = [244, 244, 245] // zinc-100

export function paintLife(canvas: HTMLCanvasElement, life: LifeOutput, frame: number) {
  const size = life.size, scale = size <= 128 ? 4 : 1
  const ctx = canvas.getContext('2d')!
  if (canvas.width !== size * scale) canvas.width = canvas.height = size * scale
  ctx.fillStyle = `rgb(${DEAD.join(',')})`; ctx.fillRect(0, 0, canvas.width, canvas.height)
  ctx.fillStyle = `rgb(${ALIVE.join(',')})`
  let data: ArrayLike<number> = life.frames[frame]
  if (life.encoding === 'sparse-words') {
    if (words?.length !== size * size / 32) words = new Uint32Array(size * size / 32)
    words.fill(0)
    for (let i = 0; i < data.length; i += 2) words[data[i]] = data[i + 1]
    data = words
  }
  if (scale === 1) {
    if (pixels?.width !== size) pixels = ctx.createImageData(size, size)
    const p = pixels.data
    for (let i = 0; i < size * size; i++) {
      const alive = (data[i >>> 5] >>> (i & 31)) & 1, o = i * 4, c = alive ? ALIVE : DEAD
      p[o] = c[0]; p[o + 1] = c[1]; p[o + 2] = c[2]; p[o + 3] = 255
    }
    ctx.putImageData(pixels, 0, 0)
  } else {
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++)
      if ((data[y * size / 32 + (x >>> 5)] >>> (x & 31)) & 1) ctx.fillRect(x * scale, y * scale, scale - 1, scale - 1)
  }
}
