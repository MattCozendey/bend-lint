*English | [Русский](ru/reference-demo-spec.md)*

# Specification of the «Ночной поезд — из окна» demo

Engineering reference for re-implementing the look and behaviour in another language/engine.
Source: `notes/personal/2026-07-24-nochnoy-poezd-3d.html` (1623 lines, a single file: HTML + CSS + an IIFE `<script>` in `'use strict'`). The WebGL2 context is created as `canvas.getContext('webgl2', {antialias:true, alpha:false, powerPreference:'high-performance'})`; if WebGL2 is unavailable, a text error message is shown over the page.

Below, every formula and constant is written out exactly as in the source. Numbers marked as derived (for example `58.0*0.00840 = 0.4872`) are arithmetic the engine performs; they can be computed at startup.

## Conventions for coordinates and time

* Right-handed coordinate system, `y` is up.
* The path parameter `s` is measured in metres and **is simultaneously the world coordinate `z`**: a point on the track centreline `= (trackX(s), trackY(s), s)`. `trackX` is the lateral offset, `trackY` the height.
* Heading `yaw = atan2(dx/ds, 1)` — a rotation about the `Y` axis from `+Z` towards `+X`. An object's local `+Z` axis points forward (in the direction of increasing `s`), and the local `+X` axis points sideways and equals `(cos yaw, 0, -sin yaw)`.
* Any point "with lateral offset `off`" is built as `x = trackX(s) + off*cos(yaw)`, `z = s - off*sin(yaw)`.
* World time `t = state.t` accumulates as `t += dt`, `dt = min(elapsed_ms/1000, 0.10)`.
* Progress along the path: `state.s += state.speed * dt`.

---

## 1. The scene as a whole and the camera

### 1.1 What the viewer sees

A night landscape outside a moving train. The camera hangs beside the consist, roughly at window height (`trackY(s)+3.05`), offset laterally from the track centreline. The train passes on the left/right: behind the camera is a tail of 5 cars, ahead are 9 cars and the locomotive last (`CARS_BEHIND = 5`, `CARS_AHEAD = 10`, total `CARS = 15`). Around it: a night forest, hills, a snow-covered/grassy embankment, two rails, sleepers, catenary poles with wires, occasional villages with lit windows; overhead, a starry sky with the Milky Way and the moon. Warm pools of light from the car windows fall onto the embankment, and the locomotive's headlights are on. Motes/sparks rush past the face, and smoke pours from the locomotive's stack. At the screen edges there is a CSS vignette (not a shader).

DOM overlays: `#journey` («Ночной экспресс» / «лес спит, а мы едем дальше»), `#hint` («веди пальцем, чтобы оглядеться», fades after 12 s), `#hud` (buttons), `#settings` (settings panel), `#vignette`, `#err`.

### 1.2 World matrices

Implemented by hand (the `M4` module), column-major (as in WebGL).

`M4.ident` — identity.

`M4.mul(a,b)` — the product `a*b` (column-wise, as in the source).

`M4.perspective(fovy, aspect, near, far)`:

```
f  = 1 / tan(fovy/2)
nf = 1 / (near - far)
[f/aspect, 0, 0,             0,
 0,        f, 0,             0,
 0,        0, (far+near)*nf, -1,
 0,        0, 2*far*near*nf, 0]
```

`M4.lookAt(eye, center, up)` — the standard one: `z = normalize(eye-center)`, `x = normalize(cross(up,z))`, `y = cross(z,x)`, translation `-(x·eye, y·eye, z·eye)`.

`M4.rigid(px,py,pz,yaw,roll,sx,sy,sz)` — the car model `T(p) * Ry(yaw) * Rz(roll) * S(sx,sy,sz)`:

```
cy=cos(yaw), sy_=sin(yaw), cr=cos(roll), sr=sin(roll)

m00 =  cy*cr,  m01 = -cy*sr,  m02 = sy_
m10 =  sr,     m11 =  cr,     m12 = 0
m20 = -sy_*cr, m21 =  sy_*sr, m22 = cy

matrix (column-major) =
[ m00*sx, m10*sx, m20*sx, 0,
  m01*sy, m11*sy, m21*sy, 0,
  m02*sz, m12*sz, m22*sz, 0,
  px,     py,     pz,     1 ]
```

### 1.3 Camera position and orientation

For every frame, with `s = state.s` and `baseYaw = trackYaw(s)`:

```
sway = state.motion ? sin(t*1.9)*0.022 + sin(t*3.7)*0.008 : 0
bob  = state.motion ? sin(t*5.3)*0.018 + sin(t*2.6)*0.016 : 0
state.lean += (state.leanTarget - state.lean) * min(1, dt*2.8)

sideOffset = -2.15 - state.lean*2.45 + (state.motion ? sin(t*0.31)*0.12 : 0)
camX = trackX(s) + sideOffset * cos(baseYaw)
camZ = s        - sideOffset * sin(baseYaw)
camY = trackY(s) + 3.05 + bob
cam  = (camX, camY, camZ)
```

Total lateral camera offset: `-4.60` m at `lean = 1` ("at the window") and `-2.15` m at `lean = 0` ("lean out"); with `motion`, a slow "breathing" of amplitude 0.12 m is added.

View direction:

```
lookYaw   = baseYaw + state.yaw + sway*0.35
lookPitch = state.pitch + sway*0.1
dir = ( sin(lookYaw)*cos(lookPitch),
        sin(lookPitch),
        cos(lookYaw)*cos(lookPitch) )
center = cam + dir
```

Frame matrices:

```
proj = perspective(fovy, W/H, 0.15, 1500)
fovy = (W < H) ? 1.20 : 1.12          // radians: 68.8° in portrait, 64.2° in landscape
view = lookAt(cam, center, (0,1,0))
vp   = proj * view
```

The inverse matrix `invVP = invert(vp)` is used only by the sky shader (a full-screen triangle). An explicit 4×4 inverter is implemented; at zero determinant it returns the identity matrix.

### 1.4 Smoothing and target angles

```
state.yaw   += (state.yawTarget   - state.yaw)   * min(1, dt*7)
state.pitch += (state.pitchTarget - state.pitch) * min(1, dt*7)
```

Initial values: `state.yaw = 0`, `state.pitch = -0.02`, `state.yawTarget = 0`, `state.pitchTarget = -0.02`.

### 1.5 "Forward" mode (`autoLook`)

On by default (`state.autoLook = true`). While it is on, every frame:

```
aimS   = carS(CARS_BEHIND + round((CARS_AHEAD-1)*0.62))
       = carS(5 + round(5.58)) = carS(11)
aimYaw = trackYaw(aimS)
aimX   = trackX(aimS) + 4.2*cos(aimYaw)
aimZ   = aimS         - 4.2*sin(aimYaw)
want   = atan2(aimX - camX, aimZ - camZ) - baseYaw
want   is reduced to (-π, π]
want   = clamp(want, -0.95, 0.45)
state.yawTarget   += (want - state.yawTarget)   * min(1, dt*1.4)
state.pitchTarget += (0.012 - state.pitchTarget)* min(1, dt*1.4)
```

That is, the camera turns not towards the locomotive but towards a point 62 % of the way to it, otherwise the consist leaves the frame.

Any manual control (dragging or the arrow keys) resets `autoLook = false` and hides the `#hint` hint. The "look forward" button turns `autoLook` back on and sets `pitchTarget = -0.02`.

### 1.6 Manual view control

* Finger/mouse dragging (`pointerdown`/`pointermove` with pointer capture) — primary pointer only:
  ```
  k = 2.6 / max(360, min(innerWidth, innerHeight))
  yawTarget   = clamp(yawTarget   - dx*k,     -2.9,  0.65)
  pitchTarget = clamp(pitchTarget + dy*k*0.8, -0.95, 1.10)
  ```
* Keyboard (the canvas has `tabindex=0`): `ArrowLeft → (+0.11, 0)`, `ArrowRight → (-0.11, 0)`, `ArrowUp → (0, +0.08)`, `ArrowDown → (0, -0.08)`, where the pair is the increment `(Δyaw, Δpitch)` within the same bounds.

### 1.7 Resolution and adaptive quality

```
cap  = (quality==='high') ? 2 : (quality==='low') ? 1 : state.renderScale
dpr  = min(devicePixelRatio || 1, cap)
W = round(innerWidth * dpr);  H = round(innerHeight * dpr)
canvas.width = W; canvas.height = H; gl.viewport(0,0,W,H)
```

`state.renderScale` (`auto` mode only) starts at `1.5` and is adjusted once every 3000 ms from the smoothed frame time `state.frameMs` (EMA with coefficient 0.025):

* `frameMs > 24` → `renderScale = max(0.85, renderScale - 0.15)`;
* `frameMs < 18` → `renderScale = min(1.75, renderScale + 0.10)`.

A frame is skipped if the tab is hidden or the WebGL context is lost (`state.last = 0`, no rAF).

---

## 2. The track

The same formula defines the world, the camera and the rolling stock. In JS these are functions of `s`, duplicated in GLSL as the string `GLSL_TRACK` (with the same numbers substituted via `toFixed`).

