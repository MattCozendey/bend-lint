import { useEffect, useMemo, useRef, useState } from 'react'
import { Field, Workspace, Stat, Empty } from '@/components/Workspace'
import { Transport } from '@/components/Transport'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { useLab } from '@/lib/use-lab'
import { surface, usePaint } from '@/lib/lab-canvas'
interface Trace { values: number[]; operations: Uint32Array; computeMs: number }
const algorithms = ['Quicksort', 'Merge sort', 'Bubble sort'], patterns = ['Random values', 'Reversed', 'Already sorted', 'Few distinct values']
const descriptions = ['Lomuto partition with the last element as pivot. Average O(n log n); sorted/reversed inputs expose its O(n²) worst case.', 'Split into halves, sort each, then merge from a read buffer. O(n log n), including already-sorted inputs.', 'Compare adjacent elements and swap inversions, shortening each pass. O(n²) comparisons in this version.']
export function Sorting() {
  const { call, error } = useLab(), [algorithm, setAlgorithm] = useState('0'), [size, setSize] = useState('128'), [pattern, setPattern] = useState('0'), [seed, setSeed] = useState('42'), [runSeed, setRunSeed] = useState(42)
  const [trace, setTrace] = useState<Trace | null>(null), [frame, setFrame] = useState(0), [playing, setPlaying] = useState(false), [speed, setSpeed] = useState('300')
  const progress = useRef({ at: 0, values: [] as number[], buffer: null as number[] | null, range: [0, 0], comparisons: 0, writes: 0, a: -1, b: -1, kind: -1 })
  useEffect(() => { let cancelled = false; setTrace(null); setPlaying(false); setFrame(0); call<Trace>({ action: 'sort', algorithm: Number(algorithm), size: Number(size), pattern: Number(pattern), seed: runSeed }).then(r => { if (!cancelled) { progress.current = { at: 0, values: [...r.values], buffer: null, range: [0, 0], comparisons: 0, writes: 0, a: -1, b: -1, kind: -1 }; setTrace(r) } }).catch(() => {}); return () => { cancelled = true } }, [call, algorithm, size, pattern, runSeed])
  const last = (trace?.operations.length ?? 0) / 3
  const view = useMemo(() => {
    const s = progress.current
    if (!trace) return s
    if (frame < s.at) Object.assign(s, { at: 0, values: [...trace.values], buffer: null, range: [0, 0], comparisons: 0, writes: 0, a: -1, b: -1, kind: -1 })
    while (s.at < frame) {
      const [kind, a, b] = trace.operations.subarray(s.at * 3, s.at * 3 + 3); s.kind = kind; s.a = a; s.b = b
      if (kind === 0) s.comparisons++
      else if (kind === 1) { [s.values[a], s.values[b]] = [s.values[b], s.values[a]]; s.writes += 2 }
      else if (kind === 2) { s.values[a] = b; s.writes++ }
      else if (kind === 3) { s.buffer = [...s.values]; s.range = [a, b] }
      s.at++
    }
    return { ...s }
  }, [trace, frame])
  useEffect(() => { if (!playing || !trace) return; let raf = 0, before = performance.now(), value = frame; const tick = (now: number) => { value = Math.min(last, value + Math.min(now - before, 100) / 1000 * Number(speed)); before = now; setFrame(Math.floor(value)); if (value < last) raf = requestAnimationFrame(tick); else setPlaying(false) }; raf = requestAnimationFrame(tick); return () => cancelAnimationFrame(raf) }, [playing, trace, speed, last])
  const canvas = usePaint(cvs => {
    const { c, width, height } = surface(cvs); if (!trace) return
    const max = Math.max(...trace.values), bar = (width - 32) / view.values.length, base = height - 26, mainHeight = height * (view.buffer ? .57 : .83)
    const bars = (values: number[], bottom: number, h: number, buffer: boolean) => {
      for (let i = 0; i < values.length; i++) { const highlighted = i === view.a || (i === view.b && view.kind !== 2); c.fillStyle = !buffer && frame === last ? '#5eead4' : highlighted ? view.kind === 0 ? '#fbbf24' : '#fb7185' : buffer ? '#52525b' : '#38bdf8'; if (buffer && (i < view.range[0] || i >= view.range[1])) c.globalAlpha = .2; c.fillRect(16 + i * bar, bottom - values[i] / max * h, Math.max(1, bar - 1), values[i] / max * h); c.globalAlpha = 1 }
    }
    if (view.buffer) { bars(view.buffer, height * .28, height * .21, true); c.fillStyle = '#a1a1aa'; c.font = '12px monospace'; c.fillText('Merge read buffer', 16, 20) }
    bars(view.values, base, mainHeight, false); c.fillStyle = '#a1a1aa'; c.font = '12px monospace'; c.fillText('Array', 16, height - 8)
  })
  const action = view.kind === 0 ? `Compare ${view.a} and ${view.b}` : view.kind === 1 ? `Swap ${view.a} ↔ ${view.b}` : view.kind === 2 ? `Write ${view.b} at ${view.a}` : view.kind === 3 ? `Copy run [${view.a}, ${view.b})` : 'Ready'
  return <Workspace title="Sorting visualizer" tag="Bend · actual algorithm events" description="Watch comparisons, swaps, and writes from quicksort, merge sort, and bubble sort on the same seeded input."
    above={<div className="grid grid-cols-3 gap-3 border-b p-3"><Stat label="Comparisons" value={view.comparisons.toLocaleString()} /><Stat label="Array writes" value={view.writes.toLocaleString()} /><Stat label="Bend prepare" value={trace?.computeMs.toFixed(1)} unit="ms" /></div>}
    stage={<><canvas ref={canvas} className="absolute inset-0 h-full w-full" aria-label="Sorting array bars and active operations" />{(!trace || error) && <Empty>{error ?? 'Running the sorting algorithm in Bend…'}</Empty>}</>}
    footer={<div className="grid gap-2"><Transport label="sorting operations" playing={playing} disabled={!trace} value={frame} max={Math.max(1, last)} onPlay={() => { if (frame >= last) setFrame(0); setPlaying(!playing) }} onStep={() => { setPlaying(false); setFrame(v => Math.min(last, v + 1)) }} onReset={() => { setPlaying(false); setFrame(0) }} onScrub={v => { setPlaying(false); setFrame(v) }} readout={`${frame.toLocaleString()} / ${last.toLocaleString()}`} /><p className="text-xs text-muted-foreground">{frame === last && trace ? 'Sorted.' : action} · <span className="text-amber-300">Compare</span> · <span className="text-rose-400">Swap / write</span></p></div>}
    controls={<>
      <Field label="Algorithm"><Select value={algorithm} onValueChange={setAlgorithm}><SelectTrigger aria-label="Sorting algorithm" className="w-full"><SelectValue /></SelectTrigger><SelectContent>{algorithms.map((a, i) => <SelectItem key={a} value={String(i)}>{a}</SelectItem>)}</SelectContent></Select></Field>
      <Field label="Input"><Select value={pattern} onValueChange={setPattern}><SelectTrigger aria-label="Sorting input" className="w-full"><SelectValue /></SelectTrigger><SelectContent>{patterns.map((p, i) => <SelectItem key={p} value={String(i)}>{p}</SelectItem>)}</SelectContent></Select></Field>
      <Field label="Bars"><Select value={size} onValueChange={setSize}><SelectTrigger aria-label="Sorting size" className="w-full"><SelectValue /></SelectTrigger><SelectContent>{['32', '64', '128', '256', '512'].map(n => <SelectItem key={n} value={n}>{n}</SelectItem>)}</SelectContent></Select></Field>
      <Field label="Operations per second"><Select value={speed} onValueChange={setSpeed}><SelectTrigger aria-label="Sorting speed" className="w-full"><SelectValue /></SelectTrigger><SelectContent>{['30', '100', '300', '1000', '5000'].map(n => <SelectItem key={n} value={n}>{n}</SelectItem>)}</SelectContent></Select></Field>
      <Field label="Random seed" htmlFor="sort-seed"><Input id="sort-seed" type="number" min={0} max={4294967295} value={seed} onChange={e => setSeed(e.target.value)} /></Field><Button variant="outline" onClick={() => { const n = Number(seed); if (Number.isInteger(n) && n >= 0 && n <= 0xffffffff) { setRunSeed(n); setPlaying(false); setFrame(0) } }}>Reset with seed</Button>
      <p className="text-sm text-muted-foreground">{descriptions[Number(algorithm)]}</p><p className="text-xs text-muted-foreground">Bend sorts in a browser worker and records compact operations. The viewer replays those operations; it does not implement the sorting algorithms. Merge comparisons read the displayed buffer.</p></>} />
}
