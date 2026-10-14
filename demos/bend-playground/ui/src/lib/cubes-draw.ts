import { duration, stateAt, type CubeState } from './cube-clock'
import type { CubesOutput } from './types'

const extents = new WeakMap<CubesOutput, number>()
// Zinc palette: chrome stays neutral, the two bodies differ only in value.
const SMALL = '#fafafa', HEAVY = '#71717a', INK = '#09090b', LINE = '#3f3f46', LABEL = '#a1a1aa', FAINT = '#52525b'
const MONO = 'ui-monospace,"SF Mono",Menlo,Consolas,monospace'

function arrow(ctx: CanvasRenderingContext2D, x0: number, x1: number, y: number, color: string) {
  const dir = Math.sign(x1 - x0)
  ctx.strokeStyle = color; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(x0, y); ctx.lineTo(x1, y); ctx.stroke()
  ctx.fillStyle = color; ctx.beginPath(); ctx.moveTo(x1, y); ctx.lineTo(x1 - dir * 7, y - 4); ctx.lineTo(x1 - dir * 7, y + 4); ctx.closePath(); ctx.fill()
}
function block(ctx: CanvasRenderingContext2D, x: number, floor: number, size: number, color: string, label: string, velocity: number, font: number, ink: string) {
  const y = floor - size
  ctx.fillStyle = color; ctx.fillRect(x, y, size, size)
  ctx.strokeStyle = '#ffffff22'; ctx.lineWidth = 1; ctx.strokeRect(x + .5, y + .5, size - 1, size - 1)
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillStyle = ink; ctx.font = `600 ${font}px ${MONO}`
  ctx.fillText(label, x + size / 2, y + size / 2)
  if (Math.abs(velocity) > 1e-6) { const start = x + size / 2, len = Math.min(size * .9, 44); arrow(ctx, start, start + Math.sign(velocity) * len, y - 16, color) }
}

export function eventLabel(data: CubesOutput, s: CubeState, impact: boolean) {
  if (s.count === 0) return 'Heavy block moves left'
  if (s.count === Number(data.total)) return 'Complete · blocks move apart'
  if (impact) return s.wall ? 'Impact · small block / wall' : 'Impact · block / block'
  return 'Frictionless motion'
}

export interface DrawResult extends CubeState { impact: boolean; event: string }

export function drawCubes(canvas: HTMLCanvasElement, data: CubesOutput | null, time: number): DrawResult | null {
  const dpr = window.devicePixelRatio || 1
  const width = Math.max(1, canvas.clientWidth), fullHeight = Math.max(1, canvas.clientHeight)
  if (canvas.width !== Math.round(width * dpr) || canvas.height !== Math.round(fullHeight * dpr)) { canvas.width = Math.round(width * dpr); canvas.height = Math.round(fullHeight * dpr) }
  const ctx = canvas.getContext('2d')!
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  ctx.clearRect(0, 0, width, fullHeight)
  if (!data) return null
  const height = Math.min(fullHeight, Math.max(220, width * .55))
  ctx.translate(0, Math.round((fullHeight - height) / 2))

  const s = stateAt(data, time)
  let lo = 0, hi = data.frames.length
  while (lo + 1 < hi) { const mid = (lo + hi) >>> 1; if (data.frames[mid].count <= s.count) lo = mid; else hi = mid }
  const index = lo, impact = !s.sampled && s.count > 0 && time - s.eventTime < .06
  if (!extents.has(data)) extents.set(data, Math.max(6, stateAt(data, duration(data)).y, ...data.frames.map(f => f.y)))

  const narrow = width < 560, compact = height < 300
  const pad = narrow ? 16 : 32
  const plotR = compact || narrow ? Math.max(28, Math.min(width, height) * .13) : Math.max(40, Math.min(width * .09, height * .17))
  const plotCx = width - pad - plotR - 8, plotCy = pad + plotR + 14
  const floor = Math.round(height * (compact ? .76 : .74))
  const wall = pad + 18, trackRight = width - pad
  const small = Math.round(Math.max(28, Math.min(64, width * .055)))
  const heavy = data.digits === 1 ? small : Math.round(small * 1.75)
  const scale = (trackRight - wall - heavy - small - 12) / extents.get(data)!

  ctx.strokeStyle = LINE; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(wall, floor); ctx.lineTo(trackRight, floor); ctx.stroke()
  const wallTop = floor - heavy - 60
  ctx.strokeStyle = s.wall && impact ? SMALL : '#71717a'; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(wall, wallTop); ctx.lineTo(wall, floor); ctx.stroke()
  ctx.lineWidth = 1; ctx.strokeStyle = LINE
  for (let y = wallTop + 10; y < floor; y += 12) { ctx.beginPath(); ctx.moveTo(wall - 10, y + 8); ctx.lineTo(wall - 2, y); ctx.stroke() }
  for (let x = wall; x < trackRight; x += Math.max(24, scale)) { ctx.beginPath(); ctx.moveTo(x, floor); ctx.lineTo(x + 7, floor + 7); ctx.stroke() }

  const font = narrow ? 12 : 15
  block(ctx, wall + s.x * scale, floor, small, SMALL, '1', s.v, font, INK)
  const label = data.digits === 1 ? '1' : data.digits <= 3 ? String(100 ** (data.digits - 1)) : `10^${2 * (data.digits - 1)}`
  block(ctx, wall + s.y * scale + small, floor, heavy, HEAVY, label, s.w, font, '#fafafa')

  const cx = plotCx, cy = plotCy, r = plotR
  ctx.strokeStyle = LINE; ctx.lineWidth = 1; ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.moveTo(cx - r - 8, cy); ctx.lineTo(cx + r + 8, cy); ctx.moveTo(cx, cy - r - 8); ctx.lineTo(cx, cy + r + 8); ctx.stroke()
  ctx.strokeStyle = '#a1a1aa88'; ctx.lineWidth = 1.5; ctx.beginPath()
  const from = Math.max(0, index - 160)
  for (let j = from; j <= index; j++) { const f = data.frames[j], px = cx + f.w * r, py = cy - f.u * r; j === from ? ctx.moveTo(px, py) : ctx.lineTo(px, py) }
  ctx.stroke()
  ctx.fillStyle = SMALL; ctx.beginPath(); ctx.arc(cx + s.w * r, cy - s.u * r, 4.5, 0, Math.PI * 2); ctx.fill()
  ctx.textAlign = 'center'; ctx.textBaseline = 'alphabetic'; ctx.fillStyle = LABEL; ctx.font = `${narrow ? 9 : 10}px ${MONO}`
  ctx.fillText('VELOCITY SPACE', cx, cy - r - 16)
  if (!compact) ctx.fillText('heavy →', cx, cy + r + 24)

  ctx.textAlign = 'left'; ctx.fillStyle = FAINT; ctx.font = `${narrow ? 10 : 11}px ${MONO}`
  ctx.fillText(`t = ${time.toFixed(3)} s · block sizes are illustrative`, pad, height - pad * .6)

  return { ...s, impact, event: eventLabel(data, s, impact) }
}
