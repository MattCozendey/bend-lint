import { useEffect, useRef, useState } from 'react'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Empty, Field, Stat, Workspace } from '@/components/Workspace'
import { Transport } from '@/components/Transport'

function paint(canvas: HTMLCanvasElement, coordinates: Float32Array) {
  const rect = canvas.getBoundingClientRect(), dpr = Math.min(devicePixelRatio || 1, 2)
  const width = Math.round(rect.width * dpr), height = Math.round(rect.height * dpr)
  if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height }
  const c = canvas.getContext('2d')!, x = rect.width / 2, y = rect.height / 2, r = Math.max(1, Math.min(x, y) - 26)
  c.setTransform(dpr, 0, 0, dpr, 0, 0); c.clearRect(0, 0, rect.width, rect.height)
  c.strokeStyle = '#52525b'; c.lineWidth = 1; c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2); c.stroke()
  const gradient = c.createLinearGradient(x - r, y - r, x + r, y + r)
  gradient.addColorStop(0, '#5eead4'); gradient.addColorStop(.5, '#38bdf8'); gradient.addColorStop(1, '#c084fc')
  c.strokeStyle = gradient; c.lineWidth = .65; c.globalAlpha = .38; c.beginPath()
  for (let i = 0; i < coordinates.length; i += 4) { c.moveTo(x + coordinates[i] * r, y + coordinates[i + 1] * r); c.lineTo(x + coordinates[i + 2] * r, y + coordinates[i + 3] * r) }
  c.stroke(); c.globalAlpha = 1
}
export function TimesTable() {
  const canvas = useRef<HTMLCanvasElement>(null), worker = useRef<Worker | null>(null)
  const [factor, setFactor] = useState(0), [points, setPoints] = useState('1024'), [speed, setSpeed] = useState('2'), [playing, setPlaying] = useState(false)
  const [ready, setReady] = useState(false), [compute, setCompute] = useState<number | null>(null), [error, setError] = useState<string | null>(null)
  const geometry = useRef(new Float32Array()), sequence = useRef(0), busy = useRef(false), requested = useRef('')
  const latest = useRef({ factor, points }); latest.current = { factor, points }
  const send = useRef<() => void>(() => {})
  useEffect(() => {
    const w = new Worker(new URL('../lib/times-table.worker.ts', import.meta.url), { type: 'module' }); worker.current = w
    send.current = () => {
      const { factor, points } = latest.current, key = `${factor}:${points}`
      if (busy.current || requested.current === key) return
      busy.current = true; requested.current = key; w.postMessage({ id: ++sequence.current, n: Number(points), multiplier: factor })
    }
    w.onmessage = event => {
      busy.current = false
      if (event.data.error) { setError(event.data.error); setPlaying(false); return }
      geometry.current = event.data.coordinates
      if (canvas.current) paint(canvas.current, geometry.current)
      setCompute(event.data.computeMs); setReady(true); send.current()
    }
    w.onerror = e => { busy.current = false; setError(e.message || 'Could not load Bend module.'); setPlaying(false) }
    const observer = new ResizeObserver(() => { if (canvas.current) paint(canvas.current, geometry.current) })
    if (canvas.current) observer.observe(canvas.current)
    send.current()
    return () => { w.terminate(); worker.current = null; observer.disconnect(); busy.current = false; requested.current = ''; send.current = () => {} }
  }, [])
  useEffect(() => send.current(), [factor, points])
  useEffect(() => {
    if (!playing || !ready) return
    let raf = 0, before = performance.now(), value = factor
    const tick = (now: number) => {
      value = Math.min(200, value + Math.min(now - before, 100) / 1000 * Number(speed)); before = now
      setFactor(value)
      if (value < 200) raf = requestAnimationFrame(tick); else setPlaying(false)
    }
    raf = requestAnimationFrame(tick); return () => cancelAnimationFrame(raf)
    // Animation continues from its current position when play/speed changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [playing, speed, ready])
  const jump = (n: number) => { setPlaying(false); setFactor(n) }
  return <Workspace title="Circle times table" tag="Live Bend · 0 → 200" description="Connect point i to multiplier × i around a circle. A cardioid emerges at ×2; larger multipliers make intricate patterns."
    above={<div className="flex items-center justify-between border-b px-4 py-3"><span className="font-mono text-2xl tabular-nums">× {factor.toFixed(2)}</span><span className="text-xs text-muted-foreground">{points} points · i → (i × {factor.toFixed(2)}) mod {points}</span></div>}
    stage={<><canvas ref={canvas} className="absolute inset-0 h-full w-full" aria-label="Animated circle multiplication chords calculated in Bend" />{(!ready || error) && <Empty>{error ?? 'Loading Bend geometry…'}</Empty>}</>}
    footer={<Transport label="multiplier" playing={playing} disabled={!ready || !!error} value={factor} max={200} step={.01} onPlay={() => { if (factor >= 200) setFactor(0); setPlaying(!playing) }} onStep={() => jump(Math.min(200, Math.floor(factor) + 1))} onReset={() => jump(0)} onScrub={jump} readout={`× ${factor.toFixed(2)} / 200`} />}
    controls={<>
      <Field label="Points on the circle" htmlFor="table-points"><Select value={points} onValueChange={setPoints}><SelectTrigger id="table-points" className="w-full"><SelectValue /></SelectTrigger><SelectContent>{['256', '512', '1024', '2048', '4096'].map(n => <SelectItem key={n} value={n}>{n}</SelectItem>)}</SelectContent></Select></Field>
      <Field label="Multipliers per second" htmlFor="table-speed"><Select value={speed} onValueChange={setSpeed}><SelectTrigger id="table-speed" className="w-full"><SelectValue /></SelectTrigger><SelectContent>{['0.25', '1', '2', '5', '10'].map(n => <SelectItem key={n} value={n}>{n} / second</SelectItem>)}</SelectContent></Select></Field>
      <div className="grid grid-cols-2 gap-2">{[[0, 'Start'], [1, 'Identity'], [2, 'Cardioid'], [3, 'Two lobes'], [10, '×10'], [200, '×200']].map(([n, label]) => <Button key={n} variant="outline" onClick={() => jump(Number(n))}>{label}</Button>)}</div>
      <Stat label="Bend compute / frame" value={compute?.toFixed(2)} unit="ms" />
      <p className="text-xs text-muted-foreground">Bend computes the chord endpoints live in a browser worker; canvas draws them. No server request or recompilation when the multiplier changes.</p>
      <p className="text-xs text-muted-foreground">At ×0 all chords meet at point 0. At ×1 each point connects to itself, leaving the circle. This visualizes modular multiplication; it does not estimate π.</p>
    </>} />
}