### 2.1 The `TRACK` constants

```js
const TRACK = { a1: 58.0, f1: 0.00840, a2: 13.0, f2: 0.02150, p2: 1.3,
                b1: 3.4,  g1: 0.00625, b2: 1.6,  g2: 0.015625, q2: 0.7 };
```

| Field | Value | Meaning |
|---|---|---|
| `a1` | 58.0 | amplitude of the 1st harmonic of the lateral offset, m |
| `f1` | 0.00840 | spatial frequency of the 1st harmonic, rad/m |
| `a2` | 13.0 | amplitude of the 2nd harmonic of the lateral offset, m |
| `f2` | 0.02150 | frequency of the 2nd harmonic, rad/m |
| `p2` | 1.3 | phase of the 2nd harmonic of the lateral offset, rad |
| `b1` | 3.4 | amplitude of the 1st harmonic of the height, m |
| `g1` | 0.00625 | frequency of the 1st harmonic of the height, rad/m |
| `b2` | 1.6 | amplitude of the 2nd harmonic of the height, m |
| `g2` | 0.015625 | frequency of the 2nd harmonic of the height, rad/m |
| `q2` | 0.7 | phase of the 2nd harmonic of the height, rad |

Harmonic periods: `2π/f1 ≈ 748.0` m, `2π/f2 ≈ 292.2` m, `2π/g1 ≈ 1005.3` m, `2π/g2 ≈ 402.1` m. The curve is deliberately steep: over the length of the consist the path veers sideways by tens of metres, otherwise all you see from the window is the neighbouring car.

### 2.2 JS formulas

```
trackX(s)  = 58.0*sin(s*0.00840) + 13.0*sin(s*0.02150 + 1.3)

trackY(s)  = 3.4*sin(s*0.00625) + 1.6*sin(s*0.015625 + 0.7)

trackDX(s) = 58.0*0.00840*cos(s*0.00840)
           + 13.0*0.02150*cos(s*0.02150 + 1.3)
           = 0.4872*cos(s*0.00840) + 0.2795*cos(s*0.02150 + 1.3)

trackDY(s) = 3.4*0.00625*cos(s*0.00625)
           + 1.6*0.015625*cos(s*0.015625 + 0.7)
           = 0.02125*cos(s*0.00625) + 0.025*cos(s*0.015625 + 0.7)

trackYaw(s) = atan2(trackDX(s), 1)

trackRoll(s):
    h     = 6
    curve = (trackDX(s+h) - trackDX(s-h)) / (2*h)     // = /12
    return clamp(curve*260, -0.09, +0.09)
```

`trackDY` is used only as a reference derivative (it is never called directly in a frame); `trackRoll` gives the roll on a curve, limited to ±0.09 rad (≈±5.16°).

### 2.3 The GLSL version `GLSL_TRACK`

Substituting `toFixed(3)` / `toFixed(6)`, the string expands to exactly this text (verified against the source):

```glsl
float trackX(float s){ return 58.000*sin(s*0.008400) + 13.000*sin(s*0.021500 + 1.300); }
float trackY(float s){ return  3.400*sin(s*0.006250) +  1.600*sin(s*0.015625 + 0.700); }
float trackYaw(float s){
  float d = 58.000*0.008400*cos(s*0.008400)
          + 13.000*0.021500*cos(s*0.021500 + 1.300);
  return atan(d, 1.0);
}
float hash21(vec2 p){
  p = fract(p * vec2(123.34, 345.45));
  p += dot(p, p + 34.345);
  return fract(p.x * p.y);
}
float vnoise(vec2 p){
  vec2 i = floor(p), f = fract(p);
  f = f*f*(3.0-2.0*f);
  float a = hash21(i), b = hash21(i+vec2(1,0)), c = hash21(i+vec2(0,1)), d = hash21(i+vec2(1,1));
  return mix(mix(a,b,f.x), mix(c,d,f.x), f.y);
}
float fbm(vec2 p){
  float v = 0.0, amp = 0.5;
  for (int i = 0; i < 4; i++){ v += amp * vnoise(p); p *= 2.03; amp *= 0.5; }
  return v;
}
float terrain(float x, float z){
  float hills = (fbm(vec2(x, z) * 0.0042) - 0.5) * 34.0
              + (fbm(vec2(x, z) * 0.0210) - 0.5) *  4.5;
  float d   = abs(x - trackX(z));
  float k   = smoothstep(9.0, 46.0, d);
  float bed = trackY(z) - 0.9;
  return mix(bed, bed + hills, k);
}
```

Important: `GLSL_TRACK` does not contain `trackDX`, `trackDY` and `trackRoll` as separate functions — the lateral-offset derivative is written directly into `trackYaw`, and `trackDY` is not needed in the shaders at all. `terrain` exists **only in GLSL** — there is no JS equivalent; the JS code never computes ground height.

`terrain(x,z)`: right at the embankment (`d < 9` m) the height equals `trackY(z)-0.9`, then it transitions smoothly (smoothstep 9→46 m) to the hills: two octaves of FBM with frequencies 0.0042 and 0.021 and amplitudes 34 and 4.5 m.

---

## 3. The train

### 3.1 Dimensions and numbers

```js
const CAR_LEN = 24.0, CAR_GAP = 2.6, CAR_W = 2.9, CAR_H = 4.0;
const CARS_BEHIND = 5, CARS_AHEAD = 10;
const CARS = CARS_BEHIND + CARS_AHEAD;          // 15
```

### 3.2 Car placement

```
carIndexToS(i) = state.s - CAR_LEN*0.62 + i*(CAR_LEN + CAR_GAP)
               = state.s - 14.88 + i*26.6
carS(i)        = carIndexToS(i - CARS_BEHIND) = state.s - 14.88 + (i-5)*26.6
```

The centre of car `i` in a frame:

```
cs    = carS(i) + CAR_LEN*0.5        // = carS(i) + 12
yaw   = trackYaw(cs)
roll  = trackRoll(cs)
model = M4.rigid(trackX(cs), trackY(cs), cs, yaw, roll, 1, 1, 1)
mesh  = (i === CARS-1) ? locoMesh : carMeshes[i % 3]
isLoco = (i === CARS-1)              // i = 14 — the locomotive is in front
```

The range of the consist's `s` at `state.s = 110`: from `110 - 147.88 = -37.88` (tail) to `110 + 224.52 = 334.52` (centre of the locomotive). Livery variants alternate by `i % 3` (three meshes `carriageMesh(0/1/2)`).

### 3.3 Meshes

All meshes are procedural and built once.

* `boxMesh()` — a unit cube from -0.5 to +0.5, 6 faces, flat normals.
* `coneMesh(seg=7)` — a cone: base radius 0.5, apex `y=+0.5`, base `y=-0.5`, flat normals `(nx,0.35,nz)`.
* `pineMesh()` — a "fir tree" of 5 tiers; for tier `tier = 0..4`: `radius = 0.5 - tier*0.087`, `bottom = -0.5 + tier*0.18`, `height = 0.49 - tier*0.025`, 10 segments, radius with ripple `r = radius*(1 + sin(i*19.7 + tier)*0.14)`; normal `(cos((a+b)/2), radius/height, sin((a+b)/2))`, normalized.
* `gableMesh()` — a triangular prism (house roof) with vertices `a=(-.5,-.5,-.5)`, `b=(.5,-.5,-.5)`, `c=(0,.5,-.5)`, `d=(-.5,-.5,.5)`, `e=(.5,-.5,.5)`, `f=(0,.5,.5)`; 6 triangles `[[a,c,b],[d,e,f],[a,d,f],[a,f,c],[b,c,f],[b,f,e]]`, normals are the cross product of the edges.
* `roofMesh()` — a half-cylinder arch: `i = 0..12`, `a = i/12*π`, point `(cos a * 0.5, sin a * 0.5, z)` for `z = ±0.5`, plus two end "caps".
* `wheelMesh()` — a cylinder along the `X` axis: 14 segments, radius 0.5, length 1 (from `x=-0.5` to `x=+0.5`), with side discs.
* `coloredBuilder()` — an assembly buffer: the method `add(mesh, at, scale, color, emissive=0, rotateX=0)`, where the position is scaled and rotated about `X`, the normal is divided by the scale (`n/scale`) and normalized, and colour and emission are written per vertex; `box(at,scale,color,emissive)` is the box special case. `finish()` assembles a VAO with attributes: 0 — position (vec3), 1 — normal (vec3), 2 — colour (vec3), 3 — emission (float). Throws if there are more than 65535 vertices (`Uint16` indices).

### 3.4 Car construction (`carriageMesh(variant, loco=false)`)

Common parameters: `length = loco ? 19.7 : 24.0`; `paint = loco ? [.12,.19,.20] : [.12,.20,.22]`.
Palette: `brass = [.49,.35,.18]`, `metal = [.13,.17,.20]`, `dark = [.027,.042,.052]`.

Body and roof:

