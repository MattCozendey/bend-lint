import { standalone } from '@/lib/runtime'
import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from 'react'
import { Loader2, Play, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Separator } from '@/components/ui/separator'
import { Field, Stat } from '@/components/Workspace'
import { cancelDemo, runDemo } from '@/lib/api'
import type { DemoName, OutputMeta } from '@/lib/types'
import { cn } from '@/lib/utils'

export type Backend = 'gpu' | 'cpu1' | 'cpu8'
interface Job { demo: DemoName | null; phase: 'computing' | 'loading' | null; started: number }
interface JobContextValue {
  job: Job
  backend: Backend
  setBackend: (b: Backend) => void
  start: (demo: DemoName, body: Record<string, unknown>, after: () => Promise<void>) => Promise<void>
  cancel: () => Promise<void>
  message: { text: string; error: boolean } | null
  setMessage: (m: { text: string; error: boolean } | null) => void
}
const JobContext = createContext<JobContextValue | null>(null)

export function JobProvider({ children }: { children: ReactNode }) {
  const [job, setJob] = useState<Job>({ demo: null, phase: null, started: 0 })
  const [backend, setBackend] = useState<Backend>('gpu')
  const [message, setMessage] = useState<JobContextValue['message']>(null)
  const start: JobContextValue['start'] = async (demo, body, after) => {
    if (job.demo) return
    setMessage(null)
    setJob({ demo, phase: 'computing', started: performance.now() })
    try {
      await runDemo({ ...body, gpu: backend === 'gpu', threads: backend === 'cpu8' ? 8 : 1 })
      setJob(j => ({ ...j, phase: 'loading' }))
      await after()
      setMessage({ text: demo === 'raytracer' ? 'Render complete. RGB pixels drawn; PPM ready to save.' : 'Replay ready. Press Play to watch.', error: false })
    } catch (e) {
      setMessage({ text: (e as Error).message, error: true })
    } finally {
      setJob({ demo: null, phase: null, started: 0 })
    }
  }
  const cancel = async () => { try { await cancelDemo() } catch (e) { setMessage({ text: (e as Error).message, error: true }) } }
  return <JobContext.Provider value={{ job, backend, setBackend, start, cancel, message, setMessage }}>{children}</JobContext.Provider>
}
export const useJob = () => useContext(JobContext)!

function Elapsed({ since }: { since: number }) {
  const [now, setNow] = useState(performance.now())
  useEffect(() => { const t = setInterval(() => setNow(performance.now()), 1000); return () => clearInterval(t) }, [])
  return <>{Math.floor((now - since) / 1000)}s</>
}

interface Props { demo: DemoName; label: string; body: () => Record<string, unknown>; after: () => Promise<void>; meta: OutputMeta | null; onBeforeRun?: () => void }
export function RunPanel({ demo, label, body, after, meta, onBeforeRun }: Props) {
  const { job, backend, setBackend, start, cancel, message } = useJob()
  const busy = job.demo !== null, mine = job.demo === demo
  const cancelling = useRef(false)
  return (
    <div className="grid gap-4">
      {standalone ? <p className="text-xs text-muted-foreground">Browser CPU · compiled Bend<br />Results stay in this tab until you reload.</p> : <Field label="Compute device" htmlFor="backend">
        <Select value={backend} onValueChange={v => setBackend(v as Backend)}>
          <SelectTrigger id="backend" className="w-full"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="gpu">NVIDIA GPU · CUDA</SelectItem>
            <SelectItem value="cpu1">CPU · 1 thread</SelectItem>
            <SelectItem value="cpu8">CPU · 8 threads</SelectItem>
          </SelectContent>
        </Select>
      </Field>}
      <div className="grid gap-2">
        <Button size="lg" disabled={busy} onClick={() => { onBeforeRun?.(); cancelling.current = false; void start(demo, body(), after) }}>
          {mine ? <Loader2 className="animate-spin" /> : <Play />}{mine ? (job.phase === 'loading' ? 'Loading output' : 'Computing') : label}
        </Button>
        {mine && job.phase === 'computing' && (
          <Button variant="outline" onClick={() => { cancelling.current = true; void cancel() }}><X />Cancel</Button>
        )}
        <p role="status" aria-live="polite" className={cn('min-h-5 text-xs', message?.error ? 'text-destructive' : 'text-muted-foreground')}>
          {mine ? <>Running on {standalone ? 'your browser CPU' : backend === 'gpu' ? 'the GPU' : backend === 'cpu8' ? '8 CPU threads' : '1 CPU thread'} · <Elapsed since={job.started} /> elapsed</> : busy ? 'Another experiment is running.' : message?.text ?? 'Ready.'}
        </p>
      </div>
      <Separator />
      <div className="grid grid-cols-2 gap-3">
        <Stat label="Compute" value={meta?.kernelMs} unit="ms" />
        <Stat label="Process" value={meta?.wallMs} unit="ms" />
      </div>
      <p className="text-xs text-muted-foreground">{meta ? `${meta.backend} · process time includes startup and output.` : 'Run the experiment to see its timing.'}</p>
    </div>
  )
}
