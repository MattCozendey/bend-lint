# Bend 2 Mandelbrot

- Read the existing implementation before changing it. Keep edits focused.
- Check `bend --version` and read `bend guide` before writing Bend code.
- Preserve the requirements in `LAWS.bend` and run `bend PROOF.bend` after Bend changes. Do not weaken laws or bypass checking to make changes pass.
- Keep native backing-pixel sampling and the bounded latest-view scheduler. Do not introduce an unbounded render queue.
- Use targeted numerical, region, cancellation and interaction checks for renderer changes. Verify image quality as well as speed.
- Benchmark representative coordinates with hardware, precision, iteration budget, sampling and warm/cold state recorded. Separate cached animation from newly computed frames.
- The `v0.1.0` tag preserves the initial working viewer. Keep it intact while experimenting on branches.
- Do not commit, push, publish or install dependencies without the user's authorization.
