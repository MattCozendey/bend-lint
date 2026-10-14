#!/usr/bin/env python3
"""Render the original WebGL night-train demo headlessly at a frozen camera.

The reference demo is an animation: its state advances every rAF and its
particle fields are seeded with ``Math.random``.  Neither is reproducible, so
this tool renders a *patched copy* of ``reference/night-train-webgl.html``
(never the original) with two changes:

  1. a seeded PRNG replaces ``Math.random`` before the demo script runs, so
     every particle, mote and smoke seed is identical on every run.  The
     generator mirrors the demo's own LCG (its star field), ``--seed``
     selects it and defaults to 7; and
  2. a ``window.__nt`` hook is appended inside the demo's IIFE that stops the
     rAF loop, writes the requested camera state, draws a single frame at
     ``dt = 0`` and returns ``canvas.toDataURL('image/png')``.

The result is deterministic: the same arguments produce byte-identical PNGs,
whether the frame is rendered on its own or as frame i of a `--frames`
sequence.  A sequence pays for that by opening a page per frame -- the demo's
particle arrays carry state across draws, so frames of one session would not be
the stills they claim to be; see the note in `main`.

Camera convention
-----------------
The CLI flags map one-to-one onto the reference's own ``state`` fields:

  --s                -> state.s      position along the track (metres); 110
  --lean             -> state.lean   how far the head hangs out of the
                                     window; the demo turns it into the
                                     camera's lateral offset from the
                                     centreline::

                                       sideOffset = -2.15 - lean*2.45

                                     so lean=1 (the demo default) is
                                     ``sideOffset = -4.60`` metres.  The sign
                                     is the demo's: negative is toward the
                                     window side, i.e. the camera sits *left*
                                     of the centreline.
  --yaw              -> state.yaw    head turn off the track tangent, radians
  --pitch            -> state.pitch  head pitch, radians (default -0.02)
  --t                -> state.t      animation clock in seconds (particle
                                     phase only; the camera does not move)
  --motion/--no-motion -> state.motion
                                     sway/bob and sloshing particles; frozen
                                     (off) by default so the camera is a still
  --quality high|low -> state.quality
                                     scene density (tree count, detail step)
  --seed N           -> Math.random PRNG seed (default 7).  The same seed
                                     reproduces the same particle fields; a
                                     different seed yields a different frame.

The demo's own defaults are ``s=110, lean=1, yaw=0, pitch=-0.02, motion=true``
with ``quality`` auto.  A square frame is used because the demo picks
``fovy = W<H ? 1.20 : 1.12`` and the Bend renderer's ``S.fovy()`` is 1.12.

A *sequence* rides the same camera: ``--frames N`` renders N frames, advancing
``s`` by ``--speed/--fps`` and ``t`` by ``1/--fps`` per frame, so the clip plays
back at the demo's own 24.5 m/s.  ``--out`` is then a printf pattern.  One
browser serves the whole sequence -- launching it costs about four seconds --
but each frame gets a page of its own, which costs about 0.4 s and is what
keeps a sequence's frames the same pictures as the stills at those cameras.

Usage::

  tools/render_reference.py --out out/ref.png --s 110 --lean 1 --info
  tools/render_reference.py --out out/ref.png --size 512 --quality low
  tools/render_reference.py --out out/ref.png --seed 7
  tools/render_reference.py --out 'out/ref_%04d.png' --frames 192 --fps 24 \
      --size 512 --s 110 --no-motion
"""

from __future__ import annotations

import argparse
import base64
import json
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "reference" / "night-train-webgl.html"

# Default PRNG seed: the render is only reproducible if the particle fields
# are.  Overridable with --seed.
DEFAULT_SEED = 7

# Injected before the demo's own <script>, so the seeding happens before the
# demo builds its motes/smoke arrays.  This mirrors the demo's own generator
# (its star field, reference HTML lines 831-845):
#
#   state = (state * 1103515245 + 12345) & 0x7fffffff
#
# The product exceeds 2**53, so it is computed exactly from the low 32 bits
# with Math.imul (the +12345 stays well inside the exact-integer range) and
# the ``&`` is exact 32-bit arithmetic.  The result is divided by 2**31 rather
# than 2**31-1 so it lies in [0,1) as Math.random() requires, without changing
# the exact modulus.
SEED_SCRIPT = """
<script>
// Seeded PRNG installed before the demo script: every Math.random() call in
// the demo (motes, smoke, reset positions) must be reproducible.
(function(){
  var state = %d & 0x7fffffff;
  Math.random = function(){
    state = (Math.imul(state, 1103515245) + 12345) & 0x7fffffff;
    return state / 0x80000000;
  };
})();
</script>
<script>
"""

