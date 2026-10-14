import { useCallback, useEffect, useRef, useState } from 'react'
import { Field, Workspace, Stat, Empty } from '@/components/Workspace'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { useLab } from '@/lib/use-lab'
interface Genome { text: string; fitness: number }
interface Generation { generation: number; best: Genome; average: number; candidates: Genome[]; finished: boolean; targetLength: number; attempts: number; computeMs: number }
export function Shakespeare() {
  const { call, error, setError } = useLab(), [target, setTarget] = useState('To be or not to be!'), [population, setPopulation] = useState('200'), [mutation, setMutation] = useState('1'), [seed, setSeed] = useState('42'), [mode, setMode] = useState('evolution')
  const [config, setConfig] = useState({ target: 'To be or not to be!', population: 200, mutation: 100, seed: 42, mode: 'evolution' }), [run, setRun] = useState(0), [data, setData] = useState<Generation | null>(null), [playing, setPlaying] = useState(false), [busy, setBusy] = useState(false)
  const active = useRef(true), generationRun = useRef(0), inFlight = useRef(false), history = useRef<number[]>([])
  useEffect(() => { active.current = true; return () => { active.current = false } }, [])
  useEffect(() => { const token = ++generationRun.current; setPlaying(false); setData(null); history.current = []; call<Generation>({ action: 'shakespeare-init', ...config }).then(r => { if (active.current && generationRun.current === token) { setData(r); history.current.push(r.best.fitness / r.targetLength) } }).catch(() => {}); }, [call, config, run])
  const step = useCallback(async () => {
    if (inFlight.current) return
    const token = generationRun.current; inFlight.current = true; setBusy(true)
    try { const r = await call<Generation>({ action: 'shakespeare-step' }); if (active.current && token === generationRun.current) { setData(r); history.current = [...history.current.slice(-199), r.best.fitness / r.targetLength]; if (r.finished) setPlaying(false) } } catch { setPlaying(false) } finally { inFlight.current = false; if (active.current) setBusy(false) }
  }, [call])
  useEffect(() => {
    if (!playing || !data || data.finished) return
    let stopped = false, timer = 0
    const tick = async () => { await step(); if (!stopped) timer = window.setTimeout(tick, 50) }
    void tick(); return () => { stopped = true; clearTimeout(timer) }
    // One generation in flight, then yield. Changing a result doesn't restart the loop.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [playing, step])
  const renderPhrase = (g: Genome) => <span className="whitespace-pre-wrap break-all">{Array.from(g.text).map((c, i) => <span key={i} className={c === Array.from(config.target)[i] ? 'text-teal-300' : 'text-zinc-500'}>{c}</span>)}</span>
  const restart = () => { const p = Number(population), m = Number(mutation), s = Number(seed); if (!target.trim()) { setError('Enter a nonempty target phrase.'); return } if (!Number.isFinite(m) || m < 0 || m > 100 || !Number.isInteger(s) || s < 0 || s > 0xffffffff) { setError('Mutation must be 0–100%; seed must be an unsigned 32-bit integer.'); return } setError(null); setPlaying(false); setConfig({ target, population: p, mutation: Math.round(m * 100), seed: s, mode }); setRun(n => n + 1) }
  return <Workspace title="Shakespeare’s monkeys" tag="Live Bend · seeded evolution" description="Evolve random text toward a phrase, following your genetic-algorithm sketch. Compare it with independent random typing."
    stage={<div className="absolute inset-0 overflow-auto p-5 sm:p-8">{!data || error ? <Empty>{error ?? 'Creating a population in Bend…'}</Empty> : <div className="mx-auto grid max-w-4xl gap-6">
      <div><p className="mb-2 text-xs uppercase tracking-wide text-muted-foreground">Target</p><p className="break-words font-mono text-lg">{config.target}</p></div>
      <div className="rounded-xl border bg-background/80 p-5"><p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">Best so far · {(100 * data.best.fitness / data.targetLength).toFixed(1)}% {data.finished ? '· Matched!' : ''}</p><p className="font-mono text-2xl sm:text-3xl" data-testid="best-phrase">{renderPhrase(data.best)}</p></div>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3"><Stat label="Generation" value={data.generation.toLocaleString()} /><Stat label="Mean fitness" value={`${(100 * data.average / data.targetLength).toFixed(1)}%`} /><Stat label="Candidates evaluated" value={data.attempts.toLocaleString()} /></div>
      <div><p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">Current population · first 12 candidates</p><div className="grid gap-2 font-mono text-sm">{data.candidates.map((g, i) => <div key={i} className="flex justify-between gap-3 border-b border-zinc-800/50 pb-1">{renderPhrase(g)}<span className="shrink-0 text-muted-foreground">{g.fitness}/{data.targetLength}</span></div>)}</div></div>
    </div>}</div>}
    footer={<div className="flex flex-wrap items-center gap-2"><Button variant="secondary" disabled={!data || data.finished || !!error} onClick={() => setPlaying(!playing)}>{playing ? 'Pause evolution' : 'Run evolution'}</Button><Button variant="outline" disabled={!data || data.finished || busy || playing || !!error} onClick={() => void step()}>One generation</Button><span className="ml-auto text-xs text-muted-foreground">{data?.finished ? 'Target matched.' : config.mode === 'random' ? 'Independent random phrases; no selection.' : 'Correct letters stay; unmatched letters can mutate.'}</span></div>}
    controls={<><Field label="Target phrase" htmlFor="target"><Input id="target" value={target} onChange={e => setTarget(e.target.value)} /></Field>
      <Field label="Method"><Select value={mode} onValueChange={setMode}><SelectTrigger aria-label="Shakespeare method" className="w-full"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="evolution">Selection + crossover + mutation</SelectItem><SelectItem value="random">Independent random typing</SelectItem></SelectContent></Select></Field>
      <Field label="Population"><Select value={population} onValueChange={setPopulation}><SelectTrigger aria-label="Population size" className="w-full"><SelectValue /></SelectTrigger><SelectContent>{['100', '200', '500'].map(n => <SelectItem key={n} value={n}>{n}</SelectItem>)}</SelectContent></Select></Field>
      <Field label="Mutation probability (%)" htmlFor="mutation"><Input id="mutation" type="number" min={0} max={100} step={.1} value={mutation} onChange={e => setMutation(e.target.value)} disabled={mode === 'random'} /></Field>
      <Field label="Random seed" htmlFor="monkey-seed"><Input id="monkey-seed" type="number" min={0} value={seed} onChange={e => setSeed(e.target.value)} /></Field><Button variant="outline" onClick={restart}>Restart with settings</Button>
      <Stat label="Bend generation compute" value={data?.computeMs.toFixed(2)} unit="ms" />
      <p className="text-xs text-muted-foreground">Selection weights phrases by matching positions. Crossover preserves correct letters, mutation explores other letters, and the best candidate survives each generation. This guided search is not a demonstration of independent infinite-monkey typing.</p>
      <svg viewBox="0 0 300 80" role="img" aria-label="Best fitness over the last 200 generations"><polyline points={history.current.map((v, i) => `${i / Math.max(1, history.current.length - 1) * 300},${76 - v * 72}`).join(' ')} fill="none" stroke="#5eead4" strokeWidth="2" /></svg></>} />
}
