import { useEffect, useRef, useState } from 'react'
import { Workspace, Field, Stat, Empty } from '@/components/Workspace'
import { Transport } from '@/components/Transport'
import { Button } from '@/components/ui/button'
import { Slider } from '@/components/ui/slider'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { useLab } from '@/lib/use-lab'
import { surface, usePaint } from '@/lib/lab-canvas'
import drawingCsv from '../../../demos/fourier/drawing.csv?raw'

type Point = [number, number]
type Step = { cx: number; cy: number; radius: number; x: number; y: number }
function normalize(points: Point[]) {
  const xs = points.map(p => p[0]), ys = points.map(p => p[1]), x = (Math.min(...xs) + Math.max(...xs)) / 2, y = (Math.min(...ys) + Math.max(...ys)) / 2
  const scale = Math.max(Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys), 1e-6) / 2
  return points.map(p => [(p[0] - x) / scale, (p[1] - y) / scale] as Point)
}
// The p5 epicycle sketch applies a pi rotation to its saved coordinates.
const original = normalize(drawingCsv.trim().split('\n').map(row => row.split(',').map(Number) as Point)).map(([x, y]) => [-x, -y] as Point)
function resample(points: Point[]): Point[] {
  const closed = [...points, points[0]], distances = [0]
  for (let i = 1; i < closed.length; i++) distances.push(distances[i - 1] + Math.hypot(closed[i][0] - closed[i - 1][0], closed[i][1] - closed[i - 1][1]))
  const total = distances.at(-1)!; if (!total) return points
  let j = 1
  return normalize(Array.from({ length: 256 }, (_, i) => { const d = i * total / 256; while (j < closed.length - 1 && distances[j] < d) j++; const t = (d - distances[j - 1]) / (distances[j] - distances[j - 1] || 1); return [closed[j - 1][0] * (1 - t) + closed[j][0] * t, closed[j - 1][1] * (1 - t) + closed[j][1] * t] as Point }))
}
export function Fourier({ mode }: { mode: 'wave' | 'drawing' }) {
  const { call, error, setError } = useLab(), [points, setPoints] = useState<Point[]>(original)
  const [terms, setTerms] = useState(mode === 'wave' ? 5 : 50), [phase, setPhase] = useState(0), [playing, setPlaying] = useState(true), [speed, setSpeed] = useState('0.15')
  const [path, setPath] = useState<Float32Array | null>(null), [chain, setChain] = useState<Step[]>([]), [available, setAvailable] = useState(mode === 'wave' ? 64 : original.length), [compute, setCompute] = useState<number | null>(null)
  const [drawing, setDrawing] = useState(false), [ink, setInk] = useState<Point[]>([]), stroke = useRef<Point[] | null>(null)
  const appliedTerms = useRef<number | null>(null)
  const initialized = useRef(false), active = useRef(true), frameBusy = useRef(false), latestPhase = useRef(phase); latestPhase.current = phase
  useEffect(() => { active.current = true; return () => { active.current = false } }, [])
  useEffect(() => {
    let cancelled = false; initialized.current = false; setPath(null); setChain([])
    call<{ path: Float32Array; available: number; computeMs: number }>({ action: 'fourier-init', mode, points, terms }).then(r => { if (!cancelled) { initialized.current = true; appliedTerms.current = terms; setTerms(t => Math.min(t, r.available)); setPath(r.path); setAvailable(r.available); setCompute(r.computeMs); setPhase(0) } }).catch(() => {})
    return () => { cancelled = true }
    // Recompute DFT only for new input. Changing terms reuses coefficients below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [call, mode, points])
  useEffect(() => {
    if (!initialized.current || appliedTerms.current === terms) return
    appliedTerms.current = terms
    let cancelled = false
    call<{ path: Float32Array; computeMs: number }>({ action: 'fourier-terms', terms }).then(r => { if (!cancelled) { setPath(r.path); setCompute(r.computeMs) } }).catch(() => {})
    return () => { cancelled = true }
  }, [call, terms, !!path])
  useEffect(() => {
    if (!path || frameBusy.current) return
    frameBusy.current = true
    const update = async () => {
      try { let requested: number; do { requested = latestPhase.current; const r = await call<{ chain: Step[] }>({ action: 'fourier-frame', phase: requested }); if (active.current) setChain(r.chain) } while (active.current && requested !== latestPhase.current) }
      catch {} finally { frameBusy.current = false }
    }; void update()
  }, [call, path, phase])
  useEffect(() => {
    if (!playing || !path || drawing) return
    let raf = 0, before = performance.now(), value = phase
    const tick = (now: number) => { value = (value + Math.min(now - before, 100) / 1000 * Number(speed)) % 1; before = now; setPhase(value); raf = requestAnimationFrame(tick) }
    raf = requestAnimationFrame(tick); return () => cancelAnimationFrame(raf)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [playing, !!path, speed, drawing])
  const canvas = usePaint(cvs => {
    const { c, width, height } = surface(cvs), wave = mode === 'wave', scale = Math.min(wave ? width * .23 / Math.max(1, chain.reduce((sum, s) => sum + s.radius, 0)) : width * .4, height * .36), ox = wave ? width * .25 : width / 2, oy = height / 2
    if (drawing) {
      c.fillStyle = '#a1a1aa'; c.font = '14px sans-serif'; c.textAlign = 'center'; c.fillText('Draw a continuous outline. Release to build its epicycles.', width / 2, 30)
      c.strokeStyle = '#5eead4'; c.lineWidth = 2; c.beginPath(); ink.forEach(([x, y], i) => { if (!i) c.moveTo(x * width, y * height); else c.lineTo(x * width, y * height) }); c.stroke(); return
    }
    if (!path) return
    const trace = (full: boolean) => {
      c.beginPath(); const count = full ? 512 : Math.max(1, Math.floor(phase * 512))
      for (let i = 0; i <= count; i++) { const x = wave ? width * .57 + i / 512 * width * .39 : ox + path[i * 2] * scale, y = oy + path[i * 2 + 1] * scale; if (!i) c.moveTo(x, y); else c.lineTo(x, y) }
      c.stroke()
    }
    c.strokeStyle = '#3f3f46'; c.lineWidth = 1; trace(true)
    c.strokeStyle = '#5eead4'; c.lineWidth = 2; trace(false)
    for (const [i, s] of chain.entries()) {
      c.strokeStyle = `hsla(${175 + i * 7},70%,65%,.45)`; c.lineWidth = 1; c.beginPath(); c.arc(ox + s.cx * scale, oy + s.cy * scale, Math.abs(s.radius * scale), 0, Math.PI * 2); c.stroke()
      c.strokeStyle = '#d4d4d8'; c.beginPath(); c.moveTo(ox + s.cx * scale, oy + s.cy * scale); c.lineTo(ox + s.x * scale, oy + s.y * scale); c.stroke()
    }
    const end = chain.at(-1)
    if (end) { const x = ox + end.x * scale, y = oy + end.y * scale; c.fillStyle = '#fafafa'; c.beginPath(); c.arc(x, y, 3, 0, Math.PI * 2); c.fill(); if (wave) { c.setLineDash([4, 4]); c.strokeStyle = '#71717a'; c.beginPath(); c.moveTo(x, y); c.lineTo(width * .57 + phase * width * .39, y); c.stroke(); c.setLineDash([]) } }
  })
  const pos = (e: React.PointerEvent<HTMLCanvasElement>): Point => { const r = e.currentTarget.getBoundingClientRect(); return [(e.clientX - r.left) / r.width, (e.clientY - r.top) / r.height] }
  return <Workspace title={mode === 'wave' ? 'Fourier series' : 'Drawing with epicycles'} tag="Live Bend · Fourier" description={mode === 'wave' ? 'Add rotating odd harmonics to reconstruct a square wave, as in your original Fourier sketch.' : 'A complex discrete Fourier transform turns your original drawing—or a new sketch—into rotating circles.'}
    stage={<><canvas ref={canvas} className={`absolute inset-0 h-full w-full ${drawing ? 'touch-none cursor-crosshair' : ''}`} aria-label={mode === 'wave' ? 'Fourier circles and square wave' : 'Fourier epicycles tracing a drawing'}
      onPointerDown={e => { if (drawing) { e.currentTarget.setPointerCapture(e.pointerId); stroke.current = [pos(e)]; setInk(stroke.current) } }}
      onPointerMove={e => { if (stroke.current) { stroke.current.push(pos(e)); setInk([...stroke.current]) } }}
      onPointerUp={() => { const p = stroke.current; stroke.current = null; if (p && p.length >= 8) { setPoints(resample(p)); setDrawing(false); setPlaying(true); setError(null) } }} onPointerCancel={() => { stroke.current = null; setInk([]) }} />
      {!drawing && (!path || error) && <Empty>{error ?? 'Computing Fourier coefficients in Bend…'}</Empty>}</>}
    footer={<Transport label="Fourier phase" playing={playing} disabled={!path || drawing} value={phase} max={1} step={.001} onPlay={() => setPlaying(!playing)} onStep={() => { setPlaying(false); setPhase(p => (p + 1 / 512) % 1) }} onReset={() => { setPlaying(false); setPhase(0) }} onScrub={v => { setPlaying(false); setPhase(v) }} readout={`${(phase * 360).toFixed(1)}°`} />}
    controls={<><Field label={`Circles / terms · ${terms}`}><Slider value={[terms]} min={1} max={available} step={1} onValueChange={([v]) => setTerms(v)} aria-label="Fourier terms" /></Field>
      <Field label="Cycles per second"><Select value={speed} onValueChange={setSpeed}><SelectTrigger className="w-full" aria-label="Fourier speed"><SelectValue /></SelectTrigger><SelectContent>{['0.05', '0.15', '0.3', '0.6'].map(v => <SelectItem key={v} value={v}>{v}</SelectItem>)}</SelectContent></Select></Field>
      {mode === 'drawing' && <div className="grid gap-2"><Button variant="outline" onClick={() => { setPlaying(false); setDrawing(true); setInk([]) }}>Draw your own</Button><Button variant="outline" onClick={() => { setDrawing(false); setPoints([...original]); setPlaying(true) }}>Original p5 drawing</Button></div>}
      <Stat label="Bend prepare" value={compute?.toFixed(2)} unit="ms" />
      <p className="text-xs text-muted-foreground">{mode === 'wave' ? 'Amplitude 4/(πn), frequency n = 1, 3, 5… More terms sharpen the edges; the overshoot near a jump is the Gibbs phenomenon.' : `${points.length} input samples. Terms are ordered by amplitude; the full set reconstructs the sampled path. Drawn outlines are closed and resampled evenly.`}</p>
      <p className="text-xs text-muted-foreground">Bend computes coefficients, rotating vectors, and paths in a browser worker. Changing terms reuses the transform; no server requests or recompilation.</p></>} />
}
