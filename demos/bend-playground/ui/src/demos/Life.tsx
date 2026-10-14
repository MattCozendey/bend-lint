import { useCallback, useEffect, useRef, useState } from 'react'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Empty, Field, Workspace } from '@/components/Workspace'
import { RunPanel } from '@/components/RunPanel'
import { Transport } from '@/components/Transport'
import { paintLife } from '@/lib/life'
import type { LifeOutput } from '@/lib/types'

interface Props { data: LifeOutput | null; loading: boolean; error: string | null; reload: () => Promise<void>; active: boolean }

export function Life({ data, loading, error, reload, active }: Props) {
  const canvas = useRef<HTMLCanvasElement>(null)
  const [frame, setFrame] = useState(0)
  const [playing, setPlaying] = useState(false)
  const [fps, setFps] = useState('24')
  const [pattern, setPattern] = useState('random')
  const [size, setSize] = useState('128')
  const [steps, setSteps] = useState('120')
  const [seed, setSeed] = useState('42')
  const synced = useRef(false)
  const last = data ? data.frames.length - 1 : 0

  useEffect(() => {
    if (!data || synced.current) return
    synced.current = true
    setPattern(data.pattern); setSize(String(data.size)); setSteps(String(data.steps)); setSeed(String(data.seed))
  }, [data])
  useEffect(() => { setFrame(0); setPlaying(false) }, [data])
  useEffect(() => { if (!active) setPlaying(false) }, [active])
  useEffect(() => { if (data && canvas.current) paintLife(canvas.current, data, frame) }, [data, frame])

  useEffect(() => {
    if (!playing || !data) return
    let raf = 0, lastTick = 0
    const tick = (now: number) => {
      if (now - lastTick >= 1000 / Number(fps)) {
        lastTick = now
        setFrame(f => { if (f >= last) { setPlaying(false); return f } return f + 1 })
      }
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [playing, data, fps, last])

  const play = useCallback(() => { if (!data) return; if (playing) { setPlaying(false); return } if (frame >= last) setFrame(0); setPlaying(true) }, [data, playing, frame, last])

  return (
    <Workspace
      tag={data ? `${data.size} × ${data.size} · B3 / S23` : 'B3 / S23 · toroidal grid'}
      title="Game of Life"
      description="Every cell follows the same rule. Patterns emerge from their neighbors."
      stage={
        <>
          <canvas ref={canvas} hidden={!data} className="absolute inset-0 m-auto max-h-full max-w-full object-contain p-4 [image-rendering:pixelated] drop-shadow-2xl" style={{ width: '100%', height: '100%' }} aria-label="Game of Life generation" />
          {!data && <Empty>{loading ? 'Loading saved output…' : error ?? 'No replay yet. Pick a pattern and press Generate.'}</Empty>}
        </>
      }
      footer={
        <Transport label="replay" playing={playing} onPlay={play} disabled={!data}
          onStep={() => { setPlaying(false); setFrame(f => Math.min(f + 1, last)) }}
          value={frame} max={Math.max(1, last)} onScrub={v => { setPlaying(false); setFrame(v) }}
          readout={<span className="tabular-nums">{frame} / {last}</span>}
          extra={
            <Select value={fps} onValueChange={setFps}>
              <SelectTrigger size="sm" className="h-8 w-[100px] font-mono text-xs" aria-label="Frames per second"><SelectValue /></SelectTrigger>
              <SelectContent>{['12', '24', '60'].map(v => <SelectItem key={v} value={v}>{v} fps</SelectItem>)}</SelectContent>
            </Select>
          } />
      }
      controls={
        <>
          <Field label="Starting pattern" htmlFor="pattern">
            <Select value={pattern} onValueChange={setPattern}>
              <SelectTrigger id="pattern" className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="random">Random soup</SelectItem>
                <SelectItem value="glider">Glider</SelectItem>
                <SelectItem value="blinker">Blinker</SelectItem>
              </SelectContent>
            </Select>
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Grid size" htmlFor="size">
              <Select value={size} onValueChange={setSize}>
                <SelectTrigger id="size" className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>{['64', '128', '256', '512'].map(v => <SelectItem key={v} value={v}>{v}</SelectItem>)}</SelectContent>
              </Select>
            </Field>
            <Field label="Generations" htmlFor="steps"><Input id="steps" type="number" min={0} value={steps} onChange={e => setSteps(e.target.value)} /></Field>
          </div>
          <Field label="Random seed" htmlFor="seed"><Input id="seed" type="number" min={0} value={seed} onChange={e => setSeed(e.target.value)} /></Field>
          <RunPanel demo="life" label="Generate replay" meta={data} after={reload} onBeforeRun={() => setPlaying(false)}
            body={() => ({ demo: 'life', size, steps, seed, pattern })} />
        </>
      }
    />
  )
}
