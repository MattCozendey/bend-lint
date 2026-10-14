*[English](../reference-demo-spec.md) | Русский*

# Спецификация демо «Ночной поезд — из окна»

Инженерный референс для повторной реализации внешнего вида и поведения в другом языке/движке.
Источник: `notes/personal/2026-07-24-nochnoy-poezd-3d.html` (1623 строки, один файл: HTML + CSS + IIFE-`<script>` в `'use strict'`). Контекст WebGL2 создаётся как `canvas.getContext('webgl2', {antialias:true, alpha:false, powerPreference:'high-performance'})`; при отсутствии WebGL2 показывается текстовое сообщение об ошибке поверх страницы.

Ниже все формулы и константы выписаны точно по исходнику. Числа, помеченные как производные (например `58.0*0.00840 = 0.4872`), — арифметика, которую делает движок; их можно вычислять на старте.

## Соглашения о координатах и времени

* Правая система координат, `y` — вверх.
* Параметр пути `s` измеряется в метрах и **одновременно является мировой координатой `z`**: точка осевой линии пути `= (trackX(s), trackY(s), s)`. `trackX` — боковое смещение, `trackY` — высота.
* Курс `yaw = atan2(dx/ds, 1)` — поворот вокруг оси `Y` от `+Z` к `+X`. Локальная ось `+Z` объекта направлена вперёд (в сторону роста `s`), локальная ось `+X` — вбок и равна `(cos yaw, 0, -sin yaw)`.
* Любая точка «с боковым смещением `off`» строится как `x = trackX(s) + off*cos(yaw)`, `z = s - off*sin(yaw)`.
* Мировое время `t = state.t` накапливается как `t += dt`, `dt = min(elapsed_ms/1000, 0.10)`.
* Продвижение вдоль пути: `state.s += state.speed * dt`.

---

## 1. Общая сцена и камера

### 1.1 Что видит зритель

Ночной пейзаж снаружи идущего поезда. Камера висит сбоку от состава, примерно на высоте окна (`trackY(s)+3.05`), и смещена вбок от осевой линии пути. Слева/справа проходит поезд: за камерой — хвост из 5 вагонов, впереди — 9 вагонов и локомотив последним (`CARS_BEHIND = 5`, `CARS_AHEAD = 10`, всего `CARS = 15`). Вокруг — ночной лес, холмы, заснеженная/травяная насыпь, две нити рельсов, шпалы, столбы контактной сети с проводами, редкие деревни с горящими окнами; над головой — звёздное небо с Млечным Путём и луной. Из окон вагонов на насыпь падают тёплые пятна света, у локомотива горят фары. Мимо лица проносятся пылинки/искры, из трубы локомотива валит дым. По краям экрана — CSS-виньетка (не шейдер).

DOM-оверлеи: `#journey` («Ночной экспресс» / «лес спит, а мы едем дальше»), `#hint` («веди пальцем, чтобы оглядеться», гаснет через 12 с), `#hud` (кнопки), `#settings` (панель настроек), `#vignette`, `#err`.

### 1.2 Мировые матрицы

Реализованы вручную (модуль `M4`), column-major (как в WebGL).

`M4.ident` — единичная.

`M4.mul(a,b)` — произведение `a*b` (по столбцам, как в исходнике).

`M4.perspective(fovy, aspect, near, far)`:

```
f  = 1 / tan(fovy/2)
nf = 1 / (near - far)
[f/aspect, 0, 0,             0,
 0,        f, 0,             0,
 0,        0, (far+near)*nf, -1,
 0,        0, 2*far*near*nf, 0]
```

`M4.lookAt(eye, center, up)` — стандартный: `z = normalize(eye-center)`, `x = normalize(cross(up,z))`, `y = cross(z,x)`, трансляция `-(x·eye, y·eye, z·eye)`.

`M4.rigid(px,py,pz,yaw,roll,sx,sy,sz)` — модель вагона `T(p) * Ry(yaw) * Rz(roll) * S(sx,sy,sz)`:

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

### 1.3 Позиция и ориентация камеры

Для каждого кадра, при `s = state.s` и `baseYaw = trackYaw(s)`:

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

Итого боковое смещение камеры: `-4.60` м при `lean = 1` («у окна») и `-2.15` м при `lean = 0` («выглянуть»); при `motion` добавляется медленное «дыхание» амплитудой 0.12 м.

Направление взгляда:

```
lookYaw   = baseYaw + state.yaw + sway*0.35
lookPitch = state.pitch + sway*0.1
dir = ( sin(lookYaw)*cos(lookPitch),
        sin(lookPitch),
        cos(lookYaw)*cos(lookPitch) )
center = cam + dir
```

Матрицы кадра:

```
proj = perspective(fovy, W/H, 0.15, 1500)
fovy = (W < H) ? 1.20 : 1.12          // радианы: 68.8° в портрете, 64.2° в ландшафте
view = lookAt(cam, center, (0,1,0))
vp   = proj * view
```

Обратная матрица `invVP = invert(vp)` используется только шейдером неба (полноэкранный треугольник). Реализован развёрнутый 4×4-инвертор; при нулевом детерминанте возвращается единичная матрица.

### 1.4 Сглаживание и целевые углы

```
state.yaw   += (state.yawTarget   - state.yaw)   * min(1, dt*7)
state.pitch += (state.pitchTarget - state.pitch) * min(1, dt*7)
```

Начальные значения: `state.yaw = 0`, `state.pitch = -0.02`, `state.yawTarget = 0`, `state.pitchTarget = -0.02`.

### 1.5 Режим «вперёд» (`autoLook`)

Включён по умолчанию (`state.autoLook = true`). Пока он включён, каждый кадр:

```
aimS   = carS(CARS_BEHIND + round((CARS_AHEAD-1)*0.62))
       = carS(5 + round(5.58)) = carS(11)
aimYaw = trackYaw(aimS)
aimX   = trackX(aimS) + 4.2*cos(aimYaw)
aimZ   = aimS         - 4.2*sin(aimYaw)
want   = atan2(aimX - camX, aimZ - camZ) - baseYaw
want   приводится к (-π, π]
want   = clamp(want, -0.95, 0.45)
state.yawTarget   += (want - state.yawTarget)   * min(1, dt*1.4)
state.pitchTarget += (0.012 - state.pitchTarget)* min(1, dt*1.4)
```

То есть камера доворачивается не на локомотив, а на точку на 62 % пути к нему, иначе состав уходит за край кадра.

Любое ручное управление (перетаскивание или стрелки) сбрасывает `autoLook = false` и прячет подсказку `#hint`. Кнопка «смотреть вперёд» включает `autoLook` обратно и ставит `pitchTarget = -0.02`.

### 1.6 Ручное управление взглядом

* Перетаскивание пальцем/мышью (`pointerdown`/`pointermove` с захватом указателя) — только первичный указатель:
  ```
  k = 2.6 / max(360, min(innerWidth, innerHeight))
  yawTarget   = clamp(yawTarget   - dx*k,     -2.9,  0.65)
  pitchTarget = clamp(pitchTarget + dy*k*0.8, -0.95, 1.10)
  ```
* Клавиатура (canvas имеет `tabindex=0`): `ArrowLeft → (+0.11, 0)`, `ArrowRight → (-0.11, 0)`, `ArrowUp → (0, +0.08)`, `ArrowDown → (0, -0.08)`, где пара — приращение `(Δyaw, Δpitch)` в тех же границах.

### 1.7 Разрешение и адаптивное качество

```
cap  = (quality==='high') ? 2 : (quality==='low') ? 1 : state.renderScale
dpr  = min(devicePixelRatio || 1, cap)
W = round(innerWidth * dpr);  H = round(innerHeight * dpr)
canvas.width = W; canvas.height = H; gl.viewport(0,0,W,H)
```

`state.renderScale` (только режим `auto`) стартует с `1.5`, раз в 3000 мс корректируется по сглаженному времени кадра `state.frameMs` (EMA с коэффициентом 0.025):

* `frameMs > 24` → `renderScale = max(0.85, renderScale - 0.15)`;
* `frameMs < 18` → `renderScale = min(1.75, renderScale + 0.10)`.

Кадр пропускается, если вкладка скрыта или потерян WebGL-контекст (`state.last = 0`, без rAF).

---

## 2. Путь (track)

Одна и та же формула задаёт и мир, и камеру, и подвижной состав. В JS — функции от `s`, продублированные в GLSL строкой `GLSL_TRACK` (с теми же числами, подставленными через `toFixed`).

### 2.1 Константы `TRACK`

```js
const TRACK = { a1: 58.0, f1: 0.00840, a2: 13.0, f2: 0.02150, p2: 1.3,
                b1: 3.4,  g1: 0.00625, b2: 1.6,  g2: 0.015625, q2: 0.7 };
```

