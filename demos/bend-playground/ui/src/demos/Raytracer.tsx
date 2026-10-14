import { rayPpmUrl } from '@/lib/api'
import { useEffect, useRef, useState } from 'react'
import { Download } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Empty, Field, Workspace } from '@/components/Workspace'
import { RunPanel } from '@/components/RunPanel'
import { decodePpm } from '@/lib/ppm'
import type { RayOutput } from '@/lib/types'

type Scene = 'mirrors' | 'materials' | 'weekend'
const SCENES: Record<Scene, string> = {
  mirrors: 'Four spheres, one checkerboard, and a ray for every sample.',
  materials: 'Matte, polished metal, and refracting glass under a bright sky.',
  weekend: 'Hundreds of seeded spheres. Matte colors, rough metals, glass, and depth of field.',
}

interface Props { data: RayOutput | null; loading: boolean; error: string | null; reload: () => Promise<void> }

export function Raytracer({ data, loading, error, reload }: Props) {
  const canvas = useRef<HTMLCanvasElement>(null)
  const [scene, setScene] = useState<Scene>('mirrors')
  const [resolution, setResolution] = useState('512,320')
  const [bounces, setBounces] = useState('3')
  const [samples, setSamples] = useState('16')
  const [seed, setSeed] = useState('42')
  const [pixelError, setPixelError] = useState<string | null>(null)
  const synced = useRef(false)

  useEffect(() => {
    if (!data || synced.current) return
    synced.current = true
    setScene(data.scene ?? 'mirrors'); setResolution(`${data.width},${data.height}`); setBounces(String(data.bounces))
    setSamples(String(data.samples ?? 16)); setSeed(String(data.seed ?? 42))
  }, [data])

  useEffect(() => {
    if (!data) return
    let cancelled = false
    setPixelError(null)
    fetch(rayPpmUrl()!, { cache: 'no-cache' })
      .then(async r => {
        if (!r.ok) throw new Error('RGB output is missing. Render the scene to generate a PPM file.')
        const pixels = decodePpm(await r.text())
        if (pixels.width !== data.width || pixels.height !== data.height) throw new Error('RGB output dimensions changed. Render the scene again.')
        if (cancelled || !canvas.current) return
        canvas.current.width = pixels.width; canvas.current.height = pixels.height
        canvas.current.getContext('2d')!.putImageData(new ImageData(pixels.rgba, pixels.width, pixels.height), 0, 0)
      })
      .catch(e => { if (!cancelled) setPixelError((e as Error).message) })
    return () => { cancelled = true }
  }, [data])

  const path = scene !== 'mirrors'
  return (
    <Workspace
      tag={data ? `${data.width} × ${data.height} · ${data.samples ?? 4} spp · PPM` : 'Ray tracer'}
      title="Ray tracer"
      description={SCENES[scene]}
      stage={
        <>
          <canvas ref={canvas} hidden={!data} className="absolute inset-0 m-auto max-h-full max-w-full object-contain p-4 [image-rendering:auto] drop-shadow-2xl" style={{ width: '100%', height: '100%' }} aria-label="Ray-traced scene drawn from Bend-computed RGB pixels" />
          {!data && <Empty>{loading ? 'Loading saved output…' : error ?? 'No render yet. Choose a scene and press Render.'}</Empty>}
          {pixelError && <Empty>{pixelError}</Empty>}
        </>
      }
      footer={
        <div className="flex items-center justify-between gap-4 text-xs text-muted-foreground">
          <span>{path ? 'Path tracing · matte / metal / glass · depth of field' : 'Analytic intersections · hard shadows · recursive reflections'}</span>
          <Button asChild size="sm" variant="ghost" disabled={!data}><a href={rayPpmUrl()} download="bend-raytracer.ppm"><Download />Save PPM</a></Button>
        </div>
      }
      controls={
        <>
          <Field label="Scene" htmlFor="scene">
            <Select value={scene} onValueChange={v => { setScene(v as Scene); setBounces(v === 'mirrors' ? '3' : '12'); setSamples('16') }}>
              <SelectTrigger id="scene" className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="mirrors">Original · mirrors & checkerboard</SelectItem>
                <SelectItem value="materials">Material study · matte, metal & glass</SelectItem>
                <SelectItem value="weekend">Weekend · field of spheres</SelectItem>
              </SelectContent>
            </Select>
          </Field>
          <Field label="Resolution" htmlFor="resolution">
            <Select value={resolution} onValueChange={setResolution}>
              <SelectTrigger id="resolution" className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="256,160">256 × 160 · quick</SelectItem>
                <SelectItem value="512,320">512 × 320</SelectItem>
                <SelectItem value="1024,640">1024 × 640</SelectItem>
              </SelectContent>
            </Select>
          </Field>
          <Field label="Maximum bounces" htmlFor="bounces"><Input id="bounces" type="number" min={0} step={1} value={bounces} onChange={e => setBounces(e.target.value)} /></Field>
          {path && (
            <div className="grid grid-cols-2 gap-3">
              <Field label="Samples / pixel" htmlFor="samples"><Input id="samples" type="number" min={1} step={1} value={samples} onChange={e => setSamples(e.target.value)} /></Field>
              <Field label="Random seed" htmlFor="ray-seed"><Input id="ray-seed" type="number" min={0} step={1} value={seed} onChange={e => setSeed(e.target.value)} /></Field>
              <p className="col-span-2 text-xs text-muted-foreground">More samples reduce grain; more bounces allow longer light paths. Start small, then increase quality.</p>
            </div>
          )}
          <RunPanel demo="raytracer" label="Render scene" meta={data} after={reload}
            body={() => { const [width, height] = resolution.split(',').map(Number); return { demo: 'raytracer', width, height, bounces, scene, samples, seed } }} />
        </>
      }
    />
  )
}
