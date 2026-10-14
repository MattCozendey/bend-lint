import { useEffect, useState } from 'react'
import { Field, Workspace, Stat, Empty } from '@/components/Workspace'
import { Transport } from '@/components/Transport'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Slider } from '@/components/ui/slider'
import { useLab } from '@/lib/use-lab'
import { surface, usePaint } from '@/lib/lab-canvas'
const curves = ['Heart', 'Quadratic spiral', 'Rose', 'Cardioid', 'Archimedean spiral']
const formulas = ['x = 16 sin³ θ; y = −(13 cos θ − 5 cos 2θ − 2 cos 3θ − cos 4θ)', 'r ∝ θ²', 'r = cos(kθ)', 'r = 1 − cos θ', 'r ∝ θ']
export function Polar() {
  const { call, error } = useLab(), [kind, setKind] = useState('0'), [petals, setPetals] = useState(5), [turns, setTurns] = useState(3)
  const [path, setPath] = useState<Float32Array | null>(null), [phase, setPhase] = useState(0), [playing, setPlaying] = useState(true), [compute, setCompute] = useState<number | null>(null)
  useEffect(() => { let cancelled = false; call<{ path: Float32Array; computeMs: number }>({ action: 'polar', kind: Number(kind), petals, turns }).then(r => { if (!cancelled) { setPath(r.path); setCompute(r.computeMs); setPhase(0) } }).catch(() => {}); return () => { cancelled = true } }, [call, kind, petals, turns])
  useEffect(() => { if (!playing || !path) return; let raf = 0, before = performance.now(), value = phase; const tick = (now: number) => { value = Math.min(1, value + Math.min(now - before, 100) / 6000); before = now; setPhase(value); if (value < 1) raf = requestAnimationFrame(tick); else setPlaying(false) }; raf = requestAnimationFrame(tick); return () => cancelAnimationFrame(raf) }, [playing, path])
  const canvas = usePaint(cvs => { const { c, width, height } = surface(cvs), r = Math.min(width, height) * .4, x = width / 2, y = height / 2; c.strokeStyle = '#27272a'; c.beginPath(); c.moveTo(x - r * 1.1, y); c.lineTo(x + r * 1.1, y); c.moveTo(x, y - r * 1.1); c.lineTo(x, y + r * 1.1); c.stroke(); if (!path) return; const count = Math.floor(phase * 2048); for (const full of [true, false]) { c.strokeStyle = full ? '#3f3f46' : '#5eead4'; c.lineWidth = full ? 1 : 2; c.beginPath(); for (let i = 0; i <= (full ? 2048 : count); i++) { const a = x + path[i * 2] * r, b = y + path[i * 2 + 1] * r; if (!i) c.moveTo(a, b); else c.lineTo(a, b) } c.stroke() } c.strokeStyle = '#c084fc'; c.beginPath(); c.moveTo(x, y); c.lineTo(x + path[count * 2] * r, y + path[count * 2 + 1] * r); c.stroke(); c.fillStyle = '#fafafa'; c.beginPath(); c.arc(x + path[count * 2] * r, y + path[count * 2 + 1] * r, 4, 0, Math.PI * 2); c.fill() })
  return <Workspace title="Polar curves" tag="Bend · parametric geometry" description="Trace the heart and spiral from your sketch, plus roses, a cardioid, and a linear spiral."
    stage={<><canvas ref={canvas} className="absolute inset-0 h-full w-full" aria-label="Bend-computed polar curve" />{(!path || error) && <Empty>{error ?? 'Computing curve…'}</Empty>}</>}
    footer={<Transport label="curve progress" playing={playing} disabled={!path} value={phase} max={1} step={.001} onPlay={() => { if (phase >= 1) setPhase(0); setPlaying(!playing) }} onStep={() => { setPlaying(false); setPhase(p => Math.min(1, p + .01)) }} onReset={() => { setPlaying(false); setPhase(0) }} onScrub={v => { setPlaying(false); setPhase(v) }} readout={`${(phase * 100).toFixed(0)}%`} />}
    controls={<><Field label="Curve"><Select value={kind} onValueChange={v => { setKind(v); setPlaying(true) }}><SelectTrigger className="w-full" aria-label="Curve"><SelectValue /></SelectTrigger><SelectContent>{curves.map((name, i) => <SelectItem key={name} value={String(i)}>{name}</SelectItem>)}</SelectContent></Select></Field>
      {kind === '2' && <Field label={`Rose frequency k · ${petals}`}><Slider value={[petals]} min={1} max={12} step={1} onValueChange={([v]) => setPetals(v)} aria-label="Rose frequency" /></Field>}
      {(kind === '1' || kind === '4') && <Field label={`Spiral turns · ${turns}`}><Slider value={[turns]} min={1} max={10} step={.25} onValueChange={([v]) => setTurns(v)} aria-label="Spiral turns" /></Field>}
      <p className="rounded-lg border p-4 font-mono text-sm">{formulas[Number(kind)]}</p><Stat label="Bend curve compute" value={compute?.toFixed(2)} unit="ms" />
      <p className="text-xs text-muted-foreground">Bend computes 2,049 points when settings change. Playback only reveals those coordinates.</p><p className="text-xs text-muted-foreground">The original sketch labels its θ² spiral “Archimedean”; here it is named quadratic. The heart uses parametric x/y equations.</p></>} />
}
