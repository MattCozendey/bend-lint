# About the first voxel slice

The slice stores one body and derives a rendered scene after edits or camera movement. The body remains the only authority for occupancy.

`voxel.bend` owns `Body`, `Cell`, `Sphere`, six face directions, and explicit `Surface` faces. `Body` holds a dense affine `Array<U32>`. Zero means empty. A positive value identifies a material. An edit moves the body through the destruction operation and returns the next body.

`material.bend` owns four named material identities and their authored OKLCH definitions. Storage remains U32 so appearance does not narrow the geometry domain. Material 1 remains the default foundation. The renderer displays unsupported positive IDs as magenta without changing their stored value or occupied geometry.

`lighting.bend` implements the daylight part of the [reference lighting change](https://github.com/aivv73/bend-voxel/commit/cf188d2afeaf47836ffe023907f81efafc40878c). It converts the authored material colors to linear RGB and applies cool hemispherical sky ambient light and warm directional sunlight, adapting the source's Y-up light vector to this slice's Z-up coordinates. Six face directions and ten shadow visibility levels produce cached sRGB ramps. Pixel leaves select packed colors; they do not repeat gamut fitting or sRGB transfer. Unsupported positive IDs and voxel edges use flat display colors. The older three-level material swatches remain available as palette utilities. Night mode and the camera work light are omitted.

The renderer builds a 128 × 128 orthographic sun-depth image from the complete exposed surface, using short tile candidate lists and sequential leaves. `Shadow.depth` controls its resolution separately from the main renderer's tile/fork depths. The light projection fits the occupied extent and covers all face directions; it is independent of the camera. Each receiver compares a three-by-three footprint against the depth map. Comparisons use the receiver plane at each texel centre plus a small world-space bias, preventing slope acne while keeping contact shadows close to the caster. Ambient light remains in full shadow.

After building sun depths, the renderer samples visibility into 16 × 16 world-space fields on each sun-facing voxel face and a 256 × 256 field on the ground. Uniform regions collapse to single quadtree leaves. Displayed pixels sample these compressed fields, so GPU dispatch does not carry or traverse the complete sun-depth tree. Nearest field sampling approximates the filtered shadow boundary; its resolutions are independent of the main renderer's decomposition.

`RenderScene.reproject` retains both sun depths and illumination fields during camera flight and look. Body edits rebuild them together with the exposed surface. A finite ground plane below the body receives the same lighting and shadows, with a grid expressed in world coordinates. The ground is presentation geometry and never supplies a voxel pick or brush target. The brush tint and rings retain their display colors and share the existing hit depth. All lighting and shadow code is Bend; it adds no execution backend assumptions or new forks.

Surface extraction creates a temporary immutable snapshot for neighbor reads. The snapshot stays inside the geometry module and disappears after extraction. Bounds checks prevent wrapped array indices from connecting opposite body edges. `Body.destroy` accepts a center inside the body and a radius no larger than its side. Invalid brush inputs leave the body unchanged.

The legacy integer `Sphere` API retains those geometry fixtures. Interactive cuts use `PointCm` and `MetricSphere`: one grid unit is 10cm, and the brush radius is 20cm. `Body.cut` selects occupied voxel centres with one closed squared-distance predicate. Finite spheres may have centres outside the body and overlap it. Negative radii, non-finite radii or centres, and an overflowing squared radius preserve the body.

`render.bend` owns `Camera`, its derived `Basis`, and the projected exposed faces in `RenderScene`. Each face stores camera-relative plane and UV offsets plus its daylight ramp. Its four corners produce conservative screen bounds after clipping near the eye. The tile tree holds short lists of candidate faces. Pixels intersect the original axis-aligned face planes, check closed unit UV coverage, and choose the nearest forward depth. Stable face ordinals break equal-depth ties. Drawing and picking share this test. All six face directions remain available when the camera crosses the body.

`main.bend` owns the affine `Model`, `Controls`, and the frame clock. A batch reduces its events against the scene just presented. Body edits and camera movement rebuild the scene once at the end of that batch. Idle frames retain the cached scene. Movement follows the full sight direction, camera right, and world vertical. The combined world displacement is normalized before applying eight cells per second. The first clock sample has zero elapsed time, and later samples cap elapsed time at 100 milliseconds.

`Interactive.step` owns the native pointer boundary. Each right-button transition queues a `Window.grab` request, which the wrapper consumes once before presenting the next frame. Relative `Look` events affect the camera only while right-button intent is held. The wrapper does not reacquire capture on every idle frame. Primary clicks use the presented scene even when an earlier event in the same batch changes the camera or body. R restores the body while preserving the pose and controls.

Model owns an absolute screen `Pointer`. Free motion updates it; RMB targeting uses screen centre. `RenderScene.target` reconstructs a continuous surface point from the same winning depth and pixel ray as drawing and picking. `Model.preview` derives its sphere on each presented frame, so edits and flight cannot leave a stale world target. `Model.view` remains an explicit geometry-only path for dumps and benchmarks. Hover changes no body, surface, or cached geometry.

The preview colours visible selected cells using the exact `MetricSphere.contains` predicate used by removal. Three original 32-segment great-circle rings show the sphere. Segments are clipped at the near plane, projected once per preview, and filtered for existing tiles. Sequential pixel leaves use a bounded screen distance and reciprocal-depth interpolation to hide wire behind geometry. Rings and tint never enter picking. The same code runs on CPU and GPU without new forks.

`scripts/ui_check.bend` owns a native test window and drives the slice through `Interactive.step`. The fork's `Window.capture` reads its client pixels. `scripts/ui_capture.bend` consumes the affine RGB array and builds the existing `Image` used by assertions and screenshot export. It admits only the checker's 512x512 frame and its exact pixel capacity. Row-major reads pass the array owner sequentially through the four image quadrants. The checker passes the exported `WindowRef` directly to the public API of [bend-ui-test](https://github.com/aivv73/bend-ui-test). The library owns native input, close requests, and expiry checks. `scripts/flight_ui_check.bend` uses `xdotool` for key holds, releases, and relative mouse motion that the library's matched event plans cannot express. The ordinary application still builds with upstream Bend.

The `deps/bend-ui-test` git submodule pins the library without copying its native implementation into this project's sources. A sibling checkout would require separate version and import-path configuration. Vendoring would duplicate upstream source and its update work. The build lists all four library source files as prerequisites. Only the UI checker imports the dependency.

Projection and intersection use `F32` arithmetic. The camera basis is derived once per scene build. Pixel rays stay unnormalized so their intersection parameter is forward depth. Conservative near clipping and outward screen padding keep culling separate from exact hit acceptance. CPU and GPU calls use the same algorithm. Runtime image comparisons check the floating-point results.

## Accepted limits

The slice has one fixed 8³ body and one spherical destruction operation. The default body uses foundation, and engine callers can assign any of the four palette materials. Each edit rebuilds the complete surface and scene. Camera movement rebuilds only the projected scene and retains the sun-depth cache. There is no collision, smooth meshing, physics, streaming, or incremental surface update.

Base exposes no focus-loss event or key-state query. Native focus loss releases pointer capture, but the app cannot automatically clear held keys or its right-button intent. A fresh right-button press can request capture again. Key releases delivered to the app stop flight.

The displayed-frame benchmark includes `Window.frame`, image disposal, and scripted edit rebuilds. The native display can limit CPU results to its refresh interval. Historical measurements of the fixed camera reached the development display cadence. They do not establish a perspective-flight decomposition choice or a GPU compute speedup.

Core algorithms contain no backend intrinsics, hardware lane counts, or backend-specific synchronization. Tile and fork depths are runtime configuration. The Linux SDK path appears only in the build setup.

## Examples considered

The [official Bend demos](https://github.com/bendlang/bend/tree/main/demos) show native events, pure `Image` quadtrees, and GPU dispatch. The triangle, Pong, ray tracer, and Slash Boss examples informed the app and tile renderer shapes. This project contains original source and does not copy the large demo renderer.

For the perspective restoration, the fixed Slash Boss revision and the earlier bend-voxel revision supplied camera and input examples. The current camera, plane intersections, clipping bounds, reducers, and native checks are written for this slice's existing body. Triangle projection, analytic voxel planes, and full-screen near-plane fallback were compared. Analytic planes retain one candidate per face and avoid triangle interpolation and artificial face diagonals.

The [Bend hub](https://hub.bend-lang.com/) and [awesome-bend](https://github.com/777genius/awesome-bend) were inspected for reusable packages. The inspected candidates included bendlib, Jonlib, bend-collections, bend-parallel, and WordLib. The engine and ordinary application require only Base. Native UI checks also use bend-ui-test.

## Principles applied

Model the Domain shaped the affine body, explicit faces, tile lists, and edit reducer. Boundary Discipline kept input and Window effects outside the pure geometry and renderer. Sequence Work into Verifiable Units placed exact geometry checks before native rendering. Test Behavior, Not Implementation shaped complete face-set and image assertions. Prove It Works required forced GPU execution and actual native input with screenshots.

For the library migration, Model the Domain keeps `WindowRef` as the test address and `Window` as the application's owner. Boundary Discipline puts native event delivery in UITest. Migrate Callers Then Delete Legacy APIs removes every local `Desktop` caller and the three adapter files together. Laziness Protocol and Minimize Reader Load remove the key, click, and alive forwarding helpers. The close helper remains because it selects between Escape and a window close request. Exhaust the Design Space compared a pinned submodule, a sibling checkout, and vendored source. Prove It Works compares actual window screenshots before and after the migration.