* body box `[0, 2.6, 0]`, scale `[CAR_W=2.9, 3.0, length]`, colour `paint` (the body occupies `y` from 1.1 to 4.1);
* frame `[0, 1.04, 0]`, scale `[2.8, .28, length]`, `dark`;
* roof arch `roofMesh()` at `[0, 4.1, 0]`, scale `[3.02, 1.3, length+.12]`, colour `[.21,.25,.28]`;
* roof ribs: for `z` from `-length/2+1` to `< length/2` in steps of `2.2` — `roofMesh()` at `[0,4.115,z]`, scale `[3.04,1.31,.035]`, `metal`;
* vent mushrooms: `z = -6..6` in steps of `4` — box `[0,4.79,z]`, scale `[.52,.17,.86]`, `metal`.

Side (`side = ±1`):

* moldings `[side*1.464, 1.78, 0]` `[.025,.055,length]` and `[side*1.464, 3.92, 0]` `[.025,.045,length]`, `brass`;
* lower corrugations: `y = 1.27 .. <1.7` in steps of `.105` — `[side*1.462, y, 0]`, scale `[.022,.025,length-.2]`, colour `[.19,.25,.26]`;
* windows, `w = 0 .. (loco?3:7)-1`, `z = loco ? 6 + w*1.15 : (w-3)*3`:
  * `lit = ((variant*7 + w)*7919) % 11 > 2` (the same predicate is used for the window glow sprites);
  * window trim `[side*1.475, 3.05, z]` `[.045,1.24,1.83]`, `brass`;
  * frame `[side*1.503, 3.05, z]` `[.025,1.08,1.66]`, `dark`;
  * glass `[side*1.522, 3.05, z]` `[.012,.94,1.51]`, colour `lit ? [.94,.62,.29] : [.07,.13,.19]`, **emission `lit ? .62 : .02`**;
  * if `lit` — a curtain `[side*1.533, 3.05, z-.57]`, `[.01,.94, (w%3===0)?.56:.24]`, colour `[.28,.20,.14]`, emission `.25`;
  * posts/handrails: `[side*1.544, 3.05, z]` `[.022,1.0,.032]`, `[side*1.544, 3.37, z]` `[.022,.032,1.5]`, `[side*1.55, 2.47, z]` `[.14,.065,1.9]` — all `metal`;
* side ends, `end = ±1`, `z = end*(length/2 - 1)`:
  * `[side*1.47, 2.5, z]` `[.025,2.65,1.3]` `dark`;
  * `[side*1.49, 2.5, z]` `[.022,2.50,1.18]` `[.14,.21,.22]`;
  * `[side*1.514, 3.13, z]` `[.02,.77,.69]` `[.11,.16,.19]`;
  * `[side*1.56, 2.23, z+.4]` `[.07,.10,.21]` `brass`;
  * steps `y = 1 .. <1.5` in steps of `.22`: `[side*1.62, y, z]` `[.38,.065,1.28]` `metal`;
  * handrail `[side*1.59, 2.34, z-.78]` `[.065,1.75,.055]` `brass`.

Car ends (`end = ±1`):

* gangway bellows `[0, 2.5, end*(length/2+.2)]`, scale `[1.65, 2.5, .4]`, `dark`;
* 5 ribs `z = 0..4`: `[0, 2.5, end*(length/2+.08 + z*.105)]`, scale `[1.75, 2.6, .04]`, `metal`;
* coupler `[0, .76, end*(length/2+.45)]`, scale `[.32,.25,.9]`, `metal`;
* bogie `bogie = end*length*.33`: box `[0, .64, bogie]` `[2.65,.48,3.6]` `dark`;
* axles `axle = ±1`: `[0, .48, bogie + axle*1.15]` `[2.75,.17,.17]` `metal`;
  * wheels: `wheelMesh()` at `[side*1.20, .46, …]` scale `[.22,.91,.91]` colour `[.21,.23,.24]`; and an inner disc `[side*1.34, .46, …]` scale `[.05,.33,.33]` `brass`.
  * **The wheels are part of the car's static mesh and do not rotate** — the demo has no separate wheel-spin animation.

Additionally, for the locomotive (`loco = true`):

* windshield `[0, 3.35, length/2+.015]`, scale `[2.2,.75,.06]`, colour `[.29,.39,.41]`, emission `.15`;
* stack `[0, 4.9, -3]`, scale `[.6,.65,.7]`, `dark`;
* grille `i = 0..7`: `[-1.48, 2.8, -5 + i*.65]`, scale `[.04,.72,.12]`, `dark`.

### 3.5 Glowing parts of the cars

* Window glass: emission `.62` (lit) / `.02` (dark); curtain `.25`.
* Window billboards (see §4.5) — for non-locomotives only: `side = ±1`, `w = 0..6`, the point in local coordinates `(side*1.75, 3.05, (w-3)*3)`, sprite radius `2.8`, colour `(1.0, 0.67, 0.32)`, alpha `0.14`; the skip condition is the same: `((i%3)*7 + w)*7919 % 11 <= 2`.
* Locomotive headlights are billboards (see §4.5); the locomotive's "glass" geometry itself also has emission `.15`.

---

## 4. Environment

### 4.1 Ground

Mesh: `buildGrid(96, 120, xFrom=0, xTo=1, yFrom=-1, yTo=1)` — a `96×120` grid (97×121 vertices, 96*120*2 triangles), attribute `aGrid = (x: 0..1 along the path, y: -1..1 across)`.

The vertex shader builds the world around the camera:

```
t     = aGrid.x
ahead = pow(t, 2.2) * 1250.0 - 330.0      // from -330 to +920 m relative to uS
s     = uS + ahead
side  = sign(g.y) * pow(abs(g.y), 1.7) * 430.0
x     = trackX(s) + side
p     = (x, terrain(x, s), s)
```

The normal is a central difference over the grid parameters:

```
px = groundPoint(aGrid + (0.0015, 0.0))
pz = groundPoint(aGrid + (0.0, 0.004))
n  = normalize(cross(pz - p, px - p));  if (n.y < 0) n = -n;
```

(the shader declares an unused `float e = 2.2;` — dead code).

Grass colour:

```
wet   = smoothstep(0.0, 26.0, abs(p.x - trackX(p.z)))
grass = mix(vec3(0.105,0.125,0.108), vec3(0.070,0.092,0.120), wet)   // grass → wet slope
blotch = fbm(vec2(p.x, p.z) * 0.03)
grass *= 0.75 + blotch * 0.6
```

For the ground `vEmissive = 0`.

### 4.2 The rail track

Mesh: `buildGrid(420, 7, 0, 1, 0, 7)`, but indices are assembled only between row pairs `(0,1)`, `(2,3)`, `(4,5)`, `(6,7)` — four independent "ribbons"; adjacent lanes must not be joined, otherwise the gap between the rails gets filled in. That is 420 segments per ribbon.

Vertex shader:

```
t    = aGrid.x
s    = uS - 330.0 + pow(t, 1.9) * 1100.0     // from uS-330 to uS+770
lane = int(aGrid.y)
```

| `lane` | What | `off` | `h` | RGB colour |
|---|---|---|---|---|
| 0 | left embankment shoulder | -4.6 | `trackY(s) - 0.62` | (0.085, 0.078, 0.070) |
| 1 | right embankment shoulder | +4.6 | `trackY(s) - 0.62` | (0.085, 0.078, 0.070) |
| 2 | left rail, inner thread | -0.79 | `trackY(s) - 0.02` | (0.38, 0.40, 0.44) |
| 3 | left rail, outer thread | -0.65 | `trackY(s) - 0.02` | (0.38, 0.40, 0.44) |
| 4 | right rail, inner thread | +0.65 | `trackY(s) - 0.02` | (0.38, 0.40, 0.44) |
| 5 | right rail, outer thread | +0.79 | `trackY(s) - 0.02` | (0.38, 0.40, 0.44) |
| 6 | contact wire | -0.14 | `trackY(s) + 5.15 - sag` | (0.10, 0.10, 0.11) |
| 7 | contact wire | +0.14 | `trackY(s) + 5.15 - sag` | (0.10, 0.10, 0.11) |

Wire sag: `span = 44.0`, `k = fract(s/span)`, `sag = sin(k*π)*0.9`.

Conversion to world: `yaw = trackYaw(s)`, `x = trackX(s) + off*cos(yaw)`, `z = s - off*sin(yaw)`, the normal is always `(0,1,0)` (a flat ribbon), `vEmissive = 0`. `CULL_FACE` is disabled for this pass.

### 4.3 Instances (sleepers, poles, trees, village, rocks)

A single shader `instProg`, attributes `aPos`, `aNormal`, uniforms `uKind`, `uStep`, `uStart`, `uS`. Common basis: `id = float(gl_InstanceID)`.

**`uKind = 0` — sleepers.** `s = floor((uS + uStart)/uStep)*uStep + id*uStep`; `yaw = trackYaw(s)`; scale `(2.7, 0.16, 0.28)`; rotation about `Y` by `yaw`: `p = (p.x*c + p.z*sn, p.y, -p.x*sn + p.z*c)` (same for the normal); translation `+ (trackX(s), trackY(s) - 0.30, s)`; colour `(0.070, 0.058, 0.048)`.
Draw call: `step = 0.62`, `start = -200`, `count = 620` (a span of ≈ 384 m), `boxVao`.