# Appended inside the demo's IIFE, replacing the line that would start the rAF
# loop.  `rafId=0` at the end of frame() is handled by the other replacement.
HOOK = """
window.__nt = {
  render: function(opts){
    opts = opts || {};
    var s = (opts.s === undefined) ? state.s : opts.s;
    var t = (opts.t === undefined) ? 0 : opts.t;
    var lean = (opts.lean === undefined) ? 1 : opts.lean;
    var yaw = (opts.yaw === undefined) ? 0 : opts.yaw;
    var pitch = (opts.pitch === undefined) ? -0.02 : opts.pitch;
    state.quality = (opts.quality === undefined) ? 'high' : opts.quality;
    state.speed = 0; state.motion = !!opts.motion;
    state.s = s; state.t = t;
    state.lean = lean; state.leanTarget = lean;
    state.yaw = yaw; state.yawTarget = yaw;
    state.pitch = pitch; state.pitchTarget = pitch;
    state.autoLook = false; state.headOn = true;
    if (rafId){ cancelAnimationFrame(rafId); rafId = 0; }
    state.last = 1e-9;          // truthy, and now - last = 0 => dt = 0
    frame(1e-9);
    rafId = 0;                  // a frozen frame must not re-arm the loop
    return canvas.toDataURL('image/png');
  },
  info: function(){
    var sideOffset = -2.15 - state.lean * 2.45
                     + (state.motion ? Math.sin(state.t * .31) * .12 : 0);
    return {s: state.s, yaw: state.yaw, pitch: state.pitch, W: W, H: H,
            fovy: (W < H ? 1.20 : 1.12), lean: state.lean,
            sideOffset: sideOffset, t: state.t, motion: state.motion,
            quality: state.quality, cars: CARS, behind: CARS_BEHIND,
            ahead: CARS_AHEAD};
  }
};
"""


