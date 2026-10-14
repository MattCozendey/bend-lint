import { useEffect, useRef } from 'react'
export function surface(canvas: HTMLCanvasElement) {
  const { width, height } = canvas.getBoundingClientRect(), dpr = Math.min(devicePixelRatio || 1, 2)
  if (canvas.width !== Math.round(width * dpr) || canvas.height !== Math.round(height * dpr)) { canvas.width = Math.round(width * dpr); canvas.height = Math.round(height * dpr) }
  const c = canvas.getContext('2d')!; c.setTransform(dpr, 0, 0, dpr, 0, 0); c.clearRect(0, 0, width, height)
  return { c, width, height }
}
export function usePaint(draw: (canvas: HTMLCanvasElement) => void) {
  const ref = useRef<HTMLCanvasElement>(null), latest = useRef(draw); latest.current = draw
  useEffect(() => { const paint = () => { if (ref.current) latest.current(ref.current) }; const o = new ResizeObserver(paint); if (ref.current) o.observe(ref.current); paint(); return () => o.disconnect() }, [])
  useEffect(() => { if (ref.current) draw(ref.current) })
  return ref
}
