import type { ProbabilityOutput } from './types'

export function paintProbability(canvas: HTMLCanvasElement, data: ProbabilityOutput | null, frame: number, needle: boolean) {
  const rect = canvas.getBoundingClientRect(), dpr = Math.min(devicePixelRatio || 1, 2)
  const w = Math.round(rect.width * dpr), h = Math.round(rect.height * dpr)
  if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h }
  const c = canvas.getContext('2d')!
  c.setTransform(dpr, 0, 0, dpr, 0, 0)
  const width = rect.width, height = rect.height, size = Math.max(1, Math.min(width - 64, height - 70)), x = (width - size) / 2, y = (height - size) / 2
  c.clearRect(0, 0, width, height)
  c.lineWidth = 1; c.strokeStyle = '#52525b'
  if (needle) {
    for (let i = 0; i < 8; i++) { c.fillStyle = i % 2 ? '#30241c' : '#251c16'; c.fillRect(x + i * size / 8, y, size / 8, size) }
    for (let i = 0; i <= 8; i++) { c.beginPath(); c.moveTo(x + i * size / 8, y); c.lineTo(x + i * size / 8, y + size); c.stroke() }
  } else {
    c.fillStyle = '#18181b'; c.fillRect(x, y, size, size); c.strokeRect(x, y, size, size)
    c.beginPath(); c.arc(x + size / 2, y + size / 2, size / 2, 0, Math.PI * 2); c.fillStyle = '#102723'; c.fill(); c.strokeStyle = '#5eead4'; c.stroke()
  }
  // Every visible sample is an actual Bend-computed sample, including its hit flag.
  c.save(); c.beginPath(); c.rect(x, y, size, size); c.clip()
  for (const f of data?.frames.slice(0, frame) ?? []) {
    for (let i = 0; i < f.points.length; i += 5) {
      const [a, b, dx, dy, hit] = f.points.slice(i, i + 5)
      c.strokeStyle = c.fillStyle = hit ? '#5eead4' : '#fb7185'
      if (needle) {
        c.globalAlpha = .75; c.lineWidth = 1.3
        c.beginPath(); c.moveTo(x + (a - dx / 2) * size / 8, y + (b - dy / 2) * size / 8); c.lineTo(x + (a + dx / 2) * size / 8, y + (b + dy / 2) * size / 8); c.stroke()
      } else { c.globalAlpha = .85; c.fillRect(x + (a + 1) * size / 2 - 1.3, y + (b + 1) * size / 2 - 1.3, 2.6, 2.6) }
    }
  }
  c.restore(); c.globalAlpha = 1
  c.font = '12px ui-monospace, monospace'; c.textAlign = 'center'; c.fillStyle = '#a1a1aa'
  c.fillText(needle ? 'Toothpick length = plank width = 1' : 'Radius r = 1 · square side 2r = 2', width / 2, y + size + 26)
}
