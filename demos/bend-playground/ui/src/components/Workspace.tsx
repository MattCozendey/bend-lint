import type { ReactNode } from 'react'
import { Badge } from '@/components/ui/badge'
import { ScrollArea } from '@/components/ui/scroll-area'
import { cn } from '@/lib/utils'

interface Props {
  tag: string
  title: string
  description: string
  stage: ReactNode
  footer?: ReactNode
  above?: ReactNode
  controls: ReactNode
  stageClassName?: string
}

export function Workspace({ tag, title, description, stage, footer, above, controls, stageClassName }: Props) {
  return (
    <div className="grid min-h-0 flex-1 grid-cols-1 lg:grid-cols-[minmax(0,1fr)_360px] lg:overflow-hidden">
      <section className="flex min-h-0 min-w-0 flex-col bg-background" aria-label="Experiment output">
        <div className="flex h-11 shrink-0 items-center justify-between border-b px-4">
          <span className="text-sm font-medium text-muted-foreground">{title}</span>
          <Badge variant="outline" className="font-mono text-[11px] font-normal tracking-wide text-muted-foreground uppercase">{tag}</Badge>
        </div>
        {above}
        <div className={cn('relative min-h-0 min-w-0 flex-none h-[56dvh] lg:flex-1 lg:h-auto bg-zinc-950 [background-image:radial-gradient(circle_at_1px_1px,theme(colors.zinc.900)_1px,transparent_0)] [background-size:24px_24px]', stageClassName)}>
          {stage}
        </div>
        {footer && <div className="shrink-0 border-t px-4 py-3">{footer}</div>}
      </section>
      <aside className="min-h-0 border-t bg-card lg:border-t-0 lg:border-l">
        <ScrollArea className="h-full">
          <div className="flex flex-col gap-6 p-5 pb-10">
            <div>
              <h2 className="text-xl font-semibold tracking-tight">{title}</h2>
              <p className="mt-1 text-sm text-muted-foreground">{description}</p>
            </div>
            {controls}
          </div>
        </ScrollArea>
      </aside>
    </div>
  )
}

export function Field({ label, htmlFor, children, hint }: { label: string; htmlFor?: string; children: ReactNode; hint?: ReactNode }) {
  return (
    <div className="grid gap-2">
      <label htmlFor={htmlFor} className="text-sm font-medium leading-none">{label}</label>
      {children}
      {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
    </div>
  )
}

export function Stat({ label, value, unit }: { label: string; value: string | number | null | undefined; unit?: string }) {
  return (
    <div className="rounded-lg border bg-background p-3">
      <div className="text-[11px] font-medium tracking-wide text-muted-foreground uppercase">{label}</div>
      <div className="mt-1 text-2xl font-semibold tabular-nums tracking-tight">
        {value ?? '—'}{unit && <span className="ml-1 text-sm font-normal text-muted-foreground">{unit}</span>}
      </div>
    </div>
  )
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="absolute inset-0 grid place-items-center p-6 text-center text-sm text-muted-foreground">{children}</div>
}
