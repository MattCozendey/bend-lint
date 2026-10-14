import type { ReactNode } from 'react'
import { Pause, Play, RotateCcw, StepForward } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Slider } from '@/components/ui/slider'

interface Props {
  playing: boolean
  onPlay: () => void
  onStep: () => void
  onReset?: () => void
  value: number
  max: number
  step?: number
  onScrub: (v: number) => void
  readout: ReactNode
  extra?: ReactNode
  disabled?: boolean
  label: string
}

export function Transport({ playing, onPlay, onStep, onReset, value, max, step = 1, onScrub, readout, extra, disabled, label }: Props) {
  return (
    <div className="grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-3 sm:grid-cols-[auto_minmax(0,1fr)_auto]">
      <div className="order-2 flex gap-1.5 sm:order-1">
        <Button size="sm" variant="secondary" onClick={onPlay} disabled={disabled} aria-label={playing ? `Pause ${label}` : `Play ${label}`}>
          {playing ? <Pause /> : <Play />}{playing ? 'Pause' : 'Play'}
        </Button>
        <Button size="sm" variant="outline" onClick={onStep} disabled={disabled} aria-label={`Step ${label}`}><StepForward />Step</Button>
        {onReset && <Button size="sm" variant="outline" onClick={onReset} disabled={disabled} aria-label={`Reset ${label}`}><RotateCcw /></Button>}
      </div>
      <Slider className="order-1 col-span-2 sm:order-2 sm:col-span-1" value={[value]} min={0} max={max} step={step} onValueChange={([v]) => onScrub(v)} disabled={disabled} aria-label={label} />
      <div className="order-3 flex items-center justify-end gap-3 font-mono text-xs whitespace-nowrap text-muted-foreground">{readout}{extra}</div>
    </div>
  )
}