| Поле | Значение | Смысл |
|---|---|---|
| `a1` | 58.0 | амплитуда 1-й гармоники бокового смещения, м |
| `f1` | 0.00840 | пространственная частота 1-й гармоники, рад/м |
| `a2` | 13.0 | амплитуда 2-й гармоники бокового смещения, м |
| `f2` | 0.02150 | частота 2-й гармоники, рад/м |
| `p2` | 1.3 | фаза 2-й гармоники бокового смещения, рад |
| `b1` | 3.4 | амплитуда 1-й гармоники высоты, м |
| `g1` | 0.00625 | частота 1-й гармоники высоты, рад/м |
| `b2` | 1.6 | амплитуда 2-й гармоники высоты, м |
| `g2` | 0.015625 | частота 2-й гармоники высоты, рад/м |
| `q2` | 0.7 | фаза 2-й гармоники высоты, рад |

Периоды гармоник: `2π/f1 ≈ 748.0` м, `2π/f2 ≈ 292.2` м, `2π/g1 ≈ 1005.3` м, `2π/g2 ≈ 402.1` м. Дуга намеренно крутая: на длине состава путь уводит вбок на десятки метров, иначе из окна виден только соседний вагон.

### 2.2 Формулы JS

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

`trackDY` используется только как справочная производная (в кадре напрямую не вызывается); `trackRoll` даёт крен на дуге, ограниченный ±0.09 рад (≈±5.16°).

### 2.3 GLSL-версия `GLSL_TRACK`

Подставляя `toFixed(3)` / `toFixed(6)`, строка разворачивается ровно в такой текст (проверено по исходнику):

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

Важно: `GLSL_TRACK` не содержит `trackDX`, `trackDY` и `trackRoll` как отдельных функций — производная бокового смещения вписана прямо в `trackYaw`, а `trackDY` в шейдерах вообще не нужен. `terrain` есть **только в GLSL** — в JavaScript аналога нет, JS-код высоту земли не считает.

`terrain(x,z)`: у самой насыпи (`d < 9` м) высота равна `trackY(z)-0.9`, затем плавно (smoothstep 9→46 м) переходит к холмам: два октавных FBM с частотами 0.0042 и 0.021 и амплитудами 34 и 4.5 м.

---

## 3. Поезд

### 3.1 Размеры и числа

```js
const CAR_LEN = 24.0, CAR_GAP = 2.6, CAR_W = 2.9, CAR_H = 4.0;
const CARS_BEHIND = 5, CARS_AHEAD = 10;
const CARS = CARS_BEHIND + CARS_AHEAD;          // 15
```

### 3.2 Размещение вагонов

```
carIndexToS(i) = state.s - CAR_LEN*0.62 + i*(CAR_LEN + CAR_GAP)
               = state.s - 14.88 + i*26.6
carS(i)        = carIndexToS(i - CARS_BEHIND) = state.s - 14.88 + (i-5)*26.6
```

Центр вагона `i` в кадре:

```
cs    = carS(i) + CAR_LEN*0.5        // = carS(i) + 12
yaw   = trackYaw(cs)
roll  = trackRoll(cs)
model = M4.rigid(trackX(cs), trackY(cs), cs, yaw, roll, 1, 1, 1)
mesh  = (i === CARS-1) ? locoMesh : carMeshes[i % 3]
isLoco = (i === CARS-1)              // i = 14 — локомотив впереди
```

Диапазон `s` составa при `state.s = 110`: от `110 - 147.88 = -37.88` (хвост) до `110 + 224.52 = 334.52` (центр локомотива). Варианты окраски чередуются по `i % 3` (три меша `carriageMesh(0/1/2)`).

### 3.3 Меши

Все меши — процедурные, строятся один раз.

* `boxMesh()` — единичный куб от -0.5 до +0.5, 6 граней, плоские нормали.
* `coneMesh(seg=7)` — конус: основание радиуса 0.5, вершина `y=+0.5`, основание `y=-0.5`, плоские нормали `(nx,0.35,nz)`.
* `pineMesh()` — «ёлка» из 5 ярусов; для яруса `tier = 0..4`: `radius = 0.5 - tier*0.087`, `bottom = -0.5 + tier*0.18`, `height = 0.49 - tier*0.025`, 10 сегментов, радиус с рябью `r = radius*(1 + sin(i*19.7 + tier)*0.14)`; нормаль `(cos((a+b)/2), radius/height, sin((a+b)/2))`, нормированная.
* `gableMesh()` — треугольная призма (крыша дома) с вершинами `a=(-.5,-.5,-.5)`, `b=(.5,-.5,-.5)`, `c=(0,.5,-.5)`, `d=(-.5,-.5,.5)`, `e=(.5,-.5,.5)`, `f=(0,.5,.5)`; 6 треугольников `[[a,c,b],[d,e,f],[a,d,f],[a,f,c],[b,c,f],[b,f,e]]`, нормали — векторное произведение рёбер.
* `roofMesh()` — полуцилиндр-арка: `i = 0..12`, `a = i/12*π`, точка `(cos a * 0.5, sin a * 0.5, z)` для `z = ±0.5`, плюс две торцевые «заглушки».
* `wheelMesh()` — цилиндр вдоль оси `X`: 14 сегментов, радиус 0.5, длина 1 (от `x=-0.5` до `x=+0.5`), с боковинами-дисками.
* `coloredBuilder()` — сборочный буфер: метод `add(mesh, at, scale, color, emissive=0, rotateX=0)`, где позиция масштабируется и поворачивается вокруг `X`, нормаль делится на масштаб (`n/scale`) и нормируется, цвет и эмиссия пишутся по вершинам; `box(at,scale,color,emissive)` — частный случай куба. `finish()` собирает VAO с атрибутами: 0 — позиция (vec3), 1 — нормаль (vec3), 2 — цвет (vec3), 3 — эмиссия (float). Бросает исключение, если вершин больше 65535 (индексы `Uint16`).

### 3.4 Конструкция вагона (`carriageMesh(variant, loco=false)`)

Общие параметры: `length = loco ? 19.7 : 24.0`; `paint = loco ? [.12,.19,.20] : [.12,.20,.22]`.
Палитра: `brass = [.49,.35,.18]`, `metal = [.13,.17,.20]`, `dark = [.027,.042,.052]`.

Корпус и крыша:

* коробка корпуса `[0, 2.6, 0]`, масштаб `[CAR_W=2.9, 3.0, length]`, цвет `paint` (корпус занимает `y` от 1.1 до 4.1);
* рама `[0, 1.04, 0]`, масштаб `[2.8, .28, length]`, `dark`;
* крыша-арка `roofMesh()` в `[0, 4.1, 0]`, масштаб `[3.02, 1.3, length+.12]`, цвет `[.21,.25,.28]`;
* рёбра крыши: для `z` от `-length/2+1` до `< length/2` шагом `2.2` — `roofMesh()` в `[0,4.115,z]`, масштаб `[3.04,1.31,.035]`, `metal`;
* вентиляционные грибки: `z = -6..6` шагом `4` — коробка `[0,4.79,z]`, масштаб `[.52,.17,.86]`, `metal`.

Борт (`side = ±1`):

* молдинги `[side*1.464, 1.78, 0]` `[.025,.055,length]` и `[side*1.464, 3.92, 0]` `[.025,.045,length]`, `brass`;
* гофры низа: `y = 1.27 .. <1.7` шагом `.105` — `[side*1.462, y, 0]`, масштаб `[.022,.025,length-.2]`, цвет `[.19,.25,.26]`;
* окна, `w = 0 .. (loco?3:7)-1`, `z = loco ? 6 + w*1.15 : (w-3)*3`:
  * `lit = ((variant*7 + w)*7919) % 11 > 2` (тот же предикат используется для glow-спрайтов окна);
  * наличник `[side*1.475, 3.05, z]` `[.045,1.24,1.83]`, `brass`;
  * рама `[side*1.503, 3.05, z]` `[.025,1.08,1.66]`, `dark`;
  * стекло `[side*1.522, 3.05, z]` `[.012,.94,1.51]`, цвет `lit ? [.94,.62,.29] : [.07,.13,.19]`, **эмиссия `lit ? .62 : .02`**;
  * если `lit` — занавеска `[side*1.533, 3.05, z-.57]`, `[.01,.94, (w%3===0)?.56:.24]`, цвет `[.28,.20,.14]`, эмиссия `.25`;
  * стойки/поручни: `[side*1.544, 3.05, z]` `[.022,1.0,.032]`, `[side*1.544, 3.37, z]` `[.022,.032,1.5]`, `[side*1.55, 2.47, z]` `[.14,.065,1.9]` — все `metal`;
* торцы борта, `end = ±1`, `z = end*(length/2 - 1)`:
  * `[side*1.47, 2.5, z]` `[.025,2.65,1.3]` `dark`;
  * `[side*1.49, 2.5, z]` `[.022,2.50,1.18]` `[.14,.21,.22]`;
  * `[side*1.514, 3.13, z]` `[.02,.77,.69]` `[.11,.16,.19]`;
  * `[side*1.56, 2.23, z+.4]` `[.07,.10,.21]` `brass`;
  * ступеньки `y = 1 .. <1.5` шагом `.22`: `[side*1.62, y, z]` `[.38,.065,1.28]` `metal`;
  * поручень `[side*1.59, 2.34, z-.78]` `[.065,1.75,.055]` `brass`.

