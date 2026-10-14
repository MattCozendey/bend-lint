import { useEffect, useMemo, useRef, useState } from 'react'
import { Input } from '@/components/ui/input'
import { Empty, Field, Stat, Workspace } from '@/components/Workspace'
import { RunPanel } from '@/components/RunPanel'
import { Transport } from '@/components/Transport'
import { paintProbability } from '@/lib/probability-draw'
import type { ProbabilityOutput } from '@/lib/types'

interface Props { method: 'montecarlo' | 'buffon'; data: ProbabilityOutput | null; loading: boolean; error: string | null; reload: () => Promise<void> }
export function Probability({ method, data, loading, error, reload }: Props) {
  const needle = method === 'buffon', canvas = useRef<HTMLCanvasElement>(null)
  const [samples, setSamples] = useState(String(data?.samples ?? 1000000)), [seed, setSeed] = useState(String(data?.seed ?? 42))
  const [frame, setFrame] = useState(data?.frames.length ?? 0), [playing, setPlaying] = useState(false)
  const last = data?.frames.length ?? 0, current = data?.frames[frame - 1]
  const shown = useMemo(() => data?.frames.slice(0, frame).reduce((n, f) => n + f.points.length / 5, 0) ?? 0, [data, frame])
  const latest = useRef({ data, frame, needle }); latest.current = { data, frame, needle }
  useEffect(() => { if (data) { setSamples(String(data.samples)); setSeed(String(data.seed)); setFrame(data.frames.length) } }, [data])
  useEffect(() => {
    if (!canvas.current) return
    const redraw = () => { if (canvas.current) { const s = latest.current; paintProbability(canvas.current, s.data, s.frame, s.needle) } }
    const observer = new ResizeObserver(redraw); observer.observe(canvas.current); redraw()
    return () => observer.disconnect()
  }, [])
  useEffect(() => { if (canvas.current) paintProbability(canvas.current, data, frame, needle) }, [data, frame, needle])
  useEffect(() => {
    if (!playing || !last) return
    let raf = 0, before = performance.now(), position = frame
    const tick = (now: number) => {
      position = Math.min(last, position + (now - before) * last / 8000); before = now
      setFrame(Math.floor(position))
      if (position < last) raf = requestAnimationFrame(tick); else setPlaying(false)
    }
    raf = requestAnimationFrame(tick); return () => cancelAnimationFrame(raf)
    // Capture the start position; scrubbing pauses playback.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [playing, last])
  const estimates = data?.frames.slice(0, frame).filter(f => f.estimate !== null) ?? []
  const chart = estimates.map(f => `${8 + f.n / (data?.samples ?? 1) * 284},${76 - Math.max(2.5, Math.min(3.8, f.estimate!)) / 1.3 * 64 + 2.5 / 1.3 * 64}`).join(' ')
  return <Workspace title={needle ? 'Buffon’s needle' : 'Monte Carlo π'} tag="Bend · random sampling"
    description={needle ? 'Drop toothpicks on a wooden floor. Count those crossing a seam between planks.' : 'Scatter points uniformly into a square of side 2r. Count the points inside its inscribed circle.'}
    above={<div className="grid grid-cols-3 gap-3 border-b p-3 [&_.tabular-nums]:break-all [&_.tabular-nums]:text-base sm:[&_.tabular-nums]:text-2xl">
      <Stat label="π estimate" value={current?.estimate?.toFixed(6)} />
      <Stat label={needle ? 'Crossing needles' : 'Inside circle'} value={(current?.hits ?? 0).toLocaleString()} />
      <Stat label={needle ? 'Needles dropped' : 'Points sampled'} value={(current?.n ?? 0).toLocaleString()} />
    </div>}
    stage={<><canvas ref={canvas} className="absolute inset-0 h-full w-full" aria-label={needle ? 'Bend-computed toothpicks on parallel planks' : 'Bend-computed points in a square and circle'} />{loading && <Empty>Loading samples…</Empty>}{error && <Empty>{error}</Empty>}</>}
    footer={<div className="grid gap-3"><Transport label="sampling replay" playing={playing} disabled={!data} value={frame} max={Math.max(1, last)}
      onPlay={() => { if (frame >= last) setFrame(0); setPlaying(!playing) }} onStep={() => { setPlaying(false); setFrame(f => Math.min(f + 1, last)) }} onReset={() => { setPlaying(false); setFrame(0) }} onScrub={v => { setPlaying(false); setFrame(v) }} readout={`${current?.n.toLocaleString() ?? 0} / ${data?.samples.toLocaleString() ?? 0}`} />
      <p className="text-xs text-muted-foreground"><span className="text-teal-300">● {needle ? 'Crosses a seam' : 'Inside'}</span> · <span className="text-rose-400">● {needle ? 'Within one plank' : 'Outside'}</span> · Showing {shown.toLocaleString()} actual samples; the estimate counts all {(current?.n ?? 0).toLocaleString()}.</p>
    </div>}
    controls={<>
      <div className="rounded-lg border bg-background p-4"><p className="font-mono text-lg">{needle ? 'π ≈ 2 × drops / crossings' : 'π ≈ 4 × inside / total'}</p><p className="mt-2 text-xs text-muted-foreground">{needle ? 'Needle length equals plank spacing. Orientations are uniform; Bend samples them without a π constant.' : 'Circle area / square area = πr² / (2r)² = π/4.'} Random estimates fluctuate; more samples improve typical accuracy.</p>{needle && current?.hits === 0 && <p className="mt-2 text-xs text-muted-foreground">No crossings yet. Drop more toothpicks for an estimate.</p>}</div>
      <Field label={needle ? 'Number of toothpicks' : 'Number of points'} htmlFor="pi-samples"><Input id="pi-samples" type="number" min={1} step={1} value={samples} onChange={e => setSamples(e.target.value)} /></Field>
      <Field label="Random seed" htmlFor="pi-seed"><Input id="pi-seed" type="number" min={0} step={1} value={seed} onChange={e => setSeed(e.target.value)} /></Field>
      <RunPanel demo={method} label={needle ? 'Drop toothpicks' : 'Scatter points'} meta={data} after={reload} onBeforeRun={() => setPlaying(false)} body={() => ({ demo: 'probability', method, samples, seed })} />
      {data && <div><p className="text-xs text-muted-foreground">Convergence · dashed line is π; chart range 2.5–3.8</p><svg viewBox="0 0 300 88" className="mt-2 w-full" role="img" aria-label="Pi estimate as sample count increases"><line x1="8" y1={76 - (Math.PI - 2.5) / 1.3 * 64} x2="292" y2={76 - (Math.PI - 2.5) / 1.3 * 64} stroke="#71717a" strokeDasharray="4 4" /><polyline points={chart} fill="none" stroke="#5eead4" strokeWidth="1.5" /></svg><p className="text-xs text-muted-foreground">Absolute error: {current?.estimate == null ? '—' : Math.abs(current.estimate - Math.PI).toPrecision(3)}</p></div>}
    </>} />
}