def patch(html: str, seed: int) -> str:
    """Return the demo HTML with the seeded PRNG and the __nt hook installed."""
    if "<script>" not in html:
        raise SystemExit("reference HTML: no <script> tag found")
    seeded = html.replace("<script>", SEED_SCRIPT % seed, 1)

    # frame() must not re-arm the loop; it used to schedule the next frame.
    if "rafId=requestAnimationFrame(frame);" not in seeded:
        raise SystemExit("reference HTML: frame() re-arm line not found")
    stopped = seeded.replace("rafId=requestAnimationFrame(frame);", "rafId=0;", 1)

    # The auto-start at the end of the IIFE becomes the hook definition.
    start = "window.__train3d = state;\nrafId=requestAnimationFrame(frame);\n})();"
    if start not in stopped:
        raise SystemExit("reference HTML: IIFE start line not found")
    return stopped.replace(start, "window.__train3d = state;" + HOOK + "\n})();", 1)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, help="output PNG path")
    ap.add_argument("--s", type=float, default=110.0, help="state.s (track position)")
    ap.add_argument("--lean", type=float, default=1.0, help="state.lean (window lean; 1 => sideOffset -4.60)")
    ap.add_argument("--yaw", type=float, default=0.0, help="state.yaw (head turn, rad)")
    ap.add_argument("--pitch", type=float, default=-0.02, help="state.pitch (head pitch, rad)")
    ap.add_argument("--t", type=float, default=0.0, help="state.t (animation clock, s)")
    ap.add_argument("--size", type=int, default=1024, help="square frame size, px")
    ap.add_argument("--frames", type=int, default=1,
                    help="number of frames; >1 advances s and t per frame and "
                         "needs a printf pattern in --out (default: 1)")
    ap.add_argument("--fps", type=float, default=30.0,
                    help="frames per second of the sequence: t advances by "
                         "1/fps, s by --speed/fps (default: 30)")
    ap.add_argument("--speed", type=float, default=24.5,
                    help="metres per second along the track (default: 24.5, the "
                         "demo's own ride speed)")
    ap.add_argument("--seed", type=int, default=DEFAULT_SEED,
                    help="PRNG seed for the demo's Math.random (default: %d)" % DEFAULT_SEED)
    ap.add_argument("--motion", dest="motion", action="store_true", default=False,
                    help="keep sway/bob on (default: frozen, no motion)")
    ap.add_argument("--no-motion", dest="motion", action="store_false",
                    help="freeze sway/bob (default)")
    ap.add_argument("--quality", choices=("high", "low"), default="high",
                    help="scene density")
    ap.add_argument("--info", action="store_true",
                    help="print the frozen camera (s, yaw, pitch, W, H, fovy) as JSON")
    args = ap.parse_args(argv)

    if args.size <= 0:
        ap.error("--size must be positive")
    if args.frames <= 0:
        ap.error("--frames must be positive")
    if args.fps <= 0:
        ap.error("--fps must be positive")
    if args.frames > 1 and "%" not in args.out:
        ap.error("--frames > 1 needs a printf pattern in --out, "
                 "e.g. 'out/ref_%04d.png'")

    try:
        from playwright.sync_api import sync_playwright
    except ImportError as exc:  # pragma: no cover - environment guard
        raise SystemExit(f"render_reference: playwright is required: {exc}")

    if not REFERENCE.is_file():
        raise SystemExit(f"render_reference: missing {REFERENCE}")
    patched = patch(REFERENCE.read_text(encoding="utf-8"), args.seed)

    out = pathlib.Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)

    tmpdir = pathlib.Path(tempfile.mkdtemp(prefix="nt-reference-"))
    html_path = tmpdir / "night-train-webgl.patched.html"
    html_path.write_text(patched, encoding="utf-8")

    opts = {"s": args.s, "lean": args.lean, "yaw": args.yaw,
            "pitch": args.pitch, "t": args.t, "motion": args.motion,
            "quality": args.quality}

    console: list[str] = []
    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch(args=[
                "--enable-unsafe-swiftshader",
                "--use-gl=angle",
                "--use-angle=swiftshader",
            ])
            # A frame per page, not a frame per session.  The demo's motes and
            # smoke are *stateful*: rendering frame i where frame i-1 left off
            # gives a different picture from a fresh page at the same camera,
            # and the difference grows along the clip (measured at 256x256:
            # 5e-5 MAE after one frame, 5e-2 after 150 -- larger than every real
            # difference between the two renderers).  A page costs about 0.4 s,
            # against 5.5 s for a whole browser.
            dt = 1.0 / args.fps
            ds = args.speed / args.fps
            raws: list[bytes] = []
            info: dict = {}
            checked = False
            try:
                for i in range(args.frames):
                    page = browser.new_page(
                        viewport={"width": args.size, "height": args.size},
                        device_scale_factor=1,
                    )
                    try:
                        page.on("console",
                                lambda m: console.append(f"{m.type}: {m.text}"))
                        page.on("pageerror",
                                lambda e: console.append(f"pageerror: {e}"))
                        page.goto(html_path.as_uri())
                        try:
                            page.wait_for_function("() => !!window.__nt",
                                                   timeout=15000)
                        except Exception:
                            raise SystemExit(
                                "render_reference: the __nt hook did not install; "
                                "the demo probably failed to start. Full console "
                                "output:\n  %s"
                                % ("\n  ".join(console) or "(empty)"))

                        # The canvas check is about this host, not this frame:
                        # once is enough.
                        if not checked:
                            webgl = page.evaluate(
                                "() => { const c = document.getElementById('gl');"
                                " if (!c) return 'no canvas';"
                                " const g = c.getContext('webgl2');"
                                " return g ? 'ok' : 'no webgl2'; }")
                            if webgl != "ok":
                                raise SystemExit(
                                    "render_reference: WebGL2 is unavailable (%s). "
                                    "Full console output:\n  %s"
                                    % (webgl, "\n  ".join(console) or "(empty)"))
                            checked = True

                        # The camera of frame i: the same still, ridden along
                        # the track.  t drives the particles, so the clip moves.
                        frame_opts = dict(opts, s=args.s + i * ds,
                                          t=args.t + i * dt)
                        data_url = page.evaluate("(o) => window.__nt.render(o)",
                                                 frame_opts)
                        if not isinstance(data_url, str) or "," not in data_url:
                            raise SystemExit(
                                "render_reference: frame %d returned no PNG data "
                                "URL" % i)
                        raws.append(base64.b64decode(data_url.split(",", 1)[1]))
                        info = page.evaluate("() => window.__nt.info()")
                    finally:
                        page.close()
            finally:
                browser.close()
    finally:
        html_path.unlink(missing_ok=True)
        tmpdir.rmdir()

    paths = [out] if args.frames == 1 else [pathlib.Path(str(out) % i)
                                           for i in range(args.frames)]
    for path, raw in zip(paths, raws):
        path.write_bytes(raw)

    if (info.get("W"), info.get("H")) != (args.size, args.size):
        print("render_reference: warning: frame is %sx%s, expected %sx%s"
              % (info.get("W"), info.get("H"), args.size, args.size),
              file=sys.stderr)
    if args.info:
        print(json.dumps(info, indent=2, sort_keys=True))
    if args.frames == 1:
        print("%s  %dx%d  %d bytes" % (out, info["W"], info["H"], len(raws[0])),
              file=sys.stderr)
    else:
        print("%s .. %s  %dx%d  %d frames (%d bytes each)"
              % (paths[0], paths[-1], info["W"], info["H"], len(paths),
                 len(raws[0])), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