Торцы вагона (`end = ±1`):

* гармошка `[0, 2.5, end*(length/2+.2)]`, масштаб `[1.65, 2.5, .4]`, `dark`;
* 5 рёбер `z = 0..4`: `[0, 2.5, end*(length/2+.08 + z*.105)]`, масштаб `[1.75, 2.6, .04]`, `metal`;
* сцепка `[0, .76, end*(length/2+.45)]`, масштаб `[.32,.25,.9]`, `metal`;
* тележка `bogie = end*length*.33`: коробка `[0, .64, bogie]` `[2.65,.48,3.6]` `dark`;
* оси `axle = ±1`: `[0, .48, bogie + axle*1.15]` `[2.75,.17,.17]` `metal`;
  * колёса: `wheelMesh()` в `[side*1.20, .46, …]` масштаб `[.22,.91,.91]` цвет `[.21,.23,.24]`; и внутренний диск `[side*1.34, .46, …]` масштаб `[.05,.33,.33]` `brass`.
  * **Колёса входят в статический меш вагона и не вращаются** — отдельной анимации вращения колёс в демо нет.

Дополнительно для локомотива (`loco = true`):

* лобовое стекло `[0, 3.35, length/2+.015]`, масштаб `[2.2,.75,.06]`, цвет `[.29,.39,.41]`, эмиссия `.15`;
* труба `[0, 4.9, -3]`, масштаб `[.6,.65,.7]`, `dark`;
* решётка `i = 0..7`: `[-1.48, 2.8, -5 + i*.65]`, масштаб `[.04,.72,.12]`, `dark`.

### 3.5 Светящиеся части вагонов

* Стёкла окон: эмиссия `.62` (зажжено) / `.02` (погашено); занавеска `.25`.
* Билборды окон (см. §4.5) — только для не-локомотивов: `side = ±1`, `w = 0..6`, точка в локальных координатах `(side*1.75, 3.05, (w-3)*3)`, спрайт радиуса `2.8`, цвет `(1.0, 0.67, 0.32)`, альфа `0.14`; условие пропуска то же: `((i%3)*7 + w)*7919 % 11 <= 2`.
* Фары локомотива — билборды (см. §4.5); сама геометрия «стекла» у локомотива тоже имеет эмиссию `.15`.

---

## 4. Окружение

### 4.1 Земля

Меш: `buildGrid(96, 120, xFrom=0, xTo=1, yFrom=-1, yTo=1)` — сетка `96×120` (97×121 вершин, 96*120*2 треугольников), атрибут `aGrid = (x: 0..1 вдоль пути, y: -1..1 поперёк)`.

Вершинный шейдер строит мир вокруг камеры:

```
t     = aGrid.x
ahead = pow(t, 2.2) * 1250.0 - 330.0      // от -330 до +920 м относительно uS
s     = uS + ahead
side  = sign(g.y) * pow(abs(g.y), 1.7) * 430.0
x     = trackX(s) + side
p     = (x, terrain(x, s), s)
```

Нормаль — центральная разность по параметрам сетки:

```
px = groundPoint(aGrid + (0.0015, 0.0))
pz = groundPoint(aGrid + (0.0, 0.004))
n  = normalize(cross(pz - p, px - p));  if (n.y < 0) n = -n;
```

(в шейдере объявлена неиспользуемая `float e = 2.2;` — мёртвый код).

Цвет травы:

```
wet   = smoothstep(0.0, 26.0, abs(p.x - trackX(p.z)))
grass = mix(vec3(0.105,0.125,0.108), vec3(0.070,0.092,0.120), wet)   // трава → мокрый откос
blotch = fbm(vec2(p.x, p.z) * 0.03)
grass *= 0.75 + blotch * 0.6
```

У земли `vEmissive = 0`.

### 4.2 Рельсовый путь

Меш: `buildGrid(420, 7, 0, 1, 0, 7)`, но индексы собираются только между парами строк `(0,1)`, `(2,3)`, `(4,5)`, `(6,7)` — четыре независимые «ленты»; соединять соседние полосы нельзя, иначе затянется зазор между рельсами. Итого 420 сегментов на ленту.

Вершинный шейдер:

```
t    = aGrid.x
s    = uS - 330.0 + pow(t, 1.9) * 1100.0     // от uS-330 до uS+770
lane = int(aGrid.y)
```

| `lane` | Что | `off` | `h` | Цвет RGB |
|---|---|---|---|---|
| 0 | левая бровка насыпи | -4.6 | `trackY(s) - 0.62` | (0.085, 0.078, 0.070) |
| 1 | правая бровка насыпи | +4.6 | `trackY(s) - 0.62` | (0.085, 0.078, 0.070) |
| 2 | левый рельс, внутр. нить | -0.79 | `trackY(s) - 0.02` | (0.38, 0.40, 0.44) |
| 3 | левый рельс, внеш. нить | -0.65 | `trackY(s) - 0.02` | (0.38, 0.40, 0.44) |
| 4 | правый рельс, внутр. нить | +0.65 | `trackY(s) - 0.02` | (0.38, 0.40, 0.44) |
| 5 | правый рельс, внеш. нить | +0.79 | `trackY(s) - 0.02` | (0.38, 0.40, 0.44) |
| 6 | контактный провод | -0.14 | `trackY(s) + 5.15 - sag` | (0.10, 0.10, 0.11) |
| 7 | контактный провод | +0.14 | `trackY(s) + 5.15 - sag` | (0.10, 0.10, 0.11) |

Провис провода: `span = 44.0`, `k = fract(s/span)`, `sag = sin(k*π)*0.9`.

Пересчёт в мир: `yaw = trackYaw(s)`, `x = trackX(s) + off*cos(yaw)`, `z = s - off*sin(yaw)`, нормаль всегда `(0,1,0)` (плоская лента), `vEmissive = 0`. Для этого прохода `CULL_FACE` выключается.

### 4.3 Инстансы (шпалы, столбы, деревья, деревня, камни)

Один шейдер `instProg`, атрибуты `aPos`, `aNormal`, униформы `uKind`, `uStep`, `uStart`, `uS`. Общий базис: `id = float(gl_InstanceID)`.

**`uKind = 0` — шпалы.** `s = floor((uS + uStart)/uStep)*uStep + id*uStep`; `yaw = trackYaw(s)`; масштаб `(2.7, 0.16, 0.28)`; поворот вокруг `Y` на `yaw`: `p = (p.x*c + p.z*sn, p.y, -p.x*sn + p.z*c)` (так же для нормали); сдвиг `+ (trackX(s), trackY(s) - 0.30, s)`; цвет `(0.070, 0.058, 0.048)`.
Вызов отрисовки: `step = 0.62`, `start = -200`, `count = 620` (охват ≈ 384 м), `boxVao`.

**`uKind = 1` — столбы контактной сети.** Та же формула `s`; масштаб `(0.16, 5.4, 0.16)`; сдвиг `+ (trackX(s) - 6.4, trackY(s) + 2.65, s)`; цвет `(0.055, 0.052, 0.050)`.
Вызов: `step = 44.0`, `start = -260`, `count = 30`, `boxVao`.

**`uKind = 2/3/4` — деревья.** `cell = floor((uS + uStart)/uStep) + id`; `r1 = hash21(vec2(cell, 3.7))`, `r2 = hash21(vec2(cell, 9.1))`, `r3 = hash21(vec2(cell, 17.3))`; `s = cell*uStep + r1*uStep`; `side = (r2 < 0.5 ? -1 : 1) * (13.0 + pow(r3, 1.5)*210.0)`; `x = trackX(s) + side`; `ground = terrain(x, s)`; `scale = 0.85 + hash21(vec2(cell, 24.7))*1.9`.

* `uKind = 2` — ствол: масштаб `(0.24*scale, 5.0*scale, 0.24*scale)`, сдвиг `(x, ground + 2.5*scale, s)`, цвет `(0.035, 0.030, 0.028)`, меш `boxVao`.
* `uKind = 3` — нижний ярус кроны: масштаб `(4.2*scale, 7.8*scale, 4.2*scale)`, сдвиг `(x, ground + 4.7*scale, s)`, цвет `mix(vec3(0.055,0.095,0.080), vec3(0.105,0.155,0.125), r1)`, меш `pineVao`.
* `uKind = 4` — верхний ярус (в шейдере есть, но в списке отрисовки не вызывается): масштаб `(1.9*scale, 3.4*scale, 1.9*scale)`, сдвиг `(x, ground + 5.4*scale + 1.5*scale, s)`, цвет `mix(vec3(0.063,0.105,0.087), vec3(0.12,0.17,0.14), r1)`.

Вызов: `treeCount = (quality==='low') ? 600 : 1000`; `start = -320`; `step = (quality==='low') ? 1.8 : 1.1`; вид 2 — `boxVao`, вид 3 — `pineVao`.

