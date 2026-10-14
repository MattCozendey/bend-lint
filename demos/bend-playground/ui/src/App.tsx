import { useCallback, useEffect, useState } from 'react'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { TooltipProvider } from '@/components/ui/tooltip'
import { JobProvider } from '@/components/RunPanel'
import { Raytracer } from '@/demos/Raytracer'
import { Life } from '@/demos/Life'
import { Cubes } from '@/demos/Cubes'
import { Rubik } from '@/demos/Rubik'
import { Probability } from '@/demos/Probability'
import { TimesTable } from '@/demos/TimesTable'
import { Fourier } from '@/demos/Fourier'
import { Sorting } from '@/demos/Sorting'
import { Shakespeare } from '@/demos/Shakespeare'
import { Polar } from '@/demos/Polar'
import { readOutput } from '@/lib/api'
import { DEMOS, type CubesOutput, type DemoName, type LifeOutput, type RayOutput, type ProbabilityOutput } from '@/lib/types'

const TABS: { id: DemoName; label: string }[] = [
  { id: 'raytracer', label: 'Ray tracer' }, { id: 'life', label: 'Game of Life' }, { id: 'cubes', label: 'π cubes' }, { id: 'rubik', label: 'Rubik graph' },
  { id: 'montecarlo', label: 'Monte Carlo π' }, { id: 'buffon', label: 'Buffon’s needle' }, { id: 'times-table', label: 'Times table' },
  { id: 'fourier', label: 'Fourier' }, { id: 'epicycles', label: 'Epicycles' }, { id: 'shakespeare', label: 'Shakespeare' }, { id: 'sorting', label: 'Sorting' }, { id: 'polar', label: 'Polar curves' },
]
const fromHash = (): DemoName => { const h = location.hash.slice(1) as DemoName; return DEMOS.includes(h) ? h : 'raytracer' }

interface Slot<T> { data: T | null; loading: boolean; error: string | null; loaded: boolean }
const empty = { data: null, loading: false, error: null, loaded: false }

export default function App() {
  const [demo, setDemo] = useState<DemoName>(fromHash)
  const [ray, setRay] = useState<Slot<RayOutput>>(empty)
  const [life, setLife] = useState<Slot<LifeOutput>>(empty)
  const [cubes, setCubes] = useState<Slot<CubesOutput>>(empty)

  const [montecarlo, setMontecarlo] = useState<Slot<ProbabilityOutput>>(empty)
  const [buffon, setBuffon] = useState<Slot<ProbabilityOutput>>(empty)

  useEffect(() => { const h = () => setDemo(fromHash()); addEventListener('hashchange', h); return () => removeEventListener('hashchange', h) }, [])

  const load = useCallback(async <T,>(name: string, set: (f: (s: Slot<T>) => Slot<T>) => void) => {
    set(s => ({ ...s, loading: true, error: null }))
    try { const data = await readOutput<T>(name); set(() => ({ data, loading: false, error: null, loaded: true })) }
    catch (e) { set(s => ({ ...s, loading: false, error: (e as Error).message, loaded: true })) }
  }, [])
  const reloadRay = useCallback(() => load<RayOutput>('raytracer', setRay), [load])
  const reloadLife = useCallback(() => load<LifeOutput>('life', setLife), [load])
  const reloadCubes = useCallback(() => load<CubesOutput>('cubes', setCubes), [load])

  const reloadMontecarlo = useCallback(() => load<ProbabilityOutput>('montecarlo', setMontecarlo), [load])
  const reloadBuffon = useCallback(() => load<ProbabilityOutput>('buffon', setBuffon), [load])

  useEffect(() => {
    if (demo === 'raytracer' && !ray.loaded && !ray.loading) void reloadRay()
    if (demo === 'life' && !life.loaded && !life.loading) void reloadLife()
    if (demo === 'cubes' && !cubes.loaded && !cubes.loading) void reloadCubes()
    if (demo === 'montecarlo' && !montecarlo.loaded && !montecarlo.loading) void reloadMontecarlo()
    if (demo === 'buffon' && !buffon.loaded && !buffon.loading) void reloadBuffon()
  }, [demo, ray, life, cubes, montecarlo, buffon, reloadRay, reloadLife, reloadCubes, reloadMontecarlo, reloadBuffon])

  useEffect(() => {
    const reveal = () => document.querySelector('header [role=tab][data-state=active]')?.scrollIntoView({ block: 'nearest', inline: 'nearest' })
    reveal(); addEventListener('resize', reveal); return () => removeEventListener('resize', reveal)
  }, [demo])

  const select = (id: string) => { history.replaceState(null, '', `#${id}`); setDemo(id as DemoName) }

  return (
    <TooltipProvider>
      <JobProvider>
        <div className="flex min-h-dvh flex-col lg:h-dvh lg:overflow-hidden">
          <header className="flex h-14 shrink-0 items-center gap-4 border-b bg-card px-4">
            <div className="hidden shrink-0 items-center gap-2.5 whitespace-nowrap sm:flex">
              <span className="size-2.5 rounded-sm bg-foreground" aria-hidden />
              <span className="hidden text-sm font-semibold tracking-tight sm:inline">Bend playground</span>
            </div>
            <div className="min-w-0 flex-1 overflow-x-auto overflow-y-hidden [scrollbar-width:none] [&::-webkit-scrollbar]:hidden sm:ml-auto sm:flex-initial">
              <Tabs value={demo} onValueChange={select}>
                <TabsList className="w-max">
                  {TABS.map(t => <TabsTrigger key={t.id} value={t.id} className="shrink-0">{t.label}</TabsTrigger>)}
                </TabsList>
              </Tabs>
            </div>
          </header>
          {demo === 'raytracer' && <Raytracer {...ray} reload={reloadRay} />}
          {demo === 'life' && <Life {...life} reload={reloadLife} active />}
          {demo === 'cubes' && <Cubes {...cubes} reload={reloadCubes} active />}
          {demo === 'rubik' && <Rubik active />}
          {demo === 'montecarlo' && <Probability key="montecarlo" method="montecarlo" {...montecarlo} reload={reloadMontecarlo} />}
          {demo === 'buffon' && <Probability key="buffon" method="buffon" {...buffon} reload={reloadBuffon} />}
          {demo === 'times-table' && <TimesTable />}
          {demo === 'fourier' && <Fourier key="wave" mode="wave" />}
          {demo === 'epicycles' && <Fourier key="drawing" mode="drawing" />}
          {demo === 'sorting' && <Sorting />}
          {demo === 'shakespeare' && <Shakespeare />}
          {demo === 'polar' && <Polar />}
        </div>
      </JobProvider>
    </TooltipProvider>
  )
}