**`uKind = 1` — catenary poles.** The same `s` formula; scale `(0.16, 5.4, 0.16)`; translation `+ (trackX(s) - 6.4, trackY(s) + 2.65, s)`; colour `(0.055, 0.052, 0.050)`.
Call: `step = 44.0`, `start = -260`, `count = 30`, `boxVao`.

**`uKind = 2/3/4` — trees.** `cell = floor((uS + uStart)/uStep) + id`; `r1 = hash21(vec2(cell, 3.7))`, `r2 = hash21(vec2(cell, 9.1))`, `r3 = hash21(vec2(cell, 17.3))`; `s = cell*uStep + r1*uStep`; `side = (r2 < 0.5 ? -1 : 1) * (13.0 + pow(r3, 1.5)*210.0)`; `x = trackX(s) + side`; `ground = terrain(x, s)`; `scale = 0.85 + hash21(vec2(cell, 24.7))*1.9`.

* `uKind = 2` — trunk: scale `(0.24*scale, 5.0*scale, 0.24*scale)`, translation `(x, ground + 2.5*scale, s)`, colour `(0.035, 0.030, 0.028)`, mesh `boxVao`.
* `uKind = 3` — lower crown tier: scale `(4.2*scale, 7.8*scale, 4.2*scale)`, translation `(x, ground + 4.7*scale, s)`, colour `mix(vec3(0.055,0.095,0.080), vec3(0.105,0.155,0.125), r1)`, mesh `pineVao`.
* `uKind = 4` — upper tier (it exists in the shader but is not called in the draw list): scale `(1.9*scale, 3.4*scale, 1.9*scale)`, translation `(x, ground + 5.4*scale + 1.5*scale, s)`, colour `mix(vec3(0.063,0.105,0.087), vec3(0.12,0.17,0.14), r1)`.

Call: `treeCount = (quality==='low') ? 600 : 1000`; `start = -320`; `step = (quality==='low') ? 1.8 : 1.1`; kind 2 — `boxVao`, kind 3 — `pineVao`.

**`uKind = 5` — catenary cross-beams and hangers.** `cell = floor((uS+uStart)/uStep) + floor(id/2)`; `s = cell*uStep`; an even `id` — a cross-beam: scale `(6.65, .10, .10)`, translation `(trackX(s) - 3.2, trackY(s) + 5.3, s)`; an odd one — a hanger: scale `(.065, .55, .065)`, translation `(trackX(s), trackY(s) + 5.0, s)`; colour `(.18, .20, .21)`.
Call: `step = 44.0`, `start = -260`, `count = 60`, `boxVao`.

**`uKind = 6/7` — rocks and grass by the embankment.** `cell = floor((uS+uStart)/uStep) + id`; `r = hash21(vec2(cell,4.21))`, `r2 = hash21(vec2(cell,8.71))`; `s = cell*uStep + r*uStep`; `x = trackX(s) + (r < .5 ? -1 : 1)*(5.4 + r2*30.0)`.

* `uKind = 6` — rocks: scale `(.4+r2, .16+r*.6, .3+r2)`, colour `(.17,.19,.22)`, translation `(x, terrain(x,s) + .14, s)`, mesh `boxVao`, parameters `step = 2`, `start = -160`, `count = 300`.
* `uKind = 7` — grass: scale `(.24+r*.3, .5+r2*.9, .24)`, colour `mix(vec3(.09,.14,.10), vec3(.22,.23,.15), r)`, translation `(x, terrain(x,s) + .25, s)`, mesh `coneVao`, `step = .30`, `start = -140`, `count = 1600`; not drawn when `quality === 'low'`.

**`uKind = 8/9/10/11` — the village (fixed in world coordinates).** `cell = floor((uS+uStart)/uStep) + floor(id/5)`; `house = mod(id, 5)`; `r = hash21(vec2(cell, house + 23.0))`; `s = cell*uStep + (house - 2.0)*17.0`; `side = hash21(vec2(cell,71.0)) < .5 ? -1 : 1`; `x = trackX(s) + side*(48.0 + r*44.0)`; `y = terrain(x, s)`; `width = 4.3 + r*2.5`, `height = 2.6 + r*1.4`, `depth = 5.5 + r*3.0`.

* `uKind = 8` — house: scale `(width, height, depth)`, translation `(x, y + height*.5, s)`, colour `mix(vec3(.20,.19,.18), vec3(.30,.24,.20), r)`, `boxVao`.
* `uKind = 9` — roof: scale `(width*1.15, 1.8, depth*1.15)`, translation `(x, y + height + .9, s)`, colour `(.13,.16,.18)`, `gableVao`.
* `uKind = 10` — glowing window: scale `(.85,.85,.03)`, translation `(x + .7, y + height*.55, s - depth*.5 - .025)`, colour `(.95,.56,.22)`, **`emissive = 1.4`**, `boxVao`.
* `uKind = 11` — chimney: scale `(.48,1.8,.48)`, translation `(x - width*.25, y + height + 1.1, s + 1.1)`, colour `(.20,.16,.14)`, `boxVao`.
* Calls for all four: `step = 240`, `start = -480`, `count = 35`.

### 4.4 Sky

A full-screen triangle (vertices via `gl_VertexID`: `p = ((id<<1)&2, id&2)`, `vNdc = p*2-1`, `gl_Position = (vNdc, 1, 1)`), depth is not written (`depthMask(false)`), colour is always written. The ray is reconstructed via `uInvVP`:

```
far = uInvVP * vec4(vNdc, 1, 1)
dir = normalize(far.xyz / far.w - uCam)
h   = clamp(dir.y, -1, 1)
```

Base colours: `top = (0.014, 0.020, 0.052)`, `mid = (0.045, 0.061, 0.126)`, `low = (0.150, 0.135, 0.190)`.

```
col = h > 0.18 ? mix(mid, top, smoothstep(0.18, 0.85, h))
               : mix(low, mid, smoothstep(-0.05, 0.18, h))
```

Milky Way: `axis = normalize(0.62, 0.42, -0.66)`; `band = 1 - abs(dot(dir, axis))`; `core = smoothstep(0.80, 1.0, band)`; `q = dir*7.0`; 4 octaves `cloud += amp*vnoise3(q); q *= 2.07; amp *= 0.52`, starting from `amp = 0.62`; `milky = core*(0.25 + cloud*0.95)*smoothstep(-0.02, 0.22, h)`; `col += vec3(0.10, 0.108, 0.150)*milky`.

Sky hash/noise:

```glsl
float hash31(vec3 p){
  p = fract(p * 0.3183 + vec3(0.71, 0.113, 0.419));
  p *= 17.0;
  return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
// vnoise3 — trilinear interpolation of hash31 over the 8 cube corners
// with the smoothing f = f*f*(3-2f)
```

Moon (direction `uMoonDir`): `md = dot(dir, uMoonDir)`;

```
col += vec3(0.55, 0.62, 0.85) * pow(max(md,0), 420.0) * 0.32     // narrow disc
col += vec3(0.24, 0.29, 0.45) * pow(max(md,0),  14.0) * 0.30     // wide halo
if (md > 0.99965) {
    e     = smoothstep(0.99965, 0.99985, md)
    maria = vnoise3(dir * 320.0)
    col   = mix(col, vec3(0.90, 0.93, 0.88) * (0.8 + maria*0.2), e)
}
```

Clouds/haze at the horizon: `cloudP = dir*5.0 + vec3(uTime*0.0015, 0, 0)`; `clouds = smoothstep(0.50, 0.78, vnoise3(cloudP)*0.7 + vnoise3(cloudP*2.7)*0.3)`; `col = mix(col, vec3(0.105,0.135,0.19), clouds*0.42*smoothstep(0.02,0.23,h))`.

Joining with the fog and "mountain ridges":

```
col = mix(col, uFogColor, 1 - smoothstep(-0.06, 0.16, h))
az   = atan(dir.x, dir.z)
ridge      = 0.025 + sin(az*7.0)*0.015      + sin(az*17.0 + 2.0)*0.009
col = mix(col, vec3(0.060,0.087,0.128), 1 - smoothstep(ridge, ridge + 0.004, h))
nearRidge  = 0.008 + sin(az*11.0 + 1.0)*0.011
col = mix(col, uFogColor, 1 - smoothstep(nearRidge, nearRidge + 0.003, h))
```

`vnoise3` is value noise over a 3D grid with the `hash31` hash, needed to prevent the clouds from looking "cubic".

### 4.5 Glow sprites (luminous billboards)

Constant `MAX_GLOW = 440`. Three dynamic arrays of `MAX_GLOW` elements: position (vec3), parameters (vec4: `radius, r, g, b`), alpha (float). `addGlow(x,y,z,radius,r,g,b,alpha)` silently ignores overflow.

Instanced mesh: a quad of 6 vertices `(-1,-1),(1,-1),(1,1),(-1,-1),(1,1),(-1,1)`; the instance position has divisor 1. Vertex shader:

```
world = iPos + (uRight*aCorner.x + uUp*aCorner.y) * iParam.x
```