**`uKind = 5` — траверсы и подвесы контактной сети.** `cell = floor((uS+uStart)/uStep) + floor(id/2)`; `s = cell*uStep`; чётный `id` — траверса: масштаб `(6.65, .10, .10)`, сдвиг `(trackX(s) - 3.2, trackY(s) + 5.3, s)`; нечётный — подвес: масштаб `(.065, .55, .065)`, сдвиг `(trackX(s), trackY(s) + 5.0, s)`; цвет `(.18, .20, .21)`.
Вызов: `step = 44.0`, `start = -260`, `count = 60`, `boxVao`.

**`uKind = 6/7` — камни и трава у насыпи.** `cell = floor((uS+uStart)/uStep) + id`; `r = hash21(vec2(cell,4.21))`, `r2 = hash21(vec2(cell,8.71))`; `s = cell*uStep + r*uStep`; `x = trackX(s) + (r < .5 ? -1 : 1)*(5.4 + r2*30.0)`.

* `uKind = 6` — камни: масштаб `(.4+r2, .16+r*.6, .3+r2)`, цвет `(.17,.19,.22)`, сдвиг `(x, terrain(x,s) + .14, s)`, меш `boxVao`, параметры `step = 2`, `start = -160`, `count = 300`.
* `uKind = 7` — трава: масштаб `(.24+r*.3, .5+r2*.9, .24)`, цвет `mix(vec3(.09,.14,.10), vec3(.22,.23,.15), r)`, сдвиг `(x, terrain(x,s) + .25, s)`, меш `coneVao`, `step = .30`, `start = -140`, `count = 1600`; при `quality === 'low'` не рисуется.

**`uKind = 8/9/10/11` — деревня (фиксирована в мировых координатах).** `cell = floor((uS+uStart)/uStep) + floor(id/5)`; `house = mod(id, 5)`; `r = hash21(vec2(cell, house + 23.0))`; `s = cell*uStep + (house - 2.0)*17.0`; `side = hash21(vec2(cell,71.0)) < .5 ? -1 : 1`; `x = trackX(s) + side*(48.0 + r*44.0)`; `y = terrain(x, s)`; `width = 4.3 + r*2.5`, `height = 2.6 + r*1.4`, `depth = 5.5 + r*3.0`.

* `uKind = 8` — дом: масштаб `(width, height, depth)`, сдвиг `(x, y + height*.5, s)`, цвет `mix(vec3(.20,.19,.18), vec3(.30,.24,.20), r)`, `boxVao`.
* `uKind = 9` — крыша: масштаб `(width*1.15, 1.8, depth*1.15)`, сдвиг `(x, y + height + .9, s)`, цвет `(.13,.16,.18)`, `gableVao`.
* `uKind = 10` — светящееся окно: масштаб `(.85,.85,.03)`, сдвиг `(x + .7, y + height*.55, s - depth*.5 - .025)`, цвет `(.95,.56,.22)`, **`emissive = 1.4`**, `boxVao`.
* `uKind = 11` — труба: масштаб `(.48,1.8,.48)`, сдвиг `(x - width*.25, y + height + 1.1, s + 1.1)`, цвет `(.20,.16,.14)`, `boxVao`.
* Вызовы для всех четырёх: `step = 240`, `start = -480`, `count = 35`.

### 4.4 Небо

Полноэкранный треугольник (вершины через `gl_VertexID`: `p = ((id<<1)&2, id&2)`, `vNdc = p*2-1`, `gl_Position = (vNdc, 1, 1)`), глубина не пишется (`depthMask(false)`), цвет пишется всегда. Луч восстанавливается через `uInvVP`:

```
far = uInvVP * vec4(vNdc, 1, 1)
dir = normalize(far.xyz / far.w - uCam)
h   = clamp(dir.y, -1, 1)
```

Базовые цвета: `top = (0.014, 0.020, 0.052)`, `mid = (0.045, 0.061, 0.126)`, `low = (0.150, 0.135, 0.190)`.

```
col = h > 0.18 ? mix(mid, top, smoothstep(0.18, 0.85, h))
               : mix(low, mid, smoothstep(-0.05, 0.18, h))
```

Млечный Путь: `axis = normalize(0.62, 0.42, -0.66)`; `band = 1 - abs(dot(dir, axis))`; `core = smoothstep(0.80, 1.0, band)`; `q = dir*7.0`; 4 октавы `cloud += amp*vnoise3(q); q *= 2.07; amp *= 0.52`, начиная с `amp = 0.62`; `milky = core*(0.25 + cloud*0.95)*smoothstep(-0.02, 0.22, h)`; `col += vec3(0.10, 0.108, 0.150)*milky`.

Хеш/шум неба:

```glsl
float hash31(vec3 p){
  p = fract(p * 0.3183 + vec3(0.71, 0.113, 0.419));
  p *= 17.0;
  return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
// vnoise3 — трилинейная интерполяция hash31 по 8 углам куба
// со сглаживанием f = f*f*(3-2f)
```

Луна (направление `uMoonDir`): `md = dot(dir, uMoonDir)`;

```
col += vec3(0.55, 0.62, 0.85) * pow(max(md,0), 420.0) * 0.32     // узкий диск
col += vec3(0.24, 0.29, 0.45) * pow(max(md,0),  14.0) * 0.30     // широкое гало
if (md > 0.99965) {
    e     = smoothstep(0.99965, 0.99985, md)
    maria = vnoise3(dir * 320.0)
    col   = mix(col, vec3(0.90, 0.93, 0.88) * (0.8 + maria*0.2), e)
}
```

Облака/дымка у горизонта: `cloudP = dir*5.0 + vec3(uTime*0.0015, 0, 0)`; `clouds = smoothstep(0.50, 0.78, vnoise3(cloudP)*0.7 + vnoise3(cloudP*2.7)*0.3)`; `col = mix(col, vec3(0.105,0.135,0.19), clouds*0.42*smoothstep(0.02,0.23,h))`.

Сшивка с туманом и «горные гряды»:

```
col = mix(col, uFogColor, 1 - smoothstep(-0.06, 0.16, h))
az   = atan(dir.x, dir.z)
ridge      = 0.025 + sin(az*7.0)*0.015      + sin(az*17.0 + 2.0)*0.009
col = mix(col, vec3(0.060,0.087,0.128), 1 - smoothstep(ridge, ridge + 0.004, h))
nearRidge  = 0.008 + sin(az*11.0 + 1.0)*0.011
col = mix(col, uFogColor, 1 - smoothstep(nearRidge, nearRidge + 0.003, h))
```

`vnoise3` — значение шума по 3D-сетке с хешем `hash31`, нужно для предотвращения «кубичности» облаков.

### 4.5 Глоу-спрайты (светящиеся билборды)

Константа `MAX_GLOW = 440`. Три динамических массива на `MAX_GLOW` элементов: позиция (vec3), параметры (vec4: `radius, r, g, b`), альфа (float). `addGlow(x,y,z,radius,r,g,b,alpha)` молча игнорирует переполнение.

Инстансный меш: quad из 6 вершин `(-1,-1),(1,-1),(1,1),(-1,-1),(1,1),(-1,1)`; позиция инстанса идёт с делителем 1. Вершинный шейдер:

```
world = iPos + (uRight*aCorner.x + uUp*aCorner.y) * iParam.x
```

где `uRight`, `uUp` — экранные оси камеры (см. ниже), `iParam.x` — радиус. Фрагмент: `d = length(vUv)`; `if (d > 1.0) discard`; `a = pow(1.0 - d, 2.6) * vAlpha`; вывод `vec4(vTint * a, a)`.

Смешивание аддитивное (`blendFunc(ONE, ONE)`), глубина не пишется (`depthMask(false)`), сортировки нет (аддитивность делает порядок неважным).

Экранные оси (одинаково для звёзд и глоу) при `fwd = dir`:

```
rgt = normalize((fwd.z, 0, -fwd.x))
up  = cross(rgt, fwd)
```

Правила порождения спрайтов (в порядке отрисовки кадра):

1. **Окна вагонов.** Для каждого не-локомотива `i`, `side = ±1`, `w = 0..6`; пропуск при `((i%3)*7 + w)*7919 % 11 <= 2`; локальная точка `(side*1.75, 3.05, (w-3)*3)` переводится в мир матрицей вагона; `radius = 2.8`, цвет `(1.0, 0.67, 0.32)`, альфа `0.14`.
2. **Фары локомотива** (только при `state.headOn`): `yaw = trackYaw(sHead)`, `rx = cos(yaw)`, `rz = -sin(yaw)`; для `k = ±1`: точка `(headPos.x + rx*k, headPos.y, headPos.z + rz*k)`, два спрайта — `radius 2.2, цвет (1.0,0.93,0.75), alpha 0.95` и `radius 7.0, цвет (1.0,0.88,0.62), alpha 0.32`; плюс маркер `(headPos.x, headPos.y+1.5, headPos.z)`, `radius 1.2, цвет (1.0,0.85,0.55), alpha 0.55`.
3. **Конус света в воздухе** (только при `state.headOn`): `i = 1..9`, `d = i*7.5`, `fs = sHead + d`; точка `(trackX(fs), trackY(fs)+1.2, fs)`, `radius = 2.0 + d*0.30`, цвет `(1.0,0.86,0.62)`, `alpha = 0.055*(1 - i/11)`.
4. **Пылинки/искры** — по одной на частицу, см. §6.2.
5. **Путевые сигналы**: `i = 0..7`, `gs = (floor(s/176) - 2 + i)*176`; две точки в `(trackX(gs)-6.4, trackY(gs)+3.8, gs)`: `radius .26, цвет (.30,1.0,.57), alpha .9` и `radius 1.2, цвет (.20,1.0,.43), alpha .18`.
6. **Светлячки**: `i = 0..27`, `cell = floor(s/8) - 8 + i`, `gs = cell*8`, `side = -12 - sin(cell*6.3)*5`, `blink = pow(max(0, sin(t*0.75 + cell*3.1)), 3)`; точка `(trackX(gs) + side, trackY(gs) + 1.1 + sin(cell)*0.7, gs)`, `radius .28`, цвет `(.73,.95,.37)`, `alpha = blink*0.26`.
7. **Дым** — по одной на частицу, см. §6.1.

