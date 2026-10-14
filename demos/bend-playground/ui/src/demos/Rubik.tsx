import { useEffect, useRef, useState } from 'react'
import { Pause, Play, RotateCcw, Shuffle, Undo2 } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Separator } from '@/components/ui/separator'
import { Empty, Field, Workspace } from '@/components/Workspace'
import { createRubik, FACE_COLORS, FACES, loadCube, moveName, type RubikEngine, type RubikStatus } from '@/lib/rubik-engine'

export function Rubik({ active }: { active: boolean }) {
  const cubeSvg = useRef<SVGSVGElement>(null), graphSvg = useRef<SVGSVGElement>(null), history = useRef<HTMLDivElement>(null)
  const engine = useRef<RubikEngine | null>(null)
  const [status, setStatus] = useState<RubikStatus | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [speed, setSpeed] = useState('450')
  const [length, setLength] = useState('20')

  useEffect(() => {
    let disposed = false
    loadCube().then(Cube => {
      if (disposed || !cubeSvg.current || !graphSvg.current) return
      engine.current = createRubik(Cube, cubeSvg.current, graphSvg.current, setStatus)
      engine.current.setActive(active)
    }).catch(e => setError((e as Error).message))
    return () => { disposed = true; engine.current?.destroy(); engine.current = null }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  useEffect(() => { engine.current?.setActive(active) }, [active])
  useEffect(() => { engine.current?.setSpeed(Number(speed)) }, [speed])
  useEffect(() => { if (history.current) history.current.scrollTop = history.current.scrollHeight }, [status?.history.length])

  const busy = !!status?.busy
  return (
    <Workspace
      tag="Live · 54 stickers"
      title="Rubik graph"
      description="Every move updates the cube and the sticker graph together. The engine is Bend compiled to JavaScript and runs in your browser."
      stageClassName="h-[80dvh] lg:h-auto"
      stage={
        <>
          <div className="grid h-full w-full grid-rows-2 md:grid-cols-2 md:grid-rows-1">
            <div className="relative min-h-0 border-b md:border-r md:border-b-0">
              <span className="absolute top-3 left-4 font-mono text-[11px] tracking-wide text-muted-foreground uppercase">3 × 3 cube</span>
              <svg ref={cubeSvg} viewBox="0 0 500 500" className="h-full w-full cursor-grab touch-none active:cursor-grabbing" role="img" aria-label="Interactive 3D Rubik's cube; drag to rotate the view" />
              <span className="absolute bottom-3 left-4 font-mono text-[11px] text-muted-foreground">Drag to orbit · keys U R F D L B · Shift for inverse</span>
            </div>
            <div className="relative min-h-0">
              <span className="absolute top-3 left-4 font-mono text-[11px] tracking-wide text-muted-foreground uppercase">54 sticker positions</span>
              <svg ref={graphSvg} viewBox="0 0 500 500" className="h-full w-full" role="group" aria-label="Cube sticker positions and face-turn connections" />
            </div>
          </div>
          {error && <Empty>{error}</Empty>}
          {!status && !error && <Empty>Loading the Bend cube engine…</Empty>}
        </>
      }
      footer={
        <div className="flex flex-wrap items-center gap-2">
          <Button size="sm" variant="secondary" disabled={!busy} onClick={() => engine.current?.togglePause()}>{status?.paused ? <Play /> : <Pause />}{status?.paused ? 'Resume' : 'Pause'}</Button>
          <Button size="sm" variant="outline" disabled={!status?.history.length || busy} onClick={() => engine.current?.undo()}><Undo2 />Undo move</Button>
          <Button size="sm" variant="outline" disabled={!status} onClick={() => engine.current?.reset()}><RotateCcw />Reset cube</Button>
          <span className="ml-auto text-xs text-muted-foreground">Each dot is a sticker position; lines show where face turns move it.</span>
        </div>
      }
      controls={
        <>
          <div className="flex items-center justify-between">
            <div className="text-base font-medium">{status ? status.animating ? `${status.animating} · ${status.paused ? 'paused' : 'turning'}` : status.solved ? 'Solved' : 'Scrambled' : 'Loading…'}</div>
            <Badge variant={status?.solved ? 'default' : 'secondary'}>{status?.history.length ?? 0} moves</Badge>
          </div>
          <div className="grid gap-2">
            <div className="text-sm font-medium">Face turns</div>
            <div className="grid grid-cols-3 gap-1.5" aria-label="Face turns">
              {FACES.map((face, f) => [0, 1, 2].map(turn => (
                <Button key={face + turn} size="sm" variant="outline" className="font-mono" style={{ borderLeftColor: FACE_COLORS[f], borderLeftWidth: 3 }}
                  aria-label={`Turn ${face} ${turn === 0 ? 'clockwise' : turn === 1 ? '180 degrees' : 'counterclockwise'}`}
                  disabled={!status} onMouseEnter={() => engine.current?.preview(f)} onFocus={() => engine.current?.preview(f)} onClick={() => engine.current?.enqueue([f * 3 + turn])}>
                  {moveName(f * 3 + turn)}
                </Button>
              )))}
            </div>
          </div>
          <Field label="Turn duration" htmlFor="rubik-speed">
            <Select value={speed} onValueChange={setSpeed}>
              <SelectTrigger id="rubik-speed" className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="150">Fast · 0.15 s</SelectItem>
                <SelectItem value="450">Normal · 0.45 s</SelectItem>
                <SelectItem value="1000">Slow · 1 s</SelectItem>
              </SelectContent>
            </Select>
          </Field>
          <div className="grid grid-cols-[1fr_auto] items-end gap-2">
            <Field label="Scramble moves" htmlFor="rubik-length"><Input id="rubik-length" type="number" min={1} step={1} value={length} onChange={e => setLength(e.target.value)} /></Field>
            <Button variant="secondary" disabled={!status || busy} onClick={() => { const n = Number(length); if (Number.isSafeInteger(n) && n >= 1) engine.current?.scramble(n) }}><Shuffle />Scramble</Button>
          </div>
          <Button size="lg" disabled={!status?.history.length || busy} onClick={() => engine.current?.unwind()}><Undo2 />Undo all</Button>
          <Separator />
          <div className="grid gap-2">
            <div className="text-sm font-medium">Move history</div>
            <div ref={history} aria-live="polite" className="max-h-24 overflow-auto rounded-md border bg-background p-2 font-mono text-xs leading-relaxed break-words text-muted-foreground">{status?.history.map(moveName).join(' ') || '—'}</div>
            <p className="text-xs text-muted-foreground">Bend move: {(status?.lastMs ?? 0).toFixed(2)} ms · runs locally in your browser</p>
          </div>
        </>
      }
    />
  )
}