where `uRight`, `uUp` are the camera's screen axes (see below), and `iParam.x` is the radius. Fragment: `d = length(vUv)`; `if (d > 1.0) discard`; `a = pow(1.0 - d, 2.6) * vAlpha`; output `vec4(vTint * a, a)`.

Blending is additive (`blendFunc(ONE, ONE)`), depth is not written (`depthMask(false)`), there is no sorting (additivity makes order irrelevant).

Screen axes (the same for stars and glow) with `fwd = dir`:

```
rgt = normalize((fwd.z, 0, -fwd.x))
up  = cross(rgt, fwd)
```

Rules for spawning sprites (in frame draw order):

1. **Car windows.** For each non-locomotive `i`, `side = ±1`, `w = 0..6`; skip when `((i%3)*7 + w)*7919 % 11 <= 2`; the local point `(side*1.75, 3.05, (w-3)*3)` is transformed into world space by the car matrix; `radius = 2.8`, colour `(1.0, 0.67, 0.32)`, alpha `0.14`.
2. **Locomotive headlights** (only when `state.headOn`): `yaw = trackYaw(sHead)`, `rx = cos(yaw)`, `rz = -sin(yaw)`; for `k = ±1`: the point `(headPos.x + rx*k, headPos.y, headPos.z + rz*k)`, two sprites — `radius 2.2, colour (1.0,0.93,0.75), alpha 0.95` and `radius 7.0, colour (1.0,0.88,0.62), alpha 0.32`; plus a marker `(headPos.x, headPos.y+1.5, headPos.z)`, `radius 1.2, colour (1.0,0.85,0.55), alpha 0.55`.
3. **Light cone in the air** (only when `state.headOn`): `i = 1..9`, `d = i*7.5`, `fs = sHead + d`; the point `(trackX(fs), trackY(fs)+1.2, fs)`, `radius = 2.0 + d*0.30`, colour `(1.0,0.86,0.62)`, `alpha = 0.055*(1 - i/11)`.
4. **Motes/sparks** — one per particle, see §6.2.
5. **Track signals**: `i = 0..7`, `gs = (floor(s/176) - 2 + i)*176`; two points at `(trackX(gs)-6.4, trackY(gs)+3.8, gs)`: `radius .26, colour (.30,1.0,.57), alpha .9` and `radius 1.2, colour (.20,1.0,.43), alpha .18`.
6. **Fireflies**: `i = 0..27`, `cell = floor(s/8) - 8 + i`, `gs = cell*8`, `side = -12 - sin(cell*6.3)*5`, `blink = pow(max(0, sin(t*0.75 + cell*3.1)), 3)`; the point `(trackX(gs) + side, trackY(gs) + 1.1 + sin(cell)*0.7, gs)`, `radius .28`, colour `(.73,.95,.37)`, `alpha = blink*0.26`.
7. **Smoke** — one per particle, see §6.1.

Maximum estimate: 14 non-locomotives × 14 windows + 14 (headlights) + 70 (dust) + 16 (signals) + 28 (fireflies) + 44 (smoke) = 368 < 440.

### 4.6 Stars

`STARS = 1100`. Directions are generated once by a deterministic LCG: `seed = 7`, step `seed = (seed*1103515245 + 12345) & 0x7fffffff`, `rnd() = seed / 0x7fffffff`.

```
u = rnd(); v = rnd()
theta = u * 2π
y     = pow(v, 0.75)                       // bias towards the zenith
r     = sqrt(max(0, 1 - y*y))
dir   = (cos(theta)*r, y, sin(theta)*r)
w     = 0.40 + pow(rnd(), 2) * 0.85        // brightness: many faint, a few bright
```

Vertex shader (instances, a 6-vertex quad):

```
tw    = 0.72 + 0.28*sin(uTime*(0.6 + fract(iDir.w*13.0)*2.2) + iDir.w*40.0)
low   = smoothstep(-0.04, 0.16, iDir.y)     // at the horizon they drown in haze
vAlpha = iDir.w * tw * low
vTint  = mix(vec3(0.78,0.85,1.0), vec3(1.0,0.90,0.76), fract(iDir.w*31.0))
size   = 0.75 + iDir.w * 2.0
world  = uCam + iDir.xyz*900.0 + (uRight*aCorner.x + uUp*aCorner.y)*size
```

Fragment: `if (d > 1.0) discard`; `core = pow(1-d, 3.5)`; `halo = pow(1-d, 1.2)*0.22`; `a = (core + halo)*vAlpha`; output `vec4(vTint*a, a)`, additive blending.

### 4.7 Vignette

Not a shader but a DOM element `#vignette` with `pointer-events:none; z-index:2`:

```css
background: radial-gradient(120% 90% at 50% 45%,
            rgba(0,0,0,0) 55%, rgba(0,0,0,.55) 100%);
```

---

## 5. Lighting and post-processing

### 5.1 Moon direction

```js
const moonDir = normalize([0.42, 0.36, 0.83])
// |v| = 0.99745 → (0.42107, 0.36092, 0.83212)
```

`moonDir` is a uniform of every pass (except glow) and of the sky shader.

### 5.2 The common fragment shader `FS_COMMON`

Used by the ground, the track, the instances and the cars. Uniforms: `uCam`, `uMoonDir`, `uHeadPos`, `uHeadDir`, `uHeadOn`, `uFogColor`, `uFogDensity`, `uWin[10]`, `uWinCount`.

```glsl
N    = normalize(vNormal)
V    = uCam - vWorld
dist = length(V)

// hemispherical ambient: cold sky above, almost black below
sky     = N.y*0.5 + 0.5
ambient = mix(vec3(0.065,0.079,0.110), vec3(0.22,0.27,0.36), sky)

// the moon: diffuse light + a narrow specular highlight
Vn   = V / max(dist, 0.001)
moon = max(dot(N, uMoonDir), 0.0)
Hv   = normalize(uMoonDir + Vn)
spec = pow(max(dot(N, Hv), 0.0), 48.0)
light = ambient
      + vec3(0.40,0.47,0.66) * moon * 1.15
      + vec3(0.55,0.62,0.82) * spec * 0.55

// locomotive headlight beam
L = uHeadPos - vWorld
ld = length(L); L /= max(ld, 0.001)
cone    = smoothstep(0.955, 0.995, dot(-L, uHeadDir))
atten   = 1.0 / (1.0 + 0.0022 * ld * ld)
lambert = max(dot(N, L), 0.0)
light += vec3(1.0,0.87,0.66) * cone * atten * lambert * 26.0 * uHeadOn

// light from car windows onto the embankment and grass (up to 10 sources)
for (int i = 0; i < 10; i++){
  if (float(i) >= uWinCount) break;
  WL   = uWin[i] - vWorld
  wd2  = dot(WL, WL)
  watt = 1.0 / (1.0 + wd2*0.055)
  light += vec3(1.0,0.70,0.36) * watt * max(dot(N, normalize(WL)), 0.0) * 1.25
}

// procedural surface "grain" (non-emissive and nearby only)
grain = fract(sin(dot(floor(vWorld.xz*18.0), vec2(12.9898,78.233))) * 43758.5453)
textureAmount = (1.0 - step(0.01, vEmissive)) * (1.0 - smoothstep(15.0, 100.0, dist))
col = vColor * light * (1.0 - textureAmount*grain*0.12) + vColor*vEmissive

// tonemapping (soft compression, "Reinhard-like")
col = col / (vec3(1.0) + col*0.38)

// fog
f   = 1.0 - exp(-pow(dist * uFogDensity, 2.0))
col = mix(col, uFogColor, clamp(f, 0.0, 1.0))
fragColor = vec4(col, 1.0)
```

Constants: `uFogColor = (0.055, 0.068, 0.115)`, `uFogDensity = 0.0026`.

Typical fog values `f = 1-exp(-(0.0026·d)²)`: at 100 m — 0.065; 300 m — 0.456; 500 m — 0.815; 1000 m — 0.999.

### 5.3 Light sources coming from JS

* `uHeadPos`, `uHeadDir`, `uHeadOn` — the headlights (see §3.5/§6.3).
* `uWin[10]` — 10 pools of warm light, filled every frame: for `i = 0..9`, `ws = state.s - 120 + i*42`, `yaw = trackYaw(ws)`:
  ```
  uWin[i] = ( trackX(ws) - 2.4*cos(yaw),
              trackY(ws) + 2.9,
              ws + 2.4*sin(yaw) )
  ```
  `uWinCount = 10` (the shader loop still caps at 10; the array is declared with 10, the JS buffer is 30 floats).
* `moonDir`, `fogColor`, `fogDensity` — see above.

There are no other sources: no shadows, no point lamps, no SSAO. No shadows are cast at all.

### 5.4 GL state and pass order

Frame order:

1. `clearColor(fogColor); clear(COLOR|DEPTH)`; `enable(DEPTH_TEST)`, `depthFunc(LEQUAL)`, `enable(CULL_FACE)`, `disable(BLEND)`.
2. **Sky**: `depthMask(false)`, `drawArrays(TRIANGLES, 0, 3)`.
3. **Stars**: still `depthMask(false)`; `enable(BLEND)`, `blendFunc(ONE,ONE)`, `drawArraysInstanced(..., STARS)`; then `disable(BLEND)`.
4. `depthMask(true)`.
5. **Ground**: `groundVao`, `drawElements`.
6. **Track**: `disable(CULL_FACE)`, `trackVao`, `drawElements`, `enable(CULL_FACE)`.
7. **Instances** (order as in §4.3): sleepers, poles, trees (trunk + crowns), cross-beams, then `[rocks, grass, houses, roofs, windows, chimneys]`.
8. **Cars**: `meshProg`, one `drawElements` per car (the mesh is chosen by `i%3`, or the locomotive), while the glow list is filled in parallel.
9. **Glow**: `depthMask(false)`, `enable(BLEND)`, `blendFunc(ONE,ONE)`, `drawArraysInstanced(..., glowCount)`, `depthMask(true)`, `disable(BLEND)`.
10. `bindVertexArray(null)`; the next frame is scheduled.

Tonemapping and fog are in the shader; there are no separate post passes/FBOs. Rendering goes straight to the default framebuffer.

---

## 6. Animation and particles

### 6.1 Smoke from the locomotive stack

44 particles (`smoke`), initially `{ life: Math.random() }`.

Per frame:

```
emitS = headCenterS - 3                      // headCenterS = carS(CARS-1) + CAR_LEN*0.5
for each particle:
    life += dt * 0.30                       // lifetime exactly 1/0.30 ≈ 3.33 s
    if life > 1:
        life = 0; s = emitS; side = (rand-0.5)*0.5; rise = 0; seed = rand
    if s === undefined:                     // first frame
        s = emitS - rand*60; side = 0; seed = rand
    rise = life * 7.5                        // rises up to 7.5 m
    back = life * 46                         // drifts back up to 46 m
    ps   = s - back
    px   = trackX(ps) + side + sin(seed*12 + life*3) * life * 3.5
    py   = trackY(ps) + 4.6 + rise
    a    = max(0, 0.30 * (1 - life) * min(1, life*6))     // fast attack, linear decay
    addGlow(px, py, ps, 2.0 + life*11, 0.62, 0.63, 0.70, a)
```

New particles are not spawned on a timer: a pool of 44 works, each one restarting once `life = 1`. The resulting rate is about `44 / 3.33 ≈ 13.2` particles/s. The sprite radius grows from 2.0 to 13.0 m, the colour is grey-smoky `(0.62, 0.63, 0.70)`, alpha up to 0.30.

### 6.2 Motes and sparks

70 particles (`motes`). Initialization:

```
ds    = rand*90 - 30            // offset along the path relative to the camera, m
side  = (rand - 0.5)*9          // lateral offset
up    = rand*5 - 1.4
r     = 0.035 + rand*0.13       // sprite radius
warm  = rand < 0.28             // 28 % warm sparks, 72 % cold dust
drift = (rand - 0.5)*1.6
seed  = rand*10
```

Per frame:

```
ds -= state.speed * dt * (0.85 + seed*0.03)
if ds < -26:  ds += 110; side = (rand-0.5)*9; up = rand*5 - 1.4
ms     = s + ds
yaw    = trackYaw(ms)
wobble = sin(t*3.1 + seed*6) * drift
mx     = trackX(ms) + (-3.1 + side*0.55 + wobble) * cos(yaw)
mz     = ms          - (-3.1 + side*0.55 + wobble) * sin(yaw)
my     = trackY(ms) + 2.2 + up
near   = 1 - min(1, abs(ds)/26)                      // brighter near the camera
warm: addGlow(mx,my,mz, r*2.4, 1.0, 0.80, 0.52, 0.22*near)
otherwise: addGlow(mx,my,mz, r*2.0, 0.72, 0.80, 0.95, 0.12*near)
```

The dust "flies backwards" relative to the camera at the speed of the train (a particle catches up/overtakes thanks to `0.85 + seed*0.03`), and is recycled over the distance range `[-26, +84]` m.

### 6.3 Locomotive, headlights, beam

```
headCenterS = carS(CARS-1) + CAR_LEN*0.5          // centre of the locomotive
headYaw     = trackYaw(headCenterS)
sHead       = headCenterS + 9.92*cos(headYaw)
headPos     = ( trackX(headCenterS) + 9.92*sin(headYaw),
                trackY(headCenterS) + 1.6,
                sHead )
headDir     = normalize( sin(headYaw), -0.075, cos(headYaw) )
```

`9.92` is the headlight's forward offset from the locomotive centre (slightly less than the half-width 19.7/2 = 9.85 plus margin). The headlights/beam are toggled by the "Фары" checkbox (`state.headOn`, default `true`) and affect both the shader lighting (§5.2) and the glow sprites (§4.5).

### 6.4 Rocking, camera roll, shake

* The car rolls on a curve via `trackRoll(cs)` (amplitude ±0.09 rad).
* Camera: `sway` (turn) and `bob` (vertical rocking) — formulas in §1.3; both fade to zero when the "Покачивание" checkbox is cleared.
* An additional "breathing" lateral drift: `sin(t*0.31)*0.12` m (also only with `motion`).
* Smoothing of `lean` towards `leanTarget`: `min(1, dt*2.8)`; `yaw`/`pitch` towards their targets: `min(1, dt*7)`; `autoLook` targets: `min(1, dt*1.4)`.

### 6.5 Wheel rotation

Absent. The wheels are part of the static `carriageMesh`; there is no instanced spin animation. The train's motion is conveyed only by the shift in `state.s` and by the world "rushing" towards the camera.

### 6.6 Speeds

`state.speed` in m/s: 16 «Не спеша» (57.6 km/h), 24.5 «Обычная» (88.2 km/h, the default), 32 «Экспресс» (115.2 km/h). Initial position `state.s = 110`.

---

## 7. Sound

A completely procedural WebAudio graph (no files). It is built lazily on the first press of "звук".

### 7.1 Noise buffer

Duration 2 s, one channel, `sampleRate` from the AudioContext. Brownian-like noise:

```
last = 0
for i = 0..len-1:
    w = Math.random()*2 - 1
    last = (last + 0.02*w) / 1.02
    d[i] = last * 3.2
```

### 7.2 The graph

```
master (Gain, 0 → ramp) → destination

wind:
  noiseBuffer(loop) → BiquadFilter(bandpass, freq=480, Q=0.55) → wind Gain(0.42) → master
  LFO: Oscillator(sine, 0.09 Hz) → Gain(0.14) → wind.gain   (additive modulation)

running rumble:
  noiseBuffer(loop) → BiquadFilter(lowpass, freq=200) → Gain(0.30) → master

wheel clatter:
  wheels Gain(1) → master
```

`setInterval(schedule, 200)` is started after the graph is built.

### 7.3 The clatter scheduler

`schedule` every 200 ms (when `on`, `ac.state === 'running'`, and the tab is visible):

```
nextClack = max(nextClack, ac.currentTime + 0.025)
wind.gain.setTargetAtTime(0.12 + state.lean*0.30, ac.currentTime, 0.3)
windFilter.frequency.setTargetAtTime(240 + state.lean*280, ac.currentTime, 0.3)

period = 25 / max(4, state.speed)          // a rail joint every 25 m
bogie  = min(0.22, 3.4 / max(4, state.speed))   // spread between the bogies

while (nextClack < ac.currentTime + 0.5):
    t = nextClack
    clack(t, 1.0)
    clack(t + bogie, 0.7)
    clack(t + period*0.45, 0.85)
    clack(t + period*0.45 + bogie, 0.6)
    nextClack += period
```

That is, four hits per joint: the main one, one after `bogie`, and the same pair shifted by `0.45` of a period (the second bogie/second rail).

### 7.4 Synthesis of a single hit

```
clack(t, power):
    tt = t + (rand - 0.5)*0.012           // phase jitter ±6 ms
    v  = power * (0.9 + rand*0.2)
    hit(tt,          1.30*v, 'lowpass',  130, 1.2, 0.18)
    hit(tt + 0.004,  0.55*v, 'bandpass', 300, 1.1, 0.10)
    hit(tt + 0.002,  0.30*v, 'bandpass', 1500, 1.4, 0.05)

hit(t, gain, type, freq, q, decay):
    source: noiseBuffer(loop), starts at a random offset rand*1.5 s
    filter: BiquadFilter(type, freq, Q=q)
    gain envelope:
        setValueAtTime(0.0001, t)
        exponentialRampToValueAtTime(gain, t + 0.005)
        exponentialRampToValueAtTime(0.0001, t + decay)
    stop(t + decay + 0.05), nodes disconnect on onended
```

### 7.5 Turning on/off

`toggle()`: build the graph, `await ac.resume()`, flip `on`, `nextClack = currentTime + 0.1`, then `master.gain.cancelScheduledValues(ct)` and `linearRampToValueAtTime(on ? 0.5 : 0.0001, ct + (on ? 1.6 : 0.9))`. `visibility()`: when the tab is hidden, `ac.suspend()`; on return (if `on`), `ac.resume()` and reset `nextClack`.

---

## 8. UI/controls