Оценка максимума: 14 не-локомотивов × 14 окон + 14 (фары) + 70 (пыль) + 16 (сигналы) + 28 (светлячки) + 44 (дым) = 368 < 440.

### 4.6 Звёзды

`STARS = 1100`. Направления генерируются один раз детерминированным LCG: `seed = 7`, шаг `seed = (seed*1103515245 + 12345) & 0x7fffffff`, `rnd() = seed / 0x7fffffff`.

```
u = rnd(); v = rnd()
theta = u * 2π
y     = pow(v, 0.75)                       // смещение к зениту
r     = sqrt(max(0, 1 - y*y))
dir   = (cos(theta)*r, y, sin(theta)*r)
w     = 0.40 + pow(rnd(), 2) * 0.85        // яркость: много слабых, редкие яркие
```

Вершинный шейдер (инстансы, quad 6 вершин):

```
tw    = 0.72 + 0.28*sin(uTime*(0.6 + fract(iDir.w*13.0)*2.2) + iDir.w*40.0)
low   = smoothstep(-0.04, 0.16, iDir.y)     // у горизонта тонут в дымке
vAlpha = iDir.w * tw * low
vTint  = mix(vec3(0.78,0.85,1.0), vec3(1.0,0.90,0.76), fract(iDir.w*31.0))
size   = 0.75 + iDir.w * 2.0
world  = uCam + iDir.xyz*900.0 + (uRight*aCorner.x + uUp*aCorner.y)*size
```

Фрагмент: `if (d > 1.0) discard`; `core = pow(1-d, 3.5)`; `halo = pow(1-d, 1.2)*0.22`; `a = (core + halo)*vAlpha`; вывод `vec4(vTint*a, a)`, смешивание аддитивное.

### 4.7 Виньетка

Не шейдер, а DOM-элемент `#vignette` с `pointer-events:none; z-index:2`:

```css
background: radial-gradient(120% 90% at 50% 45%,
            rgba(0,0,0,0) 55%, rgba(0,0,0,.55) 100%);
```

---

## 5. Освещение и пост-обработка

### 5.1 Направление на луну

```js
const moonDir = normalize([0.42, 0.36, 0.83])
// |v| = 0.99745 → (0.42107, 0.36092, 0.83212)
```

`moonDir` — униформа всех проходов (кроме глоу) и шейдера неба.

### 5.2 Общий фрагментный шейдер `FS_COMMON`

Используется землёй, путём, инстансами и вагонами. Униформы: `uCam`, `uMoonDir`, `uHeadPos`, `uHeadDir`, `uHeadOn`, `uFogColor`, `uFogDensity`, `uWin[10]`, `uWinCount`.

```glsl
N    = normalize(vNormal)
V    = uCam - vWorld
dist = length(V)

// полусферный ambient: сверху холодное небо, снизу почти чернота
sky     = N.y*0.5 + 0.5
ambient = mix(vec3(0.065,0.079,0.110), vec3(0.22,0.27,0.36), sky)

// луна: рассеянный свет + узкий блик
Vn   = V / max(dist, 0.001)
moon = max(dot(N, uMoonDir), 0.0)
Hv   = normalize(uMoonDir + Vn)
spec = pow(max(dot(N, Hv), 0.0), 48.0)
light = ambient
      + vec3(0.40,0.47,0.66) * moon * 1.15
      + vec3(0.55,0.62,0.82) * spec * 0.55

// прожектор локомотива
L = uHeadPos - vWorld
ld = length(L); L /= max(ld, 0.001)
cone    = smoothstep(0.955, 0.995, dot(-L, uHeadDir))
atten   = 1.0 / (1.0 + 0.0022 * ld * ld)
lambert = max(dot(N, L), 0.0)
light += vec3(1.0,0.87,0.66) * cone * atten * lambert * 26.0 * uHeadOn

// свет из окон вагонов на насыпь и траву (до 10 источников)
for (int i = 0; i < 10; i++){
  if (float(i) >= uWinCount) break;
  WL   = uWin[i] - vWorld
  wd2  = dot(WL, WL)
  watt = 1.0 / (1.0 + wd2*0.055)
  light += vec3(1.0,0.70,0.36) * watt * max(dot(N, normalize(WL)), 0.0) * 1.25
}

// процедурное «зерно» поверхности (только для неэмиссивных и вблизи)
grain = fract(sin(dot(floor(vWorld.xz*18.0), vec2(12.9898,78.233))) * 43758.5453)
textureAmount = (1.0 - step(0.01, vEmissive)) * (1.0 - smoothstep(15.0, 100.0, dist))
col = vColor * light * (1.0 - textureAmount*grain*0.12) + vColor*vEmissive

// тонмаппинг (мягкое сжатие, «Reinhard-подобное»)
col = col / (vec3(1.0) + col*0.38)

// туман
f   = 1.0 - exp(-pow(dist * uFogDensity, 2.0))
col = mix(col, uFogColor, clamp(f, 0.0, 1.0))
fragColor = vec4(col, 1.0)
```

Константы: `uFogColor = (0.055, 0.068, 0.115)`, `uFogDensity = 0.0026`.

Характерные значения тумана `f = 1-exp(-(0.0026·d)²)`: при 100 м — 0.065; 300 м — 0.456; 500 м — 0.815; 1000 м — 0.999.

### 5.3 Источники света, приходящие из JS

* `uHeadPos`, `uHeadDir`, `uHeadOn` — фары (см. §3.5/§6.3).
* `uWin[10]` — 10 пятен тёплого света, заполняются каждый кадр: для `i = 0..9`, `ws = state.s - 120 + i*42`, `yaw = trackYaw(ws)`:
  ```
  uWin[i] = ( trackX(ws) - 2.4*cos(yaw),
              trackY(ws) + 2.9,
              ws + 2.4*sin(yaw) )
  ```
  `uWinCount = 10` (в цикле шейдера всё равно стоит ограничение 10; массив объявлен на 10, JS-буфер — 30 float).
* `moonDir`, `fogColor`, `fogDensity` — см. выше.

Других источников нет: ни теней, ни точечных ламп, ни SSAO. Тени не отбрасываются вообще.

### 5.4 Состояние GL и порядок проходов

Порядок кадра:

1. `clearColor(fogColor); clear(COLOR|DEPTH)`; `enable(DEPTH_TEST)`, `depthFunc(LEQUAL)`, `enable(CULL_FACE)`, `disable(BLEND)`.
2. **Небо**: `depthMask(false)`, `drawArrays(TRIANGLES, 0, 3)`.
3. **Звёзды**: по-прежнему `depthMask(false)`; `enable(BLEND)`, `blendFunc(ONE,ONE)`, `drawArraysInstanced(..., STARS)`; затем `disable(BLEND)`.
4. `depthMask(true)`.
5. **Земля**: `groundVao`, `drawElements`.
6. **Путь**: `disable(CULL_FACE)`, `trackVao`, `drawElements`, `enable(CULL_FACE)`.
7. **Инстансы** (порядок как в §4.3): шпалы, столбы, деревья (ствол + кроны), траверсы, затем `[камни, трава, дома, крыши, окна, трубы]`.
8. **Вагоны**: `meshProg`, по одному `drawElements` на вагон (меш выбирается по `i%3` или локомотив), параллельно наполняется список глоу.
9. **Глоу**: `depthMask(false)`, `enable(BLEND)`, `blendFunc(ONE,ONE)`, `drawArraysInstanced(..., glowCount)`, `depthMask(true)`, `disable(BLEND)`.
10. `bindVertexArray(null)`; планируется следующий кадр.

Тонмаппинг и туман — в шейдере, отдельных пост-проходов/FBO нет. Рендер идёт прямо в дефолтный фреймбуфер.

---

## 6. Анимация и частицы

### 6.1 Дым из трубы локомотива

44 частицы (`smoke`), изначально `{ life: Math.random() }`.

Кадр:

```
emitS = headCenterS - 3                      // headCenterS = carS(CARS-1) + CAR_LEN*0.5
для каждой частицы:
    life += dt * 0.30                       // жизнь ровно 1/0.30 ≈ 3.33 с
    если life > 1:
        life = 0; s = emitS; side = (rand-0.5)*0.5; rise = 0; seed = rand
    если s === undefined:                    // первый кадр
        s = emitS - rand*60; side = 0; seed = rand
    rise = life * 7.5                        // подъём до 7.5 м
    back = life * 46                         // снос назад до 46 м
    ps   = s - back
    px   = trackX(ps) + side + sin(seed*12 + life*3) * life * 3.5
    py   = trackY(ps) + 4.6 + rise
    a    = max(0, 0.30 * (1 - life) * min(1, life*6))     // быстрый вход, линейный спад
    addGlow(px, py, ps, 2.0 + life*11, 0.62, 0.63, 0.70, a)
```

Новые частицы не спавнятся по таймеру: работает пул из 44 штук, каждая перезапускается по достижении `life = 1`. Итоговая частота — примерно `44 / 3.33 ≈ 13.2` частиц/с. Радиус спрайта растёт от 2.0 до 13.0 м, цвет серо-дымчатый `(0.62, 0.63, 0.70)`, альфа до 0.30.

### 6.2 Пылинки и искры

70 частиц (`motes`). Инициализация:

```
ds    = rand*90 - 30            // смещение вдоль пути относительно камеры, м
side  = (rand - 0.5)*9          // поперечное смещение
up    = rand*5 - 1.4
r     = 0.035 + rand*0.13       // радиус спрайта
warm  = rand < 0.28             // 28 % — тёплые искры, 72 % — холодная пыль
drift = (rand - 0.5)*1.6
seed  = rand*10
```

Кадр:

```
ds -= state.speed * dt * (0.85 + seed*0.03)
если ds < -26:  ds += 110; side = (rand-0.5)*9; up = rand*5 - 1.4
ms     = s + ds
yaw    = trackYaw(ms)
wobble = sin(t*3.1 + seed*6) * drift
mx     = trackX(ms) + (-3.1 + side*0.55 + wobble) * cos(yaw)
mz     = ms          - (-3.1 + side*0.55 + wobble) * sin(yaw)
my     = trackY(ms) + 2.2 + up
near   = 1 - min(1, abs(ds)/26)                      // ярче у камеры
warm: addGlow(mx,my,mz, r*2.4, 1.0, 0.80, 0.52, 0.22*near)
иначе: addGlow(mx,my,mz, r*2.0, 0.72, 0.80, 0.95, 0.12*near)
```

Пыль «летит назад» относительно камеры со скоростью состава (частица догоняет/обгоняет за счёт `0.85 + seed*0.03`), переиспользуется на дистанции `[-26, +84]` м.

### 6.3 Локомотив, фары, прожектор

```
headCenterS = carS(CARS-1) + CAR_LEN*0.5          // центр локомотива
headYaw     = trackYaw(headCenterS)
sHead       = headCenterS + 9.92*cos(headYaw)
headPos     = ( trackX(headCenterS) + 9.92*sin(headYaw),
                trackY(headCenterS) + 1.6,
                sHead )
headDir     = normalize( sin(headYaw), -0.075, cos(headYaw) )
```

`9.92` — вынос фары вперёд от центра локомотива (чуть меньше полуширины 19.7/2 = 9.85 плюс запас). Фары/прожектор включаются чекбоксом «Фары» (`state.headOn`, по умолчанию `true`) и влияют и на шейдерное освещение (§5.2), и на глоу-спрайты (§4.5).

### 6.4 Покачивание, крен камеры, тряска

* Вагон кренится на дуге через `trackRoll(cs)` (амплитуда ±0.09 рад).
* Камера: `sway` (поворот) и `bob` (вертикальное покачивание) — формулы в §1.3; обе затухают до нуля при снятом чекбоксе «Покачивание».
* Дополнительный «дыхательный» дрейф вбок: `sin(t*0.31)*0.12` м (тоже только при `motion`).
* Сглаживание `lean` к `leanTarget`: `min(1, dt*2.8)`; `yaw`/`pitch` к целям: `min(1, dt*7)`; цели `autoLook`: `min(1, dt*1.4)`.

### 6.5 Вращение колёс

Отсутствует. Колёса — часть статического меша `carriageMesh`, инстансной анимации вращения нет. Движение поезда передаётся только смещением `state.s` и миром, который «набегает» на камеру.

### 6.6 Скорости

`state.speed` в м/с: 16 «Не спеша» (57.6 км/ч), 24.5 «Обычная» (88.2 км/ч, значение по умолчанию), 32 «Экспресс» (115.2 км/ч). Начальная позиция `state.s = 110`.

---

## 7. Звук

Полностью процедурный WebAudio-граф (без файлов). Строится лениво при первом нажатии «звук».

### 7.1 Шумовой буфер

Длительность 2 с, один канал, `sampleRate` из AudioContext. Коричнево-подобный шум:

```
last = 0
для i = 0..len-1:
    w = Math.random()*2 - 1
    last = (last + 0.02*w) / 1.02
    d[i] = last * 3.2
```

### 7.2 Граф

```
master (Gain, 0 → ramp) → destination

ветер:
  noiseBuffer(loop) → BiquadFilter(bandpass, freq=480, Q=0.55) → wind Gain(0.42) → master
  LFO: Oscillator(sine, 0.09 Гц) → Gain(0.14) → wind.gain   (аддитивная модуляция)

гул хода:
  noiseBuffer(loop) → BiquadFilter(lowpass, freq=200) → Gain(0.30) → master

стук колёс:
  wheels Gain(1) → master
```

`setInterval(schedule, 200)` запускается после сборки графа.

### 7.3 Планировщик стука

`scheduled` каждые 200 мс (при `on`, `ac.state === 'running'`, вкладка видима):

```
nextClack = max(nextClack, ac.currentTime + 0.025)
wind.gain.setTargetAtTime(0.12 + state.lean*0.30, ac.currentTime, 0.3)
windFilter.frequency.setTargetAtTime(240 + state.lean*280, ac.currentTime, 0.3)

period = 25 / max(4, state.speed)          // стык рельса раз в 25 м
bogie  = min(0.22, 3.4 / max(4, state.speed))   // разлёт между тележками

while (nextClack < ac.currentTime + 0.5):
    t = nextClack
    clack(t, 1.0)
    clack(t + bogie, 0.7)
    clack(t + period*0.45, 0.85)
    clack(t + period*0.45 + bogie, 0.6)
    nextClack += period
```

То есть на каждый стык — четыре удара: основной, через `bogie`, и та же пара со сдвигом `0.45` периода (вторая тележка/второй рельс).

### 7.4 Синтез одного удара

```
clack(t, power):
    tt = t + (rand - 0.5)*0.012           // дрожание фазы ±6 мс
    v  = power * (0.9 + rand*0.2)
    hit(tt,          1.30*v, 'lowpass',  130, 1.2, 0.18)
    hit(tt + 0.004,  0.55*v, 'bandpass', 300, 1.1, 0.10)
    hit(tt + 0.002,  0.30*v, 'bandpass', 1500, 1.4, 0.05)

hit(t, gain, type, freq, q, decay):
    source: noiseBuffer(loop), старт с произвольного смещения rand*1.5 с
    filter: BiquadFilter(type, freq, Q=q)
    gain-огибающая:
        setValueAtTime(0.0001, t)
        exponentialRampToValueAtTime(gain, t + 0.005)
        exponentialRampToValueAtTime(0.0001, t + decay)
    stop(t + decay + 0.05), узлы отключаются по onended
```

### 7.5 Включение/выключение

`toggle()`: собрать граф, `await ac.resume()`, переключить `on`, `nextClack = currentTime + 0.1`, затем `master.gain.cancelScheduledValues(ct)` и `linearRampToValueAtTime(on ? 0.5 : 0.0001, ct + (on ? 1.6 : 0.9))`. `visibility()`: при скрытой вкладке `ac.suspend()`, при возврате (если `on`) `ac.resume()` и сброс `nextClack`.

---

## 8. UI/управление

### 8.1 Элементы

| Элемент | Тип | Начальное состояние | Действие |
|---|---|---|---|
| `#btnSound` | кнопка | текст «звук», `aria-pressed=false` | включение/выключение звука; текст «звук вкл» / «звук»; класс `on` |
| `#btnLean` | кнопка | `aria-pressed=true`, текст «у окна» | `leanTarget = leanTarget ? 0 : 1`; текст «у окна» / «выглянуть» |
| `#btnLook` | кнопка | — | `autoLook = true`, `pitchTarget = -0.02` (широкий вид вдоль состава) |
| `#btnSettings` | кнопка | «ещё», `aria-expanded=false` | открыть/закрыть панель `#settings` (переключает `hidden`) |
| `#quality` | `<select>` | `auto` | `Автоматически` / `Максимум` / `Экономно` → `state.quality`; сбрасывает `frameMs=16.7`, `frames=0`, вызывает `resize()` |
| `#speed` | `<select>` | `24.5` (`selected`) | `Не спеша = 16`, `Обычная = 24.5`, `Экспресс = 32` (м/с) → `state.speed` |
| `#motion` | `<input type=checkbox>` | `checked`, принудительно = `!prefers-reduced-motion` | `state.motion` — покачивание/дрожание камеры |
| `#btnLamp` | `<input type=checkbox>` | `checked` | `state.headOn` — фары, прожектор и глоу-спрайты |
| `#btnFullscreen` | кнопка | скрыта, если `requestFullscreen` недоступен | вход/выход из полноэкранного режима; текст «на весь экран» / «свернуть экран» |

