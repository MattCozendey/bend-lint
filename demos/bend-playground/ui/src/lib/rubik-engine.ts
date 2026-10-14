import { asset } from './runtime'
// Imperative SVG renderer for the Bend-compiled Rubik engine. React owns the
// surrounding controls; this module owns the two SVG scenes and the move queue.
const NS = 'http://www.w3.org/2000/svg'
export const FACES = ['U', 'R', 'F', 'D', 'L', 'B'] as const
export const FACE_COLORS = ['#fde047', '#f87171', '#4ade80', '#fafafa', '#fb923c', '#60a5fa']
export const moveName = (move: number) => FACES[Math.floor(move / 3)] + ['', '2', '′'][move % 3]

type Vec = [number, number, number]
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Cube = any
type List = { $: 'Nil' } | { $: 'Con'; head: number; tail: List }
const list = (values: number[]): List => values.reduceRight<List>((tail, head) => ({ $: 'Con', head, tail }), { $: 'Nil' })
const array = (values: List): number[] => { const out: number[] = []; for (let x = values; x.$ === 'Con'; x = x.tail) out.push(x.head); return out }
const node = (tag: string, attrs: Record<string, string | number> = {}, text?: string) => { const el = document.createElementNS(NS, tag); for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, String(v)); if (text !== undefined) el.textContent = text; return el }
const vec = (p: { x: number; y: number; z: number }): Vec => [p.x - 1, p.y - 1, p.z - 1]
const dot = (a: Vec, b: Vec) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
const add = (a: Vec, b: Vec): Vec => [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
const scale = (a: Vec, k: number): Vec => [a[0] * k, a[1] * k, a[2] * k]
function rotate(v: Vec, axis: Vec, angle: number): Vec {
  const c = Math.cos(angle), s = Math.sin(angle), cross: Vec = [axis[1] * v[2] - axis[2] * v[1], axis[2] * v[0] - axis[0] * v[2], axis[0] * v[1] - axis[1] * v[0]]
  return v.map((x, i) => x * c + cross[i] * s + axis[i] * dot(axis, v) * (1 - c)) as Vec
}
const graphPoints: [number, number][] = Array.from({ length: 54 }, (_, i) => {
  const face = Math.floor(i / 9), a = -Math.PI / 2 + face * Math.PI / 3
  return [250 + Math.cos(a) * 162 + (i % 3 - 1) * 19, 250 + Math.sin(a) * 162 + (Math.floor(i % 9 / 3) - 1) * 19]
})
function curve(i: number, j: number) {
  const a = graphPoints[i], b = graphPoints[j], dx = b[0] - a[0], dy = b[1] - a[1]
  const bend = Math.floor(i / 9) === Math.floor(j / 9) ? .32 : .23
  return { a, b, c: [(a[0] + b[0]) / 2 - dy * bend, (a[1] + b[1]) / 2 + dx * bend] as [number, number] }
}
type Curve = ReturnType<typeof curve>
const curvePath = ({ a, b, c }: Curve) => `M${a} Q${c} ${b}`
const curveAt = ({ a, b, c }: Curve, t: number) => a.map((x, i) => (1 - t) ** 2 * x + 2 * (1 - t) * t * c[i] + t * t * b[i]) as [number, number]

export interface RubikStatus {
  solved: boolean
  busy: boolean
  paused: boolean
  animating: string | null
  history: number[]
  lastMs: number
}
export interface RubikEngine {
  enqueue(moves: number[], undo?: boolean): void
  undo(): void
  unwind(): void
  scramble(n: number): void
  reset(): void
  togglePause(): void
  setSpeed(ms: number): void
  setActive(active: boolean): void
  preview(face: number): void
  destroy(): void
}

let enginePromise: Promise<Cube> | null = null
export function loadCube(): Promise<Cube> {
  enginePromise ??= (import(/* @vite-ignore */ asset('rubik-engine.js')) as Promise<{ default: Cube }>).then(m => m.default)
  return enginePromise
}

export function createRubik(Cube: Cube, cubeSvg: SVGSVGElement, graphSvg: SVGSVGElement, onStatus: (s: RubikStatus) => void): RubikEngine {
  const sites = Array.from({ length: 54 }, (_, i) => Cube.site(i))
  const normals: Vec[] = FACES.map((_, i) => vec(sites[i * 9 + 4].normal))
  const axes: [Vec, Vec][] = FACES.map((_, i) => {
    const mid = vec(sites[i * 9 + 4].position)
    return [vec(sites[i * 9 + 5].position).map((x, j) => x - mid[j]) as Vec, vec(sites[i * 9 + 7].position).map((x, j) => x - mid[j]) as Vec]
  })
  let history = array(Cube.scramble(20n, 42, 6)), state = Cube.sequence(list(history), Cube.solved()), values: number[] = array(state)
  let queue: { move: number; undo: boolean }[] = [], animation: { move: number; undo: boolean; after: unknown; elapsed: number; duration: number } | null = null
  let paused = false, active = false, raf = 0, last = 0, selected = 0, yaw = -.6, pitch = .46, drag: { x: number; y: number } | null = null, lastMs = 0, speed = 450
  const cubeGroup = node('g'), edges = node('g'), highlight = node('g'), dots = node('g')
  cubeSvg.replaceChildren(cubeGroup)
  graphSvg.replaceChildren(edges, highlight, dots)
  const seen = new Set<string>()
  for (let f = 0; f < 6; f++) for (let i = 0; i < 54; i++) {
    const j = Cube.destination(i, f * 3), key = [i, j].sort((a, b) => a - b).join(':')
    if (i === j || seen.has(key)) continue; seen.add(key)
    edges.append(node('path', { d: curvePath(curve(i, j)), fill: 'none', stroke: '#71717a', 'stroke-opacity': .25, 'stroke-width': 1 }))
  }
  const dotNodes = graphPoints.map((p, i) => {
    const circle = node('circle', { cx: p[0], cy: p[1], r: 7, stroke: '#09090b', 'stroke-width': 2 })
    circle.append(node('title', {}, `${FACES[Math.floor(i / 9)]}${i % 9 + 1}`)); dots.append(circle); return circle
  })
  for (let f = 0; f < 6; f++) {
    const p = graphPoints[f * 9 + 4], label = node('text', { x: p[0], y: p[1] - 33, 'text-anchor': 'middle', fill: FACE_COLORS[f], class: 'cursor-pointer font-mono text-[14px] font-semibold', tabindex: 0, role: 'button', 'aria-label': `Turn ${FACES[f]} clockwise` }, FACES[f])
    label.addEventListener('click', e => enqueue([f * 3 + ((e as MouseEvent).shiftKey ? 2 : 0)]))
    label.addEventListener('keydown', e => { const k = e as KeyboardEvent; if (k.key === 'Enter' || k.key === ' ') { k.preventDefault(); enqueue([f * 3 + (k.shiftKey ? 2 : 0)]) } })
    graphSvg.append(label)
  }
  interface Geometry { p: Vec; normal: Vec; axes: [Vec, Vec]; radius: number; offset: number; color?: string; sticker: number; point: unknown }
  const geometry: Geometry[] = []
  for (let x = 0; x < 3; x++) for (let y = 0; y < 3; y++) for (let z = 0; z < 3; z++) for (let f = 0; f < 6; f++) geometry.push({ p: [x - 1, y - 1, z - 1], normal: normals[f], axes: axes[f], radius: .49, offset: .49, color: '#18181b', sticker: -1, point: { $: 'Point', x, y, z } })
  for (let i = 0; i < 54; i++) geometry.push({ p: vec(sites[i].position), normal: vec(sites[i].normal), axes: axes[Math.floor(i / 9)], radius: .43, offset: .505, sticker: i, point: sites[i].position })
  const polygons = geometry.map(g => { const polygon = node('polygon', { 'stroke-linejoin': 'round', 'stroke-width': .8 }); cubeGroup.append(polygon); return { g, polygon } })
  const camera = (v: Vec) => rotate(rotate(v, [0, 1, 0], yaw), [1, 0, 0], pitch)
  function render(progress = animation ? animation.elapsed / animation.duration : 0) {
    const eased = progress * progress * (3 - 2 * progress), face = animation ? Math.floor(animation.move / 3) : selected
    const angle = animation ? -Math.PI / 2 * ([1, 2, -1][animation.move % 3]) * eased : 0
    const projected: { polygon: Element; z: number }[] = []
    for (const { g, polygon } of polygons) {
      const moving = animation && Cube.in_layer(face, g.point), spin = (v: Vec) => moving ? rotate(v, normals[face], angle) : v
      const n = camera(spin(g.normal)); if (n[2] <= .001) { polygon.setAttribute('display', 'none'); continue } polygon.removeAttribute('display')
      const center = add(g.p, scale(g.normal, g.offset))
      const points = ([[-1, -1], [1, -1], [1, 1], [-1, 1]] as const).map(([u, v]) => camera(spin(add(add(center, scale(g.axes[0], u * g.radius)), scale(g.axes[1], v * g.radius)))))
      polygon.setAttribute('points', points.map(p => `${250 + p[0] * 79},${251 - p[1] * 79}`).join(' '))
      polygon.setAttribute('fill', g.sticker < 0 ? g.color! : FACE_COLORS[Math.floor(values[g.sticker] / 9)])
      polygon.setAttribute('stroke', g.sticker < 0 ? '#09090b' : '#09090b88')
      projected.push({ polygon, z: camera(spin(center))[2] })
    }
    projected.sort((a, b) => a.z - b.z).forEach(({ polygon }) => cubeGroup.append(polygon))
    highlight.replaceChildren()
    const move = animation?.move ?? selected * 3
    for (let i = 0; i < 54; i++) {
      const j = Cube.destination(i, move), moving = animation && i !== j
      if (i !== j) highlight.append(node('path', { d: curvePath(curve(i, j)), fill: 'none', stroke: FACE_COLORS[face], 'stroke-width': animation ? 2 : 1.5, 'stroke-opacity': animation ? .8 : .45 }))
      const p = moving ? curveAt(curve(i, j), eased) : graphPoints[i], circle = dotNodes[i]
      circle.setAttribute('cx', String(p[0])); circle.setAttribute('cy', String(p[1])); circle.setAttribute('fill', FACE_COLORS[Math.floor(values[i] / 9)]); circle.setAttribute('r', moving ? '8' : '7')
    }
  }
  function ui() {
    onStatus({ solved: Cube.is_solved(state), busy: !!animation || queue.length > 0, paused, animating: animation ? moveName(animation.move) : null, history: [...history], lastMs })
  }
  function next() {
    if (animation || !queue.length) return
    const task = queue.shift()!, start = performance.now(), after = Cube.apply(state, task.move); lastMs = performance.now() - start
    animation = { ...task, after, elapsed: 0, duration: speed }; selected = Math.floor(task.move / 3); ui()
  }
  function tick(now: number) {
    raf = 0; if (!active || paused) return
    next(); if (!animation) return
    animation.elapsed = Math.min(animation.duration, animation.elapsed + (last ? Math.min(now - last, 100) : 0)); last = now
    render(animation.elapsed / animation.duration)
    if (animation.elapsed >= animation.duration) {
      state = animation.after; values = array(state); if (animation.undo) history.pop(); else history.push(animation.move); animation = null; render(0); ui()
    }
    if (animation || queue.length) raf = requestAnimationFrame(tick)
  }
  const wake = () => { if (active && !paused && !raf) { last = 0; raf = requestAnimationFrame(tick) } }
  function enqueue(moves: number[], undo = false) { queue.push(...moves.map(move => ({ move, undo }))); paused = false; ui(); wake() }
  const onDown = (e: PointerEvent) => { drag = { x: e.clientX, y: e.clientY }; cubeSvg.setPointerCapture(e.pointerId) }
  const onMove = (e: PointerEvent) => { if (!drag) return; yaw += (e.clientX - drag.x) * .008; pitch = Math.max(-1.35, Math.min(1.35, pitch + (e.clientY - drag.y) * .008)); drag = { x: e.clientX, y: e.clientY }; render() }
  const onUp = () => { drag = null }
  const onKey = (e: KeyboardEvent) => {
    if (!active || e.repeat || e.ctrlKey || e.metaKey || e.altKey || /INPUT|SELECT|TEXTAREA|BUTTON/.test((e.target as Element).tagName)) return
    const f = FACES.indexOf(e.key.toUpperCase() as typeof FACES[number]); if (f >= 0) { e.preventDefault(); enqueue([f * 3 + (e.shiftKey ? 2 : 0)]) }
  }
  cubeSvg.addEventListener('pointerdown', onDown); cubeSvg.addEventListener('pointermove', onMove); cubeSvg.addEventListener('pointerup', onUp); cubeSvg.addEventListener('pointercancel', onUp)
  window.addEventListener('keydown', onKey)
  render(); ui()
  return {
    enqueue,
    undo() { if (history.length && !animation) enqueue([Cube.inverse(history.at(-1))], true) },
    unwind() { if (history.length && !animation) enqueue(array(Cube.undo_moves(list(history), { $: 'Nil' })), true) },
    scramble(n) { const seed = crypto.getRandomValues(new Uint32Array(1))[0]; enqueue(array(Cube.scramble(BigInt(n), seed, history.length ? Math.floor(history.at(-1)! / 3) : 6))) },
    reset() { cancelAnimationFrame(raf); raf = 0; queue = []; animation = null; history = []; state = Cube.solved(); values = array(state); paused = false; render(); ui() },
    togglePause() { paused = !paused; ui(); wake() },
    setSpeed(ms) { speed = ms },
    preview(face) { selected = face; if (!animation) render() },
    setActive(value) { active = value; if (!active) { if (animation || queue.length) paused = true; cancelAnimationFrame(raf); raf = 0; last = 0; ui() } else wake() },
    destroy() { cancelAnimationFrame(raf); window.removeEventListener('keydown', onKey); cubeSvg.removeEventListener('pointerdown', onDown); cubeSvg.removeEventListener('pointermove', onMove); cubeSvg.removeEventListener('pointerup', onUp); cubeSvg.removeEventListener('pointercancel', onUp) },
  }
}