### 8.1 Elements

| Element | Type | Initial state | Action |
|---|---|---|---|
| `#btnSound` | button | text «звук», `aria-pressed=false` | toggle sound; text «звук вкл» / «звук»; class `on` |
| `#btnLean` | button | `aria-pressed=true`, text «у окна» | `leanTarget = leanTarget ? 0 : 1`; text «у окна» / «выглянуть» |
| `#btnLook` | button | — | `autoLook = true`, `pitchTarget = -0.02` (a wide view along the consist) |
| `#btnSettings` | button | «ещё», `aria-expanded=false` | open/close the `#settings` panel (toggles `hidden`) |
| `#quality` | `<select>` | `auto` | `Автоматически` / `Максимум` / `Экономно` → `state.quality`; resets `frameMs=16.7`, `frames=0`, calls `resize()` |
| `#speed` | `<select>` | `24.5` (`selected`) | `Не спеша = 16`, `Обычная = 24.5`, `Экспресс = 32` (m/s) → `state.speed` |
| `#motion` | `<input type=checkbox>` | `checked`, forced to `!prefers-reduced-motion` | `state.motion` — camera rocking/shake |
| `#btnLamp` | `<input type=checkbox>` | `checked` | `state.headOn` — headlights, beam and glow sprites |
| `#btnFullscreen` | button | hidden if `requestFullscreen` is unavailable | enter/exit fullscreen; text «на весь экран» / «свернуть экран» |

Help text in the panel: «Кнопка «у окна» придвигает тебя к вагону. «Выглянуть» возвращает широкий вид вдоль состава.»

### 8.2 Hotkeys and gestures

* Dragging on the canvas — look around (see §1.6), with pointer capture; only the primary pointer counts.
* Arrows on the canvas (`tabindex=0`) — stepped look-around.
* `Escape` — close the settings panel (and return focus to `#btnSettings`).
* Any `pointerdown` on the canvas closes the settings and disables `autoLook`.
* `#hud` dims (`opacity:.58`, class `dim`) after 7 s without `pointerdown`/`focusin` events inside the HUD and on the buttons; on hover/focus (`:hover`, `:focus-within`) it becomes fully opaque again.
* The `#hint` hint disappears after 12 s or on the first manual look-around.
* `visibilitychange`: cancel rAF, `state.last = 0`, reset the active pointer, pause/resume audio; when visibility returns — a new `requestAnimationFrame`.
* `webglcontextlost`: `preventDefault()`, stop rAF, show the message «Графика приостановлена браузером…».

### 8.3 Styling

* Background `#05060d`; text colour `#f0e2d0`; font `ui-rounded, -apple-system, "Segoe UI", Roboto, sans-serif`.
* Canvas `position:fixed; inset:0; width:100%; height:100%`.
* Buttons: pills (`border-radius:999px`), `min-height:46px`, translucent background, `backdrop-filter: blur(8px)`, active state (`on`) — warm orange `rgba(255,168,88,.2)`.
* Settings panel: `width:min(340px, 100% - 28px)`, background `#10151ef2`, `backdrop-filter: blur(14px)`.
* `@media (prefers-reduced-motion: reduce)` disables all CSS transitions.
* The state value is exposed: `window.__train3d = state`.
* An initialization failure shows `#err` with the text «Не удалось запустить поезд…»; missing WebGL2 — «Здесь нужен WebGL2…».

---

## 9. Numeric constants — summary table

### Track

| Constant | Value | Meaning |
|---|---|---|
| `TRACK.a1` | 58.0 | amplitude of the 1st harmonic of `trackX`, m |
| `TRACK.f1` | 0.00840 | frequency of the 1st harmonic of `trackX`, rad/m |
| `TRACK.a2` | 13.0 | amplitude of the 2nd harmonic of `trackX`, m |
| `TRACK.f2` | 0.02150 | frequency of the 2nd harmonic of `trackX`, rad/m |
| `TRACK.p2` | 1.3 | phase of the 2nd harmonic of `trackX`, rad |
| `TRACK.b1` | 3.4 | amplitude of the 1st harmonic of `trackY`, m |
| `TRACK.g1` | 0.00625 | frequency of the 1st harmonic of `trackY`, rad/m |
| `TRACK.b2` | 1.6 | amplitude of the 2nd harmonic of `trackY`, m |
| `TRACK.g2` | 0.015625 | frequency of the 2nd harmonic of `trackY`, rad/m |
| `TRACK.q2` | 0.7 | phase of the 2nd harmonic of `trackY`, rad |
| `trackDX` amplitudes | 0.4872 and 0.2795 | derivatives of `trackX` |
| `trackDY` amplitudes | 0.02125 and 0.025 | derivatives of `trackY` |
| `trackRoll` step `h` | 6 | half-step of the numerical derivative, m |
| `trackRoll` gain | 260 | `curve*260` |
| `trackRoll` limit | ±0.09 | roll, rad |

### Train

| Constant | Value | Meaning |
|---|---|---|
| `CAR_LEN` | 24.0 | car length, m |
| `CAR_GAP` | 2.6 | gap between cars, m |
| `CAR_W` | 2.9 | car width, m |
| `CAR_H` | 4.0 | loading-gauge height, m; **declared in the source but never used** — the geometry sets a body of 3.0 at centre y=2.6 |
| `CARS_BEHIND` | 5 | cars behind the camera |
| `CARS_AHEAD` | 10 | cars ahead (including the locomotive) |
| `CARS` | 15 | total units |
| `carIndexToS` offset | `-14.88` | `-CAR_LEN*0.62` |
| `carIndexToS` step | `26.6` | `CAR_LEN + CAR_GAP` |
| locomotive length | 19.7 | m |
| palette `brass` | (.49,.35,.18) | brass parts |
| palette `metal` | (.13,.17,.20) | metal |
| palette `dark` | (.027,.042,.052) | dark parts |
| body colour (car) | (.12,.20,.22) | |
| body colour (locomotive) | (.12,.19,.20) | |
| window emission (lit / dark) | .62 / .02 | |
| curtain emission | .25 | |
| locomotive windshield emission | .15 | |
| window glow | radius 2.8, colour (1.0,.67,.32), alpha .14 | |
| `9.92` | headlight offset from the locomotive centre, m | |
| `headPos.y` | `trackY + 1.6` | headlight height |

### Camera

| Constant | Value | Meaning |
|---|---|---|
| `state.s` (start) | 110 | initial position, m |
| `state.speed` | 24.5 (options 16 / 24.5 / 32) | m/s |
| `state.yaw` / `pitch` (start) | 0 / -0.02 | rad |
| `yawTarget` limits | [-2.9, 0.65] | manual look-around |
| `pitchTarget` limits | [-0.95, 1.10] | manual look-around |
| pointer sensitivity | `k = 2.6/max(360, min(W,H))`, `dy*k*0.8` | |
| arrow step | yaw ±0.11, pitch ±0.08 | |
| `fovy` | 1.12 (landscape) / 1.20 (portrait) | rad |
| near / far | 0.15 / 1500 | m |
| camera height | `trackY(s) + 3.05 + bob` | |
| `sideOffset` lean=1 / lean=0 | -4.60 / -2.15 | m |
| `sway` amplitudes | 0.022 (1.9 Hz) + 0.008 (3.7 Hz) | rad |
| `bob` amplitudes | 0.018 (5.3 Hz) + 0.016 (2.6 Hz) | m |
| lateral drift | `sin(t*0.31)*0.12` | m |
| `lean` smoothing | `min(1, dt*2.8)` | |
| `yaw/pitch` smoothing | `min(1, dt*7)` | |
| `autoLook` smoothing | `min(1, dt*1.4)` | |
| `autoLook` `want` limits | [-0.95, 0.45] | rad |
| `autoLook` pitch | 0.012 | rad |
| `autoLook` target | `carS(11)` + 4.2 m sideways | |
| `renderScale` start/min/max | 1.5 / 0.85 / 1.75 | |
| `renderScale` correction | ±0.15 when `frameMs>24`, ±0.10 when `<18`, every 3000 ms | |
| `dt` limit | 0.10 | s |

### Environment