Текст справки в панели: «Кнопка «у окна» придвигает тебя к вагону. «Выглянуть» возвращает широкий вид вдоль состава.»

### 8.2 Горячие клавиши и жесты

* Перетаскивание по canvas — обзор (см. §1.6), с захватом указателя; учитывается только первичный указатель.
* Стрелки на canvas (`tabindex=0`) — шаговый обзор.
* `Escape` — закрыть панель настроек (и вернуть фокус на `#btnSettings`).
* Любой `pointerdown` по canvas закрывает настройки и отключает `autoLook`.
* `#hud` тускнеет (`opacity:.58`, класс `dim`) через 7 с без событий `pointerdown`/`focusin` внутри HUD и на кнопках; при наведении/фокусе (`:hover`, `:focus-within`) снова полная непрозрачность.
* Подсказка `#hint` исчезает через 12 с или при первом ручном обзоре.
* `visibilitychange`: отмена rAF, `state.last = 0`, сброс активного указателя, пауза/возобновление аудио; при возврате видимости — новый `requestAnimationFrame`.
* `webglcontextlost`: `preventDefault()`, остановка rAF, показ сообщения «Графика приостановлена браузером…».

### 8.3 Оформление

* Фон `#05060d`; цвет текста `#f0e2d0`; шрифт `ui-rounded, -apple-system, "Segoe UI", Roboto, sans-serif`.
* Canvas `position:fixed; inset:0; width:100%; height:100%`.
* Кнопки: пилюли (`border-radius:999px`), `min-height:46px`, полупрозрачный фон, `backdrop-filter: blur(8px)`, активное состояние (`on`) — тёплый оранжевый `rgba(255,168,88,.2)`.
* Панель настроек: `width:min(340px, 100% - 28px)`, фон `#10151ef2`, `backdrop-filter: blur(14px)`.
* `@media (prefers-reduced-motion: reduce)` отключает все CSS-транзишены.
* Значение состояния доступно снаружи: `window.__train3d = state`.
* Сбой инициализации показывает `#err` с текстом «Не удалось запустить поезд…»; отсутствие WebGL2 — «Здесь нужен WebGL2…».

---

## 9. Числовые константы — сводная таблица

### Путь (track)

| Константа | Значение | Смысл |
|---|---|---|
| `TRACK.a1` | 58.0 | амплитуда 1-й гармоники `trackX`, м |
| `TRACK.f1` | 0.00840 | частота 1-й гармоники `trackX`, рад/м |
| `TRACK.a2` | 13.0 | амплитуда 2-й гармоники `trackX`, м |
| `TRACK.f2` | 0.02150 | частота 2-й гармоники `trackX`, рад/м |
| `TRACK.p2` | 1.3 | фаза 2-й гармоники `trackX`, рад |
| `TRACK.b1` | 3.4 | амплитуда 1-й гармоники `trackY`, м |
| `TRACK.g1` | 0.00625 | частота 1-й гармоники `trackY`, рад/м |
| `TRACK.b2` | 1.6 | амплитуда 2-й гармоники `trackY`, м |
| `TRACK.g2` | 0.015625 | частота 2-й гармоники `trackY`, рад/м |
| `TRACK.q2` | 0.7 | фаза 2-й гармоники `trackY`, рад |
| `trackDX` амплитуды | 0.4872 и 0.2795 | производные `trackX` |
| `trackDY` амплитуды | 0.02125 и 0.025 | производные `trackY` |
| `trackRoll` шаг `h` | 6 | полушаг численной производной, м |
| `trackRoll` усиление | 260 | `curve*260` |
| `trackRoll` предел | ±0.09 | крен, рад |

### Поезд

| Константа | Значение | Смысл |
|---|---|---|
| `CAR_LEN` | 24.0 | длина вагона, м |
| `CAR_GAP` | 2.6 | зазор между вагонами, м |
| `CAR_W` | 2.9 | ширина вагона, м |
| `CAR_H` | 4.0 | высота габарита, м; **в исходнике объявлена, но нигде не используется** — геометрия задаёт корпус 3.0 при центре y=2.6 |
| `CARS_BEHIND` | 5 | вагонов позади камеры |
| `CARS_AHEAD` | 10 | вагонов впереди (включая локомотив) |
| `CARS` | 15 | всего единиц |
| `carIndexToS` сдвиг | `-14.88` | `-CAR_LEN*0.62` |
| `carIndexToS` шаг | `26.6` | `CAR_LEN + CAR_GAP` |
| длина локомотива | 19.7 | м |
| палитра `brass` | (.49,.35,.18) | латунные детали |
| палитра `metal` | (.13,.17,.20) | металл |
| палитра `dark` | (.027,.042,.052) | тёмные детали |
| цвет корпуса (вагон) | (.12,.20,.22) | |
| цвет корпуса (локомотив) | (.12,.19,.20) | |
| эмиссия окна (lit / dark) | .62 / .02 | |
| эмиссия занавески | .25 | |
| эмиссия лобового стекла локомотива | .15 | |
| окно-глоу | radius 2.8, цвет (1.0,.67,.32), alpha .14 | |
| `9.92` | вынос фары от центра локомотива, м | |
| `headPos.y` | `trackY + 1.6` | высота фары |

### Камера

| Константа | Значение | Смысл |
|---|---|---|
| `state.s` (старт) | 110 | начальная позиция, м |
| `state.speed` | 24.5 (опции 16 / 24.5 / 32) | м/с |
| `state.yaw` / `pitch` (старт) | 0 / -0.02 | рад |
| пределы `yawTarget` | [-2.9, 0.65] | ручной обзор |
| пределы `pitchTarget` | [-0.95, 1.10] | ручной обзор |
| чувствительность указателя | `k = 2.6/max(360, min(W,H))`, `dy*k*0.8` | |
| шаг стрелок | yaw ±0.11, pitch ±0.08 | |
| `fovy` | 1.12 (ландшафт) / 1.20 (портрет) | рад |
| near / far | 0.15 / 1500 | м |
| высота камеры | `trackY(s) + 3.05 + bob` | |
| `sideOffset` lean=1 / lean=0 | -4.60 / -2.15 | м |
| `sway` амплитуды | 0.022 (1.9 Гц) + 0.008 (3.7 Гц) | рад |
| `bob` амплитуды | 0.018 (5.3 Гц) + 0.016 (2.6 Гц) | м |
| дрейф вбок | `sin(t*0.31)*0.12` | м |
| `lean` сглаживание | `min(1, dt*2.8)` | |
| `yaw/pitch` сглаживание | `min(1, dt*7)` | |
| `autoLook` сглаживание | `min(1, dt*1.4)` | |
| `autoLook` пределы `want` | [-0.95, 0.45] | рад |
| `autoLook` pitch | 0.012 | рад |
| цель `autoLook` | `carS(11)` + 4.2 м вбок | |
| `renderScale` старт/min/max | 1.5 / 0.85 / 1.75 | |
| коррекция `renderScale` | ±0.15 при `frameMs>24`, ±0.10 при `<18`, раз в 3000 мс | |
| `dt` предел | 0.10 | с |

### Окружение

| Константа | Значение | Смысл |
|---|---|---|
| `groundVao` grid | 96 × 120, x 0..1, y -1..1 | сетка земли |
| `ahead` | `pow(t,2.2)*1250 - 330` | продольный охват: -330..+920 м |
| `side` | `sign(y)*pow(abs(y),1.7)*430` | поперечный охват: ±430 м |
| `trackGrid` | 420 × 7, 4 ленты (0-1, 2-3, 4-5, 6-7) | меш пути |
| путь `s` | `uS - 330 + pow(t,1.9)*1100` | -330..+770 м |
| бровка насыпи | off ±4.6, h `trackY-0.62` | |
| рельсы | off ∓0.79 / ∓0.65, h `trackY-0.02` | |
| провод | off ±0.14, h `trackY+5.15-sag` | |
| `span` провода | 44.0 | м |
| `sag` max | 0.9 | м |
| `terrain` hills | амплитуды 34.0 и 4.5, частоты 0.0042 и 0.021 | м |
| `terrain` smoothstep | 9.0 → 46.0 | м от пути |
| `terrain` bed | `trackY(z) - 0.9` | м |
| `fbm` | 4 октавы, `p *= 2.03`, `amp *= 0.5` | |
| `MAX_GLOW` | 440 | лимит спрайтов |
| `STARS` | 1100 | число звёзд |
| LCG звёзд | seed 7, `*1103515245 + 12345`, маска `0x7fffffff` | |
| радиус сферы звёзд | 900 | м |
| шпалы | step 0.62, start -200, count 620 | |
| столбы | step 44.0, start -260, count 30, side -6.4, y +2.65 | |
| деревья | count 1000 (low: 600), step 1.1 (low: 1.8), start -320 | |
| деревья, side | `±(13.0 + r3^1.5 * 210.0)` | м |
| деревья, scale | `0.85 + hash*1.9` | |
| траверсы/подвесы | step 44, start -260, count 60 | |
| камни | step 2, start -160, count 300 | |
| трава | step 0.30, start -140, count 1600 (нет в low) | |
| деревня, дома | step 240, start -480, count 35 | |
| деревня, side | `±(48.0 + r*44.0)` | м |
| окна деревни | эмиссия 1.4, цвет (.95,.56,.22) | |
| сигналы | 8 шт., шаг 176 м, side -6.4, y +3.8 | |
| светлячки | 28 шт., ячейка 8 м, side `-12 - sin(cell*6.3)*5` | |
| `winLights` | 10 шт., шаг 42 м, старт `s-120`, side -2.4, y +2.9 | |

