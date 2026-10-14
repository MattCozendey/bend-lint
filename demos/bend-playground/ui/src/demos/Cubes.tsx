import { useCallback, useEffect, useRef, useState } from 'react'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Empty, Field, Workspace } from '@/components/Workspace'
import { RunPanel } from '@/components/RunPanel'
import { Transport } from '@/components/Transport'
import { duration, nextTime } from '@/lib/cube-clock'
import { drawCubes, type DrawResult } from '@/lib/cubes-draw'
import type { CubesOutput } from '@/lib/types'
import { cn } from '@/lib/utils'

interface Props { data: CubesOutput | null; loading: boolean; error: string | null; reload: () => Promise<void>; active: boolean }
const fmt = (v: number) => Math.abs(v) >= 10000 ? v.toExponential(2) : v.toFixed(2)

export function Cubes({ data, loading, error, reload, active }: Props) {
  const canvas = useRef<HTMLCanvasElement>(null)
  const [cursor, setCursor] = useState(0)
  const [playing, setPlaying] = useState(false)
  const [speed, setSpeed] = useState('1')
  const [digits, setDigits] = useState('3')
  const [state, setState] = useState<DrawResult | null>(null)
  const synced = useRef(false)
  const total = data ? duration(data) : 1

  useEffect(() => { if (data && !synced.current) { synced.current = true; setDigits(String(data.digits)) } }, [data])
  useEffect(() => { setCursor(0); setPlaying(false) }, [data])
  useEffect(() => { if (!active) setPlaying(false) }, [active])

  const paint = useCallback(() => { if (canvas.current) setState(drawCubes(canvas.current, data, cursor)) }, [data, cursor])
  useEffect(paint, [paint])
  useEffect(() => {
    const el = canvas.current?.parentElement; if (!el) return
    const ro = new ResizeObserver(paint); ro.observe(el); return () => ro.disconnect()
  }, [paint])

  useEffect(() => {
    if (!playing || !data) return
    let raf = 0, last = performance.now()
    const tick = (now: number) => {
      const dt = Math.min(now - last, 100) / 1000 * Number(speed); last = now
      setCursor(c => { const next = Math.min(total, c + dt); if (next >= total) setPlaying(false); return next })
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [playing, data, speed, total])

  const play = () => { if (!data) return; if (playing) { setPlaying(false); return } if (cursor >= total) setCursor(0); setPlaying(true) }
  const note = data ? (data.sampled ? 'Physical-time motion sampled in Bend. The counter includes collisions too fast to see individually; slow playback to inspect the burst.' : 'Physical-time motion with every impact computed in Bend. Use slow motion or Step to inspect individual collisions.') + (data.digits > 12 ? ' Above 12 digits, numerical accuracy is unverified.' : '') : null

  return (
    <Workspace
      tag={data ? `${data.digits} digits · physical time` : 'Elastic collisions'}
      title="π cubes"
      description="Two blocks, a wall, and the digits of π. Every collision state is computed in Bend."
      above={data && (
        <div className="grid shrink-0 grid-cols-[1fr_auto] items-start gap-x-4 gap-y-1 border-b px-4 py-3 md:grid-cols-[auto_1fr_auto] md:items-end">
          <div>
            <div className="text-[11px] font-medium tracking-wide text-muted-foreground uppercase">Collisions</div>
            <div className="text-3xl font-semibold tabular-nums tracking-tight md:text-4xl">{state?.count.toLocaleString() ?? 0}</div>
            <div className="font-mono text-xs text-muted-foreground">of {Number(data.total).toLocaleString()}</div>
          </div>
          <div className={cn('col-span-2 font-mono text-xs tracking-wide uppercase md:col-span-1 md:pb-1', state?.impact ? 'text-foreground' : 'text-muted-foreground')}>{state?.event ?? 'Heavy block moves left'}</div>
          <div className="col-start-2 row-start-1 flex flex-col gap-1 text-right font-mono text-xs text-muted-foreground md:col-start-3 md:flex-row md:gap-4 md:pb-1">
            <span><i className="mr-1.5 inline-block size-2 rounded-xs bg-zinc-50 align-[-1px]" />small <b className="font-medium text-foreground tabular-nums">{fmt(state?.v ?? 0)}</b></span>
            <span><i className="mr-1.5 inline-block size-2 rounded-xs bg-zinc-500 align-[-1px]" />heavy <b className="font-medium text-foreground tabular-nums">{fmt(state?.w ?? -1)}</b></span>
          </div>
        </div>
      )}
      stage={
        <>
          <canvas ref={canvas} hidden={!data} className="absolute inset-0 block h-full w-full" aria-label={state ? `Collision ${state.count} of ${data?.total}. Simulation time ${cursor.toFixed(3)} seconds.` : 'Two colliding blocks and a wall'} />
          {!data && <Empty>{loading ? 'Loading saved output…' : error ?? 'No replay yet. Choose the digits of π and press Calculate.'}</Empty>}
        </>
      }
      footer={
        <div className="grid gap-2">
          <Transport label="cube collisions" playing={playing} onPlay={play} disabled={!data}
            onStep={() => { setPlaying(false); if (data) setCursor(c => nextTime(data, c)) }}
            onReset={() => { setPlaying(false); setCursor(0) }}
            value={cursor} max={total} step={0.0001} onScrub={v => { setPlaying(false); setCursor(v) }}
            readout={<span className="tabular-nums">{cursor.toFixed(2)} s</span>}
            extra={
              <Select value={speed} onValueChange={setSpeed}>
                <SelectTrigger size="sm" className="h-8 w-[88px] font-mono text-xs" aria-label="Playback speed"><SelectValue /></SelectTrigger>
                <SelectContent>{['0.01', '0.1', '0.25', '1', '2'].map(v => <SelectItem key={v} value={v}>{v}×</SelectItem>)}</SelectContent>
              </Select>
            } />
          {note && <p className="text-xs text-muted-foreground">{note}</p>}
        </div>
      }
      controls={
        <>
          <Field label="Digits of π" htmlFor="digits" hint={<>Heavy mass = 100<sup>digits − 1</sup> × small mass. Larger runs sample motion in physical time.</>}>
            <Input id="digits" type="number" min={1} step={1} value={digits} onChange={e => setDigits(e.target.value)} />
          </Field>
          <div className="rounded-lg border bg-background p-4">
            <div className="text-[11px] font-medium tracking-wide text-muted-foreground uppercase">From the complete count</div>
            <div className="mt-1 break-all font-mono text-2xl font-semibold tracking-tight">{data?.pi ?? '—'}</div>
            <div className="mt-1 font-mono text-xs text-muted-foreground">{data ? `${Number(data.total).toLocaleString()} collisions` : 'Generate a collision replay.'}</div>
          </div>
          <RunPanel demo="cubes" label="Calculate & animate" meta={data} after={reload} onBeforeRun={() => setPlaying(false)}
            body={() => ({ demo: 'cubes', digits })} />
        </>
      }
    />
  )
}