| Constant | Value | Meaning |
|---|---|---|
| `groundVao` grid | 96 × 120, x 0..1, y -1..1 | ground grid |
| `ahead` | `pow(t,2.2)*1250 - 330` | longitudinal span: -330..+920 m |
| `side` | `sign(y)*pow(abs(y),1.7)*430` | lateral span: ±430 m |
| `trackGrid` | 420 × 7, 4 ribbons (0-1, 2-3, 4-5, 6-7) | track mesh |
| track `s` | `uS - 330 + pow(t,1.9)*1100` | -330..+770 m |
| embankment shoulder | off ±4.6, h `trackY-0.62` | |
| rails | off ∓0.79 / ∓0.65, h `trackY-0.02` | |
| wire | off ±0.14, h `trackY+5.15-sag` | |
| wire `span` | 44.0 | m |
| `sag` max | 0.9 | m |
| `terrain` hills | amplitudes 34.0 and 4.5, frequencies 0.0042 and 0.021 | m |
| `terrain` smoothstep | 9.0 → 46.0 | m from the track |
| `terrain` bed | `trackY(z) - 0.9` | m |
| `fbm` | 4 octaves, `p *= 2.03`, `amp *= 0.5` | |
| `MAX_GLOW` | 440 | sprite limit |
| `STARS` | 1100 | star count |
| star LCG | seed 7, `*1103515245 + 12345`, mask `0x7fffffff` | |
| star sphere radius | 900 | m |
| sleepers | step 0.62, start -200, count 620 | |
| poles | step 44.0, start -260, count 30, side -6.4, y +2.65 | |
| trees | count 1000 (low: 600), step 1.1 (low: 1.8), start -320 | |
| trees, side | `±(13.0 + r3^1.5 * 210.0)` | m |
| trees, scale | `0.85 + hash*1.9` | |
| cross-beams/hangers | step 44, start -260, count 60 | |
| rocks | step 2, start -160, count 300 | |
| grass | step 0.30, start -140, count 1600 (absent in low) | |
| village, houses | step 240, start -480, count 35 | |
| village, side | `±(48.0 + r*44.0)` | m |
| village windows | emission 1.4, colour (.95,.56,.22) | |
| signals | 8, step 176 m, side -6.4, y +3.8 | |
| fireflies | 28, cell 8 m, side `-12 - sin(cell*6.3)*5` | |
| `winLights` | 10, step 42 m, start `s-120`, side -2.4, y +2.9 | |

### Lighting / post

| Constant | Value | Meaning |
|---|---|---|
| `fogColor` | (0.055, 0.068, 0.115) | fog colour and clear colour |
| `uFogDensity` | 0.0026 | fog density |
| `moonDir` (raw) | (0.42, 0.36, 0.83) → normalized | direction to the moon |
| ambient low / high | (0.065,0.079,0.110) / (0.22,0.27,0.36) | hemispherical ambient |
| moonlight | (0.40,0.47,0.66), multiplier 1.15 | |
| moon specular | (0.55,0.62,0.82), exponent 48, multiplier 0.55 | |
| headlights (colour) | (1.0, 0.87, 0.66), multiplier 26.0 | |
| headlight cone | `smoothstep(0.955, 0.995, dot(-L, uHeadDir))` | |
| headlight attenuation | `1/(1 + 0.0022*ld²)` | |
| windows as light | (1.0,0.70,0.36), `1/(1+wd2*0.055)`, ×1.25 | |
| grain | `fract(sin(dot(floor(world.xz*18), (12.9898,78.233)))*43758.5453)`, ×0.12 | |
| tonemapping | `col / (1 + 0.38*col)` | |
| sky top / mid / low | (0.014,0.020,0.052) / (0.045,0.061,0.126) / (0.150,0.135,0.190) | |
| Milky Way axis | `normalize(0.62, 0.42, -0.66)` | |
| vignette CSS | `radial-gradient(120% 90% at 50% 45%, transparent 55%, rgba(0,0,0,.55) 100%)` | |

### Cloud/haze pattern of the sky

| Constant | Value | Meaning |
|---|---|---|
| `dir*7.0` | 7.0 | Milky Way frequency |
| cloud octaves | 4, `q *= 2.07`, `amp *= 0.52`, start 0.62 | |
| moon disc | exponent 420, ×0.32, colour (0.55,0.62,0.85) | |
| moon halo | exponent 14, ×0.30, colour (0.24,0.29,0.45) | |
| moon limb | `md > 0.99965`, `vnoise3(dir*320)`, colour (0.90,0.93,0.88) | |
| horizon haze | `dir*5 + (uTime*0.0015,0,0)`, colour (0.105,0.135,0.19), ×0.42 | |

### Particles and animation

| Constant | Value | Meaning |
|---|---|---|
| `smoke` count | 44 | smoke particles |
| `smoke` life rate | 0.30 /s | full cycle ≈ 3.33 s |
| `smoke` rise | `life*7.5` | m |
| `smoke` drift back | `life*46` | m back |
| `smoke` radius | `2.0 + life*11` | m |
| `smoke` alpha | `0.30*(1-life)*min(1, life*6)` | |
| `motes` count | 70 | dust particles |
| `motes` `ds` init | `rand*90 - 30` | m |
| `motes` window | `ds < -26 → ds += 110` | m |
| `motes` side | `(rand-0.5)*9` | m |
| `motes` up | `rand*5 - 1.4` | m |
| `motes` radius | `0.035 + rand*0.13` | |
| `motes` warm fraction | 0.28 | |
| `motes` drift | `(rand-0.5)*1.6` | |

### Sound

| Constant | Value | Meaning |
|---|---|---|
| noise buffer | 2 s, `last=(last+0.02w)/1.02`, `×3.2` | |
| wind | bandpass 480 Hz, Q 0.55, gain 0.42 | |
| wind LFO | 0.09 Hz, gain 0.14 | |
| rumble | lowpass 200 Hz, gain 0.30 | |
| master | 0 → 0.5 over 1.6 s; → 0.0001 over 0.9 s | |
| clatter period | `25 / max(4, speed)` s | a joint every 25 m |
| `bogie` | `min(0.22, 3.4 / max(4, speed))` s | |
| scheduler interval | 200 ms | `setInterval` |
| scheduling window | `currentTime + 0.5` s | |
| wind from lean | gain `.12 + lean*.30`, freq `240 + lean*280` | |
| clack low | lowpass 130 Hz, Q 1.2, gain 1.30v, decay 0.18 s | |
| clack mid | bandpass 300 Hz, Q 1.1, gain 0.55v, decay 0.10 s | |
| clack high | bandpass 1500 Hz, Q 1.4, gain 0.30v, decay 0.05 s | |
| clack jitter | ±0.012 s | |
| gain `v` | `power*(0.9 + rand*0.2)` | |

---

## Appendix A. Source map

| Lines | Subsystem |
|---|---|
| 1–95 | HTML markup and CSS (canvas, `#vignette`, `#journey`, `#hint`, `#hud`, `#settings`, `#err`) |
| 97–113 | IIFE wrapper, `'use strict'`, error handler, WebGL2 initialization |
| 115–168 | `M4`: `ident`, `mul`, `perspective`, `lookAt`, `rigid` |
| 170–185 | `TRACK`, `trackX/Y/DX/DY/Yaw/Roll` |
| 187–219 | `GLSL_TRACK`: `trackX/Y/Yaw`, `hash21`, `vnoise`, `fbm`, `terrain` |
| 221–284 | `FS_COMMON` (ambient, moon, headlights, windows, grain, tonemapping, fog) |
| 286–308 | `compile`, `program` |
| 310–398 | Sky shader (`skyProg`) |
| 400–435 | Ground shader (`groundProg`) |
| 437–485 | Track shader (`trackProg`) |
| 487–576 | Instance shader (`instProg`, kinds 0–11) |
| 578–596 | Mesh shader (`meshProg`) |
| 598–626 | Glow shader (`glowProg`) |
| 628–661 | Star shader (`starProg`) |
| 663–693 | `buildGrid`, `makeVao2` |
| 695–747 | `boxMesh`, `coneMesh`, `makeMeshVao` |
| 749–791 | Assembly of `groundVao`, `trackVao` (ribbons), `boxVao`, `coneVao`, `pineMesh`/`pineVao`, `gableMesh`/`gableVao` |
| 793–827 | `MAX_GLOW` and the glow buffers/VAO |
| 829–859 | `STARS`, LCG, `starVao` |
| 861–867 | `addGlow` |
| 869–899 | `CAR_LEN/GAP/W/H`, `coloredBuilder` |
| 900–931 | `roofMesh`, `wheelMesh` |
| 932–990 | Palettes, `carriageMesh`, `carMeshes`, `locoMesh` |
| 991–996 | `CARS_BEHIND/AHEAD/CARS`, `carIndexToS`, `carS` |
| 998–1026 | `state`, the `smoke` and `motes` arrays |
| 1028–1061 | `fogColor`, `moonDir`, `resize`, `winLights`, `setCommon` |
| 1063–1103 | `frame`: dt/quality, `s` advance, camera, locomotive/`headPos`/`headDir` |
| 1105–1134 | `autoLook`, angle smoothing, `dir`/`center`, `proj`/`view`/`vp` |
| 1136–1145 | Filling `winLights` |
| 1147–1206 | Resetting GL, sky, stars, ground, track |
| 1208–1243 | Drawing instances (all kinds) |
| 1245–1272 | Drawing cars and window glow |
| 1274–1291 | Locomotive headlights and the light cone |
| 1293–1310 | Motes/sparks |
| 1312–1323 | Track signals and fireflies |
| 1325–1346 | Smoke |
| 1348–1383 | Drawing glow and finishing the frame |
| 1385–1416 | `invert` (4×4) |
| 1418–1530 | The audio graph (`makeNoise`, `build`, `hit`, `clack`, `schedule`, `toggle`, `visibility`) |
| 1532–1619 | Controls: pointer, keyboard, buttons, settings, fullscreen, visibility, context loss |
| 1618–1623 | `window.__train3d`, starting rAF, closing the IIFE |