### Освещение / пост

| Константа | Значение | Смысл |
|---|---|---|
| `fogColor` | (0.055, 0.068, 0.115) | цвет тумана и цвет очистки |
| `uFogDensity` | 0.0026 | плотность тумана |
| `moonDir` (сырое) | (0.42, 0.36, 0.83) → нормализовано | направление на луну |
| ambient низ / верх | (0.065,0.079,0.110) / (0.22,0.27,0.36) | полусферный ambient |
| лунный свет | (0.40,0.47,0.66), множитель 1.15 | |
| лунный блик | (0.55,0.62,0.82), степень 48, множитель 0.55 | |
| фары (цвет) | (1.0, 0.87, 0.66), множитель 26.0 | |
| конус фар | `smoothstep(0.955, 0.995, dot(-L, uHeadDir))` | |
| затухание фар | `1/(1 + 0.0022*ld²)` | |
| окна как свет | (1.0,0.70,0.36), `1/(1+wd2*0.055)`, ×1.25 | |
| зерно | `fract(sin(dot(floor(world.xz*18), (12.9898,78.233)))*43758.5453)`, ×0.12 | |
| тонмаппинг | `col / (1 + 0.38*col)` | |
| небо top / mid / low | (0.014,0.020,0.052) / (0.045,0.061,0.126) / (0.150,0.135,0.190) | |
| Млечный Путь axis | `normalize(0.62, 0.42, -0.66)` | |
| виньетка CSS | `radial-gradient(120% 90% at 50% 45%, transparent 55%, rgba(0,0,0,.55) 100%)` | |

### Паттерн облаков/dымки неба

| Константа | Значение | Смысл |
|---|---|---|
| `dir*7.0` | 7.0 | частота Млечного Пути |
| cloud octaves | 4, `q *= 2.07`, `amp *= 0.52`, старт 0.62 | |
| диск луны | степень 420, ×0.32, цвет (0.55,0.62,0.85) | |
| гало луны | степень 14, ×0.30, цвет (0.24,0.29,0.45) | |
| лимб луны | `md > 0.99965`, `vnoise3(dir*320)`, цвет (0.90,0.93,0.88) | |
| дымка горизонта | `dir*5 + (uTime*0.0015,0,0)`, цвет (0.105,0.135,0.19), ×0.42 | |

### Частицы и анимация

| Константа | Значение | Смысл |
|---|---|---|
| `smoke` count | 44 | частиц дыма |
| `smoke` скорость жизни | 0.30 /с | полный цикл ≈ 3.33 с |
| `smoke` rise | `life*7.5` | м |
| `smoke` снос | `life*46` | м назад |
| `smoke` радиус | `2.0 + life*11` | м |
| `smoke` альфа | `0.30*(1-life)*min(1, life*6)` | |
| `motes` count | 70 | частиц пыли |
| `motes` `ds` init | `rand*90 - 30` | м |
| `motes` окно | `ds < -26 → ds += 110` | м |
| `motes` side | `(rand-0.5)*9` | м |
| `motes` up | `rand*5 - 1.4` | м |
| `motes` радиус | `0.035 + rand*0.13` | |
| `motes` warm доля | 0.28 | |
| `motes` drift | `(rand-0.5)*1.6` | |

### Звук

| Константа | Значение | Смысл |
|---|---|---|
| шумовой буфер | 2 с, `last=(last+0.02w)/1.02`, `×3.2` | |
| ветер | bandpass 480 Гц, Q 0.55, gain 0.42 | |
| ветер LFO | 0.09 Гц, gain 0.14 | |
| гул | lowpass 200 Гц, gain 0.30 | |
| master | 0 → 0.5 за 1.6 с; → 0.0001 за 0.9 с | |
| период стука | `25 / max(4, speed)` с | стык раз в 25 м |
| `bogie` | `min(0.22, 3.4 / max(4, speed))` с | |
| интервал планировщика | 200 мс | `setInterval` |
| окно планирования | `currentTime + 0.5` с | |
| ветер от lean | gain `.12 + lean*.30`, freq `240 + lean*280` | |
| clack low | lowpass 130 Гц, Q 1.2, gain 1.30v, decay 0.18 с | |
| clack mid | bandpass 300 Гц, Q 1.1, gain 0.55v, decay 0.10 с | |
| clack high | bandpass 1500 Гц, Q 1.4, gain 0.30v, decay 0.05 с | |
| дрожание clack | ±0.012 с | |
| gain `v` | `power*(0.9 + rand*0.2)` | |

---

## Приложение A. Карта исходника

| Строки | Подсистема |
|---|---|
| 1–95 | HTML-разметка и CSS (canvas, `#vignette`, `#journey`, `#hint`, `#hud`, `#settings`, `#err`) |
| 97–113 | Обёртка IIFE, `'use strict'`, обработчик ошибок, инициализация WebGL2 |
| 115–168 | `M4`: `ident`, `mul`, `perspective`, `lookAt`, `rigid` |
| 170–185 | `TRACK`, `trackX/Y/DX/DY/Yaw/Roll` |
| 187–219 | `GLSL_TRACK`: `trackX/Y/Yaw`, `hash21`, `vnoise`, `fbm`, `terrain` |
| 221–284 | `FS_COMMON` (ambient, луна, фары, окна, зерно, тонмаппинг, туман) |
| 286–308 | `compile`, `program` |
| 310–398 | Шейдер неба (`skyProg`) |
| 400–435 | Шейдер земли (`groundProg`) |
| 437–485 | Шейдер пути (`trackProg`) |
| 487–576 | Шейдер инстансов (`instProg`, виды 0–11) |
| 578–596 | Шейдер мешей (`meshProg`) |
| 598–626 | Шейдер глоу (`glowProg`) |
| 628–661 | Шейдер звёзд (`starProg`) |
| 663–693 | `buildGrid`, `makeVao2` |
| 695–747 | `boxMesh`, `coneMesh`, `makeMeshVao` |
| 749–791 | Сборка `groundVao`, `trackVao` (ленты), `boxVao`, `coneVao`, `pineMesh`/`pineVao`, `gableMesh`/`gableVao` |
| 793–827 | `MAX_GLOW` и буферы/VAO глоу |
| 829–859 | `STARS`, LCG, `starVao` |
| 861–867 | `addGlow` |
| 869–899 | `CAR_LEN/GAP/W/H`, `coloredBuilder` |
| 900–931 | `roofMesh`, `wheelMesh` |
| 932–990 | Палитры, `carriageMesh`, `carMeshes`, `locoMesh` |
| 991–996 | `CARS_BEHIND/AHEAD/CARS`, `carIndexToS`, `carS` |
| 998–1026 | `state`, массивы `smoke` и `motes` |
| 1028–1061 | `fogColor`, `moonDir`, `resize`, `winLights`, `setCommon` |
| 1063–1103 | `frame`: dt/качество, продвижение `s`, камера, локомотив/`headPos`/`headDir` |
| 1105–1134 | `autoLook`, сглаживание углов, `dir`/`center`, `proj`/`view`/`vp` |
| 1136–1145 | Заполнение `winLights` |
| 1147–1206 | Сброс GL, небо, звёзды, земля, путь |
| 1208–1243 | Отрисовка инстансов (все виды) |
| 1245–1272 | Отрисовка вагонов и глоу окон |
| 1274–1291 | Фары локомотива и конус света |
| 1293–1310 | Пылинки/искры |
| 1312–1323 | Путевые сигналы и светлячки |
| 1325–1346 | Дым |
| 1348–1383 | Отрисовка глоу и завершение кадра |
| 1385–1416 | `invert` (4×4) |
| 1418–1530 | Аудиограф (`makeNoise`, `build`, `hit`, `clack`, `schedule`, `toggle`, `visibility`) |
| 1532–1619 | Управление: указатель, клавиатура, кнопки, настройки, полноэкранный режим, видимость, потеря контекста |
| 1618–1623 | `window.__train3d`, запуск rAF, закрытие IIFE |
